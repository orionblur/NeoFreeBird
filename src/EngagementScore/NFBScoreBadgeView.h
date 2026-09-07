//
//  NFBScoreBadgeView.h
//  NeoFreeBird
//
//  ポストのアクション行の末尾に置く小さなスコアバッジ。
//  タップすると内訳をアラートで表示する。
//

#import <UIKit/UIKit.h>

#import "Core/NFBScoreMath.h"

NS_ASSUME_NONNULL_BEGIN

@interface NFBScoreBadgeView : UIControl

/// 内訳表示のために保持する。所有はしない。
@property (nonatomic, weak, nullable) id status;

/// 直近に描画したポスト ID。変わらない限り再計算しない。
@property (nonatomic, copy, nullable) NSString* renderedTweetID;

- (void)applyResult:(NFBScoreResult)result;

/// 現在の内容に必要な幅。
- (CGFloat)preferredWidth;

@end

NS_ASSUME_NONNULL_END
