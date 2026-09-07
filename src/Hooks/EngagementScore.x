//
//  EngagementScore.x
//  NeoFreeBird
//

#import "HookHelpers.h"

#import "EngagementScore/NFBEngagementScore.h"
#import "EngagementScore/NFBScoreBadgeView.h"

// MARK: - Engagement score badge
//
// X の公開ランキング実装 (xai-org/x-algorithm) の RankingScorer は
//     Final Score = Σ ( weight_i × P(action_i) )
// で順位を決める。P は Phoenix が閲覧者ごとに推論する確率なので端末では取れない。
// 代わりに P ≈ 行動数 / 表示数 と近似したスコアを各ポストに出す。
//
// 差し込み先はインラインアクション行 (返信・リポスト・いいね・ブックマークの並び)。
// タイムラインでも詳細画面でも同じクラスが使われるので、ここ一箇所で両方を覆える。
// 行の既存レイアウトは一切触らず、末尾の余白にだけ置いて、
// 余白が足りなければ黙って隠す。

static char kBadgeKey;
static char kUpdatingKey;

static const CGFloat kBadgeTrailingInset = 2.0;
static const CGFloat kBadgeMinimumGap = 6.0;

static NFBScoreBadgeView* existingBadge(UIView* actionsView) {
    return objc_getAssociatedObject(actionsView, &kBadgeKey);
}

static void removeBadge(UIView* actionsView) {
    NFBScoreBadgeView* badge = existingBadge(actionsView);
    if (!badge) return;

    [badge removeFromSuperview];
    objc_setAssociatedObject(actionsView, &kBadgeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

/// バッジを除いた既存サブビューの右端。ここより右が使える余白。
static CGFloat contentRightEdge(UIView* actionsView, UIView* badge) {
    CGFloat maxX = 0.0;
    for (UIView* subview in actionsView.subviews) {
        if (subview == badge || subview.hidden) continue;
        maxX = MAX(maxX, CGRectGetMaxX(subview.frame));
    }
    return maxX;
}

static void updateBadgeForActionsView(UIView* actionsView) {
    if (![actionsView isKindOfClass:[UIView class]]) return;

    // layoutSubviews から呼ばれるので、自分の変更で再入しないようにする。
    if ([objc_getAssociatedObject(actionsView, &kUpdatingKey) boolValue]) return;

    if (![NFBEngagementScore enabled]) {
        removeBadge(actionsView);
        return;
    }

    objc_setAssociatedObject(actionsView, &kUpdatingKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    @try {
        id viewModel = nil;
        if ([actionsView respondsToSelector:@selector(viewModel)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            viewModel = [actionsView performSelector:@selector(viewModel)];
#pragma clang diagnostic pop
        }

        id status = [NFBEngagementScore statusFromObject:viewModel];
        if (!status) {
            removeBadge(actionsView);
            return;
        }

        NFBScoreBadgeView* badge = existingBadge(actionsView);
        if (!badge) {
            badge = [[NFBScoreBadgeView alloc] initWithFrame:CGRectZero];
            objc_setAssociatedObject(actionsView, &kBadgeKey, badge,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (badge.superview != actionsView) {
            [actionsView addSubview:badge];
        }

        NSString* tweetID = [NFBEngagementScore tweetIDForStatus:status];

        // セルは使い回されるので、中身が変わったときだけ再計算する。
        BOOL sameTweet = tweetID.length > 0 && [tweetID isEqualToString:badge.renderedTweetID];
        if (!sameTweet) {
            NFBScoreResult result = [NFBEngagementScore scoreForStatus:status];
            badge.status = status;
            badge.renderedTweetID = tweetID;
            [badge applyResult:result];

            if ([BHTSettings boolForKey:@"engagement_score_debug"]) {
                [NFBEngagementScore dumpResolvedSelectorsForStatus:status];
            }
        }

        CGFloat width = [badge preferredWidth];
        CGFloat height = badge.intrinsicContentSize.height;
        CGFloat boundsWidth = CGRectGetWidth(actionsView.bounds);
        CGFloat available = boundsWidth - contentRightEdge(actionsView, badge) - kBadgeTrailingInset;

        if (boundsWidth <= 0 || available < width + kBadgeMinimumGap) {
            // 余白が無い画面ではレイアウトを壊すより出さないほうがよい。
            badge.hidden = YES;
            return;
        }

        badge.hidden = NO;
        badge.frame = CGRectMake(boundsWidth - width - kBadgeTrailingInset,
                                 (CGRectGetHeight(actionsView.bounds) - height) / 2.0, width,
                                 height);
    } @catch (__unused NSException* exception) {
        removeBadge(actionsView);
    } @finally {
        objc_setAssociatedObject(actionsView, &kUpdatingKey, @(NO),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// 現行のアクション行。
%hook TTAStatusInlineActionsView

- (void)layoutSubviews {
    %orig;
    updateBadgeForActionsView(self);
}

%end

// 旧世代のアクション行。存在しないビルドでは %init が黙って読み飛ばす。
%hook T1StatusInlineActionsView

- (void)layoutSubviews {
    %orig;
    updateBadgeForActionsView(self);
}

%end

%ctor {
    %init;
}
