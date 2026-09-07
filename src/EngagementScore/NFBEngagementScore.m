//
//  NFBEngagementScore.m
//  NeoFreeBird
//

#import "NFBEngagementScore.h"

#import <math.h>
#import <objc/runtime.h>

#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"

// MARK: - 数値の取り出し
//
// 内部モデルの count 系プロパティは long long / NSInteger / NSUInteger / int /
// NSNumber* のいずれでも返りうる。戻り値の型エンコーディングを見て正しく読む。

static BOOL NFBLongLongFromSelector(id object, SEL selector, long long* out) {
    if (!object || !selector || ![object respondsToSelector:selector]) return NO;

    NSMethodSignature* signature = nil;
    @try {
        signature = [object methodSignatureForSelector:selector];
    } @catch (__unused NSException* e) {
        return NO;
    }
    if (!signature || signature.numberOfArguments != 2) return NO;

    const char* type = signature.methodReturnType;
    if (!type) return NO;

    NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.selector = selector;
    @try {
        [invocation invokeWithTarget:object];
    } @catch (__unused NSException* e) {
        return NO;
    }

    switch (type[0]) {
        case 'q': { // long long
            long long v = 0;
            [invocation getReturnValue:&v];
            *out = v;
            return YES;
        }
        case 'Q': { // unsigned long long
            unsigned long long v = 0;
            [invocation getReturnValue:&v];
            *out = (long long)v;
            return YES;
        }
        case 'l': case 'i': {
            int32_t v = 0;
            [invocation getReturnValue:&v];
            *out = v;
            return YES;
        }
        case 'L': case 'I': {
            uint32_t v = 0;
            [invocation getReturnValue:&v];
            *out = v;
            return YES;
        }
        case 's': case 'S': case 'c': case 'C': {
            // 短い整数型。boolean の可能性もあるが count 系では実害がない。
            int32_t v = 0;
            [invocation getReturnValue:&v];
            *out = v;
            return YES;
        }
        case 'd': {
            double v = 0;
            [invocation getReturnValue:&v];
            *out = (long long)v;
            return YES;
        }
        case '@': {
            void* raw = NULL;
            [invocation getReturnValue:&raw];
            id value = (__bridge id)raw;
            if ([value isKindOfClass:[NSNumber class]]) {
                *out = [(NSNumber*)value longLongValue];
                return YES;
            }
            return NO;
        }
        default:
            return NO;
    }
}

// MARK: - セレクタ探索
//
// 世代ごとに違う名前が使われてきたので候補を順に試し、
// どれも無ければプロパティ一覧から名前で推測する。結果はクラス単位でキャッシュ。

static NSArray<NSString*>* NFBCandidateNames(NFBAction action) {
    switch (action) {
        case NFBActionFavorite:
            return @[ @"favoriteCount", @"favoritedCount", @"likeCount", @"favouriteCount" ];
        case NFBActionReply:
            return @[ @"replyCount", @"conversationCount", @"repliesCount" ];
        case NFBActionRetweet:
            return @[ @"retweetCount", @"repostCount", @"retweetedCount" ];
        case NFBActionQuote:
            return @[ @"quoteCount", @"quotedTweetCount", @"quoteTweetCount", @"quotesCount" ];
        case NFBActionBookmark:
            return @[ @"bookmarkCount", @"bookmarksCount" ];
        default:
            return @[];
    }
}

static NSArray<NSString*>* NFBViewCountCandidates(void) {
    return @[ @"viewCount", @"viewsCount", @"impressionCount", @"impressionsCount", @"views" ];
}

/// プロパティ名が「この指標の件数」らしいかの推測。候補が全滅したときだけ使う。
static BOOL NFBNameLooksLike(NSString* name, NFBAction action) {
    NSString* lower = name.lowercaseString;
    if (![lower hasSuffix:@"count"]) return NO;

    switch (action) {
        case NFBActionFavorite:
            return [lower containsString:@"favorite"] || [lower containsString:@"favourite"] ||
                   [lower containsString:@"like"];
        case NFBActionReply:
            return [lower containsString:@"reply"] || [lower containsString:@"replies"];
        case NFBActionRetweet:
            return [lower containsString:@"retweet"] || [lower containsString:@"repost"];
        case NFBActionQuote:
            return [lower containsString:@"quote"];
        case NFBActionBookmark:
            return [lower containsString:@"bookmark"];
        default:
            return NO;
    }
}

