#import <Foundation/Foundation.h>

// Version-only compatibility bridge. Targets specific older Strava route,
// location-search and checkout API calls without changing the login flow.
// This is experimental; the account entitlement is NEVER changed.
static NSString *const kRealClientVersion=@"422.0.1";
static BOOL SSCDisableBridge(void) {
    NSString *file=[NSHomeDirectory() stringByAppendingPathComponent:
      @"Library/Caches/StravaSearch16/disable-bridge.flag"];
    return [[NSFileManager defaultManager] fileExistsAtPath:file];
}
static BOOL SSCTarget(NSURLRequest *req) {
    NSURL *url=req.URL;
    NSString *host=url.host.lowercaseString ?: @"";
    if (![host isEqualToString:@"strava.com"] &&
        ![host hasSuffix:@".strava.com"]) return NO;
    NSString *path=url.path.lowercaseString ?: @"";
    NSArray *patterns=@[@"/route/",@"/routes",@"/search",@"/geocod",
       @"/autocomplete",@"/suggest",@"/checkout",@"/subscription",@"/purchase"];
    for (NSString *pattern in patterns)
        if ([path containsString:pattern]) return YES;
    if ([host isEqualToString:@"graphql.strava.com"]) {
        NSData *body=req.HTTPBody;
        if (!body || body.length>65536) return NO;
        id json=[NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) return NO;
        NSString *op=[json objectForKey:@"operationName"];
        if (![op isKindOfClass:[NSString class]]) return NO;
        NSString *name=op.lowercaseString;
        return [name containsString:@"route"] || [name containsString:@"search"] ||
            [name containsString:@"geocod"];
    }
    return NO;
}
NSURLRequest *SSCBridgeRequest(NSURLRequest *request, void (*logFn)(NSString *)) {
    if (!request || SSCDisableBridge() || !SSCTarget(request)) return request;
    NSDictionary *headers=request.allHTTPHeaderFields;
    if (![headers isKindOfClass:[NSDictionary class]] || headers.count==0) return request;
    NSMutableURLRequest *modified=[request mutableCopy];
    int matched=0, applied=0;
    for (NSString *field in headers) {
        if (![field isKindOfClass:[NSString class]]) continue;
        NSString *key=field.lowercaseString;
        if (!([key isEqualToString:@"user-agent"] || [key containsString:@"version"] ||
              [key containsString:@"strava-client"])) continue;
        NSString *before=headers[field];
        if (![before isKindOfClass:[NSString class]]) continue;
        NSString *after=[before stringByReplacingOccurrencesOfString:@"486.0.2"
            withString:kRealClientVersion];
        after=[after stringByReplacingOccurrencesOfString:@"487.0.0"
            withString:kRealClientVersion];
        if ([after isEqualToString:before]) continue;
        matched++;
        [modified setValue:after forHTTPHeaderField:field];
        NSString *effective=[modified valueForHTTPHeaderField:field];
        if ([effective isEqualToString:after]) applied++;
    }
    if (logFn) {
        NSString *category=@"route/search/checkout";
        logFn([NSString stringWithFormat:
            @"BRIDGE_IDENTITY category=%@ version=%@ matched=%d applied=%d",
            category,kRealClientVersion,matched,applied]);
        if (matched>0 && applied==0)
            logFn(@"BRIDGE_IDENTITY_BLOCKED: another header hook may be rewriting the version");
    }
    return applied>0 ? modified : request;
}
