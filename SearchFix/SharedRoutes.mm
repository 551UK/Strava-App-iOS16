#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>
#import <float.h>
#import <SafariServices/SafariServices.h>
#import <math.h>

// Local preview of geometry already delivered in SuggestedRoutes GraphQL.
// There is no entitlement mutation, GraphQL replay, network proxy or bypass.
static NSArray<NSDictionary *> *sRoutePreviews;

static id RValue(id source, NSString *key) {
    return [source isKindOfClass:[NSDictionary class]] ? [(NSDictionary *)source objectForKey:key] : nil;
}
// Strava 375/422/487 all declare their own route-detail URL destinations.
// These are NOT browser URLs; retain routeUrl supplied by Strava verbatim.
static NSString *RURLKind(id raw) {
    if (![raw isKindOfClass:[NSString class]] || ![raw length]) return @"missing";
    NSString *value=(NSString *)raw;
    if (value.length>2048) return @"oversize";
    NSURLComponents *c=[NSURLComponents componentsWithString:value];
    NSString *scheme=c.scheme.lowercaseString ?: @"";
    NSString *host=c.host.lowercaseString ?: @"";
    NSString *p=c.path.lowercaseString ?: @"";
    if ([scheme isEqualToString:@"strava"] &&
        ([host isEqualToString:@"route"] || [host isEqualToString:@"routes"]) &&
        p.length>1) return @"strava-deep-link";
    if ([scheme isEqualToString:@"https"] &&
        ([host isEqualToString:@"strava.com"] || [host hasSuffix:@".strava.com"]) &&
        [p containsString:@"/routes/"]) return @"https-strava-route";
    if (!scheme.length &&
        ([p hasPrefix:@"/route/suggested/"] || [p hasPrefix:@"/route/"] ||
         [p hasPrefix:@"/routes/"])) return @"relative-route";
    // Opaque routeUrl values must not be converted into arbitrary route IDs.
    if (!scheme.length && [value rangeOfString:@"/"].location==NSNotFound)
        return @"opaque";
    return @"other-url";
}
static NSURL *RNativeOrPublicURL(id raw) {
    NSString *kind=RURLKind(raw);
    if ([kind isEqualToString:@"strava-deep-link"] ||
        [kind isEqualToString:@"https-strava-route"])
        return [NSURL URLWithString:(NSString *)raw];
    if ([kind isEqualToString:@"relative-route"]) {
        NSString *relative=(NSString *)raw;
        NSString *native=[@"strava://" stringByAppendingString:
             [relative hasPrefix:@"/"] ? [relative substringFromIndex:1] : relative];
        return [NSURL URLWithString:native];
    }
    return nil;
}
// Encoded polyline decoder. Coordinates remain in process memory only.
static NSArray<NSValue *> *RPolyline(id value) {
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSString *raw=(NSString *)value;
    if (raw.length<8 || raw.length>160000) return nil;
    NSMutableArray<NSValue *> *points=[NSMutableArray array];
    long long latitude=0,longitude=0;
    NSUInteger n=raw.length,index=0;
    while (index<n && points.count<20000) {
        long long delta[2]={0,0};
        for (int k=0;k<2;k++) {
            long long result=0;
            int shift=0;
            BOOL finished=NO;
            while (index<n && shift<=55) {
                unichar c=[raw characterAtIndex:index++];
                if (c<63 || c>126) return nil;
                long long number=(long long)c-63;
                result|=(number&31) << shift;
                shift+=5;
                if (number<32) { finished=YES; break; }
            }
            if (!finished) return nil;
            delta[k]=(result&1) ? ~(result >> 1) : result >> 1;
        }
        latitude+=delta[0]; longitude+=delta[1];
        CLLocationCoordinate2D coordinate=CLLocationCoordinate2DMake(
            latitude/100000.0,longitude/100000.0);
        if (!CLLocationCoordinate2DIsValid(coordinate)) return nil;
        [points addObject:[NSValue valueWithMKCoordinate:coordinate]];
    }
    return (index==n && points.count>1) ? points : nil;
}
static NSArray<NSArray<NSValue *> *> *RSegments(id node) {
    id data=RValue(node,@"routePolylineData");
    id legs=RValue(data,@"legs");
    // An independently observed 422.0.1 SuggestedRoutes payload also
    // contains legs directly at node level. Accept either schema.
    if (![legs isKindOfClass:[NSArray class]]) legs=RValue(node,@"legs");
    if (![legs isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray *parts=[NSMutableArray array];
    for (id leg in (NSArray *)legs) {
        id paths=RValue(leg,@"paths");
        if (![paths isKindOfClass:[NSArray class]]) continue;
        for (id path in (NSArray *)paths) {
            id encoded=RValue(RValue(path,@"polyline"),@"data");
            NSArray *points=RPolyline(encoded);
            if (points.count>1) [parts addObject:points];
            if (parts.count>=100) break;
        }
        if (parts.count>=100) break;
    }
    return parts;
}
extern "C" void SSCSharedRoutesCaptureJSON(id body,void (*logger)(NSString *)) {
    id outer=RValue(RValue(body,@"data"),@"suggestedRoutesBySourceGeo");
    id routes=RValue(outer,@"routes");
    id nodes=RValue(routes,@"nodes");
    if (![nodes isKindOfClass:[NSArray class]]) return;
    NSMutableArray *candidates=[NSMutableArray array];
    NSUInteger publicLinks=0, nativeLinks=0, relativeLinks=0, opaque=0, unknownLinks=0;
    NSUInteger lines=0, missing=0, flatLegs=0, nestedLegs=0;
    for (id node in (NSArray *)nodes) {
        if (![node isKindOfClass:[NSDictionary class]]) continue;
        id raw=RValue(node,@"routeUrl");
        NSString *kind=RURLKind(raw);
        NSURL *url=RNativeOrPublicURL(raw);
        if ([kind isEqualToString:@"https-strava-route"]) publicLinks++;
        else if ([kind isEqualToString:@"strava-deep-link"]) nativeLinks++;
        else if ([kind isEqualToString:@"relative-route"]) relativeLinks++;
        else if ([kind isEqualToString:@"opaque"]) opaque++;
        else if ([kind isEqualToString:@"missing"]) missing++;
        else unknownLinks++;
        if ([RValue(node,@"legs") isKindOfClass:[NSArray class]]) flatLegs++;
        if ([RValue(RValue(node,@"routePolylineData"),@"legs") isKindOfClass:[NSArray class]]) nestedLegs++;
        NSArray *segments=RSegments(node);
        if (segments.count) lines++;
        // Show all returned routes (including ones whose link shape needs
        // another adapter). Never synthesise an entitlement or a route ID.
        id title=RValue(node,@"title");
        if (![title isKindOfClass:[NSString class]] || ![title length])
            title=@"Suggested route";
        if ([title length]>90) title=[title substringToIndex:90];
        id length=RValue(node,@"length");
        NSNumber *metres=([length isKindOfClass:[NSNumber class]] &&
          [length doubleValue]>=0 && [length doubleValue]<1000000) ? length : @0;
        [candidates addObject:@{@"title":title, @"length":metres,
          @"segments":segments ?: @[],@"url":url ?: [NSNull null],@"urlKind":kind}];
        if (candidates.count>=40) break;
    }
    if (logger) {
        logger([NSString stringWithFormat:
           @"NATIVE_ROUTE_SCAN nodes=%lu geometry=%lu flatLegs=%lu nestedLegs=%lu nativeLinks=%lu relativeLinks=%lu publicLinks=%lu opaque=%lu unknown=%lu missing=%lu retained=%lu",
           (unsigned long)[(NSArray *)nodes count],(unsigned long)lines,
           (unsigned long)flatLegs,(unsigned long)nestedLegs,
           (unsigned long)nativeLinks,(unsigned long)relativeLinks,
           (unsigned long)publicLinks,(unsigned long)opaque,(unsigned long)unknownLinks,
           (unsigned long)missing,(unsigned long)candidates.count]);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (candidates.count) sRoutePreviews=[candidates copy];
    });
}
extern "C" NSUInteger SSCSharedRoutesCount(void) {
    return sRoutePreviews.count;
}
// Offline-in-process visual guidance from the polyline the free client
// already fetched. This does not start/record a Strava activity, unlock
// native turn-by-turn navigation, or request route data from a paid API.
@interface SRoutePreview : UIViewController <MKMapViewDelegate, CLLocationManagerDelegate>
@property(nonatomic,strong) NSDictionary *route;
@property(nonatomic,strong) MKMapView *map;
@property(nonatomic,strong) CLLocationManager *gps;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIButton *followButton;
@property(nonatomic,assign) BOOL following;
@end
@implementation SRoutePreview
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.title=@"Route map";
    [[NSNotificationCenter defaultCenter] addObserver:self
      selector:@selector(stopInBackground:)
      name:UIApplicationDidEnterBackgroundNotification object:nil];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]
      initWithBarButtonSystemItem:UIBarButtonSystemItemDone
      target:self action:@selector(close)];

    MKMapView *map=[[MKMapView alloc] initWithFrame:self.view.bounds];
    self.map=map;
    map.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    map.delegate=self;
    [self.view addSubview:map];

    MKMapRect combined=MKMapRectNull;
    NSUInteger overlayCount=0;
    for (NSArray<NSValue *> *section in self.route[@"segments"]) {
        NSUInteger n=section.count;
        if (n<2 || n>20000) continue;
        CLLocationCoordinate2D *coords=(CLLocationCoordinate2D *)calloc(n,sizeof(CLLocationCoordinate2D));
        if (!coords) continue;
        for (NSUInteger j=0;j<n;j++) coords[j]=[section[j] MKCoordinateValue];
        MKPolyline *line=[MKPolyline polylineWithCoordinates:coords count:n];
        free(coords);
        [map addOverlay:line level:MKOverlayLevelAboveRoads];
        combined=MKMapRectIsNull(combined) ? line.boundingMapRect :
           MKMapRectUnion(combined,line.boundingMapRect);
        overlayCount++;
    }
    if (!MKMapRectIsNull(combined) && overlayCount) {
        [map setVisibleMapRect:combined
          edgePadding:UIEdgeInsetsMake(110,34,175,34) animated:NO];
    }

    UILabel *heading=[UILabel new];
    heading.translatesAutoresizingMaskIntoConstraints=NO;
    heading.backgroundColor=[UIColor colorWithWhite:1 alpha:0.95];
    heading.textColor=UIColor.blackColor;
    heading.layer.cornerRadius=12;
    heading.layer.masksToBounds=YES;
    heading.numberOfLines=2;
    heading.textAlignment=NSTextAlignmentCenter;
    heading.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    heading.text=[NSString stringWithFormat:@"%@\n%.2f km · Strava map data",
        self.route[@"title"],[self.route[@"length"] doubleValue]/1000.0];
    [self.view addSubview:heading];

    UIStackView *bar=[UIStackView new];
    bar.translatesAutoresizingMaskIntoConstraints=NO;
    bar.axis=UILayoutConstraintAxisVertical;
    bar.alignment=UIStackViewAlignmentFill;
    bar.distribution=UIStackViewDistributionFill;
    bar.spacing=9;
    bar.layoutMargins=UIEdgeInsetsMake(12,12,12,12);
    bar.layoutMarginsRelativeArrangement=YES;
    bar.backgroundColor=[UIColor colorWithWhite:1 alpha:0.96];
    bar.layer.cornerRadius=14;
    bar.layer.masksToBounds=YES;
    [self.view addSubview:bar];

    UILabel *status=[UILabel new];
    self.status=status;
    status.font=[UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    status.textColor=UIColor.darkGrayColor;
    status.textAlignment=NSTextAlignmentCenter;
    status.numberOfLines=2;
    status.text=@"Route line ready · GPS guidance is off";
    [bar addArrangedSubview:status];

    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    self.followButton=button;
    [button setTitle:@"Start following route" forState:UIControlStateNormal];
    button.backgroundColor=UIColor.systemOrangeColor;
    button.tintColor=UIColor.whiteColor;
    button.titleLabel.font=[UIFont boldSystemFontOfSize:16];
    button.layer.cornerRadius=11;
    [button addTarget:self action:@selector(toggleFollowing:)
       forControlEvents:UIControlEventTouchUpInside];
    [bar addArrangedSubview:button];

    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
      [heading.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
      [heading.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
      [heading.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
      [heading.heightAnchor constraintGreaterThanOrEqualToConstant:58],
      [bar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
      [bar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
      [bar.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12],
      [button.heightAnchor constraintEqualToConstant:47]
    ]];
}
- (void)toggleFollowing:(id)sender {
    if (self.following) { [self stopFollowing]; return; }
    if (![CLLocationManager locationServicesEnabled]) {
        self.status.text=@"Location Services are disabled in iOS Settings.";
        return;
    }
    if (!self.gps) {
        self.gps=[CLLocationManager new];
        self.gps.delegate=self;
        self.gps.desiredAccuracy=kCLLocationAccuracyBest;
        self.gps.distanceFilter=5;
        self.gps.activityType=CLActivityTypeFitness;
    }
    CLAuthorizationStatus auth=self.gps.authorizationStatus;
    if (auth==kCLAuthorizationStatusDenied || auth==kCLAuthorizationStatusRestricted) {
        self.status.text=@"Allow location access to Strava in iOS Settings.";
        return;
    }
    self.following=YES;
    [self.followButton setTitle:@"Stop following" forState:UIControlStateNormal];
    self.followButton.backgroundColor=UIColor.systemGrayColor;
    self.status.text=@"Waiting for your GPS position…";
    self.map.showsUserLocation=YES;
    if (auth==kCLAuthorizationStatusNotDetermined) {
        [self.gps requestWhenInUseAuthorization];
    } else {
        [self startPositionUpdates];
    }
}
- (void)startPositionUpdates {
    if (!self.following || !self.gps) return;
    CLAuthorizationStatus auth=self.gps.authorizationStatus;
    if (auth!=kCLAuthorizationStatusAuthorizedWhenInUse &&
        auth!=kCLAuthorizationStatusAuthorizedAlways) return;
    [self.gps startUpdatingLocation];
    self.map.userTrackingMode=MKUserTrackingModeFollowWithHeading;
}
- (void)stopFollowing {
    self.following=NO;
    [self.gps stopUpdatingLocation];
    self.map.userTrackingMode=MKUserTrackingModeNone;
    self.map.showsUserLocation=NO;
    [self.followButton setTitle:@"Start following route" forState:UIControlStateNormal];
    self.followButton.backgroundColor=UIColor.systemOrangeColor;
    self.status.text=@"Following stopped · route line remains visible";
}
- (void)close {
    if (self.following) [self stopFollowing];
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.following && (self.navigationController.isBeingDismissed ||
                           self.isMovingFromParentViewController))
        [self stopFollowing];
}
- (void)stopInBackground:(NSNotification *)notification {
    if (self.following) {
        [self stopFollowing];
        self.status.text=@"Guidance stopped when Strava moved to background.";
    }
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.gps stopUpdatingLocation];
    self.gps.delegate=nil;
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if (!self.following) return;
    CLAuthorizationStatus auth=self.gps.authorizationStatus;
    if (auth==kCLAuthorizationStatusAuthorizedAlways ||
        auth==kCLAuthorizationStatusAuthorizedWhenInUse)
        [self startPositionUpdates];
    else if (auth==kCLAuthorizationStatusDenied ||
             auth==kCLAuthorizationStatusRestricted) {
        [self stopFollowing];
        self.status.text=@"Location access is unavailable. Enable it in Settings.";
    }
}
// Map-match the user's location to the nearest segment. This is approximate
// route progress, not step-by-step directions or an activity recording.
- (void)locationManager:(CLLocationManager *)manager
     didUpdateLocations:(NSArray<CLLocation *> *)locations {
    if (!self.following) return;
    CLLocation *fix=locations.lastObject;
    if (!fix || fix.horizontalAccuracy<0 || fix.horizontalAccuracy>150 ||
        fabs([fix.timestamp timeIntervalSinceNow])>35) {
        self.status.text=@"Waiting for an accurate GPS fix…";
        return;
    }
    MKMapPoint current=MKMapPointForCoordinate(fix.coordinate);
    double metersPerPoint=MKMetersPerMapPointAtLatitude(fix.coordinate.latitude);
    if (!isfinite(metersPerPoint) || metersPerPoint<=0) return;
    double nearest=DBL_MAX, along=0, total=0;
    for (NSArray<NSValue *> *section in self.route[@"segments"]) {
        if (section.count<2) continue;
        for (NSUInteger i=1;i<section.count;i++) {
            MKMapPoint p=MKMapPointForCoordinate([section[i-1] MKCoordinateValue]);
            MKMapPoint q=MKMapPointForCoordinate([section[i] MKCoordinateValue]);
            double dx=q.x-p.x,dy=q.y-p.y;
            double squared=dx*dx+dy*dy;
            if (squared<0.0001) continue;
            double t=((current.x-p.x)*dx+(current.y-p.y)*dy)/squared;
            t=MAX(0,MIN(1,t));
            double ex=current.x-(p.x+t*dx),ey=current.y-(p.y+t*dy);
            double distance=hypot(ex,ey)*metersPerPoint;
            double segment=hypot(dx,dy)*metersPerPoint;
            if (distance<nearest) {
                nearest=distance;
                along=total+t*segment;
            }
            total+=segment;
        }
    }
    if (nearest==DBL_MAX) {
        self.status.text=@"No usable route line available for GPS following.";
        return;
    }
    double remaining=MAX(0,total-along);
    NSString *deviation=nearest<=30 ? @"On route" :
       [NSString stringWithFormat:@"%.0f m from route",nearest];
    self.status.text=[NSString stringWithFormat:@"%@ · ~%.2f km remaining",
        deviation,remaining/1000.0];
}
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if (!self.following) return;
    if (error.code==kCLErrorDenied) {
        [self stopFollowing];
        self.status.text=@"Location permission denied. Check iOS Settings.";
    } else {
        self.status.text=@"GPS unavailable; waiting for another location fix…";
    }
}
- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    if ([overlay isKindOfClass:[MKPolyline class]]) {
        MKPolylineRenderer *renderer=[[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay];
        renderer.strokeColor=UIColor.systemOrangeColor;
        renderer.lineWidth=5;
        return renderer;
    }
    return [[MKOverlayRenderer alloc] initWithOverlay:overlay];
}
@end
@interface SRouteChooser : UITableViewController
@property(nonatomic,copy) NSArray<NSDictionary *> *routes;
@end
@implementation SRouteChooser
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"Downloaded routes";
    self.tableView.rowHeight=65;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]
      initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self
      action:@selector(close)];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.routes.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"route"];
    if (!cell) cell=[[UITableViewCell alloc]
       initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"route"];
    NSDictionary *item=self.routes[path.row];
    cell.textLabel.text=item[@"title"];
    NSArray *parts=item[@"segments"];
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%.2f km · %@",
       [item[@"length"] doubleValue]/1000.0,
       parts.count ? @"map preview" : ([item[@"url"] isKindOfClass:[NSURL class]] ? @"native Strava link" : item[@"urlKind"])];
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    NSDictionary *item=self.routes[path.row];
    NSURL *url=item[@"url"];
    if ([url isKindOfClass:[NSURL class]] &&
        [url.scheme.lowercaseString isEqualToString:@"strava"]) {
        // This is a native deep link that Strava itself recognises in all
        // three provided IPAs. Do not rewrite it to a web URL.
        [[UIApplication sharedApplication] openURL:url options:@{}
          completionHandler:^(BOOL opened) {
            NSLog(@"[StravaSearch16] Native route URL dispatched: %@",opened?@"yes":@"no");
          }];
        return;
    }
    if ([item[@"segments"] count]) {
        SRoutePreview *viewer=[SRoutePreview new];
        viewer.route=item;
        UINavigationController *nav=[[UINavigationController alloc]
          initWithRootViewController:viewer];
        nav.modalPresentationStyle=UIModalPresentationFullScreen;
        [self presentViewController:nav animated:YES completion:nil];
        return;
    }
    if ([url isKindOfClass:[NSURL class]] &&
        [url.scheme.lowercaseString isEqualToString:@"https"]) {
        SFSafariViewController *browser=[[SFSafariViewController alloc] initWithURL:url];
        [self presentViewController:browser animated:YES completion:nil];
        return;
    }
    UIAlertController *notice=[UIAlertController alertControllerWithTitle:@"Route data found"
      message:@"Strava returned this route, but its routeUrl is an opaque or unsupported format. The tweak will not invent a destination or route identifier."
      preferredStyle:UIAlertControllerStyleAlert];
    [notice addAction:[UIAlertAction actionWithTitle:@"OK"
      style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:notice animated:YES completion:nil];
}
@end
extern "C" void SSCSharedRoutesShow(UIViewController *presenter) {
    if (!presenter || !sRoutePreviews.count) return;
    SRouteChooser *chooser=[SRouteChooser new];
    chooser.routes=[sRoutePreviews copy];
    UINavigationController *nav=[[UINavigationController alloc]
       initWithRootViewController:chooser];
    nav.modalPresentationStyle=UIModalPresentationFullScreen;
    [presenter presentViewController:nav animated:YES completion:nil];
}
