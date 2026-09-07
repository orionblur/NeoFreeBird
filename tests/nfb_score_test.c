/*
 *  nfb_score_test.c
 *  NeoFreeBird — NFBScoreMath の単体検証
 *
 *  ホスト上で実行する:
 *      clang -std=c11 -Isrc/Core -x c tests/nfb_score_test.c src/Core/NFBScoreMath.m -lm \
 *          -o /tmp/nfb_score_test && /tmp/nfb_score_test
 *
 *  期待値は x-algorithm の Rust 実装と、同じ重みで書いた JavaScript 実装
 *  （X Engagement Score 拡張）の双方に一致することを確認したもの。
 */

#include <math.h>
#include <stdio.h>

#include "NFBScoreMath.h"

static int g_pass = 0;
static int g_fail = 0;

static void eq(double actual, double expected, const char* name) {
    if (fabs(actual - expected) < 1e-9) {
        g_pass++;
    } else {
        g_fail++;
        printf("  x %s\n      expected %.12f\n      actual   %.12f\n", name, expected, actual);
    }
}

static void ok(int cond, const char* name) {
    if (cond) {
        g_pass++;
    } else {
        g_fail++;
        printf("  x %s\n", name);
    }
}

static NFBCounts makeCounts(long long fav, long long reply, long long rt, long long quote,
                            long long bm, long long views) {
    NFBCounts c;
    c.counts[NFBActionFavorite] = fav;
    c.counts[NFBActionReply] = reply;
    c.counts[NFBActionRetweet] = rt;
    c.counts[NFBActionQuote] = quote;
    c.counts[NFBActionBookmark] = bm;
    c.views = views;
    return c;
}