static NSArray<NSString*>* NFBPropertyNamesForClass(Class cls) {
    static NSMutableDictionary<NSString*, NSArray<NSString*>*>* cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });

    NSString* key = NSStringFromClass(cls);
    NSArray<NSString*>* cached = cache[key];
    if (cached) return cached;

    NSMutableArray<NSString*>* names = [NSMutableArray array];
    Class current = cls;
    while (current && current != [NSObject class]) {
        unsigned int count = 0;
        objc_property_t* properties = class_copyPropertyList(current, &count);
        for (unsigned int i = 0; i < count; i++) {
            const char* name = property_getName(properties[i]);
            if (name) [names addObject:@(name)];
        }
        if (properties) free(properties);
        current = class_getSuperclass(current);
    }

    cache[key] = [names copy];
    return cache[key];
}

/// クラス+指標 に対して実際に値が読めたセレクタ名。@"" は「解決不能」の記録。
static NSString* NFBResolvedName(id object, NFBAction action, NSArray<NSString*>* candidates) {
    static NSMutableDictionary<NSString*, NSString*>* cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });

    Class cls = object_getClass(object);
    NSString* key = [NSString stringWithFormat:@"%@#%d", NSStringFromClass(cls), (int)action];
    NSString* cached = cache[key];
    if (cached) return cached.length ? cached : nil;

    NSString* resolved = @"";
    long long scratch = 0;

    for (NSString* name in candidates) {
        SEL selector = NSSelectorFromString(name);
        if (NFBLongLongFromSelector(object, selector, &scratch)) {
            resolved = name;
            break;
        }
    }

    if (resolved.length == 0 && action < NFBActionCount) {
        for (NSString* name in NFBPropertyNamesForClass(cls)) {
            if (!NFBNameLooksLike(name, action)) continue;
            if (NFBLongLongFromSelector(object, NSSelectorFromString(name), &scratch)) {
                resolved = name;
                break;
            }
        }
    }

    cache[key] = resolved;
    return resolved.length ? resolved : nil;
}

static long long NFBCountForAction(id status, NFBAction action) {
    NSString* name = NFBResolvedName(status, action, NFBCandidateNames(action));
    long long value = 0;
    if (name && NFBLongLongFromSelector(status, NSSelectorFromString(name), &value)) {
        return value < 0 ? NFB_COUNT_UNAVAILABLE : value;
    }
    return NFB_COUNT_UNAVAILABLE;
}

static long long NFBViewCount(id status) {
    long long value = 0;

    for (NSString* name in NFBViewCountCandidates()) {
        SEL selector = NSSelectorFromString(name);
        if (NFBLongLongFromSelector(status, selector, &value)) {
            return value < 0 ? NFB_COUNT_UNAVAILABLE : value;
        }
    }

    // 表示数はネストしたオブジェクトに載っていることがある。
    for (NSString* container in @[ @"viewCountInfo", @"viewCounts", @"tweetViewCount" ]) {
        SEL selector = NSSelectorFromString(container);
        if (![status respondsToSelector:selector]) continue;

        id nested = nil;
        @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            nested = [status performSelector:selector];
#pragma clang diagnostic pop
        } @catch (__unused NSException* e) {
            continue;
        }
        if (!nested) continue;

        for (NSString* name in @[ @"count", @"viewCount", @"value" ]) {
            if (NFBLongLongFromSelector(nested, NSSelectorFromString(name), &value)) {
                return value < 0 ? NFB_COUNT_UNAVAILABLE : value;
            }
        }
    }

    return NFB_COUNT_UNAVAILABLE;
}

// MARK: - 相対順位・著者多様性の状態

static NSMutableArray<NSNumber*>* NFBRecentScores(void) {
    static NSMutableArray<NSNumber*>* recent;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        recent = [NSMutableArray array];
    });
    return recent;
}

static NSMutableDictionary<NSString*, NSMutableArray<NSNumber*>*>* NFBAuthorScores(void) {
    static NSMutableDictionary<NSString*, NSMutableArray<NSNumber*>*>* map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = [NSMutableDictionary dictionary];
    });
    return map;
}

