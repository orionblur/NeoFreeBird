//
//  WebCreateTweet.x
//  NeoFreeBird
//
//  Reroutes native tweet posting through x.com's web GraphQL CreateTweet endpoint
//  so sideloaded / legacy sessions can post without hitting native attestation.
//
//  The seam is NSURLSession: the native app still issues CreateTweet as an ordinary
//  data/upload task to .../graphql/<queryId>/CreateTweet, so we rewrite that request
//  in flight with web-session auth (auth_token + ct0 cookies + csrf header) and a
//  fresh x-client-transaction-id. We never read the response body, only its status
//  code, so response encoding (gzip) is irrelevant.
//
//  Gated on the inverse of `reply_in_webview`: when that setting is on, WebReply.x
//  handles composing in a webview instead and this interception stays out of the way.
//

#import "HookHelpers.h"

// MARK: - Constants

// The web client's bearer -- used only for the CreateTweet write, whose transaction id
// is minted for the web client shape.
static NSString* const WebBearer = @"Bearer "
                                   @"AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%"
                                   @"3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA";

// Use Native bearer for every other endpoint
static NSString* const NativeBearer =
    @"Bearer "
    @"AAAAAAAAAAAAAAAAAAAAAAj4AQAAAAAAPraK64zCZ9CSzdLesbE7LB%2Bw4uE%"
    @"3DVJQREvQNCZJNiz3rHO7lOXlkVOQkzzdsgu6wWgcazdMUaGoUGm";

static NSString* const WebQueryIDDefaultsKey = @"nfb_createtweet_queryid";
static NSString* WebCreateTweetQueryID = @"vwzfnq1lLOa1Nfx7htM2mw";

// MARK: - Session state

// Latest cookies harvested from the app's web session (the account currently signed in
// on the web). auth_multi carries the auth_token of every other signed-in account.
static NSString* WebCT0 = nil;
static NSString* WebAuthToken = nil;
static NSString* WebTwid = nil;
static NSString* WebAuthMulti = nil;

// Per-account resolved credentials (userID -> @{auth_token, ct0, twid}).
static NSMutableDictionary<NSString*, NSDictionary*>* WebAccountCookies = nil;
static NSObject* WebAccountCookiesLock = nil;

// The authenticated helper webview is kept alive so we can mint a fresh
// x-client-transaction-id per send (x rate-limits requests without one).
static WKWebView* WebHelperWebView = nil;
static BOOL WebHelperReady = NO;
static BOOL WebHelperInFlight = NO;

// x-client-transaction-id tokens are bound to (method, path), so they're cached per
// key: reads never pay for one and each write path mints/rotates its own.
static NSMutableDictionary<NSString*, NSString*>* WebXTIDByPath = nil;
static NSMutableSet<NSString*>* WebXTIDInFlightKeys = nil;
static NSObject* WebXTIDLock = nil;

// userIDs whose session came from the webview cookie login (WebLoginViewController).
// These have no real OAuth secret, so every native-OAuth call they make is re-signed
// on the wire with the harvested cookies -- not just CreateTweet.
static NSMutableSet<NSString*>* WebCookieLoginUserIDs = nil;
static NSString* const WebCookieLoginUsersKey = @"nfb_cookie_login_userids";

// Offscreen native webview used to establish/harvest a specific account's web session.
static UIWindow* WebHarvestWindow = nil;
static BOOL WebBootstrapInFlight = NO;

static const void* WebPostingUIDKey = &WebPostingUIDKey;
static const void* WebHarvestWebViewKey = &WebHarvestWebViewKey;
static const void* CreateTweetWatcherKey = &CreateTweetWatcherKey;

static void refreshXTIDForMethodPath(NSString* method, NSString* path);
static void prewarmCreateTweetXTID(void);
static void refreshWebCookiesViaWebView(void);
static void teardownWebHarvestWindow(void);
BOOL isCookieLoginUserID(NSString* userID);

@interface WKWebView (AsyncJavaScript)
- (void)callAsyncJavaScript:(NSString*)functionBody
                  arguments:(NSDictionary<NSString*, id>*)arguments
                    inFrame:(WKFrameInfo*)frame
             inContentWorld:(WKContentWorld*)contentWorld
          completionHandler:(void (^)(id result, NSError* error))completionHandler;
@end

static BOOL nativeCreateTweetInterceptEnabled(void) {
    return ![BHTSettings boolForKey:@"reply_in_webview"];
}

// MARK: - Small helpers

// twid is stored as "u=<id>" (percent-encoded). Pull the numeric account id out of it.
static NSString* userIDFromTwid(NSString* twid) {
    if (twid.length == 0) {
        return nil;
    }
    NSString* decoded = [twid stringByRemovingPercentEncoding] ?: twid;
    NSCharacterSet* nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    NSString* digits =
        [[decoded componentsSeparatedByCharactersInSet:nonDigits] componentsJoinedByString:@""];
    return digits.length ? digits : nil;
}

static NSString* userIDStringForAccount(id account) {
    if (!account || ![account respondsToSelector:@selector(userID)]) {
        return nil;
    }
    long long uid = ((long long (*)(id, SEL))objc_msgSend)(account, @selector(userID));
    return uid ? [@(uid) stringValue] : nil;
}

