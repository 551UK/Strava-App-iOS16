#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#include <dlfcn.h>
#include <stdint.h>

// Optional, version-only request identity adapter for route/search requests.
extern "C" NSURLRequest *SSCBridgeRequest(NSURLRequest *request, void (*logFn)(NSString *));

// Private local diagnostics; never save headers, cookies, tokens,
// raw URL paths/queries, request/response bodies, coordinates or search text.
// GraphQL JSON is inspected only for operation names and safe error codes.
extern "C" void SSCSharedRoutesCaptureJSON(id obj, void (*logger)(NSString *));
extern "C" NSUInteger SSCSharedRoutesCount(void);
extern "C" void SSCSharedRoutesShow(UIViewController *presenter);
static dispatch_queue_t SLogQueue;
static UIButton *SShareButton;
static UIButton *SRouteButton;
static UIWindow *SHUDWindow;
static BOOL SShowingShare=NO;

// Separate passthrough window stays above Strava's full-screen checkout window.
// Empty HUD space remains touch-transparent; the underlying app still works.
@interface STransparentWindow : UIWindow
@end
@implementation STransparentWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit=[super hitTest:point withEvent:event];
    return (hit==self || hit==self.rootViewController.view) ? nil : hit;
}
@end
static void SPrepareHUD(UIWindow *base) {
    if (!base.windowScene) return;
    if (SHUDWindow && SHUDWindow.windowScene!=base.windowScene) {
        SHUDWindow.hidden=YES;
        SHUDWindow=nil;
        SShareButton=nil;
        SRouteButton=nil;
    }
    if (!SHUDWindow) {
        STransparentWindow *w=[[STransparentWindow alloc] initWithWindowScene:base.windowScene];
        w.frame=base.windowScene.coordinateSpace.bounds;
        w.opaque=NO;
        w.backgroundColor=[UIColor clearColor];
        w.windowLevel=UIWindowLevelAlert+15;
        UIViewController *root=[UIViewController new];
        root.view.backgroundColor=[UIColor clearColor];
        root.view.opaque=NO;
        w.rootViewController=root;
        SHUDWindow=w;
    }
    SHUDWindow.frame=base.windowScene.coordinateSpace.bounds;
    SHUDWindow.hidden=NO;  // intentionally never becomeKeyWindow
}
static NSString *SLogPath;
static NSMutableDictionary *STasks; // Only within the Strava process, main queue.
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
// Static endpoint names only: never emit a request path or an identifier.
static NSString *SEndpoint(NSURL *url) {
    NSString *p=url.path.lowercaseString ?: @"";
    if ([p containsString:@"/search/searchbox/v1/suggest"]) return @"mapbox-suggest";
    if ([p containsString:@"/search/searchbox/v1/retrieve/"]) return @"mapbox-retrieve";
    if ([p containsString:@"/geocoding/v5/mapbox.places/"]) return @"mapbox-v5";
    NSArray *names=@[@"reverse-map-search",@"map-search",@"autocomplete",@"reverse_geocode",@"get_coordinate",@"geocodeearth",@"checkout",@"subscriptions",@"subscription",@"routes",@"search",@"graphql"];
    NSArray *parts=p.pathComponents;
    for (NSString *name in names) if ([parts containsObject:name]) return name;
    return @"unclassified";
}
static NSString *SRequestLabel(NSURL *url) {
    if (!url) return @"unknown";
    // Explicitly omit URL paths and query strings; routes and search keywords
    // can contain personally identifiable location/route data.
    NSString *host=[url.host lowercaseString] ?: @"unknown";
    if (host.length>100) host=[host substringToIndex:100];
    return [NSString stringWithFormat:@"host=%@ category=%@ endpoint=%@",host,SRequestCategory(url),SEndpoint(url)];
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
// Only predefined field names, types, counts and predefined error codes leave memory.
static NSString *SJSONType(id value) {
    if ([value isKindOfClass:[NSDictionary class]]) return @"object";
    if ([value isKindOfClass:[NSArray class]]) return [NSString stringWithFormat:@"array(%lu)",(unsigned long)[value count]];
    if ([value isKindOfClass:[NSString class]]) return @"string";
    if ([value isKindOfClass:[NSNumber class]]) return @"number";
    if (value==[NSNull null]) return @"null";
    return @"absent";
}
static BOOL SBodyRelevant(NSURL *url) {
    return [@[@"search",@"route",@"checkout",@"graphql"] containsObject:SRequestCategory(url)];
}
static void SInspectBody(NSURL *url, NSData *data) {
    if (!SBodyRelevant(url) || !data.length || data.length>1048576) return;
    id obj=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!obj) { SLog([NSString stringWithFormat:@"BODY_SHAPE %@ non-json bytes=%lu",SRequestLabel(url),(unsigned long)data.length]); return; }
    if ([SRequestCategory(url) isEqualToString:@"graphql"]) SSCSharedRoutesCaptureJSON(obj,SLog);
    NSArray *fields=@[@"data",@"errors",@"error",@"message",@"code",@"status",@"features",@"suggestions",@"attribution",@"geocoding",@"routes",@"nodes",@"pageInfo",@"suggestedRoutesBySourceGeo",@"extensions",@"title",@"routeUrl",@"routeDetails",@"routePolylineData",@"legs",@"properties",@"geometry",@"coordinates",@"place_name",@"text",@"mapbox_id",@"name",@"full_address",@"place_formatted",@"location",@"entries",@"products",@"subscription",@"checkout"];
    NSMutableArray *queue=[NSMutableArray arrayWithObject:@{@"value":obj,@"path":@"root",@"depth":@0}];
    NSMutableArray *parts=[NSMutableArray new];
    while (queue.count && parts.count<64) {
        NSDictionary *node=queue.firstObject; [queue removeObjectAtIndex:0];
        id value=node[@"value"]; NSString *path=node[@"path"]; NSInteger depth=[node[@"depth"] integerValue];
        [parts addObject:[NSString stringWithFormat:@"%@:%@",path,SJSONType(value)]];
        if (depth>=5) continue;
        if ([value isKindOfClass:[NSDictionary class]]) {
            for (NSString *key in fields) if (value[key]) [queue addObject:@{@"value":value[key],@"path":[path stringByAppendingFormat:@".%@",key],@"depth":@(depth+1)}];
        } else if ([value isKindOfClass:[NSArray class]] && [value count]) {
            [queue addObject:@{@"value":[value firstObject],@"path":[path stringByAppendingString:@"[]"],@"depth":@(depth+1)}];
        }
    }
    SLog([NSString stringWithFormat:@"BODY_SHAPE %@ %@",SRequestLabel(url),[parts componentsJoinedByString:@" "]]);
    SInspectGraphQLResponse(url,data);
}
static char SBodyKey, SOverflowKey, SDelegateHookKey;
static void SCollectData(NSURLSessionTask *task, NSData *data) {
    if (!SBodyRelevant(task.originalRequest.URL)) return;
    @synchronized(task) {
        if (objc_getAssociatedObject(task,&SOverflowKey)) return;
        NSMutableData *body=objc_getAssociatedObject(task,&SBodyKey);
        if (!body) { body=[NSMutableData new]; objc_setAssociatedObject(task,&SBodyKey,body,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        if (body.length+data.length>1048576) {
            objc_setAssociatedObject(task,&SBodyKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(task,&SOverflowKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else [body appendData:data];
    }
}
static void SCompleteData(NSURLSessionTask *task) {
    NSData *body;
    @synchronized(task) {
        body=[objc_getAssociatedObject(task,&SBodyKey) copy];
        objc_setAssociatedObject(task,&SBodyKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(task,&SOverflowKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    SInspectBody(task.originalRequest.URL,body);
}
static void SInstallDelegate(id delegate) {
    if (!delegate) return;
    @synchronized([NSURLSession class]) {
        Class cls=object_getClass(delegate);
        // Avoid wrapping inherited hooks twice. No delegate replacement/proxy.
        for (Class c=cls;c;c=class_getSuperclass(c)) if (objc_getAssociatedObject(c,&SDelegateHookKey)) return;
        SEL dataSel=@selector(URLSession:dataTask:didReceiveData:);
        SEL doneSel=@selector(URLSession:task:didCompleteWithError:);
        Method dm=class_getInstanceMethod(cls,dataSel), cm=class_getInstanceMethod(cls,doneSel);
        if (!dm || !cm) { SLog(@"DELEGATE_BODY unavailable"); return; }
        // Install an override when the app inherits these methods.
        class_addMethod(cls,dataSel,method_getImplementation(dm),method_getTypeEncoding(dm));
        class_addMethod(cls,doneSel,method_getImplementation(cm),method_getTypeEncoding(cm));
        __block IMP oldData=NULL,oldDone=NULL;
        IMP newData=imp_implementationWithBlock(^(id self,NSURLSession *session,NSURLSessionDataTask *task,NSData *data) {
            SCollectData(task,data);
            ((void(*)(id,SEL,id,id,id))oldData)(self,dataSel,session,task,data);
        });
        IMP newDone=imp_implementationWithBlock(^(id self,NSURLSession *session,NSURLSessionTask *task,NSError *error) {
            SCompleteData(task);
            ((void(*)(id,SEL,id,id,id))oldDone)(self,doneSel,session,task,error);
        });
        MSHookMessageEx(cls,dataSel,newData,&oldData);
        MSHookMessageEx(cls,doneSel,newDone,&oldDone);
        objc_setAssociatedObject(cls,&SDelegateHookKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SLog(@"DELEGATE_BODY installed");
    }
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
- (void)openSharedRoutes:(id)sender;
@end
static SSDiagnostics *SDiagnostics;
@implementation SSDiagnostics
- (void)openSharedRoutes:(id)sender {
    UIWindow *window=SWindow();
    SLog([NSString stringWithFormat:@"USER_ROUTE_PREVIEW_VIEWER count=%lu",
      (unsigned long)SSCSharedRoutesCount()]);
    UIViewController *top=STop(SHUDWindow.rootViewController ?: window.rootViewController);
    if (!top) return;
    if (SSCSharedRoutesCount()) {
        SSCSharedRoutesShow(top);
    } else {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"No route geometry available"
          message:@"The list response does not contain a decodable route line or supported public link. Please share the log so its geometry structure can be checked."
          preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
            style:UIAlertActionStyleDefault handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    }
}
- (void)share:(id)sender {
    UIWindow *window=SWindow();
    UIViewController *top=STop(SHUDWindow.rootViewController ?: window.rootViewController);
    if (!top) return;
    SShowingShare=YES;
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
    share.completionWithItemsHandler=^(UIActivityType activity,BOOL complete,NSArray *items,NSError *error) {
        SShowingShare=NO;
    };
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
    UIWindow *base=SWindow();
    if (!base) return;
    SPrepareHUD(base);
    UIView *surface=SHUDWindow.rootViewController.view;
    CGFloat w=surface.bounds.size.width;
    CGFloat topY=MAX(60,base.safeAreaInsets.top+8);
    if (!SShareButton) {
        SShareButton=[UIButton buttonWithType:UIButtonTypeSystem];
        SShareButton.backgroundColor=[UIColor colorWithRed:1 green:0.96 blue:0.91 alpha:0.98];
        SShareButton.tintColor=[UIColor colorWithRed:0.8 green:0.2 blue:0 alpha:1];
        SShareButton.layer.cornerRadius=10;
        SShareButton.titleLabel.font=[UIFont boldSystemFontOfSize:13];
        [SShareButton setTitle:@"Share Log" forState:UIControlStateNormal];
        [SShareButton addTarget:self action:@selector(share:) forControlEvents:UIControlEventTouchUpInside];
        [surface addSubview:SShareButton];
        SLog(@"HUD_READY share=1");
    }
    SShareButton.frame=CGRectMake(w-120,topY,110,37);
    if (!SRouteButton) {
        SRouteButton=[UIButton buttonWithType:UIButtonTypeSystem];
        SRouteButton.backgroundColor=[UIColor colorWithWhite:1 alpha:0.98];
        SRouteButton.tintColor=UIColor.blackColor;
        SRouteButton.layer.borderWidth=1;
        SRouteButton.layer.borderColor=UIColor.systemOrangeColor.CGColor;
        SRouteButton.layer.cornerRadius=10;
        SRouteButton.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        [SRouteButton addTarget:self action:@selector(openSharedRoutes:)
            forControlEvents:UIControlEventTouchUpInside];
        [surface addSubview:SRouteButton];
        SLog(@"HUD_READY publicRoutes=1");
    }
    NSUInteger available=SSCSharedRoutesCount();
    [SRouteButton setTitle:[NSString stringWithFormat:@"Route previews (%lu)",(unsigned long)available]
        forState:UIControlStateNormal];
    SRouteButton.frame=CGRectMake(10,topY,160,37);
    SShareButton.hidden=SShowingShare;
    SRouteButton.hidden=SShowingShare;
}
@end

%hook NSURLSession
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration delegate:(id)delegate delegateQueue:(NSOperationQueue *)queue {
    SInstallDelegate(delegate);
    return %orig;
}
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
      completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))completion {
    NSURL *url=request.URL;
    void (^wrapped)(NSData *,NSURLResponse *,NSError *) =
    ^(NSData *data,NSURLResponse *response,NSError *error) {
        SFinish(url,response,error);
        SInspectBody(url,data);
        if (completion) completion(data,response,error);
    };
    return %orig(SSCBridgeRequest(request,SLog),wrapped);
}
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
      completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))completion {
    void (^wrapped)(NSData *,NSURLResponse *,NSError *) =
    ^(NSData *data,NSURLResponse *response,NSError *error) {
        SFinish(url,response,error);
        SInspectBody(url,data);
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
    return %orig(SSCBridgeRequest(request,SLog),wrapped);
}
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    return %orig(SSCBridgeRequest(request,SLog));
}
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)body {
    return %orig(SSCBridgeRequest(request,SLog),body);
}
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
    fromData:(NSData *)body
    completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))completion {
    NSURL *url=request.URL;
    void (^wrapped)(NSData *,NSURLResponse *,NSError *)=
      ^(NSData *data,NSURLResponse *response,NSError *error){
        SFinish(url,response,error);
        SInspectGraphQLResponse(url,data);
        SInspectBody(url,data);
        if (completion) completion(data,response,error);
      };
    return %orig(SSCBridgeRequest(request,SLog),body,wrapped);
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
// Capture the precise call site that presents Strava's checkout from a route
// selection. Full account data/URL/coordinates are never inspected or logged.
// Mach-O relative offsets can be located in the supplied decrypted 422 binary.
static NSUInteger sCheckoutPresentCount=0;
static NSString *SVCName(UIViewController *vc) {
    NSString *c=vc ? NSStringFromClass([vc class]) : @"nil";
    if (c.length>180) c=[c substringToIndex:180];
    return c;
}
static void SLogCheckoutPresentation(UIViewController *source,UIViewController *target,BOOL animated) {
    sCheckoutPresentCount++;
    if (sCheckoutPresentCount>14) return;
    UIViewController *selected=nil;
    if ([source isKindOfClass:[UITabBarController class]])
        selected=((UITabBarController *)source).selectedViewController;
    UIViewController *visible=[selected isKindOfClass:[UINavigationController class]] ?
        ((UINavigationController *)selected).visibleViewController : selected;
    SLog([NSString stringWithFormat:
        @"CHECKOUT_PRESENT begin=%lu presenter=%@ destination=%@ selected=%@ visible=%@ animated=%d",
        (unsigned long)sCheckoutPresentCount,SVCName(source),SVCName(target),
        SVCName(selected),SVCName(visible),animated]);
    NSArray<NSNumber *> *addresses=[NSThread callStackReturnAddresses];
    NSUInteger index=0;
    for (NSNumber *number in addresses) {
        if (index>=32) break;
        uintptr_t pc=(uintptr_t)[number unsignedLongLongValue];
        Dl_info info={0};
        if (pc && dladdr((void *)pc,&info) && info.dli_fname && info.dli_fbase) {
            NSString *binary=[[@(info.dli_fname) lastPathComponent] copy] ?: @"unknown";
            // Only image names, offsets and static function symbols leave memory.
            if (binary.length>85) binary=[binary substringToIndex:85];
            NSString *symbol=info.dli_sname ? @(info.dli_sname) : @"unknown";
            if (symbol.length>180) symbol=[symbol substringToIndex:180];
            NSUInteger offset=(NSUInteger)(pc-(uintptr_t)info.dli_fbase);
            SLog([NSString stringWithFormat:
               @"CHECKOUT_FRAME event=%lu n=%lu image=%@ offset=0x%lx function=%@",
               (unsigned long)sCheckoutPresentCount,(unsigned long)index,
               binary,(unsigned long)offset,symbol]);
        }
        index++;
    }
    SLog([NSString stringWithFormat:@"CHECKOUT_PRESENT end=%lu",
       (unsigned long)sCheckoutPresentCount]);
}

%hook UIViewController
- (void)presentViewController:(UIViewController *)controllerToPresent
                     animated:(BOOL)animated completion:(void (^)(void))completion {
    NSString *destination=NSStringFromClass([controllerToPresent class]);
    if ([destination containsString:@"CheckoutLoadingView"] ||
        [destination containsString:@"Checkout19Checkout"])
        SLogCheckoutPresentation(self,controllerToPresent,animated);
    %orig;
}
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
        SLog(@"===== StravaSearch16 diagnostics 0.9.0 started; no credentials/URL queries recorded =====");
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
