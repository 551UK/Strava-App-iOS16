#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>
#import <math.h>

// Nearby-route browser for Strava 422 on iOS 16. Route sources are kept separate:
// Strava geometry already received by the app, or real Apple Maps walking directions.
// No subscription changes, fabricated coordinates, or replay of private GraphQL calls.
extern "C" NSArray<NSDictionary *> *SSCSharedRoutesNear(CLLocationCoordinate2D center, double radiusMetres);
extern "C" void SSCShowSearchScreen(UIViewController *presenter);

@interface SSCNearbyWalks : UIViewController <MKMapViewDelegate, UITableViewDataSource, UITableViewDelegate, CLLocationManagerDelegate>
@property(nonatomic,strong) MKMapItem *chosenPlace;
@property(nonatomic,strong) MKMapView *map;
@property(nonatomic,strong) UIView *sheet;
@property(nonatomic,strong) NSLayoutConstraint *sheetHeight;
@property(nonatomic,strong) UILabel *headline;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UITableView *table;
@property(nonatomic,strong) CLLocationManager *locationManager;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *entries;
@property(nonatomic,strong) NSMutableArray<MKDirections *> *directions;
@property(nonatomic,strong) NSMutableArray<MKLocalSearch *> *searches;
@property(nonatomic,assign) CLLocationCoordinate2D center;
@property(nonatomic,assign) BOOL centerReady;
@property(nonatomic,assign) BOOL expanded;
@property(nonatomic,assign) NSUInteger requestGeneration;
@property(nonatomic,assign) NSInteger searchesPending;
@property(nonatomic,strong) NSMutableArray<MKMapItem *> *destinations;
@property(nonatomic,assign) NSInteger directionsPending;
@property(nonatomic,strong) MKMapItem *startItem;
@end