int main(void) {
    NFBWeights w = NFBDefaultWeights();

    printf("\n[1] ScoringWeights::from_params の 3 つの和\n");
    eq(NFBWeightPositiveSum(&w), 43.34, "positive_sum");
    eq(NFBWeightNegativeSum(&w), 367.22, "negative_sum");
    eq(NFBWeightTotalSum(&w), 410.56, "total_sum");

    printf("[2] offset_score (ranking_scorer.rs L472-480)\n");
    eq(NFBOffsetScore(1.0, &w), 1.001, "正: combined + 0.001");
    eq(NFBOffsetScore(0.0, &w), 0.001, "0: offset のみ");
    eq(NFBOffsetScore(-10.0, &w), ((-10.0 + 367.22) / 410.56) * 0.001, "負: 正規化して写像");

    printf("[3] diversity_multiplier ((1-floor)*decay^k + floor)\n");
    eq(NFBDiversityMultiplier(0), 1.0, "k=0");
    eq(NFBDiversityMultiplier(1), 0.625, "k=1");
    eq(NFBDiversityMultiplier(2), 0.4375, "k=2");
    ok(NFBDiversityMultiplier(20) > 0.25, "floor 0.25 に漸近");

    printf("[4] 確率近似スコア\n");
    NFBScoreOptions o = NFBDefaultScoreOptions();
    NFBCounts c = makeCounts(200, 20, 30, 5, 40, 10000);
    NFBScoreResult r;
    NFBComputeScore(&c, &o, &r);

    double expected = (200.0 / 10000) * 0.5 + (20.0 / 10000) * 5.0 + (30.0 / 10000) * 1.0 +
                      (5.0 / 10000) * 5.0 + (40.0 / 10000) * 0.0;
    eq(r.probCombined, expected, "Sum w x (count/views)");
    eq(r.probScore, expected + 0.001, "offset 適用後");
    eq(r.display, (expected + 0.001) * 1000.0, "表示スケール x1000");
    eq(r.naiveScore, 200 * 0.5 + 20 * 5.0 + 30 * 1.0 + 5 * 5.0 + 40 * 0.0, "生カウント式");
    eq(r.engagementRate, 295.0 / 10000.0, "総エンゲージ率");
    eq((double)r.totalEngagements, 295.0, "総エンゲージ数");
    ok(NFBGradeLetter(&r)[0] == 'B', "グレード B");

    printf("[5] 相互フォロー時の返信ブースト (5.0 -> 20.0)\n");
    NFBScoreOptions ob = o;
    ob.assumeBidirectionalFollow = true;
    NFBScoreResult rb;
    NFBComputeScore(&c, &ob, &rb);
    eq(rb.appliedWeight[NFBActionReply], 20.0, "reply_weight_for");
    eq(rb.probCombined - r.probCombined, (20.0 / 10000) * 15.0, "差分は 15.0 x reply率");

    printf("[6] 後段補正\n");
    NFBScoreOptions od = o;
    od.applyAuthorDiversity = true;
    od.authorRank = 2;
    od.applyOonDiscount = true;
    NFBScoreResult rd;
    NFBComputeScore(&c, &od, &rd);
    eq(rd.probScore, (expected + 0.001) * 0.4375 * 0.75, "著者多様性 k=2 x OON 0.75");
    eq(rd.diversityMultiplier, 0.4375, "diversityMultiplier");
    eq(rd.oonMultiplier, 0.75, "oonMultiplier");

    printf("[7] 取得できない項目 (-1) は 0 と区別する\n");
    NFBCounts cu = makeCounts(100, 5, 10, NFB_COUNT_UNAVAILABLE, NFB_COUNT_UNAVAILABLE, 5000);
    NFBScoreResult ru;
    NFBComputeScore(&cu, &o, &ru);
    ok(ru.available[NFBActionQuote] == false, "quote は unavailable");
    ok(isnan(ru.contribution[NFBActionQuote]), "寄与に加算しない");
    eq((double)ru.totalEngagements, 115.0, "総エンゲージ数は既知分のみ");
    double expU = (100.0 / 5000) * 0.5 + (5.0 / 5000) * 5.0 + (10.0 / 5000) * 1.0;
    eq(ru.probCombined, expU, "確率近似は既知分のみ");
    eq(ru.naiveScore, 100 * 0.5 + 5 * 5.0 + 10 * 1.0, "生カウント式も既知分のみ");
    eq(ru.engagementRate, 115.0 / 5000.0, "ER も既知分のみ");

    printf("[8] 本物の 0 は 0 のまま\n");
    NFBCounts cz = makeCounts(0, 0, 0, 0, 0, 800);
    NFBScoreResult rz;
    NFBComputeScore(&cz, &o, &rz);
    ok(rz.available[NFBActionFavorite] == true, "0 件は unavailable ではない");
    eq(rz.probScore, 0.001, "全 0 なら offset のみ");

    printf("[9] 表示数が取れない場合\n");
    NFBCounts cv = makeCounts(10, 1, 2, NFB_COUNT_UNAVAILABLE, NFB_COUNT_UNAVAILABLE,
                              NFB_COUNT_UNAVAILABLE);
    NFBScoreResult rv;
    NFBComputeScore(&cv, &o, &rv);
    ok(rv.hasProbScore == false, "確率近似は計算しない");
    eq(rv.naiveScore, 10 * 0.5 + 1 * 5.0 + 2 * 1.0, "生カウント式は計算できる");
    ok(NFBGradeLetter(&rv)[0] == '?', "グレードは ?");

    printf("[10] 全項目不明なら何も出さない\n");
    NFBCounts cn = makeCounts(NFB_COUNT_UNAVAILABLE, NFB_COUNT_UNAVAILABLE, NFB_COUNT_UNAVAILABLE,
                              NFB_COUNT_UNAVAILABLE, NFB_COUNT_UNAVAILABLE, 1000);
    NFBScoreResult rn;
    NFBComputeScore(&cn, &o, &rn);
    ok(rn.hasProbScore == false, "スコアなし");
    eq(rn.naiveScore, 0.0, "生カウント式も 0");

    printf("\n%s  pass %d / fail %d\n\n", g_fail == 0 ? "OK" : "FAILED", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