static id accountForUserID(NSString* userID) {
    if (userID.length == 0) {
        return nil;
    }
    @try {
        Class twitterClass = %c(TFNTwitter);
        if (![twitterClass respondsToSelector:@selector(sharedTwitter)]) {
            return nil;
        }
        id twitter = ((id (*)(id, SEL))objc_msgSend)((id)twitterClass, @selector(sharedTwitter));
        if (![twitter respondsToSelector:@selector(accounts)]) {
            return nil;
        }
        NSArray* accounts = ((id (*)(id, SEL))objc_msgSend)(twitter, @selector(accounts));
        for (id account in accounts) {
            if ([userIDStringForAccount(account) isEqualToString:userID]) {
                return account;
            }
        }
    } @catch (__unused NSException* exception) {
    }
    return nil;
}

static UIWindowScene* activeWindowScene(void) {
    UIWindowScene* fallback = nil;
    for (UIScene* scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene*)scene;
        }
        if (!fallback) {
            fallback = (UIWindowScene*)scene;
        }
    }
    return fallback;
}

// Runs `ready` in a tight poll off the main thread, kicking `kick` every ~3s, until it
// passes or the deadline elapses. Never blocks the main thread.
static BOOL waitUntil(BOOL (^ready)(void), void (^kick)(void), NSTimeInterval maxSeconds) {
    if (ready()) {
        return YES;
    }
    if ([NSThread isMainThread]) {
        return NO;
    }

    NSUInteger maxTicks = (NSUInteger)(maxSeconds / 0.05);
    for (NSUInteger tick = 0; tick < maxTicks && !ready(); tick++) {
        if (kick && (tick % 60 == 0)) {
            dispatch_async(dispatch_get_main_queue(), kick);
        }
        [NSThread sleepForTimeInterval:0.05];
    }
    return ready();
}

// MARK: - Cookie harvesting

// Keep cookies persistent, just need a simple lookup, otherwise app starts getting wonky
static NSString* const WebAccountCookiesKey = @"nfb_web_account_cookies";

static NSObject* accountCacheLock(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        WebAccountCookiesLock = [NSObject new];
        NSDictionary* saved =
            [[NSUserDefaults standardUserDefaults] dictionaryForKey:WebAccountCookiesKey];
        WebAccountCookies = [saved isKindOfClass:[NSDictionary class]] ? [saved mutableCopy]
                                                                       : [NSMutableDictionary dictionary];
    });
    return WebAccountCookiesLock;
}

static void cacheAccountPair(NSString* userID, NSDictionary* pair) {
    if (userID.length == 0) {
        return;
    }
    @synchronized(accountCacheLock()) {
        if (pair) {
            WebAccountCookies[userID] = pair;
        } else {
            [WebAccountCookies removeObjectForKey:userID];
        }
        [[NSUserDefaults standardUserDefaults] setObject:[WebAccountCookies copy]
                                                  forKey:WebAccountCookiesKey];
    }
}

static NSDictionary* cachedAccountPair(NSString* userID) {
    if (userID.length == 0) {
        return nil;
    }
    @synchronized(accountCacheLock()) {
        return WebAccountCookies[userID];
    }
}

static void storeWebCookies(NSArray<NSHTTPCookie*>* cookies) {
    if (![cookies isKindOfClass:[NSArray class]]) {
        return;
    }

    for (NSHTTPCookie* cookie in cookies) {
        NSString* domain = cookie.domain ?: @"";
        if (![domain containsString:@"x.com"] && ![domain containsString:@"twitter.com"]) {
            continue;
        }
        if (cookie.value.length == 0) {
            continue;
        }

        if ([cookie.name isEqualToString:@"ct0"]) {
            WebCT0 = [cookie.value copy];
        } else if ([cookie.name isEqualToString:@"auth_token"]) {
            WebAuthToken = [cookie.value copy];
        } else if ([cookie.name isEqualToString:@"twid"]) {
            WebTwid = [cookie.value copy];
        } else if ([cookie.name isEqualToString:@"auth_multi"]) {
            WebAuthMulti = [cookie.value copy];
        }
    }

    NSString* userID = userIDFromTwid(WebTwid);
    if (userID.length && WebAuthToken.length && WebCT0.length) {
        cacheAccountPair(userID, @{
            @"auth_token": WebAuthToken,
            @"ct0": WebCT0,
            @"twid": WebTwid,
        });
    }
}

static void harvestSharedCookies(void) {
    NSMutableArray<NSHTTPCookie*>* all = [NSMutableArray array];
    for (NSString* domain in
         @[@"https://api.twitter.com", @"https://twitter.com", @"https://x.com", @"https://api.x.com"]) {
        NSArray* cookies =
            [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:[NSURL URLWithString:domain]];
        if (cookies) {
            [all addObjectsFromArray:cookies];
        }
    }
    storeWebCookies(all);
}

// MARK: - Cookie-login accounts

static void loadCookieLoginUsers(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        WebCookieLoginUserIDs = [NSMutableSet set];
        NSArray* saved = [[NSUserDefaults standardUserDefaults] arrayForKey:WebCookieLoginUsersKey];
        for (id uid in saved) {
            if ([uid isKindOfClass:[NSString class]]) {
                [WebCookieLoginUserIDs addObject:uid];
            }
        }
    });
}

