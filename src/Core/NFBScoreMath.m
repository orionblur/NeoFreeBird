//
//  NFBScoreMath.m
//  NeoFreeBird
//
//  純 C の実装。拡張子が .m なのは Makefile の
//      BHTwitter_FILES = $(shell find src \( -name '*.x' -o -name '*.m' \) | sort)
//  に拾わせるためで、中身に Objective-C は一切含まれない
//  （そのおかげでホスト上の clang -x c で単体テストできる）。
//

#include "NFBScoreMath.h"

#include <math.h>

// param.rs L253-277 / L229-245 / config.rs:40
static const double kNegativeScoresOffset = 0.001;
static const double kAuthorDiversityDecay = 0.5;
static const double kAuthorDiversityFloor = 0.25;
static const double kOonWeightFactor = 0.75;
static const double kBidirectionalFollowReplyBoost = 15.0;

NFBWeights NFBDefaultWeights(void) {
    NFBWeights w;
    // Engagement
    w.favorite = 0.5;             // rust_home_mixer_favorite_weight
    w.reply = 5.0;                // rust_home_mixer_reply_weight
    w.retweet = 1.0;              // rust_home_mixer_retweet_weight
    w.quote = 5.0;                // rust_home_mixer_quote_weight
    w.share = 2.0;                // rust_home_mixer_share_weight
    w.share_via_dm = 5.0;         // rust_home_mixer_share_via_dm_weight
    w.share_via_copy_link = 20.0; // rust_home_mixer_share_via_copy_link_weight
    // Clicks
    w.click = 0.4;         // rust_home_mixer_click_weight
    w.open_link = 0.2;     // rust_home_mixer_open_link_weight
    w.photo_expand = 0.05; // rust_home_mixer_photo_expand_weight
    w.video_open = 0.07;   // rust_home_mixer_video_open_weight
    w.profile_click = 0.0; // rust_home_mixer_profile_click_weight
    w.quoted_click = 0.05; // rust_home_mixer_quoted_click_weight
    // Attention
    w.vqv = 0.0;                                // rust_home_mixer_vqv_weight
    w.quoted_vqv = 0.0;                         // rust_home_mixer_quoted_vqv_weight
    w.dwell = 0.05;                             // rust_home_mixer_dwell_weight
    w.cont_dwell_time = 0.004;                  // rust_home_mixer_cont_dwell_time_weight
    w.cont_click_dwell_time = 0.0;              // rust_home_mixer_cont_click_dwell_time_weight
    w.cont_active_secs_5m_residual_norm = 0.0;  // rust_home_mixer_cont_active_secs_5m_...
    // Author / exploration
    w.follow_author = 4.0;    // rust_home_mixer_follow_author_weight
    w.post_unexplored = 0.02; // rust_home_mixer_post_unexplored_weight
    // Negative
    w.not_interested = -43.2; // rust_home_mixer_not_interested_weight
    w.block_author = -31.2;   // rust_home_mixer_block_author_weight
    w.mute_author = -58.8;    // rust_home_mixer_mute_author_weight
    w.report = -234.0;        // rust_home_mixer_report_weight
    w.not_dwelled = -0.02;    // rust_home_mixer_not_dwelled_weight
    return w;
}

void NFBDefaultObservedWeights(double out[NFBActionCount]) {
    NFBWeights w = NFBDefaultWeights();
    out[NFBActionFavorite] = w.favorite;
    out[NFBActionReply] = w.reply;
    out[NFBActionRetweet] = w.retweet;
    out[NFBActionQuote] = w.quote;
    // RankingScorer に BookmarkWeight は存在しない。Phoenix は ClientTweetBookmark を
    // 予測するが重み付き和には入らないので 0。設定で変更できる。
    out[NFBActionBookmark] = 0.0;
}

NFBScoreOptions NFBDefaultScoreOptions(void) {
    NFBScoreOptions o;
    NFBDefaultObservedWeights(o.observedWeights);
    o.assumeBidirectionalFollow = false;
    o.applyAuthorDiversity = false;
    o.authorRank = 0;
    o.applyOonDiscount = false;
    o.displayScale = 1000.0;
    return o;
}

