//
//  SourceLabels.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// MARK: - Restore Tweet Source Labels
//
// The source is gone from the on-device status models, so it's fetched from
// x.com's web GraphQL TweetDetail endpoint (reusing the web session that
// WebCreateTweet.x establishes), cached by tweet ID, and appended to the detail
// footer item's time string. Original idea by @nyaathea.

// Source labels keyed by tweet ID (declared in BHTHookHelpers.h).
NSMutableDictionary* tweetSources = nil;

// Per-tweet fetch bookkeeping. All of these — including tweetSources — are only
// mutated on the main thread, so no locking is required.
static NSMutableDictionary* fetchPending = nil;
static NSMutableDictionary* fetchRetries = nil;

static char kSourceAppendedKey;  // marks a footer item whose timeAgo already carries the source
static char kFooterTweetIDKey;   // the tweet ID a footer text view is currently showing
static char kFooterObservingKey; // whether a footer text view registered for update notifications

#define SOURCE_NOTE           @"TweetSourceUpdated"
#define MAX_SOURCE_CACHE_SIZE 200
#define MAX_FETCH_RETRIES     3

// Public web bearer token (not a secret; ships in the web client).
static NSString* const kSourceBearer = @"Bearer "
                                       @"AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puT"
                                       @"s%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA";

// TweetDetail persisted-query id. Web-client specific and can rotate; a stale value
// just yields an unavailable label rather than a wrong one.
static NSString* const kTweetDetailQueryID = @"rZA6K31W4E90vZKBmxXV3g";

// JSON-serialize `object` and percent-encode it for a GraphQL query parameter.
static NSString* encodedQueryParameter(id object) {
    NSData* data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!data) return nil;

    NSString* json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [json
        stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]];
}

// --- Model / view seams verified against classdump/12.3 (T1Twitter.c) ---

@interface T1ConversationFooterItem : NSObject
@property (nonatomic, copy) NSString* timeAgo;
@end

@interface T1ConversationFooterTextView (SourceLabels)
@property (nonatomic, readonly) T1ConversationFooterItem* footerItem;
@property (nonatomic, readonly) TFNAttributedTextView* textView;
- (void)BHT_forceRecolorSource;
@end

@interface TFNAttributedTextView (SourceLabels)
- (TFNAttributedTextModel*)textModel;
@end

// TweetSourceHelper itself is declared in Headers/BHTHelpers.h; declare only the
// internals this rewrite adds.
@interface TweetSourceHelper (SourceLabels)
+ (NSString*)unavailableString;
+ (void)pruneCacheIfNeeded;
+ (NSString*)labelFromSourceHTML:(NSString*)html;
+ (NSURL*)tweetDetailURLForTweetID:(NSString*)tweetID;
+ (NSString*)sourceHTMLFromTweetDetail:(NSDictionary*)json forTweetID:(NSString*)tweetID;
+ (void)markTweetID:(NSString*)tweetID unavailable:(BOOL)unavailable withSource:(NSString*)source;
+ (void)retryOrFailTweetID:(NSString*)tweetID;
@end

@implementation TweetSourceHelper

+ (NSString*)unavailableString {
    return [[BHTBundle sharedBundle] localizedStringForKey:@"SOURCE_UNAVAILABLE"];
}

// `source` isn't gated behind any feature flag, so the client's large `features`
// block is omitted; the required `variables` must be sent or x rejects the request.
+ (NSURL*)tweetDetailURLForTweetID:(NSString*)tweetID {
    NSDictionary* variables = @{
        @"focalTweetId": tweetID,
        @"with_rux_injections": @NO,
        @"rankingMode": @"Relevance",
        @"includePromotedContent": @NO,
        @"withCommunity": @YES,
        @"withQuickPromoteEligibilityTweetFields": @YES,
        @"withBirdwatchNotes": @YES,
        @"withVoice": @YES,
    };

    NSString* encodedVariables = encodedQueryParameter(variables);
    if (encodedVariables.length == 0) {
        return nil;
    }

    NSString* urlString =
        [NSString stringWithFormat:@"https://x.com/i/api/graphql/%@/TweetDetail?variables=%@",
                                   kTweetDetailQueryID, encodedVariables];
    return [NSURL URLWithString:urlString];
}

