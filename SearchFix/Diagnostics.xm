#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <substrate.h>

// Private local diagnostics; never save headers, cookies, tokens,
// raw URL paths/queries, request/response bodies, coordinates or search text.
// GraphQL JSON is inspected only for operation names and safe error codes.
static dispatch_queue_t SLogQueue;
static NSString *SLogPath;
static NSMutableDictionary *STasks; // Only within the Strava process, main queue.
static UIButton *SShareButton;
static BOOL SErrorVisible=NO;
static CFAbsoluteTime SLastError=0;
static CFAbsoluteTime SLastScreen=0;

static void SLog(NSString *entry) {
    if (!SLogQueue || !SLogPath || !entry.length) return;
    NSString *safe=[entry stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    safe=[safe stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    NSString *line=[NSString stringWithFormat:@"[%@] %@\n",
      [[NSDate date] descriptionWithLocale:[NSLocale localeWithLocaleIdentifier:@"en_GB"]],safe];
    dispatch_async(SLogQueue, ^{
        @autoreleasepool {
            NSFileManager *fm=[NSFileManager defaultManager];
            NSDictionary *attrs=[fm attributesOfItemAtPath:SLogPath error:nil];
            if ([attrs fileSize]>1024*1024) {
                // Rotate one 1 MB file; avoids unlimited accumulation.
                NSString *previous=[SLogPath stringByAppendingString:@".previous"];
                [fm removeItemAtPath:previous error:nil];
                [fm moveItemAtPath:SLogPath toPath:previous error:nil];
            }
            NSData *data=[line dataUsingEncoding:NSUTF8StringEncoding];
            if (![fm fileExistsAtPath:SLogPath]) [fm createFileAtPath:SLogPath contents:data attributes:nil];
            else {
                NSFileHandle *f=[NSFileHandle fileHandleForWritingAtPath:SLogPath];
                @try { [f seekToEndOfFile]; [f writeData:data]; }
                @catch (NSException *e) {}
                @finally { [f closeFile]; }
            }
        }
    });
}

static NSString *SRequestCategory(NSURL *url) {
    if (!url) return @"unknown";
    NSString *host=[url.host lowercaseString] ?: @"";
    if ([host isEqualToString:@"graphql.strava.com"]) return @"graphql";
    NSString *path=[url.path lowercaseString] ?: @"";
    if ([path containsString:@"graphql"]) return @"graphql";
    if ([path containsString:@"geocod"] || [path containsString:@"autocomplete"] ||
        [path containsString:@"searchbox"] || [path containsString:@"suggest"] ||
        [path containsString:@"search"]) return @"search";
    if ([path containsString:@"checkout"] || [path containsString:@"subscription"] ||
        [path containsString:@"purchase"]) return @"checkout";
    if ([path containsString:@"route"]) return @"route";
    if ([path containsString:@"map"] || [path containsString:@"tile"]) return @"maps";
    if ([path containsString:@"clientconfig"] || [path containsString:@"feature"]) return @"configuration";
    if ([path containsString:@"activity"]) return @"activity";
    return @"other";
}
static NSString *SRequestLabel(NSURL *url) {
    if (!url) return @"unknown";
    // Explicitly omit URL paths and query strings; routes and search keywords
    // can contain personally identifiable location/route data.
    NSString *host=[url.host lowercaseString] ?: @"unknown";
    if (host.length>100) host=[host substringToIndex:100];
    return [NSString stringWithFormat:@"host=%@ category=%@",host,SRequestCategory(url)];
}
static NSString *SGraphQLOperation(NSURLRequest *request) {
    if (![SRequestCategory(request.URL) isEqualToString:@"graphql"]) return @"none";
    NSData *body=request.HTTPBody;
    if (!body || body.length>262144) return @"unknown";
    id obj=[NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return @"unknown";
    id value=[(NSDictionary *)obj objectForKey:@"operationName"];
    if (![value isKindOfClass:[NSString class]]) return @"unknown";
    NSString *name=(NSString *)value;
    if (!name.length || name.length>90) return @"unknown";
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"];
    if ([name rangeOfCharacterFromSet:[allowed invertedSet]].location!=NSNotFound)
        return @"unknown";
    return name;
}
static void SInspectGraphQLResponse(NSURL *url,NSData *data) {
    if (![SRequestCategory(url) isEqualToString:@"graphql"] ||
        !data || data.length>1048576) return;
    id obj=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return;
    id list=[(NSDictionary *)obj objectForKey:@"errors"];
    if (![list isKindOfClass:[NSArray class]] || ![(NSArray *)list count]) return;
    NSMutableOrderedSet *codes=[NSMutableOrderedSet orderedSet];
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    for (id item in (NSArray *)list) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        id ext=[(NSDictionary *)item objectForKey:@"extensions"];
        id code=[ext isKindOfClass:[NSDictionary class]] ?
            [(NSDictionary *)ext objectForKey:@"code"] : nil;
        if (![code isKindOfClass:[NSString class]]) continue;
        NSString *str=(NSString *)code;
        if (str.length>0 && str.length<=50 &&
            [str rangeOfCharacterFromSet:[allowed invertedSet]].location==NSNotFound)
            [codes addObject:str];
    }
    SLog([NSString stringWithFormat:@"GRAPHQL_ERRORS count=%lu codes=%@",
          (unsigned long)[(NSArray *)list count],
          codes.count ? [codes.array componentsJoinedByString:@","] : @"not-provided"]);
}
static void SFinish(NSURL *url, NSURLResponse *response, NSError *error) {
    NSInteger status=[response isKindOfClass:[NSHTTPURLResponse class]] ?
       ((NSHTTPURLResponse *)response).statusCode : 0;
    NSString *mime=response.MIMEType ?: @"unknown";
    if (mime.length>48) mime=@"unknown";
    NSCharacterSet *mimeAllowed=[NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.+/-"];
    if ([mime rangeOfCharacterFromSet:[mimeAllowed invertedSet]].location!=NSNotFound)
        mime=@"unknown";
    if (error || status>=300 || status==0) {
        SLog([NSString stringWithFormat:
            @"HTTP_FINISH %@ status=%ld mime=%@ errorDomain=%@ errorCode=%ld",
            SRequestLabel(url),(long)status,mime,
            error.domain ?: @"none",(long)error.code]);
    } else {
        NSString *host=[url.host lowercaseString] ?: @"";
        if ([host containsString:@"strava.com"] ||
            [SRequestCategory(url) isEqualToString:@"graphql"])
            SLog([NSString stringWithFormat:@"HTTP_OK %@ status=%ld mime=%@",
                SRequestLabel(url),(long)status,mime]);
    }
}
static UIWindow *SWindow(void) {
    UIWindow *first=nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        if (scene.activationState!=UISceneActivationStateForegroundActive &&
            scene.activationState!=UISceneActivationStateForegroundInactive) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.hidden || w.alpha<0.05 || w.windowLevel>UIWindowLevelAlert) continue;
            if (w.isKeyWindow) return w;
            if (!first) first=w;
        }
    }
    return first;
}
static UIViewController *STop(UIViewController *vc) {
    if (!vc) return nil;
    for (int i=0;i<12;i++) {
        UIViewController *next=vc.presentedViewController;
        if (!next && [vc isKindOfClass:[UINavigationController class]])
            next=((UINavigationController *)vc).visibleViewController;
        if (!next && [vc isKindOfClass:[UITabBarController class]])
            next=((UITabBarController *)vc).selectedViewController;
        if (!next || next==vc) break;
        vc=next;
    }
    return vc;
}
static BOOL SHasRetry(UIView *view, int depth, int *count) {
    if (!view || view.hidden || view.alpha<0.01 || depth>25 || ++*count>2500) return NO;
    NSString *title=nil;
    if ([view isKindOfClass:[UILabel class]]) title=((UILabel *)view).text;
    else if ([view isKindOfClass:[UIButton class]]) title=((UIButton *)view).currentTitle;
    if (!title.length) title=view.accessibilityLabel;
    if ([title isKindOfClass:[NSString class]] &&
        [title localizedCaseInsensitiveContainsString:@"Try Again"]) return YES;
    for (UIView *child in view.subviews)
        if (SHasRetry(child,depth+1,count)) return YES;
    return NO;
}
static NSString *STaskKey(NSURLSessionTask *task) {
    return [NSString stringWithFormat:@"%p",task];
}