// Whether `userID`'s session came from the webview cookie login (so all of its
// native-OAuth calls must be re-signed with cookies). Exposed via HookHelpers.h.
BOOL isCookieLoginUserID(NSString* userID) {
    if (userID.length == 0) {
        return NO;
    }
    loadCookieLoginUsers();
    @synchronized(WebCookieLoginUserIDs) {
        return [WebCookieLoginUserIDs containsObject:userID];
    }
}

static void markCookieLoginUserID(NSString* userID) {
    if (userID.length == 0) {
        return;
    }
    loadCookieLoginUsers();
    @synchronized(WebCookieLoginUserIDs) {
        [WebCookieLoginUserIDs addObject:userID];
        [[NSUserDefaults standardUserDefaults] setObject:WebCookieLoginUserIDs.allObjects
                                                  forKey:WebCookieLoginUsersKey];
    }
}

void webLoginDidCaptureCookies(NSString* userID, __unused NSString* username,
                               NSDictionary<NSString*, NSString*>* cookiePairs) {
    if (userID.length == 0 || cookiePairs.count == 0) {
        return;
    }

    NSString* authToken = cookiePairs[@"auth_token"];
    NSString* ct0 = cookiePairs[@"ct0"];
    NSString* twid = cookiePairs[@"twid"];
    if (authToken.length == 0 || ct0.length == 0) {
        return;
    }

    WebAuthToken = [authToken copy];
    WebCT0 = [ct0 copy];
    if (twid.length) {
        WebTwid = [twid copy];
    }
    if (cookiePairs[@"auth_multi"].length) {
        WebAuthMulti = [cookiePairs[@"auth_multi"] copy];
    }

    cacheAccountPair(userID, @{
        @"auth_token": authToken,
        @"ct0": ct0,
        @"twid": twid.length ? twid : [NSString stringWithFormat:@"u=%@", userID],
    });

    markCookieLoginUserID(userID);
    refreshWebCookiesViaWebView();
}

// MARK: - Helper webview (x-client-transaction-id)

static void onHelperWebViewLoaded(WKWebView* webView);

@interface WebHelperDelegate : NSObject <WKNavigationDelegate>
@end
@implementation WebHelperDelegate
- (void)webView:(WKWebView*)webView didFinishNavigation:(__unused WKNavigation*)navigation {
    onHelperWebViewLoaded(webView);
}
- (void)webView:(__unused WKWebView*)webView
    didFailProvisionalNavigation:(__unused WKNavigation*)navigation
                       withError:(__unused NSError*)error {
    WebHelperWebView = nil;
    WebHelperReady = NO;
    WebHelperInFlight = NO;
}
@end

static WebHelperDelegate* WebHelperDelegateInstance = nil;

// Seed the helper webview's cookie store with the harvested session cookies so it loads
// authenticated.
static void seedHelperCookies(WKWebView* webView, void (^done)(void)) {
    NSDictionary* pairs =
        @{@"auth_token": WebAuthToken ?: @"", @"ct0": WebCT0 ?: @"", @"twid": WebTwid ?: @""};

    NSMutableArray<NSHTTPCookie*>* cookies = [NSMutableArray array];
    for (NSString* name in pairs) {
        NSString* value = pairs[name];
        if (value.length == 0) {
            continue;
        }
        NSHTTPCookie* cookie = [NSHTTPCookie cookieWithProperties:@{
            NSHTTPCookieName: name,
            NSHTTPCookieValue: value,
            NSHTTPCookieDomain: @".x.com",
            NSHTTPCookiePath: @"/",
        }];
        if (cookie) {
            [cookies addObject:cookie];
        }
    }

    if (cookies.count == 0) {
        done();
        return;
    }

    WKHTTPCookieStore* store = webView.configuration.websiteDataStore.httpCookieStore;
    __block NSUInteger remaining = cookies.count;
    for (NSHTTPCookie* cookie in cookies) {
        [store setCookie:cookie
            completionHandler:^{
                if (--remaining == 0) {
                    done();
                }
            }];
    }
}

static void refreshWebCookiesViaWebView(void) {
    if (WebHelperWebView) {
        prewarmCreateTweetXTID();
        return;
    }
    if (WebHelperInFlight) {
        return;
    }
    WebHelperInFlight = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        harvestSharedCookies();

        WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
        configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;

        WKWebView* webView = [[WKWebView alloc] initWithFrame:CGRectMake(-3000, -3000, 390, 844)
                                                configuration:configuration];
        WebHelperDelegateInstance = [[WebHelperDelegate alloc] init];
        webView.navigationDelegate = WebHelperDelegateInstance;
        webView.customUserAgent =
            @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like "
            @"Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
        webView.userInteractionEnabled = NO;
        webView.alpha = 0.01;
        WebHelperWebView = webView;
        WebHelperReady = NO;

        UIWindow* keyWindow = nil;
        for (UIWindow* w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) {
                keyWindow = w;
                break;
            }
        }
        keyWindow = keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
        [keyWindow addSubview:webView];

        seedHelperCookies(webView, ^{
            [webView
                loadRequest:[NSURLRequest
                                requestWithURL:[NSURL URLWithString:@"https://x.com/settings/account"]]];
        });
    });
}