// Pulls the focal tweet's raw source markup out of a TweetDetail response. The
// conversation also carries replies, so we match the entry by rest_id.
+ (NSString*)sourceHTMLFromTweetDetail:(NSDictionary*)json forTweetID:(NSString*)tweetID {
    NSDictionary* conversation = json[@"data"][@"threaded_conversation_with_injections_v2"];
    NSArray* instructions = conversation[@"instructions"];
    if (![instructions isKindOfClass:[NSArray class]]) return nil;

    for (NSDictionary* instruction in instructions) {
        NSArray* entries = instruction[@"entries"];
        if (![entries isKindOfClass:[NSArray class]]) continue;

        for (NSDictionary* entry in entries) {
            NSDictionary* result = entry[@"content"][@"itemContent"][@"tweet_results"][@"result"];
            if (![result isKindOfClass:[NSDictionary class]]) continue;

            // TweetWithVisibilityResults nests the real tweet one level down.
            NSDictionary* tweet =
                [result[@"tweet"] isKindOfClass:[NSDictionary class]] ? result[@"tweet"] : result;
            if (![tweet[@"rest_id"] isEqualToString:tweetID]) continue;

            NSString* source = tweet[@"source"];
            return [source isKindOfClass:[NSString class]] ? source : nil;
        }
    }

    return nil;
}

// Keeps the cache from growing without bound by dropping resolved/unavailable entries.
+ (void)pruneCacheIfNeeded {
    if (tweetSources.count <= MAX_SOURCE_CACHE_SIZE) return;

    NSString* unavailable = [self unavailableString];
    NSMutableArray* keysToRemove = [NSMutableArray array];

    for (NSString* key in tweetSources) {
        NSString* value = tweetSources[key];
        if (value.length == 0 || [value isEqualToString:unavailable]) {
            [keysToRemove addObject:key];
        }
    }

    for (NSString* key in keysToRemove) {
        [tweetSources removeObjectForKey:key];
        [fetchPending removeObjectForKey:key];
        [fetchRetries removeObjectForKey:key];
    }
}

// Extracts the visible label from the "<a ...>Twitter for iPhone</a>" source markup.
+ (NSString*)labelFromSourceHTML:(NSString*)html {
    if (html.length == 0) return nil;

    NSRange open = [html rangeOfString:@">"];
    NSRange close = [html rangeOfString:@"</a>"];
    if (open.location == NSNotFound || close.location == NSNotFound ||
        open.location + 1 >= close.location) {
        return nil;
    }

    NSString* label =
        [html substringWithRange:NSMakeRange(open.location + 1, close.location - open.location - 1)];
    return [label stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (void)markTweetID:(NSString*)tweetID unavailable:(BOOL)unavailable withSource:(NSString*)source {
    // Always resolves back on the main thread where the cache lives.
    dispatch_async(dispatch_get_main_queue(), ^{
        [fetchPending removeObjectForKey:tweetID];

        if (unavailable) {
            tweetSources[tweetID] = [self unavailableString];
        } else {
            tweetSources[tweetID] = source;
            [fetchRetries removeObjectForKey:tweetID];
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:SOURCE_NOTE
                                                            object:nil
                                                          userInfo:@{@"tweetID": tweetID}];
    });
}

+ (void)retryOrFailTweetID:(NSString*)tweetID {
    dispatch_async(dispatch_get_main_queue(), ^{
        [fetchPending removeObjectForKey:tweetID];

        NSInteger retries = [fetchRetries[tweetID] integerValue];
        if (retries >= MAX_FETCH_RETRIES) {
            [self markTweetID:tweetID unavailable:YES withSource:nil];
            return;
        }

        fetchRetries[tweetID] = @(retries + 1);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           [self fetchSourceForTweetID:tweetID];
                       });
    });
}