@interface SSDiagnostics : NSObject
- (void)tick:(NSTimer *)timer;
- (void)share:(id)sender;
@end
static SSDiagnostics *SDiagnostics;
@implementation SSDiagnostics
- (void)share:(id)sender {
    UIWindow *window=SWindow();
    UIViewController *top=STop(window.rootViewController);
    if (!top) return;
    SLog(@"SHARE_SNAPSHOT_BEGIN");
    CFAbsoluteTime now=CFAbsoluteTimeGetCurrent();
    unsigned int count=0;
    for (NSString *key in [STasks allKeys]) {
        NSDictionary *record=STasks[key];
        NSURLSessionTask *task=record[@"task"];
        if (!task) continue;
        if (++count>60) break;
        NSURLRequest *request=task.currentRequest ?: task.originalRequest;
        NSInteger status=[task.response isKindOfClass:[NSHTTPURLResponse class]] ?
            [(NSHTTPURLResponse *)task.response statusCode] : 0;
        SLog([NSString stringWithFormat:@"TASK_SNAPSHOT %@ method=%@ op=%@ state=%ld age=%.1f status=%ld",
             SRequestLabel(request.URL),request.HTTPMethod ?: @"GET",
             SGraphQLOperation(request),(long)task.state,
             now-[record[@"created"] doubleValue],(long)status]);
    }
    SLog(@"SHARE_SNAPSHOT_END");
    dispatch_sync(SLogQueue, ^{});
    NSString *path=SLogPath;
    BOOL hasFile=[[NSFileManager defaultManager] fileExistsAtPath:path];
    if (!hasFile) {
        SLog(@"MANUAL_SHARE requested");
        dispatch_sync(SLogQueue, ^{});
    }
    NSURL *file=[NSURL fileURLWithPath:path];
    UIActivityViewController *share=[[UIActivityViewController alloc]
      initWithActivityItems:@[file] applicationActivities:nil];
    if (share.popoverPresentationController) {
        share.popoverPresentationController.sourceView=SShareButton ?: window;
        share.popoverPresentationController.sourceRect=SShareButton ?
            SShareButton.bounds : CGRectMake(0,0,1,1);
    }
    [top presentViewController:share animated:YES completion:nil];
}
- (void)tick:(NSTimer *)timer {
    if ([UIApplication sharedApplication].applicationState==UIApplicationStateBackground) return;
    CFAbsoluteTime now=CFAbsoluteTimeGetCurrent();
    // Track session delegate tasks too: completed tasks expose HTTP status and
    // transport NSError even when the app doesn't use completion blocks.
    for (NSString *key in [STasks allKeys]) {
        NSDictionary *rec=STasks[key];
        NSURLSessionTask *task=rec[@"task"];
        CFAbsoluteTime started=[rec[@"created"] doubleValue];
        if (task.state==NSURLSessionTaskStateCompleted || now-started>90) {
            SFinish(task.originalRequest.URL ?: task.currentRequest.URL,
                    task.response,task.error);
            [STasks removeObjectForKey:key];
        }
    }
    UIWindow *window=SWindow();
    int count=0;
    BOOL retry=window && SHasRetry(window,0,&count);
    if (retry && (!SErrorVisible || now-SLastError>8)) {
        SLastError=now;
        UIViewController *top=STop(window.rootViewController);
        SLog([NSString stringWithFormat:@"UI_TRY_AGAIN controller=%@ monitoredTasks=%lu",
              NSStringFromClass(top.class) ?: @"unknown",
              (unsigned long)STasks.count]);
    }
    SErrorVisible=retry;
    // Always show the small share button: WebKit/SwiftUI errors sometimes
    // don't expose "Try Again" as a native UILabel/UIButton to inspect.
    if (window) {
        if (!SShareButton) {
            SShareButton=[UIButton buttonWithType:UIButtonTypeSystem];
            SShareButton.backgroundColor=[UIColor colorWithRed:1 green:0.96 blue:0.92 alpha:0.98];
            SShareButton.tintColor=[UIColor colorWithRed:0.93 green:0.24 blue:0.03 alpha:1];
            SShareButton.layer.cornerRadius=11;
            SShareButton.layer.borderWidth=1;
            SShareButton.layer.borderColor=[UIColor colorWithRed:1 green:0.45 blue:0.2 alpha:1].CGColor;
            SShareButton.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
            [SShareButton addTarget:self action:@selector(share:) forControlEvents:UIControlEventTouchUpInside];
        }
        if (retry) {
            [SShareButton setTitle:@"Share Diagnostics" forState:UIControlStateNormal];
            SShareButton.frame=CGRectMake(18,MAX(window.safeAreaInsets.top+14,85),155,37);
        } else {
            [SShareButton setTitle:@"Share Log" forState:UIControlStateNormal];
            SShareButton.frame=CGRectMake(MAX(18,window.bounds.size.width-118),
                MAX(80,window.bounds.size.height-window.safeAreaInsets.bottom-168),102,35);
        }
        if (SShareButton.superview!=window) [window addSubview:SShareButton];
        [window bringSubviewToFront:SShareButton];
        SShareButton.hidden=NO;
    } else if (SShareButton) {
        SShareButton.hidden=YES;
    }
}
@end

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
      completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))completion {
    NSURL *url=request.URL;
    void (^wrapped)(NSData *,NSURLResponse *,NSError *) =
    ^(NSData *data,NSURLResponse *response,NSError *error) {
        SFinish(url,response,error);
        SInspectGraphQLResponse(url,data);
        if (completion) completion(data,response,error);
    };
    return %orig(request,wrapped);
}
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
      completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))completion {
    void (^wrapped)(NSData *,NSURLResponse *,NSError *) =
    ^(NSData *data,NSURLResponse *response,NSError *error) {
        SFinish(url,response,error);
        if (completion) completion(data,response,error);
    };
    return %orig(url,wrapped);
}
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
      completionHandler:(void (^)(NSURL *,NSURLResponse *,NSError *))completion {
    NSURL *url=request.URL;
    void (^wrapped)(NSURL *,NSURLResponse *,NSError *) =
    ^(NSURL *file,NSURLResponse *response,NSError *error) {
        SFinish(url,response,error);
        if (completion) completion(file,response,error);
    };
    return %orig(request,wrapped);
}
%end
%hook NSURLSessionTask
- (void)resume {
    NSURL *url=self.originalRequest.URL ?: self.currentRequest.URL;
    if (url) {
        NSURLRequest *request=self.originalRequest ?: self.currentRequest;
        SLog([NSString stringWithFormat:@"HTTP_START %@ method=%@ op=%@",
            SRequestLabel(url),request.HTTPMethod ?: @"GET",SGraphQLOperation(request)]);
        NSURLSessionTask *task=self;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (STasks.count>=140) return;
            NSString *key=STaskKey(task);
            if (!STasks[key]) {
                STasks[key]=@{@"task":task,@"created":@(CFAbsoluteTimeGetCurrent())};
            }
        });
    }
    %orig;
}
%end
%hook WKWebView
- (WKNavigation *)loadRequest:(NSURLRequest *)request {
    SLog([NSString stringWithFormat:@"WEBVIEW_LOAD %@",SRequestLabel(request.URL)]);
    return %orig;
}
%end
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString *name=NSStringFromClass([self class]);
    if (!name || (SLastScreen && CFAbsoluteTimeGetCurrent()-SLastScreen<0.15)) return;
    SLastScreen=CFAbsoluteTimeGetCurrent();
    // Type names only, no user-entered text or route names.
    SLog([NSString stringWithFormat:@"UI_CONTROLLER %@",name]);
}
%end