static void onHelperWebViewLoaded(WKWebView* webView) {
    WebHelperInFlight = NO;

    [webView.configuration.websiteDataStore.httpCookieStore
        getAllCookies:^(NSArray<NSHTTPCookie*>* cookies) {
            storeWebCookies(cookies);
        }];

    NSString* script = nil;
    NSURL* scriptURL = [[BHTBundle sharedBundle] pathForFile:@"WebXTID.js"];
    if (scriptURL) {
        script = [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:nil];
    }
    if (script.length == 0) {
        return;
    }

    [webView evaluateJavaScript:script
              completionHandler:^(__unused id result, __unused NSError* error) {
                  WebHelperReady = YES;
                  prewarmCreateTweetXTID();
              }];
}

static NSObject* xtidLock(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        WebXTIDLock = [NSObject new];
        WebXTIDByPath = [NSMutableDictionary dictionary];
        WebXTIDInFlightKeys = [NSMutableSet set];
    });
    return WebXTIDLock;
}

static NSString* xtidKey(NSString* method, NSString* path) {
    return [NSString stringWithFormat:@"%@ %@", method ?: @"POST", path ?: @""];
}

static NSString* cachedXTIDForKey(NSString* key) {
    @synchronized(xtidLock()) {
        return WebXTIDByPath[key];
    }
}

// Mint (or rotate) the transaction id for one (method, path) by calling the web
// client's own generator in the helper webview. Deduped per key so concurrent sends
// for the same path issue a single JS call.
static void refreshXTIDForMethodPath(NSString* method, NSString* path) {
    if (path.length == 0) {
        return;
    }
    NSString* key = xtidKey(method, path);
    @synchronized(xtidLock()) {
        if ([WebXTIDInFlightKeys containsObject:key]) {
            return;
        }
        [WebXTIDInFlightKeys addObject:key];
    }

    WKWebView* webView = WebHelperWebView;
    if (![webView isKindOfClass:[WKWebView class]]) {
        @synchronized(xtidLock()) {
            [WebXTIDInFlightKeys removeObject:key];
        }
        return;
    }

    if (@available(iOS 14.0, *)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [webView callAsyncJavaScript:@"return await window.__bhtTransactionId(path, method);"
                               arguments:@{@"method": method ?: @"POST", @"path": path}
                                 inFrame:nil
                          inContentWorld:WKContentWorld.pageWorld
                       completionHandler:^(id result, __unused NSError* error) {
                           BOOL ok = [result isKindOfClass:[NSString class]] &&
                                     [(NSString*)result length] > 10 &&
                                     ![(NSString*)result hasPrefix:@"ERR:"];
                           @synchronized(xtidLock()) {
                               [WebXTIDInFlightKeys removeObject:key];
                               if (ok) {
                                   WebXTIDByPath[key] = [result copy];
                               }
                           }
                       }];
        });
    } else {
        @synchronized(xtidLock()) {
            [WebXTIDInFlightKeys removeObject:key];
        }
    }
}

static NSString* createTweetPath(void) {
    return [NSString stringWithFormat:@"/i/api/graphql/%@/CreateTweet", WebCreateTweetQueryID];
}

static void prewarmCreateTweetXTID(void) { refreshXTIDForMethodPath(@"POST", createTweetPath()); }



static NSString* transactionIdForRequest(NSURLRequest* request) {
    NSURL* url = request.URL;
    if (url.path.length == 0) {
        return nil;
    }
    NSString* method = (request.HTTPMethod ?: @"POST").uppercaseString;

    NSString* key = xtidKey(method, url.path);
    NSString* cached = cachedXTIDForKey(key);
    if (cached.length) {
        refreshXTIDForMethodPath(method, url.path);
        return cached;
    }

    waitUntil(
        ^BOOL {
            return cachedXTIDForKey(key).length > 0;
        },
        ^{
            if (!WebHelperWebView) {
                refreshWebCookiesViaWebView();
            } else if (WebHelperReady) {
                refreshXTIDForMethodPath(method, url.path);
            }
        },
        20.0);
    return cachedXTIDForKey(key);
}

// MARK: - Native bootstrap webview (per-account web session)