// Must be called on the main thread.
+ (void)fetchSourceForTweetID:(NSString*)tweetID {
    if (tweetID.length == 0) return;

    [self pruneCacheIfNeeded];

    if ([fetchPending[tweetID] boolValue]) return;

    NSString* existing = tweetSources[tweetID];
    if (existing.length > 0 && ![existing isEqualToString:[self unavailableString]]) return;

    NSDictionary* credentials = currentWebCredentials();
    NSString* authToken = credentials[@"auth_token"];
    NSString* ct0 = credentials[@"ct0"];
    if (authToken.length == 0 || ct0.length == 0) {
        // The web session may not be harvested yet on a cold start; retry rather than
        // giving up, so it recovers once the prewarmed session lands.
        [self retryOrFailTweetID:tweetID];
        return;
    }

    NSURL* url = [self tweetDetailURLForTweetID:tweetID];
    if (!url) {
        [self markTweetID:tweetID unavailable:YES withSource:nil];
        return;
    }

    fetchPending[tweetID] = @(YES);

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 10.0;
    request.HTTPShouldHandleCookies = NO;
    [request setValue:kSourceBearer forHTTPHeaderField:@"authorization"];
    [request setValue:@"OAuth2Session" forHTTPHeaderField:@"x-twitter-auth-type"];
    [request setValue:@"yes" forHTTPHeaderField:@"x-twitter-active-user"];
    [request setValue:@"en" forHTTPHeaderField:@"x-twitter-client-language"];
    [request setValue:ct0 forHTTPHeaderField:@"x-csrf-token"];
    [request setValue:[NSString stringWithFormat:@"auth_token=%@; ct0=%@", authToken, ct0]
        forHTTPHeaderField:@"Cookie"];

    NSURLSessionDataTask* task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
          completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
              NSHTTPURLResponse* http = [response isKindOfClass:[NSHTTPURLResponse class]]
                                            ? (NSHTTPURLResponse*)response
                                            : nil;

              if (error || !data || http.statusCode != 200) {
                  [self retryOrFailTweetID:tweetID];
                  return;
              }

              NSError* jsonError = nil;
              NSDictionary* json = [NSJSONSerialization JSONObjectWithData:data
                                                                   options:0
                                                                     error:&jsonError];
              if (jsonError || ![json isKindOfClass:[NSDictionary class]]) {
                  [self retryOrFailTweetID:tweetID];
                  return;
              }

              NSString* sourceHTML = [self sourceHTMLFromTweetDetail:json forTweetID:tweetID];
              if (sourceHTML.length == 0) {
                  [self markTweetID:tweetID unavailable:YES withSource:nil];
                  return;
              }

              NSString* label = [self labelFromSourceHTML:sourceHTML];
              if (label.length == 0) {
                  label = [[BHTBundle sharedBundle] localizedStringForKey:@"UNKNOWN_SOURCE"];
              }

              [self markTweetID:tweetID unavailable:NO withSource:label];
          }];
    [task resume];
}

@end

// MARK: - Footer injection
//
// -updateFooterTextView rebuilds the footer text from footerItem.timeAgo, so the
// source is appended there before %orig; when it arrives async we just re-run it.

%hook T1ConversationFooterTextView