__attribute__((constructor))
static void SetupStravaSearchDiagnostics(void) {
    @autoreleasepool {
        if (![[[NSBundle mainBundle] bundleIdentifier]
              isEqualToString:@"com.strava.stravaride"]) return;
        NSString *folder=[NSHomeDirectory() stringByAppendingPathComponent:
                         @"Library/Caches/StravaSearch16"];
        [[NSFileManager defaultManager] createDirectoryAtPath:folder
                  withIntermediateDirectories:YES attributes:nil error:nil];
        SLogPath=[folder stringByAppendingPathComponent:@"diagnostics.txt"];
        SLogQueue=dispatch_queue_create("uk.551.stravasearch.diagnostics", DISPATCH_QUEUE_SERIAL);
        SLog(@"===== StravaSearch16 diagnostics 0.3.0 started; no credentials/URL queries recorded =====");
        %init;
        dispatch_async(dispatch_get_main_queue(), ^{
            STasks=[NSMutableDictionary new];
            SDiagnostics=[SSDiagnostics new];
            NSTimer *timer=[NSTimer timerWithTimeInterval:0.8
                  target:SDiagnostics selector:@selector(tick:) userInfo:nil repeats:YES];
            [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
            SLog(@"DIAG_TIMER ready");
        });
    }
}