// Only the native authenticated webview can perform the OAuth->cookie exchange, so
// accounts with no web cookies yet get one loaded offscreen and harvested.
static void bootstrapAccount(id account, NSString* userID) {
    if (!account || userID.length == 0 || WebBootstrapInFlight) {
        return;
    }
    WebBootstrapInFlight = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (WebHarvestWindow) {
            WebHarvestWindow.hidden = YES;
            WebHarvestWindow.rootViewController = nil;
            WebHarvestWindow = nil;
        }

        Class webViewControllerClass = %c(T1WebViewController);
        SEL initSel = @selector(initWithRootURL:account:shouldAuthenticate:shouldPresentAsNativePage:
                                sourceStatus:scribeComponent:scribeParameters:);
        UIWindowScene* scene = activeWindowScene();
        if (!webViewControllerClass || !scene ||
            ![webViewControllerClass instancesRespondToSelector:initSel]) {
            WebBootstrapInFlight = NO;
            return;
        }

        NSURL* url = [NSURL URLWithString:@"https://x.com/settings/account"];
        T1WebViewController* webViewController = [[webViewControllerClass alloc] initWithRootURL:url
                                                                                         account:account
                                                                              shouldAuthenticate:YES
                                                                       shouldPresentAsNativePage:NO
                                                                                    sourceStatus:nil
                                                                                 scribeComponent:nil
                                                                                scribeParameters:nil];
        if (!webViewController) {
            WebBootstrapInFlight = NO;
            return;
        }

        objc_setAssociatedObject(webViewController, WebHarvestWebViewKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UIWindow* window = [[UIWindow alloc] initWithWindowScene:scene];
        window.frame = CGRectMake(-3000, -3000, 390, 844);
        window.windowLevel = UIWindowLevelNormal - 1000;
        window.userInteractionEnabled = NO;
        window.rootViewController = webViewController;
        window.hidden = NO;
        WebHarvestWindow = window;

        // Safety teardown in case the load never resolves.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           teardownWebHarvestWindow();
                       });
    });
}

static void teardownWebHarvestWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (WebHarvestWindow) {
            WebHarvestWindow.hidden = YES;
            WebHarvestWindow.rootViewController = nil;
            WebHarvestWindow = nil;
        }
        WebBootstrapInFlight = NO;
    });
}

void maybeHandleHarvestWebView(__unsafe_unretained id webViewController) {
    if (!webViewController || !objc_getAssociatedObject(webViewController, WebHarvestWebViewKey)) {
        return;
    }

    WKWebView* webView = nil;
    @try {
        if ([webViewController respondsToSelector:@selector(webView)]) {
            webView = ((WKWebView * (*)(id, SEL)) objc_msgSend)(webViewController, @selector(webView));
        }
    } @catch (__unused NSException* exception) {
    }

    void (^finish)(void) = ^{
        harvestSharedCookies();
        refreshWebCookiesViaWebView();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           teardownWebHarvestWindow();
                       });
    };

    if ([webView isKindOfClass:%c(WKWebView)]) {
        [webView.configuration.websiteDataStore.httpCookieStore
            getAllCookies:^(NSArray<NSHTTPCookie*>* cookies) {
                storeWebCookies(cookies);
                finish();
            }];
    } else {
        finish();
    }
}

// MARK: - Prewarm

void prewarmWebCookiesIfNeeded(void) {
    loadCookieLoginUsers();
    BOOL haveCookieLogin = NO;
    @synchronized(WebCookieLoginUserIDs) {
        haveCookieLogin = WebCookieLoginUserIDs.count > 0;
    }

    if (!haveCookieLogin && !nativeCreateTweetInterceptEnabled() &&
        ![BHTSettings boolForKey:@"restore_tweet_labels"] &&
        ![BHTSettings boolForKey:@"show_account_location"]) {
        return;
    }

    NSString* savedQueryID =
        [[NSUserDefaults standardUserDefaults] stringForKey:WebQueryIDDefaultsKey];
    if (savedQueryID.length) {
        WebCreateTweetQueryID = [savedQueryID copy];
    }

    refreshWebCookiesViaWebView();
    harvestSharedCookies();
}

// MARK: - Credential resolution

static NSString* authTokenForUserID(NSString* userID) {
    if (userID.length == 0) {
        return nil;
    }

    NSString* primaryUID = userIDFromTwid(WebTwid);
    if ([primaryUID isEqualToString:userID] && WebAuthToken.length) {
        return WebAuthToken;
    }

    if (WebAuthMulti.length == 0) {
        return nil;
    }
    NSString* decoded = [WebAuthMulti stringByRemovingPercentEncoding] ?: WebAuthMulti;
    decoded = [decoded
        stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
    NSCharacterSet* separators = [NSCharacterSet characterSetWithCharactersInString:@"|,"];
    for (NSString* entry in [decoded componentsSeparatedByCharactersInSet:separators]) {
        NSRange colon = [entry rangeOfString:@":"];
        if (colon.location == NSNotFound) {
            continue;
        }
        NSString* uid = [entry substringToIndex:colon.location];
        NSString* token = [entry substringFromIndex:NSMaxRange(colon)];
        if ([uid isEqualToString:userID] && token.length) {
            return token;
        }
    }
    return nil;
}

@interface Ct0Fetcher : NSObject <NSURLSessionTaskDelegate>
@property (nonatomic, copy) NSString* ct0;
@property (nonatomic, copy) NSString* twid;
@property (nonatomic, assign) BOOL loggedOut;
- (void)captureFromResponse:(NSURLResponse*)response;
@end

@implementation Ct0Fetcher
- (void)captureFromResponse:(NSURLResponse*)response {
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
        return;
    }
    NSHTTPURLResponse* http = (NSHTTPURLResponse*)response;
    NSArray<NSHTTPCookie*>* cookies =
        [NSHTTPCookie cookiesWithResponseHeaderFields:http.allHeaderFields
                                               forURL:http.URL ?: response.URL];
    for (NSHTTPCookie* cookie in cookies) {
        if ([cookie.name isEqualToString:@"ct0"] && cookie.value.length) {
            self.ct0 = [cookie.value copy];
        } else if ([cookie.name isEqualToString:@"twid"] && cookie.value.length) {
            self.twid = [cookie.value copy];
        }
    }
}
- (void)URLSession:(__unused NSURLSession*)session
                          task:(__unused NSURLSessionTask*)task
    willPerformHTTPRedirection:(NSHTTPURLResponse*)response
                    newRequest:(NSURLRequest*)request
             completionHandler:(void (^)(NSURLRequest*))completionHandler {
    [self captureFromResponse:response];

    NSString* target = request.URL.absoluteString.lowercaseString ?: @"";
    if ([target containsString:@"login"] || [target containsString:@"logout"] ||
        [target containsString:@"/i/flow/"] || [target containsString:@"account/access"]) {
        self.loggedOut = YES;
    }
    completionHandler(request);
}
@end

