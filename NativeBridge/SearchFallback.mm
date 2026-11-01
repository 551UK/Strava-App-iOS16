#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <objc/runtime.h>


// Standalone iOS 16 Maps search fallback for Strava 422.0.1.
// Only replaces a search screen after its visible "Try Again" failure.
// Does not change StravaCompat, login, tokens or Strava network requests.

static BOOL sArmed = NO;
static BOOL sFallbackVisible = NO;
// Keep fallback dormant during error diagnosis so its overlay cannot hide failures.

static CFAbsoluteTime sArmedAt = 0;
@class SSCPlacePreview;

@interface SSCSearchController : UITableViewController <UISearchBarDelegate, MKLocalSearchCompleterDelegate>
@property(nonatomic,strong) MKLocalSearchCompleter *completer;
@property(nonatomic,strong) NSArray<MKLocalSearchCompletion *> *results;
@property(nonatomic,strong) UISearchBar *searchBar;
@end

@interface SSCPlacePreview : UIViewController
@property(nonatomic,strong) MKMapItem *item;
@property(nonatomic,strong) MKMapView *map;
- (instancetype)initWithItem:(MKMapItem *)item;
@end

@implementation SSCPlacePreview
- (instancetype)initWithItem:(MKMapItem *)item {
    if ((self=[super init])) self.item=item;
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.item.name ?: @"Location";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    MKMapView *map = [[MKMapView alloc] initWithFrame:CGRectZero];
    map.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:map];
    [NSLayoutConstraint activateConstraints:@[
      [map.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
      [map.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
      [map.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
      [map.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
    self.map=map;
    CLLocationCoordinate2D coord=self.item.placemark.coordinate;
    MKPointAnnotation *pin=[MKPointAnnotation new];
    pin.coordinate=coord;
    pin.title=self.item.name;
    [map addAnnotation:pin];
    [map setRegion:MKCoordinateRegionMakeWithDistance(coord,1600,1600) animated:NO];
    UIBarButtonItem *apple=[[UIBarButtonItem alloc] initWithTitle:@"Apple Maps"
      style:UIBarButtonItemStylePlain target:self action:@selector(openMaps)];
    UIBarButtonItem *copy=[[UIBarButtonItem alloc] initWithTitle:@"Copy Coordinates"
      style:UIBarButtonItemStylePlain target:self action:@selector(copyCoordinates)];
    self.navigationItem.rightBarButtonItems=@[apple,copy];
}
- (void)openMaps {
    [self.item openInMapsWithLaunchOptions:nil];
}
- (void)copyCoordinates {
    CLLocationCoordinate2D c=self.item.placemark.coordinate;
    [UIPasteboard generalPasteboard].string=
      [NSString stringWithFormat:@"%.6f, %.6f",c.latitude,c.longitude];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Coordinates copied"
      message:@"The location is available on the clipboard."
      preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

@implementation SSCSearchController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"Search locations";
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]
      initWithBarButtonSystemItem:UIBarButtonSystemItemDone
      target:self action:@selector(closeSearch)];
    self.searchBar=[[UISearchBar alloc] initWithFrame:CGRectMake(0,0,300,58)];
    self.searchBar.placeholder=@"Search locations";
    self.searchBar.autocorrectionType=UITextAutocorrectionTypeNo;
    self.searchBar.delegate=self;
    self.tableView.tableHeaderView=self.searchBar;
    self.tableView.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;
    self.results=@[];
    self.completer=[MKLocalSearchCompleter new];
    self.completer.delegate=self;
    self.completer.resultTypes=MKLocalSearchCompleterResultTypeAddress|MKLocalSearchCompleterResultTypePointOfInterest;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (![self.searchBar isFirstResponder]) [self.searchBar becomeFirstResponder];
}
- (void)closeSearch {
    [self dismissViewControllerAnimated:YES completion:^{
       sFallbackVisible=NO;
       sArmed=NO;
    }];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    self.completer.queryFragment=text ?: @"";
    if (!text.length) {
        self.results=@[];
        [self.tableView reloadData];
    }
}
- (void)completerDidUpdateResults:(MKLocalSearchCompleter *)completer {
    self.results=completer.results ?: @[];
    [self.tableView reloadData];
}
- (void)completer:(MKLocalSearchCompleter *)completer didFailWithError:(NSError *)error {
    NSLog(@"[StravaSearch16] MapKit autocomplete error domain=%@ code=%ld",
          error.domain,(long)error.code);
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.results.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"location"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
      reuseIdentifier:@"location"];
    MKLocalSearchCompletion *item=self.results[path.row];
    cell.textLabel.text=item.title;
    cell.detailTextLabel.text=item.subtitle;
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.row >= self.results.count) return;
    MKLocalSearchCompletion *selected=self.results[path.row];
    MKLocalSearchRequest *request=[[MKLocalSearchRequest alloc] initWithCompletion:selected];
    MKLocalSearch *search=[[MKLocalSearch alloc] initWithRequest:request];
    __weak typeof(self) weakSelf=self;
    [search startWithCompletionHandler:^(MKLocalSearchResponse *response,NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf=weakSelf;
            if (!strongSelf) return;
            MKMapItem *item=response.mapItems.firstObject;
            if (item) {
                [strongSelf.searchBar resignFirstResponder];
                [strongSelf.navigationController pushViewController:
                  [[SSCPlacePreview alloc] initWithItem:item] animated:YES];
            } else {
                NSString *reason=[NSString stringWithFormat:@"MapKit could not load the location (%@ %ld).",
                    error.domain ?: @"unknown",(long)error.code];
                UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Search failed"
                  message:reason preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [strongSelf presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}
@end


static UIWindow *SSCFrontWindow(void) {
    UIApplication *app=[UIApplication sharedApplication];
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows)
            if (w.isKeyWindow && w.windowLevel==UIWindowLevelNormal) return w;
    }
    return nil;
}
static BOOL SSCIsSearchTouch(UIView *v,UIWindow *win,CGPoint point,int depth) {
    if (!v || v.hidden || v.alpha<0.05 || depth>26) return NO;
    NSString *label=v.accessibilityLabel;
    if ([v isKindOfClass:[UITextField class]]) label=((UITextField *)v).placeholder;
    else if ([v isKindOfClass:[UILabel class]]) label=((UILabel *)v).text;
    else if ([v isKindOfClass:[UIButton class]]) label=((UIButton *)v).currentTitle;
    if ([label localizedCaseInsensitiveContainsString:@"Search locations"]) {
        CGRect box=[v convertRect:v.bounds toView:win];
        if (CGRectContainsPoint(CGRectInset(box,-25,-15),point)) return YES;
    }
    for (UIView *child in v.subviews)
        if (SSCIsSearchTouch(child,win,point,depth+1)) return YES;
    return NO;
}
extern "C" void SSCInspectSearchTouch(UIEvent *event) {
    if (event.type!=UIEventTypeTouches) return;
    UIWindow *win=SSCFrontWindow();
    if (!win) return;
    for (UITouch *touch in event.allTouches) {
        if (touch.phase!=UITouchPhaseEnded || touch.window!=win) continue;
        if (SSCIsSearchTouch(win,win,[touch locationInView:win],0)) {
            sArmed=YES;
            sArmedAt=CFAbsoluteTimeGetCurrent();
            return;
        }
    }
}
extern "C" BOOL SSCWasRecentSearchTap(void) {
    return sArmed && CFAbsoluteTimeGetCurrent()-sArmedAt<5.0;
}
extern "C" void SSCShowSearchScreen(UIViewController *presenter) {
    if (!presenter || sFallbackVisible) return;
    sArmed=NO;
    sFallbackVisible=YES;
    UINavigationController *nav=[[UINavigationController alloc]
        initWithRootViewController:[SSCSearchController new]];
    nav.modalPresentationStyle=UIModalPresentationFullScreen;
    [presenter presentViewController:nav animated:YES completion:nil];
}