- (void)updateFooterTextView {
    if (![BHTSettings boolForKey:@"restore_tweet_labels"]) {
        %orig;
        return;
    }

    // Gather identifiers and trigger fetches before letting the system build the
    // footer; append the resolved source afterwards so it appears after any
    // supplementary content (like view counts) the system may add.
    @try {
        id viewModel = self.viewModel;
        id status = [viewModel respondsToSelector:@selector(tweet)]
                        ? [viewModel performSelector:@selector(tweet)]
                        : nil;

        NSString* tweetID = nil;
        if ([status respondsToSelector:@selector(statusID)]) {
            long long statusID = [(TFNTwitterStatus*)status statusID];
            if (statusID > 0) tweetID = [NSString stringWithFormat:@"%lld", statusID];
        }

        if (tweetID.length > 0) {
            objc_setAssociatedObject(self, &kFooterTweetIDKey, tweetID,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            if (![objc_getAssociatedObject(self, &kFooterObservingKey) boolValue]) {
                [[NSNotificationCenter defaultCenter] addObserver:self
                                                         selector:@selector(tweetSourceUpdated:)
                                                             name:SOURCE_NOTE
                                                           object:nil];
                objc_setAssociatedObject(self, &kFooterObservingKey, @(YES),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }

            // Trigger a fetch if we haven't seen this tweet yet, but don't mutate
            // the footer text until after the system's own rebuild below.
            NSString* source = tweetSources[tweetID];
            if (source == nil) {
                tweetSources[tweetID] = @""; // placeholder so we only fetch once
                [TweetSourceHelper fetchSourceForTweetID:tweetID];
            }
        }
    } @catch (__unused NSException* e) {
    }

    // Let the original implementation build the footer UI first.
    %orig;

    // Now append the resolved source (if available) so it appears after other
    // footer content such as view counts.
    if ([BHTSettings boolForKey:@"restore_tweet_labels"]) {
        @try {
            id viewModel = self.viewModel;
            id status = [viewModel respondsToSelector:@selector(tweet)]
                            ? [viewModel performSelector:@selector(tweet)]
                            : nil;

            NSString* tweetID = nil;
            if ([status respondsToSelector:@selector(statusID)]) {
                long long statusID = [(TFNTwitterStatus*)status statusID];
                if (statusID > 0) tweetID = [NSString stringWithFormat:@"%lld", statusID];
            }

            if (tweetID.length > 0) {
                NSString* source = tweetSources[tweetID];

                if (source.length > 0 &&
                    ![source isEqualToString:[TweetSourceHelper unavailableString]]) {
                    T1ConversationFooterItem* footerItem = self.footerItem;
                    NSString* timeAgo = footerItem.timeAgo;

                    if (footerItem && timeAgo.length > 0 &&
                        ![objc_getAssociatedObject(footerItem, &kSourceAppendedKey) boolValue] &&
                        ![timeAgo containsString:source]) {
                        footerItem.timeAgo = [NSString stringWithFormat:@"%@ · %@", timeAgo, source];
                        objc_setAssociatedObject(footerItem, &kSourceAppendedKey, @(YES),
                                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    }
                }
            }
        } @catch (__unused NSException* e) {
        }

        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf BHT_forceRecolorSource];
        });
    }
}

%new
- (void)BHT_forceRecolorSource {
    @try {
        NSString* tweetID = objc_getAssociatedObject(self, &kFooterTweetIDKey);
        NSString* source = tweetID.length > 0 ? tweetSources[tweetID] : nil;
        if (source.length == 0 || [source isEqualToString:[TweetSourceHelper unavailableString]]) {
            return;
        }

        TFNAttributedTextView* textView = self.textView;
        NSAttributedString* current = textView.textModel.attributedString;
        if (current.length == 0) {
            return;
        }

        NSRange range = [current.string rangeOfString:source options:NSBackwardsSearch];
        if (range.location == NSNotFound) {
            return;
        }

        NSMutableAttributedString* recolored = [current mutableCopy];
        [recolored addAttribute:NSForegroundColorAttributeName
                           value:CurrentAccentColor()
                           range:range];
        TFNAttributedTextModel* newModel =
            [[%c(TFNAttributedTextModel) alloc] initWithAttributedString:recolored];
        [textView setTextModel:newModel];
    } @catch (NSException* e) {
    }
}

%new
- (void)tweetSourceUpdated:(NSNotification*)notification {
    NSString* tweetID = notification.userInfo[@"tweetID"];
    NSString* mine = objc_getAssociatedObject(self, &kFooterTweetIDKey);
    if (tweetID.length > 0 && [tweetID isEqualToString:mine]) {
        // Posted from the main queue, so we are already on the main thread here.
        [self updateFooterTextView];
        [self setNeedsDisplay];
        [self setNeedsLayout];
    }
}

- (void)dealloc {
    if ([objc_getAssociatedObject(self, &kFooterObservingKey) boolValue]) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:SOURCE_NOTE object:nil];
    }
    %orig;
}

%end

%ctor {
    if (!tweetSources) tweetSources = [NSMutableDictionary dictionary];
    if (!fetchPending) fetchPending = [NSMutableDictionary dictionary];
    if (!fetchRetries) fetchRetries = [NSMutableDictionary dictionary];

    %init;
}