/// author_pool_counts と同じ考え方で「自分より高いスコアの同著者ポスト数」を数える。
static int NFBAuthorRank(NSString* screenName, NSString* tweetID, double preScore) {
    if (screenName.length == 0) return 0;

    NSMutableDictionary* seen = NFBAuthorScores();
    NSMutableArray<NSNumber*>* list = seen[screenName];
    if (!list) {
        list = [NSMutableArray array];
        seen[screenName] = list;
    }

    // 同じポストを二重に数えない。
    static NSMutableSet<NSString*>* counted;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        counted = [NSMutableSet set];
    });

    int rank = 0;
    for (NSNumber* value in list) {
        if (value.doubleValue > preScore) rank++;
    }

    NSString* key = tweetID.length ? tweetID : nil;
    if (!key || ![counted containsObject:key]) {
        [list addObject:@(preScore)];
        if (list.count > 50) [list removeObjectAtIndex:0];
        if (key) {
            [counted addObject:key];
            if (counted.count > 500) [counted removeAllObjects];
        }
    }

    return rank;
}

// MARK: -

@implementation NFBEngagementScore

+ (BOOL)enabled {
    return [BHTSettings boolForKey:@"show_engagement_score"];
}

+ (id)statusFromObject:(id)object {
    if (!object) return nil;

    Class statusClass = NSClassFromString(@"TFNTwitterStatus");
    if (statusClass && [object isKindOfClass:statusClass]) return object;

    static NSArray<NSString*>* paths;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        paths = @[ @"tweet", @"status", @"statusViewModel", @"viewModel", @"tweetViewModel" ];
    });

    for (NSString* name in paths) {
        SEL selector = NSSelectorFromString(name);
        if (![object respondsToSelector:selector]) continue;

        id next = nil;
        @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            next = [object performSelector:selector];
#pragma clang diagnostic pop
        } @catch (__unused NSException* e) {
            continue;
        }
        if (!next || next == object) continue;

        if (statusClass && [next isKindOfClass:statusClass]) return next;

        // 一段だけ潜る。無制限に辿るとサイクルに落ちる。
        for (NSString* inner in paths) {
            SEL innerSelector = NSSelectorFromString(inner);
            if (![next respondsToSelector:innerSelector]) continue;

            id leaf = nil;
            @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                leaf = [next performSelector:innerSelector];
#pragma clang diagnostic pop
            } @catch (__unused NSException* e) {
                continue;
            }
            if (statusClass && leaf && [leaf isKindOfClass:statusClass]) return leaf;
        }
    }

    return nil;
}

+ (NSString*)tweetIDForStatus:(id)status {
    if (!status) return nil;

    long long value = 0;
    for (NSString* name in @[ @"statusID", @"tweetID", @"identifier", @"statusId" ]) {
        if (NFBLongLongFromSelector(status, NSSelectorFromString(name), &value) && value > 0) {
            return [NSString stringWithFormat:@"%lld", value];
        }
    }
    return nil;
}

+ (NSString*)screenNameForStatus:(id)status {
    if (!status) return nil;

    for (NSString* name in @[ @"fromUserName", @"authorScreenName", @"screenName" ]) {
        SEL selector = NSSelectorFromString(name);
        if (![status respondsToSelector:selector]) continue;

        id value = nil;
        @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            value = [status performSelector:selector];
#pragma clang diagnostic pop
        } @catch (__unused NSException* e) {
            continue;
        }
        if ([value isKindOfClass:[NSString class]] && [(NSString*)value length] > 0) {
            return [(NSString*)value lowercaseString];
        }
    }

    for (NSString* name in @[ @"author", @"user" ]) {
        SEL selector = NSSelectorFromString(name);
        if (![status respondsToSelector:selector]) continue;

        id author = nil;
        @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            author = [status performSelector:selector];
#pragma clang diagnostic pop
        } @catch (__unused NSException* e) {
            continue;
        }
        if (!author) continue;

        for (NSString* inner in @[ @"screenName", @"username", @"handle" ]) {
            SEL innerSelector = NSSelectorFromString(inner);
            if (![author respondsToSelector:innerSelector]) continue;

            id value = nil;
            @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                value = [author performSelector:innerSelector];
#pragma clang diagnostic pop
            } @catch (__unused NSException* e) {
                continue;
            }
            if ([value isKindOfClass:[NSString class]] && [(NSString*)value length] > 0) {
                return [(NSString*)value lowercaseString];
            }
        }
    }

    return nil;
}