double NFBWeightPositiveSum(const NFBWeights* w) {
    return w->favorite + w->reply + w->retweet + w->photo_expand + w->video_open + w->click +
           w->open_link + w->profile_click + w->vqv + w->share + w->share_via_dm +
           w->share_via_copy_link + w->dwell + w->quote + w->quoted_click + w->quoted_vqv +
           w->follow_author + w->post_unexplored;
}

double NFBWeightNegativeSum(const NFBWeights* w) {
    return -(w->not_interested + w->block_author + w->mute_author + w->report + w->not_dwelled);
}

double NFBWeightTotalSum(const NFBWeights* w) {
    return NFBWeightPositiveSum(w) + NFBWeightNegativeSum(w);
}

double NFBOffsetScore(double combined, const NFBWeights* w) {
    double total = NFBWeightTotalSum(w);
    if (total == 0.0) {
        return combined > 0.0 ? combined : 0.0;
    }
    if (combined < 0.0) {
        return ((combined + NFBWeightNegativeSum(w)) / total) * kNegativeScoresOffset;
    }
    return combined + kNegativeScoresOffset;
}

double NFBDiversityMultiplier(int k) {
    if (k <= 0) return 1.0;
    return (1.0 - kAuthorDiversityFloor) * pow(kAuthorDiversityDecay, (double)k) +
           kAuthorDiversityFloor;
}

void NFBComputeScore(const NFBCounts* counts, const NFBScoreOptions* options,
                     NFBScoreResult* result) {
    NFBWeights weights = NFBDefaultWeights();

    for (int i = 0; i < NFBActionCount; i++) {
        result->available[i] = false;
        result->rate[i] = NAN;
        result->contribution[i] = NAN;
        result->appliedWeight[i] = options->observedWeights[i];
    }
    result->probCombined = 0.0;
    result->probScore = NAN;
    result->display = NAN;
    result->hasProbScore = false;
    result->naiveScore = 0.0;
    result->engagementRate = NAN;
    result->totalEngagements = 0;
    result->diversityMultiplier = 1.0;
    result->oonMultiplier = 1.0;

    // reply_weight_for(): 相互フォロー相手への返信は 5.0 → 20.0
    if (options->assumeBidirectionalFollow && kBidirectionalFollowReplyBoost != 0.0) {
        result->appliedWeight[NFBActionReply] =
            options->observedWeights[NFBActionReply] + kBidirectionalFollowReplyBoost;
    }

    bool hasViews = counts->views > 0;
    bool anyObserved = false;

    for (int i = 0; i < NFBActionCount; i++) {
        long long c = counts->counts[i];
        if (c == NFB_COUNT_UNAVAILABLE || c < 0) {
            continue; // 不明。0 件として扱わず項ごと除外する。
        }
        result->available[i] = true;
        anyObserved = true;
        result->totalEngagements += c;
        result->naiveScore += (double)c * result->appliedWeight[i];

        if (hasViews) {
            double rate = (double)c / (double)counts->views;
            result->rate[i] = rate;
            result->contribution[i] = rate * result->appliedWeight[i];
            result->probCombined += result->contribution[i];
        }
    }

    if (!anyObserved || !hasViews) {
        return;
    }

    result->engagementRate = (double)result->totalEngagements / (double)counts->views;

    double score = NFBOffsetScore(result->probCombined, &weights);

    if (options->applyAuthorDiversity && options->authorRank > 0) {
        result->diversityMultiplier = NFBDiversityMultiplier(options->authorRank);
        score *= result->diversityMultiplier;
    }
    if (options->applyOonDiscount) {
        result->oonMultiplier = kOonWeightFactor;
        score *= kOonWeightFactor;
    }

    result->probScore = score;
    result->display = score * options->displayScale;
    result->hasProbScore = true;
}

const char* NFBGradeLetter(const NFBScoreResult* result) {
    if (!result->hasProbScore || isnan(result->display)) return "?";
    double d = result->display;
    if (d >= 60.0) return "S";
    if (d >= 35.0) return "A";
    if (d >= 20.0) return "B";
    if (d >= 10.0) return "C";
    if (d >= 4.0) return "D";
    return "E";
}

const char* NFBActionName(NFBAction action) {
    switch (action) {
        case NFBActionFavorite: return "favorite";
        case NFBActionReply: return "reply";
        case NFBActionRetweet: return "retweet";
        case NFBActionQuote: return "quote";
        case NFBActionBookmark: return "bookmark";
        default: return "unknown";
    }
}
