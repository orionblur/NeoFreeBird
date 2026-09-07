//
//  NFBScoreMath.h
//  NeoFreeBird
//
//  X の公開ランキング実装 (xai-org/x-algorithm) の RankingScorer を再現する純 C の演算部。
//  Foundation にも UIKit にも依存しないので、ホスト側で単体テストできる。
//
//    repo   : https://github.com/xai-org/x-algorithm  (Apache-2.0)
//    commit : 902a06fd616ed815f660e5546d16d492fa1ca825 (2026-09-04)
//    files  : home-mixer/params/param.rs           … 重みの既定値
//             home-mixer/scorers/ranking_scorer.rs … 合成の算術
//             home-mixer/params/config.rs:40       … NEGATIVE_SCORES_OFFSET
//
//  本家の式:
//      Final Score = Σ ( weight_i × P(action_i) )
//  P は Phoenix が閲覧者ごとに推論する行動確率であって、生のエンゲージメント数ではない
//  (param.rs L285-313 に X 自身の注意書きがある)。端末側では P を取得できないため、
//      P(action_i) ≈ count_i / view_count
//  という経験的推定で近似する。
//

#ifndef NFB_SCORE_MATH_H
#define NFB_SCORE_MATH_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 端末の DOM/モデルから観測できる行動。
typedef enum {
    NFBActionFavorite = 0,
    NFBActionReply,
    NFBActionRetweet,
    NFBActionQuote,
    NFBActionBookmark,
    NFBActionCount
} NFBAction;

/// 取得できなかった件数を表す番兵。0 件とは区別する。
#define NFB_COUNT_UNAVAILABLE (-1LL)

/// RankingScorer の全 26 項の既定重み (param.rs)。
typedef struct {
    // Engagement
    double favorite;
    double reply;
    double retweet;
    double quote;
    double share;
    double share_via_dm;
    double share_via_copy_link;
    // Clicks
    double click;
    double open_link;
    double photo_expand;
    double video_open;
    double profile_click;
    double quoted_click;
    // Attention
    double vqv;
    double quoted_vqv;
    double dwell;
    double cont_dwell_time;
    double cont_click_dwell_time;
    double cont_active_secs_5m_residual_norm;
    // Author
    double follow_author;
    // Exploration
    double post_unexplored;
    // Negative
    double not_interested;
    double block_author;
    double mute_author;
    double report;
    double not_dwelled;
} NFBWeights;

typedef struct {
    long long counts[NFBActionCount]; ///< NFB_COUNT_UNAVAILABLE で不明
    long long views;                  ///< NFB_COUNT_UNAVAILABLE で不明
} NFBCounts;

typedef struct {
    /// 観測できる 5 行動に適用する重み。ブックマークは本家に項が無いので既定 0。
    double observedWeights[NFBActionCount];
    bool assumeBidirectionalFollow; ///< 返信の重みに +15.0 (reply_weight_for)
    bool applyAuthorDiversity;      ///< (1-floor)*decay^k + floor
    int authorRank;                 ///< 上式の k
    bool applyOonDiscount;          ///< ×0.75
    double displayScale;            ///< 表示倍率 (既定 1000)
} NFBScoreOptions;

typedef struct {
    bool available[NFBActionCount];
    double rate[NFBActionCount];         ///< count / views
    double contribution[NFBActionCount]; ///< weight × rate (表示倍率適用前)
    double appliedWeight[NFBActionCount];

    double probCombined; ///< Σ の生値
    double probScore;    ///< offset と後段補正を適用した値
    double display;      ///< probScore × displayScale
    bool hasProbScore;   ///< 表示数が無い等で計算できなければ false

    double naiveScore; ///< Σ weight × count（本家が誤りと注意している式。比較用）

    double engagementRate;
    long long totalEngagements;

    double diversityMultiplier;
    double oonMultiplier;
} NFBScoreResult;

/// param.rs の既定値。
NFBWeights NFBDefaultWeights(void);

/// 観測できる 5 行動の既定重み（bookmark は本家に項が無いため 0）。
void NFBDefaultObservedWeights(double out[NFBActionCount]);

NFBScoreOptions NFBDefaultScoreOptions(void);

/// ScoringWeights::from_params の positive_sum / negative_sum / total_sum。
double NFBWeightPositiveSum(const NFBWeights* w);
double NFBWeightNegativeSum(const NFBWeights* w);
double NFBWeightTotalSum(const NFBWeights* w);

/// RankingScorer::offset_score (ranking_scorer.rs L472-480)。
double NFBOffsetScore(double combined, const NFBWeights* w);

/// RankingScorer::diversity_multiplier (ranking_scorer.rs L561-563)。
double NFBDiversityMultiplier(int k);

/// 1 ポントのスコアを計算する。result は必ず全項目が埋まる。
void NFBComputeScore(const NFBCounts* counts, const NFBScoreOptions* options,
                     NFBScoreResult* result);

/// 表示スコアからグレード文字（"S".."E"、計算不能なら "?"）。
const char* NFBGradeLetter(const NFBScoreResult* result);

/// 行動の識別子（ログ・デバッグ用の安定した英語名）。
const char* NFBActionName(NFBAction action);

#ifdef __cplusplus
}
#endif

#endif /* NFB_SCORE_MATH_H */
