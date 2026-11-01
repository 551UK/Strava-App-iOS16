#import <UIKit/UIKit.h>
#import <SafariServices/SafariServices.h>
#import <Foundation/Foundation.h>

// Displays only real public/shared URLs already present in Strava's own
// SuggestedRoutes response. No entitlement changes or server request rewriting.
static NSArray<NSDictionary *> *sPublicRoutes;

static NSURL *ValidatedPublicRouteURL(NSString *raw) {
    if (![raw isKindOfClass:[NSString class]] || raw.length>2048) return nil;
    NSURLComponents *c=[NSURLComponents componentsWithString:raw];
    NSString *host=c.host.lowercaseString ?: @"";
    if (![c.scheme.lowercaseString isEqualToString:@"https"]) return nil;
    if (![host isEqualToString:@"strava.com"] && ![host hasSuffix:@".strava.com"]) return nil;
    NSString *path=c.path.lowercaseString ?: @"";
    if (![path containsString:@"/routes/"]) return nil;
    if (!c.URL) return nil;
    return c.URL;
}
extern "C" void SSCSharedRoutesCaptureJSON(id obj, void (*logger)(NSString *)) {
    if (![obj isKindOfClass:[NSDictionary class]]) return;
    id data=[obj objectForKey:@"data"];
    if (![data isKindOfClass:[NSDictionary class]]) return;
    id source=[data objectForKey:@"suggestedRoutesBySourceGeo"];
    if (![source isKindOfClass:[NSDictionary class]]) return;
    id routes=[source objectForKey:@"routes"];
    if (![routes isKindOfClass:[NSDictionary class]]) return;
    id nodes=[routes objectForKey:@"nodes"];
    if (![nodes isKindOfClass:[NSArray class]]) return;
    NSMutableArray *arr=[NSMutableArray array];
    NSMutableSet *seen=[NSMutableSet set];
    NSUInteger missing=0, rejected=0, valid=0;

    for (id item in (NSArray *)nodes) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *raw=[item objectForKey:@"routeUrl"];
        NSURL *url=ValidatedPublicRouteURL(raw);
        if (![raw isKindOfClass:[NSString class]] || !raw.length) missing++;
        else if (!url) rejected++;
        else valid++;
        if (!url || [seen containsObject:url.absoluteString]) continue;
        NSString *title=[item objectForKey:@"title"];
        if (![title isKindOfClass:[NSString class]] || !title.length) title=@"Untitled route";
        if (title.length>90) title=[title substringToIndex:90];
        NSNumber *distance=[item objectForKey:@"length"];
        NSString *subtitle=@"Public route link";
        if ([distance isKindOfClass:[NSNumber class]] && distance.doubleValue>=0 &&
            distance.doubleValue<1000000)
            subtitle=[NSString stringWithFormat:@"%.2f km",distance.doubleValue/1000.0];
        [arr addObject:@{@"url":url,@"title":title,@"subtitle":subtitle}];
        [seen addObject:url.absoluteString];
        if (arr.count>=60) break;
    }
    // Counts are privacy-safe: no route titles/URLs are written to the log.
    if (logger) logger([NSString stringWithFormat:
        @"PUBLIC_ROUTE_SCAN nodes=%lu valid=%lu missing=%lu rejected=%lu",
        (unsigned long)[(NSArray *)nodes count],(unsigned long)valid,
        (unsigned long)missing,(unsigned long)rejected]);
    dispatch_async(dispatch_get_main_queue(), ^{
        // Reuse the latest complete response (5 or 15 routes); preserve data
        // if a paginated request temporarily returns an empty page.
        if (arr.count) sPublicRoutes=[arr copy];
        NSLog(@"[StravaSearch16] Public-route URLs available: %lu",
            (unsigned long)arr.count);
    });
}
extern "C" NSUInteger SSCSharedRoutesCount(void) {
    return sPublicRoutes.count;
}
@interface SSCSharedRouteList : UITableViewController
@property(nonatomic,copy) NSArray<NSDictionary *> *routes;
@end
@implementation SSCSharedRouteList
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"Shared route links";
    self.tableView.rowHeight=64;
    self.tableView.tableFooterView=[UIView new];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]
      initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self
      action:@selector(done)];
    UILabel *footer=[UILabel new];
    footer.numberOfLines=0;
    footer.font=[UIFont systemFontOfSize:13];
    footer.textColor=UIColor.secondaryLabelColor;
    footer.textAlignment=NSTextAlignmentCenter;
    footer.text=@"These links come directly from Strava's public-route response. Public pages may open without a subscription; subscriber-only tools remain restricted.";
    footer.frame=CGRectMake(10,0,300,90);
    self.tableView.tableHeaderView=footer;
}
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.routes.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"shared"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
      reuseIdentifier:@"shared"];
    NSDictionary *route=self.routes[path.row];
    cell.textLabel.text=route[@"title"];
    cell.detailTextLabel.text=route[@"subtitle"];
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    NSURL *url=self.routes[path.row][@"url"];
    if (!ValidatedPublicRouteURL(url.absoluteString)) return;
    SFSafariViewController *browser=[[SFSafariViewController alloc] initWithURL:url];
    [self presentViewController:browser animated:YES completion:nil];
}
@end
extern "C" void SSCSharedRoutesShow(UIViewController *presenter) {
    if (!presenter || !sPublicRoutes.count) return;
    SSCSharedRouteList *list=[SSCSharedRouteList new];
    list.routes=[sPublicRoutes copy];
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:list];
    nav.modalPresentationStyle=UIModalPresentationFullScreen;
    [presenter presentViewController:nav animated:YES completion:nil];
}
