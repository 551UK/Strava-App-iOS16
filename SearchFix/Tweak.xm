#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <objc/runtime.h>
#import <substrate.h>

// Standalone iOS 16 Maps search fallback for Strava 422.0.1.
// Only replaces a search screen after its visible "Try Again" failure.
// Does not change StravaCompat, login, tokens or Strava network requests.

static BOOL sArmed = NO;
static BOOL sFallbackVisible = NO;
// Keep fallback dormant during error diagnosis so its overlay cannot hide failures.
static BOOL sEnableFallback = NO;
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

static BOOL IsOurController(UIViewController *controller) {
    if (!controller) return NO;
    if ([controller isKindOfClass:[SSCSearchController class]] ||
        [controller isKindOfClass:[SSCPlacePreview class]]) return YES;
    if ([controller isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav=(UINavigationController *)controller;
        return [nav.viewControllers.firstObject isKindOfClass:[SSCSearchController class]];
    }
    return NO;
}
static UIWindow *ActiveWindow(void) {
    UIApplication *application=[UIApplication sharedApplication];
    UIWindow *fallback=nil;
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.windowLevel != UIWindowLevelNormal) continue;
            if (window.isKeyWindow) return window;
            if (!fallback) fallback=window;
        }
    }
    return fallback;
}
static BOOL ViewHasText(UIView *view,NSString *needle) {
    if (!view || view.hidden || view.alpha<0.05) return NO;
    NSString *candidate=view.accessibilityLabel;
    if ([candidate localizedCaseInsensitiveContainsString:needle]) return YES;
    if ([view isKindOfClass:[UILabel class]]) {
        if ([((UILabel *)view).text localizedCaseInsensitiveContainsString:needle]) return YES;
    }
    if ([view isKindOfClass:[UIButton class]]) {
        if ([((UIButton *)view).currentTitle localizedCaseInsensitiveContainsString:needle]) return YES;
    }
    if ([view isKindOfClass:[UITextField class]]) {
        if ([((UITextField *)view).placeholder localizedCaseInsensitiveContainsString:needle]) return YES;
    }
    for (UIView *child in view.subviews)
        if (ViewHasText(child,needle)) return YES;
    return NO;
}
static BOOL TouchOnSearch(UIView *view,UIWindow *window,CGPoint pos) {
    if (!view || view.hidden || view.alpha<0.05) return NO;
    NSString *label=nil;
    if ([view isKindOfClass:[UILabel class]]) label=((UILabel *)view).text;
    else if ([view isKindOfClass:[UITextField class]]) label=((UITextField *)view).placeholder;
    else if ([view isKindOfClass:[UIButton class]]) label=((UIButton *)view).currentTitle;
    if (!label.length) label=view.accessibilityLabel;
    if ([label localizedCaseInsensitiveContainsString:@"Search locations"]) {
        CGRect rect=[view convertRect:view.bounds toView:window];
        rect=CGRectInset(rect,-100,-22);
        if (CGRectContainsPoint(rect,pos)) return YES;
    }
    for (UIView *child in view.subviews)
        if (TouchOnSearch(child,window,pos)) return YES;
    return NO;
}
static UIViewController *TopController(UIViewController *controller) {
    if (!controller) return nil;
    while (controller.presentedViewController) controller=controller.presentedViewController;
    if ([controller isKindOfClass:[UINavigationController class]]) {
        UIViewController *inner=((UINavigationController *)controller).visibleViewController;
        if (inner) return TopController(inner);
    }
    if ([controller isKindOfClass:[UITabBarController class]]) {
        UIViewController *inner=((UITabBarController *)controller).selectedViewController;
        if (inner) return TopController(inner);
    }
    return controller;
}
static void CheckSearchFailure(void) {
    if (!sEnableFallback) return;
    if (sFallbackVisible || !sArmed || CFAbsoluteTimeGetCurrent()-sArmedAt>12) return;
    UIWindow *window=ActiveWindow();
    if (!window || !window.rootViewController) return;
    UIViewController *top=TopController(window.rootViewController);
    if (!top || IsOurController(top)) return;
    if (!ViewHasText(window,@"Try Again")) return;

    // The user's exact failure state is a blank Maps search screen with Try Again.
    // Require a recent tap on the Maps "Search locations" control to avoid
    // replacing any unrelated Strava error page.
    sArmed=NO;
    sFallbackVisible=YES;
    SSCSearchController *search=[SSCSearchController new];
    UINavigationController *navigation=[[UINavigationController alloc]
      initWithRootViewController:search];
    navigation.modalPresentationStyle=UIModalPresentationFullScreen;
    NSLog(@"[StravaSearch16] Search screen failed; presenting native MapKit fallback");
    [top presentViewController:navigation animated:YES completion:nil];
}
static void ScheduleFailureChecks(void) {
    const double delays[]={0.15,0.5,1.0,2.0,3.5,5.0};
    for (int i=0;i<6;i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delays[i]*NSEC_PER_SEC)),
          dispatch_get_main_queue(), ^{ CheckSearchFailure(); });
    }
}
%hook UIApplication
- (void)sendEvent:(UIEvent *)event {
    if (event.type==UIEventTypeTouches) {
        for (UITouch *touch in event.allTouches) {
            if (touch.phase!=UITouchPhaseEnded) continue;
            UIWindow *window=touch.window ?: ActiveWindow();
            if (!window) continue;
            CGPoint point=[touch locationInView:window];
            if (TouchOnSearch(window,window,point)) {
                sArmed=YES;
                sArmedAt=CFAbsoluteTimeGetCurrent();
                NSLog(@"[StravaSearch16] Search locations tapped; awaiting screen result");
                ScheduleFailureChecks();
                break;
            }
        }
    }
    %orig;
}
%end
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (sArmed && !sFallbackVisible) ScheduleFailureChecks();
}
%end
%ctor {
    @autoreleasepool {
        if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.strava.stravaride"]) return;
        NSLog(@"[StravaSearch16] Native search fallback installed for Strava 422.0.1");
        %init;
    }
}