+ (NFBCounts)countsForStatus:(id)status {
    NFBCounts counts;
    for (int i = 0; i < NFBActionCount; i++) {
        counts.counts[i] = status ? NFBCountForAction(status, (NFBAction)i) : NFB_COUNT_UNAVAILABLE;
    }
    counts.views = status ? NFBViewCount(status) : NFB_COUNT_UNAVAILABLE;
    return counts;
}

+ (NFBScoreOptions)optionsForStatus:(id)status tweetID:(NSString*)tweetID {
    NFBScoreOptions options = NFBDefaultScoreOptions();
    options.applyOonDiscount = [BHTSettings boolForKey:@"engagement_score_oon_discount"];
    options.assumeBidirectionalFollow =
        [BHTSettings boolForKey:@"engagement_score_bidirectional_reply"];

    if ([BHTSettings boolForKey:@"engagement_score_author_diversity"]) {
        // 補正前スコアを一度計算してから k を決める（本家も pre_diversity_scores 順に数える）。
        NFBCounts counts = [self countsForStatus:status];
        NFBScoreOptions plain = NFBDefaultScoreOptions();
        plain.assumeBidirectionalFollow = options.assumeBidirectionalFollow;
        NFBScoreResult pre;
        NFBComputeScore(&counts, &plain, &pre);

        NSString* screenName = [self screenNameForStatus:status];
        options.applyAuthorDiversity = YES;
        options.authorRank =
            NFBAuthorRank(screenName, tweetID, pre.hasProbScore ? pre.probScore : 0.0);
    }

    return options;
}

+ (NFBScoreResult)scoreForStatus:(id)status {
    NFBCounts counts = [self countsForStatus:status];
    NSString* tweetID = [self tweetIDForStatus:status];
    NFBScoreOptions options = [self optionsForStatus:status tweetID:tweetID];

    NFBScoreResult result;
    NFBComputeScore(&counts, &options, &result);

    if (result.hasProbScore) {
        NSMutableArray<NSNumber*>* recent = NFBRecentScores();
        [recent addObject:@(result.display)];
        if (recent.count > 300) [recent removeObjectAtIndex:0];
    }

    return result;
}

+ (NSString*)badgeTextForResult:(NFBScoreResult)result {
    if ([BHTSettings boolForKey:@"engagement_score_naive_mode"]) {
        return [NSString stringWithFormat:@"%.0f", result.naiveScore];
    }
    if (!result.hasProbScore) {
        return [[BHTBundle sharedBundle] localizedStringForKey:@"ENGAGEMENT_SCORE_NO_VIEWS"];
    }
    return [NSString stringWithFormat:@"%.1f", result.display];
}

+ (NSString*)gradeLetterForResult:(NFBScoreResult)result {
    return @(NFBGradeLetter(&result));
}

+ (UIColor*)gradeColorForResult:(NFBScoreResult)result {
    NSString* letter = [self gradeLetterForResult:result];

    if ([letter isEqualToString:@"S"]) return [UIColor colorWithRed:0.659 green:0.333 blue:0.969 alpha:1];
    if ([letter isEqualToString:@"A"]) return [UIColor colorWithRed:0.937 green:0.267 blue:0.267 alpha:1];
    if ([letter isEqualToString:@"B"]) return [UIColor colorWithRed:0.961 green:0.620 blue:0.043 alpha:1];
    if ([letter isEqualToString:@"C"]) return [UIColor colorWithRed:0.063 green:0.725 blue:0.506 alpha:1];
    if ([letter isEqualToString:@"D"]) return [UIColor colorWithRed:0.231 green:0.510 blue:0.965 alpha:1];
    return [UIColor colorWithRed:0.420 green:0.447 blue:0.502 alpha:1];
}

+ (double)percentileForDisplay:(double)display {
    NSArray<NSNumber*>* recent = [NFBRecentScores() copy];
    if (recent.count < 5) return -1.0;

    NSUInteger below = 0;
    for (NSNumber* value in recent) {
        if (value.doubleValue < display) below++;
    }
    return (double)below / (double)recent.count;
}