@implementation SSCNearbyWalks

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"Nearby walks";
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.entries=[NSMutableArray new];
    self.searches=[NSMutableArray new];
    self.directions=[NSMutableArray new];
    self.destinations=[NSMutableArray new];

    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]
        initWithTitle:@"Search place" style:UIBarButtonItemStylePlain
        target:self action:@selector(searchAnotherPlace)];

    MKMapView *map=[[MKMapView alloc] initWithFrame:CGRectZero];
    map.translatesAutoresizingMaskIntoConstraints=NO;
    map.delegate=self;
    map.showsCompass=YES;
    self.map=map;
    [self.view addSubview:map];
    [NSLayoutConstraint activateConstraints:@[
        [map.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [map.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [map.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [map.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];

    UIView *sheet=[UIView new];
    sheet.translatesAutoresizingMaskIntoConstraints=NO;
    sheet.backgroundColor=UIColor.systemBackgroundColor;
    sheet.layer.cornerRadius=18;
    sheet.layer.maskedCorners=kCALayerMinXMinYCorner|kCALayerMaxXMinYCorner;
    sheet.layer.masksToBounds=YES;
    self.sheet=sheet;
    [self.view addSubview:sheet];
    self.sheetHeight=[sheet.heightAnchor constraintEqualToConstant:160];
    [NSLayoutConstraint activateConstraints:@[
        [sheet.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [sheet.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [sheet.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        self.sheetHeight
    ]];

    UIButton *handle=[UIButton buttonWithType:UIButtonTypeSystem];
    handle.translatesAutoresizingMaskIntoConstraints=NO;
    [handle setTitle:@"━━━━  Swipe up for walks  ━━━━" forState:UIControlStateNormal];
    handle.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [handle addTarget:self action:@selector(toggleSheet) forControlEvents:UIControlEventTouchUpInside];
    [sheet addSubview:handle];

    UILabel *headline=[UILabel new];
    headline.translatesAutoresizingMaskIntoConstraints=NO;
    headline.font=[UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    headline.text=@"Nearby walking routes";
    self.headline=headline;
    [sheet addSubview:headline];

    UILabel *status=[UILabel new];
    status.translatesAutoresizingMaskIntoConstraints=NO;
    status.font=[UIFont systemFontOfSize:12];
    status.textColor=UIColor.secondaryLabelColor;
    status.numberOfLines=2;
    status.text=@"Choose an area or allow location access.";
    self.status=status;
    [sheet addSubview:status];

    UITableView *table=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    table.translatesAutoresizingMaskIntoConstraints=NO;
    table.dataSource=self;
    table.delegate=self;
    table.rowHeight=62;
    table.tableFooterView=[UIView new];
    self.table=table;
    [sheet addSubview:table];
    [NSLayoutConstraint activateConstraints:@[
        [handle.topAnchor constraintEqualToAnchor:sheet.topAnchor constant:7],
        [handle.centerXAnchor constraintEqualToAnchor:sheet.centerXAnchor],
        [handle.heightAnchor constraintEqualToConstant:27],
        [headline.topAnchor constraintEqualToAnchor:handle.bottomAnchor constant:1],
        [headline.leadingAnchor constraintEqualToAnchor:sheet.leadingAnchor constant:18],
        [headline.trailingAnchor constraintEqualToAnchor:sheet.trailingAnchor constant:-16],
        [status.topAnchor constraintEqualToAnchor:headline.bottomAnchor constant:4],
        [status.leadingAnchor constraintEqualToAnchor:headline.leadingAnchor],
        [status.trailingAnchor constraintEqualToAnchor:headline.trailingAnchor],
        [table.topAnchor constraintEqualToAnchor:status.bottomAnchor constant:7],
        [table.leadingAnchor constraintEqualToAnchor:sheet.leadingAnchor],
        [table.trailingAnchor constraintEqualToAnchor:sheet.trailingAnchor],
        [table.bottomAnchor constraintEqualToAnchor:sheet.bottomAnchor constant:-12]
    ]];

    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc]
       initWithTarget:self action:@selector(panSheet:)];
    pan.cancelsTouchesInView=NO;
    [handle addGestureRecognizer:pan];

    if (self.chosenPlace) {
        [self loadAt:self.chosenPlace.placemark.coordinate
             title:self.chosenPlace.name ?: @"Selected location"];
    } else {
        self.locationManager=[CLLocationManager new];
        self.locationManager.delegate=self;
        self.locationManager.desiredAccuracy=kCLLocationAccuracyHundredMeters;
        if ([CLLocationManager authorizationStatus]==kCLAuthorizationStatusNotDetermined)
            [self.locationManager requestWhenInUseAuthorization];
        else
            [self requestUserLocation];
    }
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController || self.isBeingDismissed) {
        self.requestGeneration++;
        for (MKLocalSearch *search in self.searches) [search cancel];
        for (MKDirections *d in self.directions) [d cancel];
        [self.locationManager stopUpdatingLocation];
    }
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.expanded)
        self.sheetHeight.constant=MIN(470,MAX(280,self.view.bounds.size.height*0.62));
}
- (void)searchAnotherPlace {
    if (self.navigationController.viewControllers.count>1)
        [self.navigationController popViewControllerAnimated:YES];
    else
        SSCShowSearchScreen(self);
}
- (void)toggleSheet {
    self.expanded=!self.expanded;
    CGFloat height=self.expanded ? MIN(470,MAX(280,self.view.bounds.size.height*0.62)) : 160;
    [UIView animateWithDuration:0.25 animations:^{
        self.sheetHeight.constant=height;
        [self.view layoutIfNeeded];
    }];
}
- (void)panSheet:(UIPanGestureRecognizer *)pan {
    if (pan.state==UIGestureRecognizerStateEnded) {
        CGFloat velocity=[pan velocityInView:self.view].y;
        CGFloat translation=[pan translationInView:self.view].y;
        if (velocity < -80 || translation < -35) { if (!self.expanded) [self toggleSheet]; }
        else if (velocity > 80 || translation > 35) { if (self.expanded) [self toggleSheet]; }
    }
}
- (void)requestUserLocation {
    CLAuthorizationStatus state=[CLLocationManager authorizationStatus];
    if (state==kCLAuthorizationStatusAuthorizedAlways ||
        state==kCLAuthorizationStatusAuthorizedWhenInUse) {
        [self.locationManager requestLocation];
        self.status.text=@"Finding routes near your current location…";
    } else if (state==kCLAuthorizationStatusDenied || state==kCLAuthorizationStatusRestricted) {
        self.status.text=@"Location unavailable. Tap Search place to choose an area.";
    }
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    [self requestUserLocation];
}
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *fix=locations.lastObject;
    if (fix && !self.centerReady && fix.horizontalAccuracy>=0) {
        [self loadAt:fix.coordinate title:@"Your area"];
    }
}
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    self.status.text=@"Unable to locate you. Tap Search place to choose an area.";
}
- (void)loadAt:(CLLocationCoordinate2D)coordinate title:(NSString *)name {
    if (!CLLocationCoordinate2DIsValid(coordinate)) return;
    self.centerReady=YES;
    self.center=coordinate;
    self.title=name;
    self.headline.text=[NSString stringWithFormat:@"Walks near %@",name];
    [self.map removeAnnotations:self.map.annotations];
    MKPointAnnotation *pin=[MKPointAnnotation new];
    pin.coordinate=coordinate;
    pin.title=name;
    [self.map addAnnotation:pin];
    [self.map setRegion:MKCoordinateRegionMakeWithDistance(coordinate,7000,7000) animated:NO];

    self.requestGeneration++;
    NSUInteger generation=self.requestGeneration;
    for (MKLocalSearch *s in self.searches) [s cancel];
    for (MKDirections *d in self.directions) [d cancel];
    [self.searches removeAllObjects];
    [self.directions removeAllObjects];
    [self.destinations removeAllObjects];
    [self.entries removeAllObjects];
    [self.map removeOverlays:self.map.overlays];

    // Cached Strava results are shown only when their actual geometry is near
    // this coordinate. Never display an old Cape Town list for Blackburn.
    NSArray<NSDictionary *> *nearby=SSCSharedRoutesNear(coordinate,8000);
    for (NSDictionary *route in nearby) {
        NSMutableDictionary *entry=[route mutableCopy];
        entry[@"source"]=@"Strava map data";
        [self.entries addObject:entry];
    }
    [self.table reloadData];
    self.status.text=@"Looking for actual walking paths (Apple Maps)…";
    self.startItem=[[MKMapItem alloc] initWithPlacemark:
       [[MKPlacemark alloc] initWithCoordinate:coordinate]];
    self.startItem.name=name;

    // Apple Maps provides genuine pedestrian directions; never fabricate paths
    // or label these results as Strava-supplied routes.
    NSArray<NSString *> *terms=@[@"parks",@"walking trails",@"nature reserves"];
    self.searchesPending=terms.count;
    __weak typeof(self) weakSelf=self;
    for (NSString *term in terms) {
        MKLocalSearchRequest *req=[MKLocalSearchRequest new];
        req.naturalLanguageQuery=term;
        req.region=MKCoordinateRegionMakeWithDistance(coordinate,8500,8500);
        MKLocalSearch *search=[[MKLocalSearch alloc] initWithRequest:req];
        [self.searches addObject:search];
        [search startWithCompletionHandler:^(MKLocalSearchResponse *response,NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) strongSelf=weakSelf;
                if (!strongSelf || strongSelf.requestGeneration!=generation) return;
                CLLocation *origin=[[CLLocation alloc] initWithLatitude:coordinate.latitude longitude:coordinate.longitude];
                for (MKMapItem *item in response.mapItems) {
                    CLLocationCoordinate2D c=item.placemark.coordinate;
                    if (!CLLocationCoordinate2DIsValid(c)) continue;
                    CLLocation *loc=[[CLLocation alloc] initWithLatitude:c.latitude longitude:c.longitude];
                    double dist=[loc distanceFromLocation:origin];
                    if (dist<350 || dist>5000) continue;
                    BOOL duplicate=NO;
                    for (MKMapItem *existing in strongSelf.destinations) {
                        CLLocationCoordinate2D e=existing.placemark.coordinate;
                        CLLocation *p=[[CLLocation alloc] initWithLatitude:e.latitude longitude:e.longitude];
                        if ([loc distanceFromLocation:p]<220) { duplicate=YES; break; }
                    }
                    if (!duplicate) [strongSelf.destinations addObject:item];
                    if (strongSelf.destinations.count>=20) break;
                }
                strongSelf.searchesPending--;
                if (strongSelf.searchesPending==0) [strongSelf buildWalkingRoutes:generation];
            });
        }];
    }
}
- (void)buildWalkingRoutes:(NSUInteger)generation {
    CLLocation *origin=[[CLLocation alloc] initWithLatitude:self.center.latitude longitude:self.center.longitude];
    [self.destinations sortUsingComparator:^NSComparisonResult(MKMapItem *a,MKMapItem *b) {
        CLLocation *la=[[CLLocation alloc] initWithLatitude:a.placemark.coordinate.latitude longitude:a.placemark.coordinate.longitude];
        CLLocation *lb=[[CLLocation alloc] initWithLatitude:b.placemark.coordinate.latitude longitude:b.placemark.coordinate.longitude];
        double da=[la distanceFromLocation:origin], db=[lb distanceFromLocation:origin];
        return da<db ? NSOrderedAscending : (da>db ? NSOrderedDescending : NSOrderedSame);
    }];
    NSUInteger count=MIN((NSUInteger)7,self.destinations.count);
    if (!count) {
        self.status.text=self.entries.count ?
           @"No additional Apple walking paths found. Nearby Strava routes are below." :
           @"No walking routes found here. Search another place.";
        return;
    }
    self.directionsPending=count;
    self.status.text=@"Calculating real pedestrian routes…";
    __weak typeof(self) weakSelf=self;
    for (NSUInteger i=0;i<count;i++) {
        MKMapItem *destination=self.destinations[i];
        MKDirectionsRequest *request=[MKDirectionsRequest new];
        request.source=self.startItem;
        request.destination=destination;
        request.transportType=MKDirectionsTransportTypeWalking;
        request.requestsAlternateRoutes=NO;
        MKDirections *directions=[[MKDirections alloc] initWithRequest:request];
        [self.directions addObject:directions];
        [directions calculateDirectionsWithCompletionHandler:^(MKDirectionsResponse *response,NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) strongSelf=weakSelf;
                if (!strongSelf || strongSelf.requestGeneration!=generation) return;
                MKRoute *route=response.routes.firstObject;
                if (route && route.polyline.pointCount>1 && route.distance>0 && route.distance<10000) {
                    NSString *destinationName=destination.name.length ? destination.name : @"Local destination";
                    [strongSelf.entries addObject:@{
                        @"title":[NSString stringWithFormat:@"%@ out-and-back",destinationName],
                        @"length":@(route.distance*2.0),
                        @"route":route,
                        @"destination":destination,
                        @"source":@"Apple Maps walking directions"
                    }];
                    [strongSelf.table reloadData];
                }
                strongSelf.directionsPending--;
                if (!strongSelf.directionsPending) {
                    NSUInteger n=strongSelf.entries.count;
                    strongSelf.status.text=n ?
                      [NSString stringWithFormat:@"%lu available · Swipe up and select a walk",(unsigned long)n] :
                      @"No walking routes available. Search another place.";
                }
            });
        }];
    }
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.entries.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"walk"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"walk"];
    NSDictionary *item=self.entries[indexPath.row];
    cell.textLabel.text=item[@"title"];
    cell.textLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%.2f km · %@",
       [item[@"length"] doubleValue]/1000.0,item[@"source"]];
    cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item=self.entries[indexPath.row];
    [self.map removeOverlays:self.map.overlays];
    MKMapRect rect=MKMapRectNull;
    MKRoute *apple=item[@"route"];
    if ([apple isKindOfClass:[MKRoute class]]) {
        [self.map addOverlay:apple.polyline level:MKOverlayLevelAboveRoads];
        rect=apple.polyline.boundingMapRect;
    } else {
        for (NSArray<NSValue *> *part in item[@"segments"]) {
            if (part.count<2 || part.count>20000) continue;
            CLLocationCoordinate2D *coords=(CLLocationCoordinate2D *)calloc(part.count,sizeof(CLLocationCoordinate2D));
            if (!coords) continue;
            for (NSUInteger i=0;i<part.count;i++) coords[i]=[part[i] MKCoordinateValue];
            MKPolyline *line=[MKPolyline polylineWithCoordinates:coords count:part.count];
            free(coords);
            [self.map addOverlay:line level:MKOverlayLevelAboveRoads];
            rect=MKMapRectIsNull(rect) ? line.boundingMapRect : MKMapRectUnion(rect,line.boundingMapRect);
        }
    }
    if (!MKMapRectIsNull(rect))
        [self.map setVisibleMapRect:rect edgePadding:UIEdgeInsetsMake(100,35,205,35) animated:YES];
    self.headline.text=item[@"title"];
    self.status.text=[NSString stringWithFormat:@"%.2f km · %@",
        [item[@"length"] doubleValue]/1000.0,item[@"source"]];
    if (self.expanded) [self toggleSheet];
    if (apple && item[@"destination"]) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Walking route ready"
            message:@"The orange line follows real Apple walking directions. This is an out-and-back walk, not a Strava suggested route."
            preferredStyle:UIAlertControllerStyleActionSheet];
        [alert addAction:[UIAlertAction actionWithTitle:@"Open walking directions in Maps"
           style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
               [MKMapItem openMapsWithItems:@[self.startItem,item[@"destination"]]
                 launchOptions:@{MKLaunchOptionsDirectionsModeKey:MKLaunchOptionsDirectionsModeWalking}];
           }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"View on map"
            style:UIAlertActionStyleCancel handler:nil]];
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView=self.sheet;
            alert.popoverPresentationController.sourceRect=CGRectMake(20,10,50,30);
        }
        [self presentViewController:alert animated:YES completion:nil];
    }
}
- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    if ([overlay isKindOfClass:[MKPolyline class]]) {
        MKPolylineRenderer *render=[[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay];
        render.strokeColor=UIColor.systemOrangeColor;
        render.lineWidth=5;
        return render;
    }
    return [[MKOverlayRenderer alloc] initWithOverlay:overlay];
}
@end

extern "C" void SSCShowNearbyWalksFromItem(UIViewController *presenter, MKMapItem *item) {
    if (!presenter) return;
    SSCNearbyWalks *screen=[SSCNearbyWalks new];
    screen.chosenPlace=item;
    if (presenter.navigationController) {
        [presenter.navigationController pushViewController:screen animated:YES];
    } else {
        UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:screen];
        nav.modalPresentationStyle=UIModalPresentationFullScreen;
        screen.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]
          initWithBarButtonSystemItem:UIBarButtonSystemItemDone
          target:nav action:@selector(dismissViewControllerAnimated:completion:)];
        // Done is installed below using a simple block-free target.
        [presenter presentViewController:nav animated:YES completion:nil];
    }
}
extern "C" void SSCShowNearbyWalks(UIViewController *presenter) {
    SSCShowNearbyWalksFromItem(presenter,nil);
}
