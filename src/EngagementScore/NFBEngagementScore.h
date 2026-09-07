//
//  NFBEngagementScore.h
//  NeoFreeBird
//
//  ポストのエンゲージメント数を端末側のモデルから取り出し、
//  NFBScoreMath でスコアに変換するための橋渡し。
//
//  Twitter/X の内部クラスはバージョンごとにプロパティ名が変わるため、
//  セレクタ名をハードコードせず実行時に探索する。見つかった名前はクラス単位で
//  キャッシュし、見つからない指標は 0 ではなく「不明」として返す。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "Core/NFBScoreMath.h"

NS_ASSUME_NONNULL_BEGIN

@interface NFBEngagementScore : NSObject

/// スコア表示が有効か（設定 show_engagement_score）。
+ (BOOL)enabled;

/// 任意のビューモデル/セル/ビューから TFNTwitterStatus 相当のオブジェクトを取り出す。
+ (nullable id)statusFromObject:(nullable id)object;

/// ポスト ID（見つからなければ nil）。
+ (nullable NSString*)tweetIDForStatus:(nullable id)status;

/// 著者のスクリーンネーム（小文字、見つからなければ nil）。
+ (nullable NSString*)screenNameForStatus:(nullable id)status;

/// エンゲージメント数。取得できない指標は NFB_COUNT_UNAVAILABLE。
+ (NFBCounts)countsForStatus:(nullable id)status;

/// 現在の設定を反映したスコアオプション。著者多様性の k はここで解決する。
+ (NFBScoreOptions)optionsForStatus:(nullable id)status tweetID:(nullable NSString*)tweetID;

/// スコアを計算する。計算不能なら result.hasProbScore == NO。
+ (NFBScoreResult)scoreForStatus:(nullable id)status;

/// バッジに出す短い文字列（例 "31.3"）。生カウントモードでは整数表記。
+ (NSString*)badgeTextForResult:(NFBScoreResult)result;

/// グレード文字（"S".."E" / "?"）。
+ (NSString*)gradeLetterForResult:(NFBScoreResult)result;

/// グレードの表示色。
+ (UIColor*)gradeColorForResult:(NFBScoreResult)result;

/// 内訳を人間が読める形にしたもの（タップ時のアラート本文）。
+ (NSString*)breakdownTextForStatus:(nullable id)status result:(NFBScoreResult)result;

/// 直近スコアの中での相対順位（0.0-1.0）。母数が少なければ -1。
+ (double)percentileForDisplay:(double)display;

/// 解決できたセレクタ名を NSLog に出す（設定 engagement_score_debug）。
+ (void)dumpResolvedSelectorsForStatus:(nullable id)status;

@end

NS_ASSUME_NONNULL_END