+ (NSString*)breakdownTextForStatus:(id)status result:(NFBScoreResult)result {
    NFBCounts counts = [self countsForStatus:status];
    BHTBundle* bundle = [BHTBundle sharedBundle];

    NSArray<NSString*>* labels = @[
        [bundle localizedStringForKey:@"ENGAGEMENT_SCORE_ACTION_FAVORITE"],
        [bundle localizedStringForKey:@"ENGAGEMENT_SCORE_ACTION_REPLY"],
        [bundle localizedStringForKey:@"ENGAGEMENT_SCORE_ACTION_RETWEET"],
        [bundle localizedStringForKey:@"ENGAGEMENT_SCORE_ACTION_QUOTE"],
        [bundle localizedStringForKey:@"ENGAGEMENT_SCORE_ACTION_BOOKMARK"],
    ];

    NSMutableString* text = [NSMutableString string];
    double scale = 1000.0;

    for (int i = 0; i < NFBActionCount; i++) {
        NSString* label = i < (int)labels.count ? labels[i] : @(NFBActionName((NFBAction)i));
        if (!result.available[i]) {
            [text appendFormat:@"%@  —\n", label];
            continue;
        }
        if (isnan(result.rate[i])) {
            [text appendFormat:@"%@  %lld\n", label, counts.counts[i]];
            continue;
        }
        [text appendFormat:@"%@  %lld  (%.3f%%)  ×%.2f  →  %.2f\n", label, counts.counts[i],
                           result.rate[i] * 100.0, result.appliedWeight[i],
                           result.contribution[i] * scale];
    }

    [text appendString:@"\n"];

    if (counts.views != NFB_COUNT_UNAVAILABLE) {
        [text appendFormat:@"%@ %lld\n", [bundle localizedStringForKey:@"ENGAGEMENT_SCORE_VIEWS"],
                           counts.views];
    } else {
        [text appendFormat:@"%@\n", [bundle localizedStringForKey:@"ENGAGEMENT_SCORE_NO_VIEWS"]];
    }

    if (result.hasProbScore) {
        [text appendFormat:@"%@ %.2f\n",
                           [bundle localizedStringForKey:@"ENGAGEMENT_SCORE_PROBABILITY"],
                           result.display];
    }
    [text appendFormat:@"%@ %.0f\n", [bundle localizedStringForKey:@"ENGAGEMENT_SCORE_NAIVE"],
                       result.naiveScore];

    if (result.diversityMultiplier != 1.0) {
        [text appendFormat:@"%@ ×%.3f\n",
                           [bundle localizedStringForKey:@"ENGAGEMENT_SCORE_DIVERSITY"],
                           result.diversityMultiplier];
    }
    if (result.oonMultiplier != 1.0) {
        [text appendFormat:@"%@ ×%.3f\n", [bundle localizedStringForKey:@"ENGAGEMENT_SCORE_OON"],
                           result.oonMultiplier];
    }

    double percentile = result.hasProbScore ? [self percentileForDisplay:result.display] : -1.0;
    if (percentile >= 0.0) {
        [text appendFormat:@"%@ %.0f%%\n",
                           [bundle localizedStringForKey:@"ENGAGEMENT_SCORE_PERCENTILE"],
                           (1.0 - percentile) * 100.0];
    }

    [text appendFormat:@"\n%@", [bundle localizedStringForKey:@"ENGAGEMENT_SCORE_FOOTNOTE"]];
    return text;
}

+ (void)dumpResolvedSelectorsForStatus:(id)status {
    if (!status) {
        NSLog(@"[NFB/EngagementScore] status is nil");
        return;
    }

    NSLog(@"[NFB/EngagementScore] status class: %@", NSStringFromClass(object_getClass(status)));
    for (int i = 0; i < NFBActionCount; i++) {
        NSString* resolved =
            NFBResolvedName(status, (NFBAction)i, NFBCandidateNames((NFBAction)i));
        NSLog(@"[NFB/EngagementScore]   %-9s -> %@ (%lld)", NFBActionName((NFBAction)i),
              resolved ?: @"(unresolved)", NFBCountForAction(status, (NFBAction)i));
    }
    NSLog(@"[NFB/EngagementScore]   views     -> %lld", NFBViewCount(status));

    NSMutableArray<NSString*>* countish = [NSMutableArray array];
    for (NSString* name in NFBPropertyNamesForClass(object_getClass(status))) {
        if ([name.lowercaseString hasSuffix:@"count"]) [countish addObject:name];
    }
    NSLog(@"[NFB/EngagementScore]   *count properties: %@",
          [countish componentsJoinedByString:@", "]);
}

@end