// Mint a fresh ct0 for a bare auth_token by hitting x.com once and reading the Set-Cookie.
static NSString* fetchCt0Sync(NSString* authToken, NSString* expectedUserID) {
    if (authToken.length == 0 || [NSThread isMainThread]) {
        return nil;
    }

    Ct0Fetcher* fetcher = [Ct0Fetcher new];
    NSURLSessionConfiguration* config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.HTTPCookieStorage = nil;
    config.HTTPShouldSetCookies = NO;
    NSURLSession* session = [NSURLSession sessionWithConfiguration:config
                                                          delegate:fetcher
                                                     delegateQueue:nil];

    NSMutableURLRequest* request =
        [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://x.com/"]];
    request.HTTPShouldHandleCookies = NO;
    [request setValue:[NSString stringWithFormat:@"auth_token=%@", authToken]
        forHTTPHeaderField:@"Cookie"];
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
                      @"(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        forHTTPHeaderField:@"User-Agent"];

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[session dataTaskWithRequest:request
                completionHandler:^(__unused NSData* data, NSURLResponse* response,
                                    __unused NSError* error) {
                    [fetcher captureFromResponse:response];
                    dispatch_semaphore_signal(done);
                }] resume];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)));
    [session finishTasksAndInvalidate];

    if (fetcher.loggedOut) {
        return nil;
    }

    NSString* responseUserID = userIDFromTwid(fetcher.twid);
    if (expectedUserID.length && responseUserID.length &&
        ![responseUserID isEqualToString:expectedUserID]) {
        return nil;
    }
    return fetcher.ct0;
}

// Resolve credentials for the posting account.
static BOOL resolveWebCreds(NSString* userID, NSString** outAuthToken, NSString** outCt0) {
    NSDictionary* cached = cachedAccountPair(userID);
    NSString* authToken = cached[@"auth_token"];
    NSString* ct0 = cached[@"ct0"];

    if (authToken.length == 0) {
        authToken = authTokenForUserID(userID);
    }
    if (authToken.length == 0) {
        return NO;
    }

    if (ct0.length == 0) {
        ct0 = fetchCt0Sync(authToken, userID);
        if (ct0.length == 0) {
            return NO;
        }
        cacheAccountPair(userID, @{
            @"auth_token": authToken,
            @"ct0": ct0,
            @"twid": cached[@"twid"] ?: [NSString stringWithFormat:@"u=%@", userID],
        });
    }

    if (outAuthToken) *outAuthToken = authToken;
    if (outCt0) *outCt0 = ct0;
    return YES;
}

// MARK: - Request transform

static BOOL isCreateTweetURL(NSURL* url) { return url && [url.path hasSuffix:@"/CreateTweet"]; }

static BOOL isAccountURL(NSURL* url) { return url && ([url.path containsString:@"/1.1/account"] 
|| [url.path containsString:@"/1.1/users/"]); }

static BOOL isPeriscopeAuthURL(NSURL* url) {
    NSString* path = url.path ?: @"";
    return [path hasSuffix:@"/oauth/authenticate_periscope"] ||
           [path hasSuffix:@"/oauth/authenticate_periscope.json"];
}

// CreateTweet needs to go through the web path, otherwise AppAttest kicks in
static BOOL isWriteRequest(NSURL* url) {
    return isCreateTweetURL(url) || isAccountURL(url) || isPeriscopeAuthURL(url);
}

static NSURL* webEquivalentURL(NSURL* url) {
    if (!isWriteRequest(url)) {
        return url;
    }

    NSURLComponents* c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (c && isPeriscopeAuthURL(url)) {
        c.host = @"x.com";
        c.path = @"/i/api/1.1/oauth/authenticate_periscope.json";
        return c.URL ?: url;
    }
    NSString* path = c.path ?: @"";
    if (c && [path containsString:@"/graphql/"]) {
        c.host = @"x.com";
        if (![path hasPrefix:@"/i/api/"]) {
            NSRange g = [path rangeOfString:@"/graphql/"];
            c.path = [@"/i/api" stringByAppendingString:[path substringFromIndex:g.location]];
        }
        return c.URL ?: url;
    }
    return url;
}

// The queryId sits in the request path: .../graphql/<queryId>/CreateTweet
static NSString* queryIDFromCreateTweetURL(NSURL* url) {
    NSArray<NSString*>* components = url.path.pathComponents;
    if (components.count >= 2 && [components.lastObject isEqualToString:@"CreateTweet"]) {
        return components[components.count - 2];
    }
    return nil;
}

