#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <SafariServices/SafariServices.h>
#import <math.h>

// Local preview of geometry already delivered in SuggestedRoutes GraphQL.
// There is no entitlement mutation, GraphQL replay, network proxy or bypass.
static NSArray<NSDictionary *> *sRoutePreviews;

static id RValue(id source, NSString *key) {
    return [source isKindOfClass:[NSDictionary class]] ? [(NSDictionary *)source objectForKey:key] : nil;
}
static NSURL *RPublicURL(id raw) {
    if (![raw isKindOfClass:[NSString class]] || [raw length]>2048) return nil;
    NSURLComponents *c=[NSURLComponents componentsWithString:raw];
    NSString *host=c.host.lowercaseString ?: @"";
    NSString *path=c.path.lowercaseString ?: @"";
    if (![c.scheme.lowercaseString isEqualToString:@"https"] ||
        !([host isEqualToString:@"strava.com"] || [host hasSuffix:@".strava.com"]) ||
        ![path containsString:@"/routes/"]) return nil;
    return c.URL;
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
    NSUInteger validLinks=0, invalidLinks=0, lines=0, missing=0;
    for (id node in (NSArray *)nodes) {
        if (![node isKindOfClass:[NSDictionary class]]) continue;
        NSURL *url=RPublicURL(RValue(node,@"routeUrl"));
        if (url) validLinks++;
        else if (RValue(node,@"routeUrl")) invalidLinks++;
        else missing++;
        NSArray *segments=RSegments(node);
        if (segments.count) lines++;
        if (!segments.count && !url) continue;
        id title=RValue(node,@"title");
        if (![title isKindOfClass:[NSString class]] || ![title length])
            title=@"Suggested route";
        if ([title length]>90) title=[title substringToIndex:90];
        id length=RValue(node,@"length");
        NSNumber *metres=([length isKindOfClass:[NSNumber class]] &&
          [length doubleValue]>=0 && [length doubleValue]<1000000) ? length : @0;
        [candidates addObject:@{@"title":title, @"length":metres,
          @"segments":segments ?: @[],@"url":url ?: [NSNull null]}];
        if (candidates.count>=40) break;
    }
    if (logger) logger([NSString stringWithFormat:
       @"ROUTE_PREVIEW_SCAN nodes=%lu geometry=%lu publicLinks=%lu unrecognisedLinks=%lu missingLinks=%lu accepted=%lu",
       (unsigned long)[(NSArray *)nodes count],(unsigned long)lines,
       (unsigned long)validLinks,(unsigned long)invalidLinks,(unsigned long)missing,
       (unsigned long)candidates.count]);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (candidates.count) sRoutePreviews=[candidates copy];
    });
}
extern "C" NSUInteger SSCSharedRoutesCount(void) {
    return sRoutePreviews.count;
}
@interface SRoutePreview : UIViewController <MKMapViewDelegate>
@property(nonatomic,strong) NSDictionary *route;
@property(nonatomic,strong) MKMapView *map;
@end
@implementation SRoutePreview
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.title=@"Route preview";
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
          edgePadding:UIEdgeInsetsMake(95,28,120,28) animated:NO];
    }
    UILabel *heading=[[UILabel alloc] initWithFrame:CGRectMake(12,12,
       self.view.bounds.size.width-24,60)];
    heading.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    heading.backgroundColor=[UIColor colorWithWhite:1 alpha:0.95];
    heading.textColor=UIColor.blackColor;
    heading.layer.cornerRadius=9;
    heading.layer.masksToBounds=YES;
    heading.numberOfLines=2;
    heading.textAlignment=NSTextAlignmentCenter;
    heading.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    heading.text=[NSString stringWithFormat:@"%@\n%.2f km (Strava route data)",
        self.route[@"title"],[self.route[@"length"] doubleValue]/1000.0];
    [self.view addSubview:heading];
    // This viewer never downloads routes, launches navigation or fakes a trial.
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    if ([overlay isKindOfClass:[MKPolyline class]]) {
        MKPolylineRenderer *r=[[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay];
        r.strokeColor=UIColor.systemOrangeColor;
        r.lineWidth=5;
        return r;
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
       parts.count ? @"map preview" : @"public web link"];
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    NSDictionary *item=self.routes[path.row];
    if ([item[@"segments"] count]) {
        SRoutePreview *viewer=[SRoutePreview new];
        viewer.route=item;
        UINavigationController *nav=[[UINavigationController alloc]
          initWithRootViewController:viewer];
        nav.modalPresentationStyle=UIModalPresentationFullScreen;
        [self presentViewController:nav animated:YES completion:nil];
        return;
    }
    NSURL *url=item[@"url"];
    if ([url isKindOfClass:[NSURL class]]) {
        SFSafariViewController *browser=[[SFSafariViewController alloc] initWithURL:url];
        [self presentViewController:browser animated:YES completion:nil];
    }
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
