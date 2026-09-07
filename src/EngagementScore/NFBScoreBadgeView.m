//
//  NFBScoreBadgeView.m
//  NeoFreeBird
//

#import "NFBScoreBadgeView.h"

#import "Core/BHTBundle.h"
#import "NFBEngagementScore.h"

static const CGFloat kBadgeHeight = 18.0;
static const CGFloat kHorizontalPadding = 6.0;
static const CGFloat kGradeWidth = 15.0;
static const CGFloat kInterItemSpacing = 4.0;

@interface NFBScoreBadgeView ()
@property (nonatomic, strong) UILabel* valueLabel;
@property (nonatomic, strong) UILabel* gradeLabel;
@property (nonatomic, assign) NFBScoreResult lastResult;
@end

@implementation NFBScoreBadgeView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.userInteractionEnabled = YES;
    self.layer.cornerRadius = kBadgeHeight / 2.0;
    self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.clipsToBounds = YES;

    _valueLabel = [[UILabel alloc] init];
    _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:11.0 weight:UIFontWeightSemibold];
    _valueLabel.textAlignment = NSTextAlignmentRight;
    [self addSubview:_valueLabel];

    _gradeLabel = [[UILabel alloc] init];
    _gradeLabel.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightHeavy];
    _gradeLabel.textAlignment = NSTextAlignmentCenter;
    _gradeLabel.textColor = UIColor.whiteColor;
    _gradeLabel.layer.cornerRadius = 3.0;
    _gradeLabel.clipsToBounds = YES;
    [self addSubview:_gradeLabel];

    [self addTarget:self
                  action:@selector(nfb_didTap)
        forControlEvents:UIControlEventTouchUpInside];

    return self;
}

- (void)applyResult:(NFBScoreResult)result {
    self.lastResult = result;

    self.valueLabel.text = [NFBEngagementScore badgeTextForResult:result];
    self.gradeLabel.text = [NFBEngagementScore gradeLetterForResult:result];
    self.gradeLabel.backgroundColor = [NFBEngagementScore gradeColorForResult:result];

    UIColor* foreground = self.tintColor ?: UIColor.labelColor;
    self.valueLabel.textColor = [foreground colorWithAlphaComponent:0.85];
    self.layer.borderColor = [foreground colorWithAlphaComponent:0.25].CGColor;
    self.backgroundColor = [foreground colorWithAlphaComponent:0.06];

    [self setNeedsLayout];
}

- (CGFloat)preferredWidth {
    CGSize valueSize = [self.valueLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, kBadgeHeight)];
    return kHorizontalPadding * 2 + ceil(valueSize.width) + kInterItemSpacing + kGradeWidth;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake([self preferredWidth], kBadgeHeight);
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat gradeX = CGRectGetWidth(self.bounds) - kHorizontalPadding - kGradeWidth;
    self.gradeLabel.frame = CGRectMake(gradeX, 3.0, kGradeWidth, kBadgeHeight - 6.0);

    CGFloat valueWidth = gradeX - kInterItemSpacing - kHorizontalPadding;
    self.valueLabel.frame = CGRectMake(kHorizontalPadding, 0, MAX(valueWidth, 0), kBadgeHeight);
}

- (void)nfb_didTap {
    UIViewController* presenter = [self nfb_nearestViewController];
    if (!presenter) return;

    BHTBundle* bundle = [BHTBundle sharedBundle];
    NSString* title = [bundle localizedStringForKey:@"ENGAGEMENT_SCORE_BREAKDOWN_TITLE"];
    NSString* message = [NFBEngagementScore breakdownTextForStatus:self.status
                                                            result:self.lastResult];

    UIAlertController* alert =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle
                                                        localizedStringForKey:@"ENGAGEMENT_SCORE_OK"]
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (UIViewController*)nfb_nearestViewController {
    UIResponder* responder = self.nextResponder;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            UIViewController* controller = (UIViewController*)responder;
            while (controller.presentedViewController) {
                controller = controller.presentedViewController;
            }
            return controller;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

@end