// The native request signs with OAuth: oauth_token="<userID>-<secret>".
static NSString* postingUserIDFromRequest(NSURLRequest* request) {
    NSString* auth = [request valueForHTTPHeaderField:@"Authorization"];
    if (![auth isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSRange marker = [auth rangeOfString:@"oauth_token=\""];
    if (marker.location == NSNotFound) {
        return nil;
    }
    NSString* rest = [auth substringFromIndex:NSMaxRange(marker)];
    NSRange endQuote = [rest rangeOfString:@"\""];
    if (endQuote.location == NSNotFound) {
        return nil;
    }
    NSString* token = [rest substringToIndex:endQuote.location];
    NSRange dash = [token rangeOfString:@"-"];
    return dash.location != NSNotFound ? [token substringToIndex:dash.location] : nil;
}

// Replace the (invalid, placeholder) native OAuth with the web session's cookie auth.
static void applyWebAuth(NSMutableURLRequest* request, NSString* authToken, NSString* ct0,
                         NSString* userID) {
    request.HTTPShouldHandleCookies = NO;

    BOOL isWrite = isWriteRequest(request.URL);
    NSArray<NSString*>* headersToStrip = isWrite
        ? @[
              @"Authorization", @"X-Twitter-Client-DeviceID", @"X-Twitter-Client-Version",
              @"X-Twitter-Client", @"X-Twitter-API-Version", @"X-Twitter-Client-Limit-Ad-Tracking",
              @"X-B3-TraceId", @"Timezone", @"kdt", @"X-Client-UUID", @"Host"
          ]
        : @[ @"Authorization", @"X-B3-TraceId", @"Host" ];
    for (NSString* header in headersToStrip) {
        [request setValue:nil forHTTPHeaderField:header];
    }

    // Reads present the app bearer (native timeline semantics); the write presents the
    // web bearer its transaction id is minted for.
    [request setValue:isWrite ? WebBearer : NativeBearer forHTTPHeaderField:@"authorization"];
    if (isWrite) {
        [request setValue:@"OAuth2Session" forHTTPHeaderField:@"x-twitter-auth-type"];
        [request setValue:@"yes" forHTTPHeaderField:@"x-twitter-active-user"];
        if ([request.URL.host isEqualToString:@"api.twitter.com"]) {
            NSURLComponents* c = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
            c.host = @"api.x.com";
            request.URL = c.URL;
        }
    }
    if (ct0.length) {
        [request setValue:ct0 forHTTPHeaderField:@"x-csrf-token"];
    }

    NSMutableArray<NSString*>* cookiePairs = [NSMutableArray array];
    if (authToken.length) {
        [cookiePairs addObject:[NSString stringWithFormat:@"auth_token=%@", authToken]];
    }
    if (ct0.length) {
        [cookiePairs addObject:[NSString stringWithFormat:@"ct0=%@", ct0]];
    }
    if (userID.length) {
        [cookiePairs addObject:[NSString stringWithFormat:@"twid=u%%3D%@", userID]];
    }
    [request setValue:[cookiePairs componentsJoinedByString:@"; "] forHTTPHeaderField:@"Cookie"];
}

// A native, OAuth1-signed request -- the app's normal authenticated call shape. These
// are what a cookie-login account can't legitimately sign, so we re-sign them.
static BOOL requestUsesNativeOAuth(NSURLRequest* request) {
    NSString* auth = [request valueForHTTPHeaderField:@"Authorization"]
                         ?: [request valueForHTTPHeaderField:@"authorization"];
    return [auth isKindOfClass:[NSString class]] && [auth containsString:@"oauth_token="];
}

static NSMutableURLRequest* webRequestFromNativeSend(NSURLRequest* request) {
    NSURL* url = request.URL;
    if (!url) {
        return nil;
    }

    BOOL isCreateTweet = isCreateTweetURL(url);
    BOOL createTweetReroute = isCreateTweet && nativeCreateTweetInterceptEnabled();

    NSString* postingUserID = postingUserIDFromRequest(request);
    if (postingUserID.length == 0 && requestUsesNativeOAuth(request)) {
        postingUserID = userIDFromTwid(WebTwid);
    }
    BOOL cookieReplication = requestUsesNativeOAuth(request) && isCookieLoginUserID(postingUserID);

    if (!createTweetReroute && !cookieReplication) {
        return nil;
    }
    if (postingUserID.length == 0) {
        return nil;
    }

    if (isCreateTweet) {
        NSString* queryID = queryIDFromCreateTweetURL(url);
        if (queryID.length && ![queryID isEqualToString:WebCreateTweetQueryID]) {
            WebCreateTweetQueryID = [queryID copy];
            [[NSUserDefaults standardUserDefaults] setObject:queryID forKey:WebQueryIDDefaultsKey];
        }
    }

    harvestSharedCookies();

    NSString *authToken = nil, *ct0 = nil;
    if (!resolveWebCreds(postingUserID, &authToken, &ct0)) {
        return nil;
    }

    NSMutableURLRequest* outgoing = [request mutableCopy];

    outgoing.URL = webEquivalentURL(outgoing.URL);
    if (isPeriscopeAuthURL(outgoing.URL)) {
        outgoing.HTTPMethod = @"GET";
        outgoing.HTTPBody = nil;
    }
    applyWebAuth(outgoing, authToken, ct0, postingUserID);

    // Only the write (CreateTweet) is routed to the web endpoint and carries a
    // transaction id; reads stay native and never need one.
    NSString* token = isWriteRequest(outgoing.URL) ? transactionIdForRequest(outgoing) : nil;
    if (token.length) {
        [outgoing setValue:token forHTTPHeaderField:@"x-client-transaction-id"];
    } else if (isCreateTweet) {
        return nil;
    }

    if (isCreateTweet) {
        objc_setAssociatedObject(outgoing, WebPostingUIDKey, postingUserID,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return outgoing;
}

// MARK: - Task watcher

@interface CreateTweetWatcher : NSObject
@property (nonatomic, copy) NSString* userID;
@end

@implementation CreateTweetWatcher
- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(__unused NSDictionary*)change
                       context:(__unused void*)context {
    NSURLSessionTask* task = object;
    if (![keyPath isEqualToString:@"state"] || task.state != NSURLSessionTaskStateCompleted) {
        return;
    }

    CreateTweetWatcher* keepAlive = self; // survive detaching our own retainer below
    @try {
        [task removeObserver:self forKeyPath:@"state"];
    } @catch (__unused NSException* exception) {
    }
    objc_setAssociatedObject(task, CreateTweetWatcherKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSInteger code = [task.response isKindOfClass:[NSHTTPURLResponse class]]
                         ? [(NSHTTPURLResponse*)task.response statusCode]
                         : 0;
    // On a 4xx, drop only the ct0 (keeping the cemented auth_token) so the next send
    // re-mints a fresh csrf.
    if (code >= 400 && code < 500 && keepAlive.userID.length) {
        NSDictionary* pair = cachedAccountPair(keepAlive.userID);
        NSString* authToken = pair[@"auth_token"];
        if (authToken.length) {
            cacheAccountPair(keepAlive.userID,
                             @{@"auth_token": authToken, @"twid": pair[@"twid"] ?: @""});
        }
    }
}
@end

static void watchCreateTweetTask(id task, NSString* userID) {
    if (![task isKindOfClass:[NSURLSessionTask class]] || userID.length == 0) {
        return;
    }
    CreateTweetWatcher* watcher = [CreateTweetWatcher new];
    watcher.userID = userID;
    objc_setAssociatedObject(task, CreateTweetWatcherKey, watcher, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        [task addObserver:watcher
               forKeyPath:@"state"
                  options:NSKeyValueObservingOptionNew
                  context:NULL];
    } @catch (__unused NSException* exception) {
    }
}

// MARK: - Shared account accessor

id accountForAuthenticatedWebView(void) {
    Class hostClass = %c(T1HostViewController);
    if ([hostClass respondsToSelector:@selector(sharedHostViewController)]) {
        id host = [hostClass sharedHostViewController];
        if ([host respondsToSelector:@selector(currentAccount)]) {
            id account = [host currentAccount];
            if (account) {
                return account;
            }
        }
    }
    return nil;
}

// The current web session's auth_token + ct0, for read-only web GraphQL GETs (e.g.
// SourceLabels.x). Harvests the shared cookie jar first; nil until a session exists.
NSDictionary* currentWebCredentials(void) {
    harvestSharedCookies();
    if (WebAuthToken.length == 0 || WebCT0.length == 0) {
        return nil;
    }
    return @{@"auth_token": WebAuthToken, @"ct0": WebCT0};
}

// MARK: - Hooks

%hook NSURLSession

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request {
    NSMutableURLRequest* outgoing = webRequestFromNativeSend(request);
    if (outgoing) {
        NSURLSessionDataTask* task = %orig(outgoing);
        watchCreateTweetTask(task, objc_getAssociatedObject(outgoing, WebPostingUIDKey));
        return task;
    }
    return %orig;
}

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request
                           completionHandler:(id)completionHandler {
    NSMutableURLRequest* outgoing = webRequestFromNativeSend(request);
    if (outgoing) {
        NSURLSessionDataTask* task = %orig(outgoing, completionHandler);
        watchCreateTweetTask(task, objc_getAssociatedObject(outgoing, WebPostingUIDKey));
        return task;
    }
    return %orig;
}

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request fromData:(NSData*)bodyData {
    NSMutableURLRequest* outgoing = webRequestFromNativeSend(request);
    if (outgoing) {
        NSURLSessionUploadTask* task = %orig(outgoing, bodyData);
        watchCreateTweetTask(task, objc_getAssociatedObject(outgoing, WebPostingUIDKey));
        return task;
    }
    return %orig;
}

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request fromFile:(NSURL*)fileURL {
    NSMutableURLRequest* outgoing = webRequestFromNativeSend(request);
    if (outgoing) {
        NSURLSessionUploadTask* task = %orig(outgoing, fileURL);
        watchCreateTweetTask(task, objc_getAssociatedObject(outgoing, WebPostingUIDKey));
        return task;
    }
    return %orig;
}

%end
