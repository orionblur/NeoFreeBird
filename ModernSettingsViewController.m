//
//  ModernSettingsViewController.m
//  NeoFreeBird
//
//  Created by BandarHelal on 25/11/2021.
//

#import "ModernSettingsViewController.h"
#import "BHTManager.h"
#import "BHTBundle/BHTBundle.h"
#import "BHDimPalette.h"
#import "Colours/Colours.h"

@class TFNTwitterAccount;
@interface GeneralSettingsViewController : UIViewController
- (instancetype)initWithAccount:(TFNTwitterAccount *)account;
@end

@interface TwitterBlueSettingsViewController : UIViewController
- (instancetype)initWithAccount:(TFNTwitterAccount *)account;
@end

@interface MediaDownloadsSettingsViewController : UIViewController
- (instancetype)initWithAccount:(TFNTwitterAccount *)account;
@end

@interface ProfilesSettingsViewController : UIViewController
- (instancetype)initWithAccount:(TFNTwitterAccount *)account;
@end

@interface TweetsSettingsViewController : UIViewController
- (instancetype)initWithAccount:(TFNTwitterAccount *)account;
@end

@interface SearchSettingsViewController : UIViewController
- (instancetype)initWithAccount:(TFNTwitterAccount *)account;
@end

@interface BrandingSettingsViewController : UIViewController
- (instancetype)initWithAccount:(TFNTwitterAccount *)account;
@end

@interface ExperimentalSettingsViewController : UIViewController
- (instancetype)initWithAccount:(TFNTwitterAccount *)account;
@end

@interface WebSettingsViewController : UIViewController
- (instancetype)initWithAccount:(TFNTwitterAccount *)account;
@end

@interface DebugSettingsViewController : UIViewController
- (instancetype)initWithAccount:(TFNTwitterAccount *)account;
@end

extern UIColor *BHTCurrentAccentColor(void);

typedef NS_ENUM(NSInteger, TwitterFontStyle) {
    TwitterFontStyleRegular,
    TwitterFontStyleSemibold,
    TwitterFontStyleBold
};

static UIFont *TwitterChirpFont(TwitterFontStyle style) {
    switch (style) {
        case TwitterFontStyleBold:
            return [UIFont fontWithName:@"ChirpUIVF_wght3200000_opsz150000" size:17] ?:
                   [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
        case TwitterFontStyleSemibold:
            return [UIFont fontWithName:@"ChirpUIVF_wght2BC0000_opszE0000" size:14] ?:
                   [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        case TwitterFontStyleRegular:
        default:
            return [UIFont fontWithName:@"ChirpUIVF_wght1900000_opszE0000" size:12] ?:
                   [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    }
}

@interface ModernSettingsTableViewCell : UITableViewCell
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIImageView *chevronImageView;
@end

@interface ModernSettingsSimpleButtonCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *chevronImageView;
@end

@interface ModernSettingsCompactButtonCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIImageView *chevronImageView;
@end

@interface ModernSettingsToggleCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UISwitch *toggleSwitch;
- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle;
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)events;
@end

@interface ModernSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TFNTwitterAccount *account;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) NSArray *developerCells;
@property (nonatomic, strong) NSArray *coolKidsCells;
@property (nonatomic, strong) NSArray *specialThanksCells;
@property (nonatomic, strong) NSArray *officialPageCells;
@end

@implementation ModernSettingsTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupViews];
        [self setupConstraints];
    }
    return self;
}

- (void)setupViews {
    self.iconImageView = [[UIImageView alloc] init];
    self.iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconImageView.tintColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:self.iconImageView];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    id fontGroup = [BHTManager sharedFontGroup];
    self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    self.titleLabel.textColor = [UIColor labelColor];
    [self.contentView addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    [self updateSubtitleColor];
    self.subtitleLabel.numberOfLines = 0;
    [self.contentView addSubview:self.subtitleLabel];

    self.chevronImageView = [[UIImageView alloc] init];
    self.chevronImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentView addSubview:self.chevronImageView];

    self.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
}

- (void)setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        [self.iconImageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.iconImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.iconImageView.widthAnchor constraintEqualToConstant:20],
        [self.iconImageView.heightAnchor constraintEqualToConstant:20],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconImageView.trailingAnchor constant:16],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.chevronImageView.leadingAnchor constant:-16],

        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:2],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [self.subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-16],

        [self.chevronImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [self.chevronImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.chevronImageView.widthAnchor constraintEqualToConstant:18],
        [self.chevronImageView.heightAnchor constraintEqualToConstant:18]
    ]];
}

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle iconName:(NSString *)iconName {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    objc_setAssociatedObject(self, @selector(iconName), iconName, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self updateIconColors];
}

- (void)updateIconColors {
    NSString *iconName = objc_getAssociatedObject(self, @selector(iconName));
    if (iconName) {
        Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
        id settings = [TAEColorSettingsCls sharedSettings];
        id currentPalette = [settings currentColorPalette];
        id colorPalette = [currentPalette colorPalette];
        UIColor *iconColor = [colorPalette performSelector:@selector(tabBarItemColor)];
        self.iconImageView.image = [UIImage tfn_vectorImageNamed:iconName fitsSize:CGSizeMake(20, 20) fillColor:iconColor];
    }
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id currentPalette = [settings currentColorPalette];
    id colorPalette = [currentPalette colorPalette];
    UIColor *chevronColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    self.chevronImageView.image = [UIImage tfn_vectorImageNamed:@"chevron_right" fitsSize:CGSizeMake(18, 18) fillColor:chevronColor];
}

- (void)updateSubtitleColor {
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id currentPalette = [settings currentColorPalette];
    id colorPalette = [currentPalette colorPalette];
    UIColor *subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    self.subtitleLabel.textColor = subtitleColor;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.backgroundColor = [BHDimPalette currentBackgroundColor];
    [self updateIconColors];
    [self updateSubtitleColor];
    if (previousTraitCollection.preferredContentSizeCategory != self.traitCollection.preferredContentSizeCategory) {
        id fontGroup = [BHTManager sharedFontGroup];
        self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
        self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    }
}

@end

@implementation ModernSettingsSimpleButtonCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupViews];
        [self setupConstraints];
    }
    return self;
}

- (void)setupViews {
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    id fontGroup = [BHTManager sharedFontGroup];
    self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    self.titleLabel.textColor = [UIColor labelColor];
    [self.contentView addSubview:self.titleLabel];

    self.chevronImageView = [[UIImageView alloc] init];
    self.chevronImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentView addSubview:self.chevronImageView];

    self.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
    [self updateChevronColor];
}

- (void)setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.chevronImageView.leadingAnchor constant:-16],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [self.titleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-16],

        [self.chevronImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [self.chevronImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.chevronImageView.widthAnchor constraintEqualToConstant:18],
        [self.chevronImageView.heightAnchor constraintEqualToConstant:18]
    ]];
}

- (void)configureWithTitle:(NSString *)title {
    self.titleLabel.text = title;
}

- (void)updateChevronColor {
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id currentPalette = [settings currentColorPalette];
    id colorPalette = [currentPalette colorPalette];
    UIColor *chevronColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    self.chevronImageView.image = [UIImage tfn_vectorImageNamed:@"chevron_right" fitsSize:CGSizeMake(18, 18) fillColor:chevronColor];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.backgroundColor = [BHDimPalette currentBackgroundColor];
    [self updateChevronColor];
    if (previousTraitCollection.preferredContentSizeCategory != self.traitCollection.preferredContentSizeCategory) {
        id fontGroup = [BHTManager sharedFontGroup];
        self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    }
}

@end

@implementation ModernSettingsCompactButtonCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupViews];
        [self setupConstraints];
    }
    return self;
}

- (void)setupViews {
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    id fontGroup = [BHTManager sharedFontGroup];
    self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    self.titleLabel.textColor = [UIColor labelColor];
    [self.contentView addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    self.subtitleLabel.textAlignment = NSTextAlignmentRight;
    [self updateSubtitleColor];
    [self.contentView addSubview:self.subtitleLabel];

    self.chevronImageView = [[UIImageView alloc] init];
    self.chevronImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentView addSubview:self.chevronImageView];

    self.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
    [self updateChevronColor];
}

- (void)setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [self.titleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-16],

        [self.subtitleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.titleLabel.trailingAnchor constant:16],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.chevronImageView.leadingAnchor constant:-8],
        [self.subtitleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

        [self.chevronImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [self.chevronImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.chevronImageView.widthAnchor constraintEqualToConstant:18],
        [self.chevronImageView.heightAnchor constraintEqualToConstant:18]
    ]];
    [self.titleLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [self.subtitleLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.subtitleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
}

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
}

- (void)updateChevronColor {
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id currentPalette = [settings currentColorPalette];
    id colorPalette = [currentPalette colorPalette];
    UIColor *chevronColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    self.chevronImageView.image = [UIImage tfn_vectorImageNamed:@"chevron_right" fitsSize:CGSizeMake(18, 18) fillColor:chevronColor];
}

- (void)updateSubtitleColor {
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id currentPalette = [settings currentColorPalette];
    id colorPalette = [currentPalette colorPalette];
    UIColor *subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    self.subtitleLabel.textColor = subtitleColor;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.backgroundColor = [BHDimPalette currentBackgroundColor];
    [self updateChevronColor];
    [self updateSubtitleColor];
    if (previousTraitCollection.preferredContentSizeCategory != self.traitCollection.preferredContentSizeCategory) {
        id fontGroup = [BHTManager sharedFontGroup];
        self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
        self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    }
}

@end

@implementation ModernSettingsToggleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [BHDimPalette currentBackgroundColor];
        self.titleLabel = [UILabel new];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.titleLabel];
        self.subtitleLabel = [UILabel new];
        self.subtitleLabel.numberOfLines = 0;
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.subtitleLabel];
        // Our own settings text must not be rewritten by the terminology restorer.
        [BHTManager markViewSkipRename:self.titleLabel];
        [BHTManager markViewSkipRename:self.subtitleLabel];
        self.toggleSwitch = [UISwitch new];
        self.toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.toggleSwitch];
        [self applyTheme];
        [NSLayoutConstraint activateConstraints:@[
            [self.toggleSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:14],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.toggleSwitch.leadingAnchor constant:-16],
            [self.toggleSwitch.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
            [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
            [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4],
            [self.subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-14]
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
}

- (void)addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)events {
    [self.toggleSwitch addTarget:target action:action forControlEvents:events];
}

- (void)applyTheme {
    id fontGroup = [BHTManager sharedFontGroup];
    self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    self.titleLabel.textColor = [colorPalette performSelector:@selector(textColor)];
    self.subtitleLabel.textColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    self.toggleSwitch.onTintColor = BHTCurrentAccentColor();
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

@end

// ========================================
// ModernSettingsPlaceholderViewController
// ========================================
@interface ModernSettingsPlaceholderViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TFNTwitterAccount *account;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSString *navigationTitleKey;
- (instancetype)initWithAccount:(TFNTwitterAccount *)account
                       titleKey:(NSString *)titleKey;
@end

@implementation ModernSettingsPlaceholderViewController

- (instancetype)initWithAccount:(TFNTwitterAccount *)account
                       titleKey:(NSString *)titleKey {
    if ((self = [super init])) {
        self.account = account;
        self.navigationTitleKey = [titleKey copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
    [self setupTable];
}

- (void)setupNav {
    NSString *titleKey = self.navigationTitleKey.length > 0
        ? self.navigationTitleKey
        : @"NFB_SETTINGS_TITLE";

    NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:titleKey];

    if (self.account) {
        self.navigationItem.titleView = [objc_getClass("TFNTitleView")
                                         titleViewWithTitle:title
                                         subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

- (void)setupTable {
    self.view.backgroundColor = [BHDimPalette currentBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.estimatedRowHeight = 80;

    [self.view addSubview:self.tableView];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // Placeholder only, no rows
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                  reuseIdentifier:nil];
}

#pragma mark - UITableViewDelegate

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.numberOfLines = 0;
    titleLabel.text = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PLACEHOLDER_TEXT"];

    UILabel *detailLabel = [[UILabel alloc] init];
    detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    detailLabel.numberOfLines = 0;
    detailLabel.text = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PLACEHOLDER_DETAIL_TEXT"];

    id fontGroup = [BHTManager sharedFontGroup];
    if (fontGroup) {
        if ([fontGroup respondsToSelector:@selector(bodyBoldFont)]) {
            titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
        }
        if ([fontGroup respondsToSelector:@selector(subtext2Font)]) {
            detailLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
        }
    }

    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    UIColor *titleColor = [colorPalette performSelector:@selector(textColor)];
    UIColor *subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];

    titleLabel.textColor = titleColor;
    detailLabel.textColor = subtitleColor;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, detailLabel]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 4.0;

    [header addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-16]
    ]];

    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

@end

@implementation ModernSettingsViewController

#pragma mark - Section Headers

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        // Top subtitle header
        UIView *headerView = [[UIView alloc] init];
        headerView.backgroundColor = [BHDimPalette currentBackgroundColor];

        UILabel *subtitleLabel = [[UILabel alloc] init];
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        subtitleLabel.text = [[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_DETAIL"];
        subtitleLabel.numberOfLines = 0;
        subtitleLabel.textAlignment = NSTextAlignmentLeft;

        id fontGroup = [BHTManager sharedFontGroup];
        subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];

        Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
        id settings = [TAEColorSettingsCls sharedSettings];
        id currentPalette = [settings currentColorPalette];
        id colorPalette = [currentPalette colorPalette];
        UIColor *subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
        subtitleLabel.textColor = subtitleColor;

        [headerView addSubview:subtitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [subtitleLabel.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor constant:20],
            [subtitleLabel.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor constant:-20],
            [subtitleLabel.topAnchor constraintEqualToAnchor:headerView.topAnchor constant:16],
            [subtitleLabel.bottomAnchor constraintEqualToAnchor:headerView.bottomAnchor constant:-16]
        ]];

        return headerView;
    }
    else if (section == 1) {
        // Developers section header
        return [self headerViewWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"DEVELOPER_SECTION_HEADER_TITLE"]];
    }
    else if (section == 2) {
    // Cool Kids section header
    return [self headerViewWithTitle:
        [[BHTBundle sharedBundle] localizedStringForKey:@"COOL_KIDS_SECTION_HEADER_TITLE"]];
    }
    else if (section == 3) {
    // Special Thanks section header
    return [self headerViewWithTitle:
        [[BHTBundle sharedBundle] localizedStringForKey:@"SPECIAL_THANKS_SECTION_HEADER_TITLE"]];
    }
    else if (section == 4) {
    // Official Page section header
    return [self headerViewWithTitle:
        [[BHTBundle sharedBundle] localizedStringForKey:@"FOLLOW_OFFICIAL_PAGE_SECTION_HEADER_TITLE"]];
    }
    return nil;
}

- (UIView *)headerViewWithTitle:(NSString *)title {
    UIView *headerView = [[UIView alloc] init];
    headerView.backgroundColor = [BHDimPalette currentBackgroundColor];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;

    id fontGroup = [BHTManager sharedFontGroup];
    titleLabel.font = [fontGroup performSelector:@selector(headline1BoldFont)];

    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id currentPalette = [settings currentColorPalette];
    id colorPalette = [currentPalette colorPalette];
    UIColor *titleColor = [colorPalette performSelector:@selector(textColor)];
    titleLabel.textColor = titleColor;

    [headerView addSubview:titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor constant:-20],
        [titleLabel.topAnchor constraintEqualToAnchor:headerView.topAnchor constant:32],
        [titleLabel.bottomAnchor constraintEqualToAnchor:headerView.bottomAnchor constant:-16]
    ]];

    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == 0 || section == 1 || section == 2 || section == 3 || section == 4) {
        return UITableViewAutomaticDimension;
    }
    return 0;
}

#pragma mark - Section Footers

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section == 0) {
        UIView *separator = [[UIView alloc] initWithFrame:CGRectZero];
        separator.backgroundColor = [UIColor separatorColor];
        return separator;
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return 1.0 / UIScreen.mainScreen.scale;
    }
    return CGFLOAT_MIN;
}

- (instancetype)initWithAccount:(TFNTwitterAccount *)account {
    self = [super init];
    if (self) {
        _account = account;
        [self setupSections];
        [self setupDeveloperCells];
    }
    return self;
}

- (void)setupSections {
    self.sections = @[
        @{ @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_LAYOUT_TITLE"],
           @"subtitle": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_LAYOUT_SUBTITLE"],
           @"icon": @"settings_stroke", @"action": @"showLayoutSettings" },
        @{ @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TWITTER_BLUE_TITLE"],
           @"subtitle": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TWITTER_BLUE_SUBTITLE"],
           @"icon": @"verified_stroke", @"action": @"showTwitterBlueSettings" },
        @{ @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TWEETS_TITLE"],
           @"subtitle": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TWEETS_SUBTITLE"],
           @"icon": @"quill", @"action": @"showTweetsSettings" },
        @{ @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_MEDIA_TITLE"],
           @"subtitle": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_MEDIA_SUBTITLE"],
           @"icon": @"media_tab_stroke", @"action": @"showDownloadsSettings" },
        @{ @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PROFILES_TITLE"],
           @"subtitle": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PROFILES_SUBTITLE"],
           @"icon": @"account", @"action": @"showProfilesSettings" },
        @{ @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_SEARCH_TITLE"],
           @"subtitle": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_SEARCH_SUBTITLE"],
           @"icon": @"search_stroke", @"action": @"showSearchSettings" },
        @{ @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_WEB_TITLE"],
           @"subtitle": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_WEB_SUBTITLE"],
           @"icon": @"globe_stroke", @"action": @"showWebSettings" },
        @{ @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_BRANDING_TITLE"],
           @"subtitle": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_BRANDING_SUBTITLE"],
           @"icon": @"hash_stroke", @"action": @"showBrandingSettings" },
        @{ @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PRESETS_TITLE"],
           @"subtitle": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PRESETS_SUBTITLE"],
           @"icon": @"receipt_checkmark_stroke", @"action": @"showPresetsSettings" },
        @{ @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_EXPERIMENTAL_TITLE"],
           @"subtitle": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_EXPERIMENTAL_SUBTITLE"],
           @"icon": @"flask", @"action": @"showExperimentalSettings" },
        @{ @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_DEBUG_TITLE"],
           @"subtitle": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_DEBUG_SUBTITLE"],
           @"icon": @"code", @"action": @"showDebugSettings" }
    ];
}

- (void)setupDeveloperCells {
    self.developerCells = @[
        @{ @"title": @"aridan", @"username": @"actuallyaridan", @"avatarURL": @"https://unavatar.io/x/actuallyaridan?fallback=https://neofreebird.com/images/actuallyaridan.png", @"userID": @"1351218086649720837" },
        @{ @"title": @"Thea 🐾", @"username": @"nyaathea", @"avatarURL": @"https://unavatar.io/github/nyathea?fallback=https://neofreebird.com/images/theameoww.png", @"userID": @"1541742676009226241" },
        @{ @"title": @"timi2506", @"username": @"timi2506", @"avatarURL": @"https://unavatar.io/github/timi2506?fallback=https://neofreebird.com/images/timi2506.png", @"userID": @"1684856685486063616" }
    ];

    self.coolKidsCells = @[
        @{ @"title": @"Eevee", @"username": @"whoeevee1", @"avatarURL": @"https://unavatar.io/github/whoeevee?fallback=https://neofreebird.com/images/whoeevee.png", @"userID": @"1547956497342115844" },
        @{ @"title": @"zxcvbn", @"username": @"zxxvbn0", @"avatarURL": @"https://unavatar.io/x/zxxvbn0?fallback=https://neofreebird.com/images/zxxvbn0.png", @"userID": @"1678444396717514760" }
    ];

    self.specialThanksCells = @[
        @{ @"title": @"BandarHelal", @"username": @"BandarHL", @"avatarURL": @"https://unavatar.io/x/BandarHL?fallback=https://neofreebird.com/images/BandarHL.png", @"userID": @"827842200708853762" },
        @{ @"title": @"YouGottaBillieve", @"username": @"ugottabillieve", @"avatarURL": @"https://unavatar.io/x/ugottabillieve?fallback=https://neofreebird.com/images/ugottabillieve.png", @"userID": @"1616194182187732992" }
    ];

    self.officialPageCells = @[
        @{ @"title": @"NeoFreeBird", @"username": @"NeoFreeBird", @"avatarURL": @"https://unavatar.io/x/NeoFreeBird?fallback=https://neofreebird.com/images/NeoFreeBird.png", @"userID": @"1878595268255297537" }
    ];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNavigationBar];
    [self setupTableView];
    [self setupLayout];
    [self setupFooterLabel];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contentSizeCategoryDidChange:) name:UIContentSizeCategoryDidChangeNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)contentSizeCategoryDidChange:(NSNotification *)notification {
    [self.tableView reloadData];
}

- (void)setupNavigationBar {
    self.view.backgroundColor = [BHDimPalette currentBackgroundColor];
    if (self.account) {
        self.navigationItem.titleView = [objc_getClass("TFNTitleView") titleViewWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_TITLE"] subtitle:self.account.displayUsername];
    } else {
        self.title = [[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_TITLE"];
    }
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.estimatedRowHeight = 80;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionHeaderHeight = 50;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    [self.tableView registerClass:[ModernSettingsTableViewCell class]
           forCellReuseIdentifier:@"SettingsCell"];
    [self.view addSubview:self.tableView];
}

- (void)setupLayout {
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupFooterLabel {
    UIView *footerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 60)];
    footerView.backgroundColor = [BHDimPalette currentBackgroundColor];

    UILabel *footerLabel = [[UILabel alloc] init];
    footerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    footerLabel.text = @"NeoFreeBird v2.2 (release)\nNeoFreeBird-BHTwitter v5.3 (beta)";
    footerLabel.numberOfLines = 0;
    footerLabel.textAlignment = NSTextAlignmentLeft; // <-- Left aligned now

    // Use Chirp Regular font
    footerLabel.font = TwitterChirpFont(TwitterFontStyleRegular);

    // Match subtitle color
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id currentPalette = [settings currentColorPalette];
    id colorPalette = [currentPalette colorPalette];
    UIColor *subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    footerLabel.textColor = subtitleColor;

    [footerView addSubview:footerLabel];

    [NSLayoutConstraint activateConstraints:@[
        [footerLabel.leadingAnchor constraintEqualToAnchor:footerView.leadingAnchor constant:20], // match table cell padding
        [footerLabel.trailingAnchor constraintEqualToAnchor:footerView.trailingAnchor constant:-20],
        [footerLabel.topAnchor constraintEqualToAnchor:footerView.topAnchor constant:8],
        [footerLabel.bottomAnchor constraintEqualToAnchor:footerView.bottomAnchor constant:-8]
    ]];

    self.tableView.tableFooterView = footerView;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return self.sections.count;
    } else if (section == 1) {
        return self.developerCells.count;
    } else if (section == 2) {
        return self.coolKidsCells.count;
    } else if (section == 3) {
        return self.specialThanksCells.count;
    } else if (section == 4) {
        return self.officialPageCells.count;
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        ModernSettingsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SettingsCell"
                                                                             forIndexPath:indexPath];
        NSDictionary *sectionData = self.sections[indexPath.row];
        [cell configureWithTitle:sectionData[@"title"]
                        subtitle:sectionData[@"subtitle"]
                        iconName:sectionData[@"icon"]];
        return cell;
    }
    else if (indexPath.section == 1) {
        return [self developerCellForTableView:tableView
                                   atIndexPath:indexPath
                                     fromArray:self.developerCells];
    }
    else if (indexPath.section == 2) {
        return [self developerCellForTableView:tableView
                                   atIndexPath:indexPath
                                     fromArray:self.coolKidsCells];
    }
    else if (indexPath.section == 3) {
        return [self developerCellForTableView:tableView
                                   atIndexPath:indexPath
                                     fromArray:self.specialThanksCells];
    }
    else if (indexPath.section == 4) {
        return [self developerCellForTableView:tableView
                                   atIndexPath:indexPath
                                     fromArray:self.officialPageCells];
    }

    return nil;
}

- (UITableViewCell *)developerCellForTableView:(UITableView *)tableView atIndexPath:(NSIndexPath *)indexPath fromArray:(NSArray *)array {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DeveloperCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"DeveloperCell"];
        [self setupDeveloperCell:cell];
    }
    NSDictionary *developer = array[indexPath.row];
    [self configureDeveloperCell:cell withDeveloper:developer];
    return cell;
}

#pragma mark - Developer Cell Setup

- (void)setupDeveloperCell:(UITableViewCell *)cell {
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = nil;
    UIImageView *avatarImageView = [[UIImageView alloc] init];
    avatarImageView.translatesAutoresizingMaskIntoConstraints = NO;
    avatarImageView.layer.cornerRadius = 26;
    avatarImageView.clipsToBounds = YES;
    avatarImageView.contentMode = UIViewContentModeScaleAspectFill;
    avatarImageView.tag = 100;
    [cell.contentView addSubview:avatarImageView];
    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.tag = 101;
    nameLabel.adjustsFontForContentSizeCategory = YES;
    [cell.contentView addSubview:nameLabel];
    UILabel *usernameLabel = [[UILabel alloc] init];
    usernameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    usernameLabel.tag = 102;
    usernameLabel.adjustsFontForContentSizeCategory = YES;
    [cell.contentView addSubview:usernameLabel];
    UIImageView *devChevron = [[UIImageView alloc] init];
    devChevron.translatesAutoresizingMaskIntoConstraints = NO;
    devChevron.tag = 103;
    devChevron.contentMode = UIViewContentModeScaleAspectFit;
    [cell.contentView addSubview:devChevron];
    [NSLayoutConstraint activateConstraints:@[
        [avatarImageView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:20],
        [avatarImageView.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [avatarImageView.widthAnchor constraintEqualToConstant:52],
        [avatarImageView.heightAnchor constraintEqualToConstant:52],
        [nameLabel.leadingAnchor constraintEqualToAnchor:avatarImageView.trailingAnchor constant:12],
        [nameLabel.trailingAnchor constraintEqualToAnchor:devChevron.leadingAnchor constant:-12],
        [nameLabel.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:16],
        [usernameLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [usernameLabel.trailingAnchor constraintEqualToAnchor:devChevron.leadingAnchor constant:-12],
        [usernameLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:2],
        [usernameLabel.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-16],
        [devChevron.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-20],
        [devChevron.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [devChevron.widthAnchor constraintEqualToConstant:18],
        [devChevron.heightAnchor constraintEqualToConstant:18]
    ]];
    cell.backgroundColor = [BHDimPalette currentBackgroundColor];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
}

- (void)configureDeveloperCell:(UITableViewCell *)cell withDeveloper:(NSDictionary *)developer {
    UIImageView *avatarImageView = [cell.contentView viewWithTag:100];
    UILabel *nameLabel = [cell.contentView viewWithTag:101];
    UILabel *usernameLabel = [cell.contentView viewWithTag:102];
    id fontGroup = [BHTManager sharedFontGroup];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id currentPalette = [settings currentColorPalette];
    id colorPalette = [currentPalette colorPalette];
    UIColor *textColor = [colorPalette performSelector:@selector(textColor)];
    UIColor *subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    nameLabel.text = developer[@"title"];
    nameLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    nameLabel.textColor = textColor;
    usernameLabel.text = [NSString stringWithFormat:@"@%@", developer[@"username"]];
    usernameLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    usernameLabel.textColor = subtitleColor;
    UIImageView *devChevron = [cell.contentView viewWithTag:103];
    devChevron.image = [UIImage tfn_vectorImageNamed:@"chevron_right" fitsSize:CGSizeMake(18, 18) fillColor:subtitleColor];
    NSString *avatarURL = developer[@"avatarURL"];
    if (avatarURL.length > 0) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:avatarURL]];
            UIImage *img = [UIImage imageWithData:data];
            dispatch_async(dispatch_get_main_queue(), ^{
                avatarImageView.image = img ?: [UIImage systemImageNamed:@"person.circle.fill"];
            });
        });
    } else {
        avatarImageView.image = [UIImage systemImageNamed:@"person.circle.fill"];
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        NSDictionary *sectionData = self.sections[indexPath.row];
        NSString *action = sectionData[@"action"];
        SEL selector = NSSelectorFromString(action);
        if ([self respondsToSelector:selector]) {
            IMP imp = [self methodForSelector:selector];
            void (*func)(id, SEL) = (void *)imp;
            func(self, selector);
        }
    }
    else if (indexPath.section == 1) {
        NSDictionary *developer = self.developerCells[indexPath.row];
        [self openTwitterProfileWithUserID:developer[@"userID"]];
    }
    else if (indexPath.section == 2) {
        NSDictionary *developer = self.coolKidsCells[indexPath.row];
        [self openTwitterProfileWithUserID:developer[@"userID"]];
    }
    else if (indexPath.section == 3) {
        NSDictionary *developer = self.specialThanksCells[indexPath.row];
        [self openTwitterProfileWithUserID:developer[@"userID"]];
    }
    else if (indexPath.section == 4) {
        NSDictionary *developer = self.officialPageCells[indexPath.row];
        [self openTwitterProfileWithUserID:developer[@"userID"]];
    }
}

- (void)openTwitterProfileWithUserID:(NSString *)userID {
    if (!userID.length) return;
    NSString *twitterURL = [NSString stringWithFormat:@"twitter://user?id=%@", userID];
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:twitterURL]
                                       options:@{}
                             completionHandler:nil];
}

#pragma mark - Navigation to Sub-pages

- (void)showLayoutSettings {
    GeneralSettingsViewController *vc = [[GeneralSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showTwitterBlueSettings {
    TwitterBlueSettingsViewController *vc = [[TwitterBlueSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showDownloadsSettings {
    MediaDownloadsSettingsViewController *vc = [[MediaDownloadsSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showProfilesSettings {
    ProfilesSettingsViewController *vc = [[ProfilesSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showTweetsSettings {
    TweetsSettingsViewController *vc = [[TweetsSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showBrandingSettings {
    BrandingSettingsViewController *vc = [[BrandingSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showExperimentalSettings {
    ExperimentalSettingsViewController *vc = [[ExperimentalSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showDebugSettings {
    DebugSettingsViewController *vc = [[DebugSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showSearchSettings {
    SearchSettingsViewController *vc = [[SearchSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showWebSettings {
    WebSettingsViewController *vc = [[WebSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showPresetsSettings {
    ModernSettingsPlaceholderViewController *vc =
        [[ModernSettingsPlaceholderViewController alloc] initWithAccount:self.account
                                                                titleKey:@"MODERN_SETTINGS_PRESETS_TITLE"];
    [self.navigationController pushViewController:vc animated:YES];
}

@end

// ==============================
// TwitterBlueSettingsViewController
// ==============================
@interface TwitterBlueSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TFNTwitterAccount *account;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *settings;
@end

@implementation TwitterBlueSettingsViewController

- (instancetype)initWithAccount:(TFNTwitterAccount *)account {
    if ((self = [super init])) {
        self.account = account;
        [self buildSettingsList];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
    [self setupTable];
}

- (void)setupNav {
    NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TWITTER_BLUE_TITLE"];
    if (self.account) {
        self.navigationItem.titleView = [objc_getClass("TFNTitleView") titleViewWithTitle:title subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

- (void)setupTable {
    self.view.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.estimatedRowHeight = 60;
    [self.tableView registerClass:[ModernSettingsToggleCell class] forCellReuseIdentifier:@"ToggleCell"];
    [self.tableView registerClass:[ModernSettingsSimpleButtonCell class] forCellReuseIdentifier:@"SimpleButtonCell"];
    [self.view addSubview:self.tableView];
}

- (void)buildSettingsList {
    self.settings = @[
        @{ @"key": @"undo_tweet", @"titleKey": @"UNDO_TWEET_OPTION_TITLE", @"subtitleKey": @"UNDO_TWEET_OPTION_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"hide_promoted", @"titleKey": @"HIDE_ADS_OPTION_TITLE", @"subtitleKey": @"HIDE_ADS_OPTION_DETAIL_TITLE", @"default": @YES, @"type": @"toggle" },
        @{ @"key": @"hide_premium_offer", @"titleKey": @"HIDE_PREMIUM_OFFER_OPTION", @"subtitleKey": @"HIDE_PREMIUM_OFFER_OPTION_DETAIL_TITLE", @"default": @YES, @"type": @"toggle" },
        @{ @"titleKey": @"THEME_OPTION_TITLE", @"action": @"showThemeViewController:", @"type": @"button" },
        @{ @"titleKey": @"APP_ICON_TITLE", @"action": @"showBHAppIconViewController:", @"type": @"button" },
        @{ @"titleKey": @"CUSTOM_TAB_BAR_OPTION_TITLE", @"action": @"showCustomTabBarVC:", @"type": @"button" }
    ];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.settings.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *settingData = self.settings[indexPath.row];
    NSString *type = settingData[@"type"];
    if ([type isEqualToString:@"button"]) {
        ModernSettingsSimpleButtonCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SimpleButtonCell" forIndexPath:indexPath];
        NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:settingData[@"titleKey"]];
        [cell configureWithTitle:title];
        return cell;
    } else {
        ModernSettingsToggleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ToggleCell" forIndexPath:indexPath];
        NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:settingData[@"titleKey"]];
        NSString *subtitleKey = settingData[@"subtitleKey"];
        NSString *subtitle = (subtitleKey.length > 0) ? [[BHTBundle sharedBundle] localizedStringForKey:subtitleKey] : @"";
        [cell configureWithTitle:title subtitle:subtitle];
        NSString *key = settingData[@"key"];
        BOOL isEnabled = [[[NSUserDefaults standardUserDefaults] objectForKey:key] ?: settingData[@"default"] boolValue];
        cell.toggleSwitch.on = isEnabled;
        objc_setAssociatedObject(cell.toggleSwitch, @"prefKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [cell addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        return cell;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *data = self.settings[indexPath.row];
    if ([data[@"type"] isEqualToString:@"button"]) {
        NSString *actionName = data[@"action"];
        if (actionName) {
            SEL action = NSSelectorFromString(actionName);
            if ([self respondsToSelector:action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [self performSelector:action withObject:data];
#pragma clang diagnostic pop
            }
        }
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TWITTER_BLUE_SUBTITLE"];
    label.numberOfLines = 0;
    id fontGroup = [BHTManager sharedFontGroup];
    label.font = [fontGroup performSelector:@selector(subtext2Font)];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    UIColor *subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    label.textColor = subtitleColor;
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [label.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8]
    ]];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, @"prefKey");
    if (key) {
        [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
    }
}

- (void)showThemeViewController:(NSDictionary *)sender {
    Class BHColorThemeViewControllerClass = objc_getClass("BHColorThemeViewController");
    if (BHColorThemeViewControllerClass) {
        UIViewController *themeVC = [[BHColorThemeViewControllerClass alloc] init];
        if (self.account) {
            [themeVC.navigationItem setTitleView:[objc_getClass("TFNTitleView") titleViewWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"THEME_SETTINGS_NAVIGATION_TITLE"] subtitle:self.account.displayUsername]];
        }
        [self.navigationController pushViewController:themeVC animated:YES];
    }
}

- (void)showBHAppIconViewController:(NSDictionary *)sender {
    Class BHAppIconViewControllerClass = objc_getClass("BHAppIconViewController");
    if (BHAppIconViewControllerClass) {
        UIViewController *appIconVC = [[BHAppIconViewControllerClass alloc] init];
        if (self.account) {
            [appIconVC.navigationItem setTitleView:[objc_getClass("TFNTitleView") titleViewWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"APP_ICON_NAV_TITLE"] subtitle:self.account.displayUsername]];
        }
        [self.navigationController pushViewController:appIconVC animated:YES];
    }
}

- (void)showCustomTabBarVC:(NSDictionary *)sender {
    Class BHCustomTabBarViewControllerClass = objc_getClass("BHCustomTabBarViewController");
    if (BHCustomTabBarViewControllerClass) {
        UIViewController *customTabBarVC = [[BHCustomTabBarViewControllerClass alloc] init];
        if (self.account) {
            [customTabBarVC.navigationItem setTitleView:[objc_getClass("TFNTitleView") titleViewWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"CUSTOM_TAB_BAR_SETTINGS_NAVIGATION_TITLE"] subtitle:self.account.displayUsername]];
        }
        [self.navigationController pushViewController:customTabBarVC animated:YES];
    }
}

@end

// ==============================
// MediaDownloadsSettingsViewController
// ==============================
@interface MediaDownloadsSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TFNTwitterAccount *account;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *settings;
@end

@implementation MediaDownloadsSettingsViewController

- (instancetype)initWithAccount:(TFNTwitterAccount *)account {
    if ((self = [super init])) {
        self.account = account;
        [self buildSettingsList];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
    [self setupTable];
}

- (void)setupNav {
    NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_MEDIA_TITLE"];
    if (self.account) {
        self.navigationItem.titleView = [objc_getClass("TFNTitleView") titleViewWithTitle:title subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

- (void)setupTable {
    self.view.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.estimatedRowHeight = 80;
    [self.tableView registerClass:[ModernSettingsToggleCell class] forCellReuseIdentifier:@"ToggleCell"];
    [self.view addSubview:self.tableView];
}

- (void)buildSettingsList {
    self.settings = @[
        @{ @"key": @"dw_v", @"titleKey": @"DOWNLOAD_VIDEOS_OPTION_TITLE", @"subtitleKey": @"DOWNLOAD_VIDEOS_OPTION_DETAIL_TITLE", @"default": @YES, @"type": @"toggle" },
        @{ @"key": @"direct_save", @"titleKey": @"DIRECT_SAVE_OPTION_TITLE", @"subtitleKey": @"DIRECT_SAVE_OPTION_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"video_layer_caption", @"titleKey": @"DISABLE_VIDEO_LAYER_CAPTIONS_OPTION_TITLE", @"subtitleKey": @"", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"autoHighestLoad", @"titleKey": @"AUTO_HIGHEST_LOAD_OPTION_TITLE", @"subtitleKey": @"AUTO_HIGHEST_LOAD_OPTION_DETAIL_TITLE", @"default": @YES, @"type": @"toggle" },
        @{ @"key": @"force_tweet_full_frame", @"titleKey": @"FORCE_TWEET_FULL_FRAME_TITLE", @"subtitleKey": @"", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"restore_video_timestamp", @"titleKey": @"RESTORE_VIDEO_TIMESTAMP_TITLE", @"subtitleKey": @"RESTORE_VIDEO_TIMESTAMP_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" }
    ];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.settings.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *settingData = self.settings[indexPath.row];
    ModernSettingsToggleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ToggleCell" forIndexPath:indexPath];
    NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:settingData[@"titleKey"]];
    NSString *subtitleKey = settingData[@"subtitleKey"];
    NSString *subtitle = (subtitleKey.length > 0) ? [[BHTBundle sharedBundle] localizedStringForKey:subtitleKey] : @"";
    [cell configureWithTitle:title subtitle:subtitle];
    NSString *key = settingData[@"key"];
    BOOL isEnabled = [[[NSUserDefaults standardUserDefaults] objectForKey:key] ?: settingData[@"default"] boolValue];
    cell.toggleSwitch.on = isEnabled;
    objc_setAssociatedObject(cell.toggleSwitch, @"prefKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [cell addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_MEDIA_SUBTITLE"];
    label.numberOfLines = 0;
    id fontGroup = [BHTManager sharedFontGroup];
    label.font = [fontGroup performSelector:@selector(subtext2Font)];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    UIColor *subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    label.textColor = subtitleColor;
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [label.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8]
    ]];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, @"prefKey");
    if (key) {
        [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
    }
}

@end

// ==============================
// ProfilesSettingsViewController
// ==============================
@interface ProfilesSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TFNTwitterAccount *account;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *settings;
@end

@implementation ProfilesSettingsViewController

- (instancetype)initWithAccount:(TFNTwitterAccount *)account {
    if ((self = [super init])) {
        self.account = account;
        [self buildSettingsList];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
    [self setupTable];
}

- (void)setupNav {
    NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PROFILES_TITLE"];
    if (self.account) {
        self.navigationItem.titleView = [objc_getClass("TFNTitleView") titleViewWithTitle:title subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

- (void)setupTable {
    self.view.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.estimatedRowHeight = 80;
    [self.tableView registerClass:[ModernSettingsToggleCell class] forCellReuseIdentifier:@"ToggleCell"];
    [self.view addSubview:self.tableView];
}

- (void)buildSettingsList {
    self.settings = @[
        @{ @"key": @"follow_con", @"titleKey": @"FOLLOW_CONFIRM_OPTION_TITLE", @"subtitleKey": @"FOLLOW_CONFIRM_OPTION_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"CopyProfileInfo", @"titleKey": @"COPY_PROFILE_INFO_OPTION_TITLE", @"subtitleKey": @"COPY_PROFILE_INFO_OPTION_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"bio_translate", @"titleKey": @"BIO_TRANSLATE_OPTION_TITLE", @"subtitleKey": @"BIO_TRANSLATE_OPTION_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"disableMediaTab", @"titleKey": @"DISABLE_MEDIA_TAB_OPTION_TITLE", @"subtitleKey": @"DISABLE_MEDIA_TAB_OPTION_DETAIL_TITLE", @"default": @YES, @"type": @"toggle" },
        @{ @"key": @"disableArticles", @"titleKey": @"DISABLE_ARTICLES_OPTION_TITLE", @"subtitleKey": @"DISABLE_ARTICLES_OPTION_DETAIL_TITLE", @"default": @YES, @"type": @"toggle" },
        @{ @"key": @"disableHighlights", @"titleKey": @"DISABLE_HIGHLIGHTS_OPTION_TITLE", @"subtitleKey": @"DISABLE_HIGHLIGHTS_OPTION_DETAIL_TITLE", @"default": @YES, @"type": @"toggle" },
        @{ @"key": @"hide_follow_button", @"titleKey": @"HIDE_FOLLOW_BUTTON_TITLE", @"subtitleKey": @"HIDE_FOLLOW_BUTTON_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"restore_follow_button", @"titleKey": @"RESTORE_FOLLOW_BUTTON_TITLE", @"subtitleKey": @"RESTORE_FOLLOW_BUTTON_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"square_avatars", @"titleKey": @"SQUARE_AVATARS_TITLE", @"subtitleKey": @"SQUARE_AVATARS_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" }
    ];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.settings.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *settingData = self.settings[indexPath.row];
    ModernSettingsToggleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ToggleCell" forIndexPath:indexPath];
    NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:settingData[@"titleKey"]];
    NSString *subtitleKey = settingData[@"subtitleKey"];
    NSString *subtitle = (subtitleKey.length > 0) ? [[BHTBundle sharedBundle] localizedStringForKey:subtitleKey] : @"";
    [cell configureWithTitle:title subtitle:subtitle];
    NSString *key = settingData[@"key"];
    BOOL isEnabled = [[[NSUserDefaults standardUserDefaults] objectForKey:key] ?: settingData[@"default"] boolValue];
    cell.toggleSwitch.on = isEnabled;
    objc_setAssociatedObject(cell.toggleSwitch, @"prefKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [cell addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PROFILES_SUBTITLE"];
    label.numberOfLines = 0;
    id fontGroup = [BHTManager sharedFontGroup];
    label.font = [fontGroup performSelector:@selector(subtext2Font)];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    UIColor *subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    label.textColor = subtitleColor;
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [label.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8]
    ]];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, @"prefKey");
    if (key) {
        [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
            if ([key isEqualToString:@"square_avatars"]) {
            [self showRestartRequiredAlert:@"RESTART_REQUIRED_ALERT_MESSAGE"];
        }
    }
}

- (void)showRestartRequiredAlert:(NSString *)messageKey {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"RESTART_REQUIRED_ALERT_TITLE"]
                                                                   message:[[BHTBundle sharedBundle] localizedStringForKey:messageKey]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"NOT_NOW_BUTTON_TITLE"] style:UIAlertActionStyleDefault handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"RESTART_NOW_BUTTON_TITLE"] style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {exit(0);}]];
    [self presentViewController:alert animated:YES completion:nil];
}


@end

// ==============================
// SearchSettingsViewController
// ==============================
@interface SearchSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TFNTwitterAccount *account;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *settings;
@end

@implementation SearchSettingsViewController

- (instancetype)initWithAccount:(TFNTwitterAccount *)account {
    if ((self = [super init])) {
        self.account = account;
        [self buildSettingsList];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
    [self setupTable];
}

- (void)setupNav {
    NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_SEARCH_TITLE"];
    if (self.account) {
        self.navigationItem.titleView = [objc_getClass("TFNTitleView") titleViewWithTitle:title subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

- (void)setupTable {
    self.view.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.estimatedRowHeight = 80;
    [self.tableView registerClass:[ModernSettingsToggleCell class] forCellReuseIdentifier:@"ToggleCell"];
    [self.view addSubview:self.tableView];
}

- (void)buildSettingsList {
    self.settings = @[
        @{ @"key": @"no_his", @"titleKey": @"NO_HISTORY_OPTION_TITLE", @"subtitleKey": @"NO_HISTORY_OPTION_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"hide_trends", @"titleKey": @"HIDE_TRENDS_OPTION_TITLE", @"subtitleKey": @"HIDE_TRENDS_OPTION_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"hide_trend_videos", @"titleKey": @"HIDE_TREND_VIDEOS_OPTION_TITLE", @"subtitleKey": @"HIDE_TREND_VIDEOS_OPTION_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" }
    ];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.settings.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *settingData = self.settings[indexPath.row];
    ModernSettingsToggleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ToggleCell" forIndexPath:indexPath];
    NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:settingData[@"titleKey"]];
    NSString *subtitleKey = settingData[@"subtitleKey"];
    NSString *subtitle = (subtitleKey.length > 0) ? [[BHTBundle sharedBundle] localizedStringForKey:subtitleKey] : @"";
    [cell configureWithTitle:title subtitle:subtitle];
    NSString *key = settingData[@"key"];
    BOOL isEnabled = [[[NSUserDefaults standardUserDefaults] objectForKey:key] ?: settingData[@"default"] boolValue];
    cell.toggleSwitch.on = isEnabled;
    objc_setAssociatedObject(cell.toggleSwitch, @"prefKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [cell addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_SEARCH_SUBTITLE"];
    label.numberOfLines = 0;
    id fontGroup = [BHTManager sharedFontGroup];
    label.font = [fontGroup performSelector:@selector(subtext2Font)];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    UIColor *subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    label.textColor = subtitleColor;
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [label.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8]
    ]];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, @"prefKey");
    if (key) {
        [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
    }
}

@end

// ==============================
// TweetsSettingsViewController (cleaned - old_style removed)
// ==============================
@interface TweetsSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TFNTwitterAccount *account;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *settings;
@end

@implementation TweetsSettingsViewController

- (instancetype)initWithAccount:(TFNTwitterAccount *)account {
    if ((self = [super init])) {
        self.account = account;
        [self buildSettingsList];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
    [self setupTable];
}

- (void)setupNav {
    NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TWEETS_TITLE"];
    if (self.account) {
        self.navigationItem.titleView = [objc_getClass("TFNTitleView") titleViewWithTitle:title subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

- (void)setupTable {
    self.view.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.estimatedRowHeight = 80;
    [self.tableView registerClass:[ModernSettingsToggleCell class] forCellReuseIdentifier:@"ToggleCell"];
    [self.view addSubview:self.tableView];
}

- (void)buildSettingsList {
    self.settings = @[
        @{ @"key": @"TweetToImage", @"titleKey": @"TWEET_TO_IMAGE_OPTION_TITLE", @"subtitleKey": @"TWEET_TO_IMAGE_OPTION_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"like_con", @"titleKey": @"LIKE_CONFIRM_OPTION_TITLE", @"subtitleKey": @"LIKE_CONFIRM_OPTION_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"tweet_con", @"titleKey": @"TWEET_CONFIRM_OPTION_TITLE", @"subtitleKey": @"TWEET_CONFIRM_OPTION_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"hide_blue_verified", @"titleKey": @"HIDE_BLUE_VERIFIED_OPTION_TITLE", @"subtitleKey": @"HIDE_BLUE_VERIFIED_OPTION_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"hide_view_count", @"titleKey": @"HIDE_VIEW_COUNT_OPTION_TITLE", @"subtitleKey": @"HIDE_VIEW_COUNT_OPTION_DETAIL_TITLE", @"default": @YES, @"type": @"toggle" },
        @{ @"key": @"hide_bookmark_button", @"titleKey": @"HIDE_MARKBOOK_BUTTON_OPTION_TITLE", @"subtitleKey": @"HIDE_MARKBOOK_BUTTON_OPTION_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"hide_downvote_button", @"titleKey": @"HIDE_DOWNVOTE_BUTTON_OPTION_TITLE", @"subtitleKey": @"HIDE_DOWNVOTE_BUTTON_OPTION_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"disableSensitiveTweetWarnings", @"titleKey": @"DISABLE_SENSITIVE_TWEET_WARNINGS_OPTION_TITLE", @"subtitleKey": @"", @"default": @YES, @"type": @"toggle" },
        @{ @"key": @"bypass_age_verification", @"titleKey": @"BYPASS_AGE_VERIFICATION_OPTION_TITLE", @"subtitleKey": @"BYPASS_AGE_VERIFICATION_OPTION_DETAIL_TITLE", @"default": @YES, @"type": @"toggle" },
        @{ @"key": @"hide_grok_analyze", @"titleKey": @"HIDE_GROK_ANALYZE_BUTTON_TITLE", @"subtitleKey": @"HIDE_GROK_ANALYZE_BUTTON_DETAIL_TITLE", @"default": @YES, @"type": @"toggle" },
        @{ @"key": @"reply_sorting_enabled", @"titleKey": @"REPLY_SORTING_TITLE", @"subtitleKey": @"REPLY_SORTING_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"restore_reply_context", @"titleKey": @"RESTORE_REPLY_CONTEXT_TITLE", @"subtitleKey": @"RESTORE_REPLY_CONTEXT_DETAIL_TITLE", @"default": @YES, @"type": @"toggle" }
    ];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.settings.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *settingData = self.settings[indexPath.row];
    ModernSettingsToggleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ToggleCell" forIndexPath:indexPath];
    NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:settingData[@"titleKey"]];
    NSString *subtitleKey = settingData[@"subtitleKey"];
    NSString *subtitle = (subtitleKey.length > 0) ? [[BHTBundle sharedBundle] localizedStringForKey:subtitleKey] : @"";
    [cell configureWithTitle:title subtitle:subtitle];
    NSString *key = settingData[@"key"];
    BOOL isEnabled = [[[NSUserDefaults standardUserDefaults] objectForKey:key] ?: settingData[@"default"] boolValue];
    cell.toggleSwitch.on = isEnabled;
    objc_setAssociatedObject(cell.toggleSwitch, @"prefKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [cell addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TWEETS_SUBTITLE"];
    label.numberOfLines = 0;
    id fontGroup = [BHTManager sharedFontGroup];
    label.font = [fontGroup performSelector:@selector(subtext2Font)];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    UIColor *subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    label.textColor = subtitleColor;
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [label.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8]
    ]];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, @"prefKey");
    if (key) {
        [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
    }
}

@end

// ==============================
// BrandingSettingsViewController
// ==============================
@interface BrandingSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TFNTwitterAccount *account;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *toggles;
@end

@implementation BrandingSettingsViewController

- (instancetype)initWithAccount:(TFNTwitterAccount *)account {
    if ((self = [super init])) {
        self.account = account;
        [self buildSettingsList];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
    [self setupTable];
}

- (void)setupNav {
    NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_BRANDING_TITLE"];
    if (self.account) {
        self.navigationItem.titleView = [objc_getClass("TFNTitleView")
                                         titleViewWithTitle:title
                                         subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

- (void)setupTable {
    self.view.backgroundColor = [BHDimPalette currentBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.estimatedRowHeight = 80;

    [self.tableView registerClass:[ModernSettingsToggleCell class]
           forCellReuseIdentifier:@"ToggleCell"];

    [self.view addSubview:self.tableView];
}

- (void)buildSettingsList {
    self.toggles = @[
        @{@"key": @"restore_twitter_names", @"titleKey": @"RESTORE_TWITTER_NAMES_OPTION_TITLE", @"subtitleKey": @"RESTORE_TWITTER_NAMES_OPTION_DETAIL_TITLE", @"default": @YES, @"type": @"toggle"},
        @{@"key": @"refresh_pill_label", @"titleKey": @"REFRESH_PILL_OPTION_TITLE", @"subtitleKey": @"REFRESH_PILL_DETAIL_TITLE", @"default": @YES, @"type": @"toggle"},
        @{@"key": @"color_twitter_icon_in_top_bar", @"titleKey": @"COLOR_TWITTER_ICON_OPTION_TITLE", @"subtitleKey": @"COLOR_TWITTER_ICON_DETAIL_TITLE", @"default": @YES, @"type": @"toggle"}
    ];
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.toggles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *toggleData = self.toggles[indexPath.row];

    ModernSettingsToggleCell *cell =
        [tableView dequeueReusableCellWithIdentifier:@"ToggleCell"
                                        forIndexPath:indexPath];

    NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:toggleData[@"titleKey"]];
    NSString *subtitleKey = toggleData[@"subtitleKey"];
    NSString *subtitle = subtitleKey.length > 0
        ? [[BHTBundle sharedBundle] localizedStringForKey:subtitleKey]
        : @"";

    [cell configureWithTitle:title subtitle:subtitle];

    NSString *key = toggleData[@"key"];
    BOOL isEnabled = [[[NSUserDefaults standardUserDefaults] objectForKey:key]
                      ?: toggleData[@"default"] boolValue];
    cell.toggleSwitch.on = isEnabled;

    objc_setAssociatedObject(cell.toggleSwitch, @"prefKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [cell addTarget:self
            action:@selector(switchChanged:)
  forControlEvents:UIControlEventValueChanged];

    return cell;
}

#pragma mark - UITableViewDelegate

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_BRANDING_SUBTITLE"];
    label.numberOfLines = 0;

    id fontGroup = [BHTManager sharedFontGroup];
    label.font = [fontGroup performSelector:@selector(subtext2Font)];

    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    UIColor *subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    label.textColor = subtitleColor;

    [header addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [label.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8]
    ]];

    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

#pragma mark - Actions

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, @"prefKey");
    if (!key) {
        return;
    }

    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
}

@end


// ==============================
// ExperimentalSettingsViewController (cleaned - translate removed)
// ==============================
@interface ExperimentalSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TFNTwitterAccount *account;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *toggles;
@property (nonatomic, strong) NSArray<NSDictionary *> *visibleToggles;
@end

@implementation ExperimentalSettingsViewController

- (instancetype)initWithAccount:(TFNTwitterAccount *)account {
    if ((self = [super init])) {
        self.account = account;
        [self buildSettingsList];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
    [self setupTable];
}

- (void)setupNav {
    NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_EXPERIMENTAL_TITLE"];
    if (self.account) {
        self.navigationItem.titleView = [objc_getClass("TFNTitleView") titleViewWithTitle:title subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

- (void)setupTable {
    self.view.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.estimatedRowHeight = 80;
    [self.tableView registerClass:[ModernSettingsToggleCell class] forCellReuseIdentifier:@"ToggleCell"];
    [self.tableView registerClass:[ModernSettingsTableViewCell class] forCellReuseIdentifier:@"ButtonCell"];
    [self.tableView registerClass:[ModernSettingsCompactButtonCell class] forCellReuseIdentifier:@"CompactButtonCell"];
    [self.view addSubview:self.tableView];
}

- (void)buildSettingsList {
    self.toggles = @[
        @{ @"key": @"restore_tweet_labels", @"titleKey": @"ENABLE_TWEET_LABELS_OPTION_TITLE", @"subtitleKey": @"ENABLE_TWEET_LABELS_OPTION_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" },
        @{ @"key": @"attestation_bypass_enabled", @"titleKey": @"ATTESTATION_BYPASS_OPTION_TITLE", @"subtitleKey": @"ATTESTATION_BYPASS_OPTION_DETAIL_TITLE", @"default": @YES, @"type": @"toggle" },
        @{ @"key": @"reply_in_webview", @"titleKey": @"REPLY_IN_WEBVIEW_OPTION_TITLE", @"subtitleKey": @"REPLY_IN_WEBVIEW_OPTION_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" }
    ];
    [self updateVisibleToggles];
    [self.tableView reloadData];
}

- (void)updateVisibleToggles {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *visible = [NSMutableArray array];
    for (NSDictionary *toggleData in self.toggles) {
        NSString *parentKey = toggleData[@"parentKey"];
        if (parentKey) {
            BOOL parentEnabled = [[defaults objectForKey:parentKey] ?: toggleData[@"default"] boolValue];
            if (parentEnabled) {
                [visible addObject:toggleData];
            }
        } else {
            [visible addObject:toggleData];
        }
    }
    self.visibleToggles = [visible copy];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.visibleToggles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *toggleData = self.visibleToggles[indexPath.row];
    NSString *type = toggleData[@"type"];
    if ([type isEqualToString:@"compactButton"]) {
        ModernSettingsCompactButtonCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell" forIndexPath:indexPath];
        NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:toggleData[@"titleKey"]];
        NSString *subtitle = @"";
        NSString *prefKey = toggleData[@"prefKeyForSubtitle"];
        if (prefKey) {
            subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: toggleData[@"subtitleDefault"];
            if ([toggleData[@"isSecure"] boolValue] && subtitle.length > 0 && ![subtitle isEqualToString:toggleData[@"subtitleDefault"]]) {
                subtitle = @"••••••••••••••••";
            }
        }
        [cell configureWithTitle:title subtitle:subtitle];
        return cell;
    } else if ([type isEqualToString:@"button"]) {
        ModernSettingsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ButtonCell" forIndexPath:indexPath];
        NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:toggleData[@"titleKey"]];
        NSString *subtitle = @"";
        NSString *prefKey = toggleData[@"prefKeyForSubtitle"];
        if (prefKey) {
            subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: toggleData[@"subtitleDefault"];
            if ([toggleData[@"isSecure"] boolValue] && subtitle.length > 0 && ![subtitle isEqualToString:toggleData[@"subtitleDefault"]]) {
                subtitle = @"••••••••••••••••";
            }
        }
        NSString *iconName = toggleData[@"icon"];
        [cell configureWithTitle:title subtitle:subtitle iconName:iconName];
        return cell;
    } else {
        ModernSettingsToggleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ToggleCell" forIndexPath:indexPath];
        NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:toggleData[@"titleKey"]];
        NSString *subtitleKey = toggleData[@"subtitleKey"];
        NSString *subtitle = (subtitleKey.length > 0) ? [[BHTBundle sharedBundle] localizedStringForKey:subtitleKey] : @"";
        [cell configureWithTitle:title subtitle:subtitle];
        NSString *key = toggleData[@"key"];
        BOOL isEnabled = [[[NSUserDefaults standardUserDefaults] objectForKey:key] ?: toggleData[@"default"] boolValue];
        cell.toggleSwitch.on = isEnabled;
        objc_setAssociatedObject(cell.toggleSwitch, @"prefKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [cell addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        return cell;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *data = self.visibleToggles[indexPath.row];
    if ([data[@"type"] isEqualToString:@"button"] || [data[@"type"] isEqualToString:@"compactButton"]) {
        NSString *actionName = data[@"action"];
        if (actionName) {
            SEL action = NSSelectorFromString(actionName);
            if ([self respondsToSelector:action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [self performSelector:action withObject:data];
#pragma clang diagnostic pop
            }
        }
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_EXPERIMENTAL_SUBTITLE"];
    label.numberOfLines = 0;
    id fontGroup = [BHTManager sharedFontGroup];
    label.font = [fontGroup performSelector:@selector(subtext2Font)];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    UIColor *subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    label.textColor = subtitleColor;
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [label.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8]
    ]];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, @"prefKey");
    if (key) {
        [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
        if ([key isEqualToString:@"flex_twitter"]) {
            if (sender.isOn) {
                [[objc_getClass("FLEXManager") sharedManager] showExplorer];
            } else {
                [[objc_getClass("FLEXManager") sharedManager] hideExplorer];
            }
        }

        if ([key isEqualToString:@"square_avatars"]) {
            [self showRestartRequiredAlert:@"RESTART_REQUIRED_ALERT_MESSAGE"];
        }
    }
}

- (void)showRestartRequiredAlert:(NSString *)messageKey {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"RESTART_REQUIRED_ALERT_TITLE"]
                                                                   message:[[BHTBundle sharedBundle] localizedStringForKey:messageKey]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"NOT_NOW_BUTTON_TITLE"] style:UIAlertActionStyleDefault handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"RESTART_NOW_BUTTON_TITLE"] style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {exit(0);}]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

// ==============================
// WebSettingsViewController (cleaned - translate removed)
// ==============================
@interface WebSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TFNTwitterAccount *account;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *toggles;
@property (nonatomic, strong) NSArray<NSDictionary *> *visibleToggles;
@end

@implementation WebSettingsViewController

- (instancetype)initWithAccount:(TFNTwitterAccount *)account {
    if ((self = [super init])) {
        self.account = account;
        [self buildSettingsList];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
    [self setupTable];
}

- (void)setupNav {
    NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_WEB_TITLE"];
    if (self.account) {
        self.navigationItem.titleView = [objc_getClass("TFNTitleView") titleViewWithTitle:title subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

- (void)setupTable {
    self.view.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.estimatedRowHeight = 80;
    [self.tableView registerClass:[ModernSettingsToggleCell class] forCellReuseIdentifier:@"ToggleCell"];
    [self.tableView registerClass:[ModernSettingsTableViewCell class] forCellReuseIdentifier:@"ButtonCell"];
    [self.tableView registerClass:[ModernSettingsCompactButtonCell class] forCellReuseIdentifier:@"CompactButtonCell"];
    [self.view addSubview:self.tableView];
}

- (void)buildSettingsList {
    self.toggles = @[
        @{ @"key": @"strip_tracking_params", @"titleKey": @"STRIP_URL_TRACKING_PARAMETERS_TITLE", @"subtitleKey": @"STRIP_URL_TRACKING_PARAMETERS_DETAIL_TITLE", @"default": @NO },
        @{ @"type": @"compactButton", @"parentKey": @"strip_tracking_params", @"key": @"url_host_button", @"titleKey": @"SELECT_URL_HOST_AFTER_COPY_OPTION_TITLE", @"action": @"showURLHostSelectionViewController:", @"prefKeyForSubtitle": @"tweet_url_host", @"subtitleDefault": @"x.com" },
        @{ @"key": @"openInBrowser", @"titleKey": @"ALWAYS_OPEN_SAFARI_OPTION_TITLE", @"subtitleKey": @"ALWAYS_OPEN_SAFARI_OPTION_DETAIL_TITLE", @"default": @NO },
        @{ @"key": @"ios_in_app_article_webview_enabled", @"titleKey": @"NEW_INAPP_WEB_OPTION_TITLE", @"subtitleKey": @"NEW_INAPP_WEB_DETAIL_TITLE", @"default": @YES }
    ];
    [self updateVisibleToggles];
    [self.tableView reloadData];
}

- (void)updateVisibleToggles {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *visible = [NSMutableArray array];
    for (NSDictionary *toggleData in self.toggles) {
        NSString *parentKey = toggleData[@"parentKey"];
        if (parentKey) {
            BOOL parentEnabled = [[defaults objectForKey:parentKey] ?: toggleData[@"default"] boolValue];
            if (parentEnabled) {
                [visible addObject:toggleData];
            }
        } else {
            [visible addObject:toggleData];
        }
    }
    self.visibleToggles = [visible copy];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.visibleToggles.count;
}

- (NSInteger)indexForToggleKey:(NSString *)key inArray:(NSArray<NSDictionary *> *)array {
    __block NSInteger foundIndex = NSNotFound;
    [array enumerateObjectsUsingBlock:^(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
        if ([obj[@"key"] isEqualToString:key]) {
            foundIndex = (NSInteger)idx;
            *stop = YES;
        }
    }];
    return foundIndex;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *toggleData = self.visibleToggles[indexPath.row];
    NSString *type = toggleData[@"type"];
if ([type isEqualToString:@"compactButton"]) {
    ModernSettingsCompactButtonCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell" forIndexPath:indexPath];
    NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:toggleData[@"titleKey"]];
    NSString *subtitle = @"";
    NSString *prefKey = toggleData[@"prefKeyForSubtitle"];
    if (prefKey) {
        subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: toggleData[@"subtitleDefault"];
        if ([toggleData[@"isSecure"] boolValue] && subtitle.length > 0 && ![subtitle isEqualToString:toggleData[@"subtitleDefault"]]) {
            subtitle = @"••••••••••••••••";
        }
    }
    [cell configureWithTitle:title subtitle:subtitle];

    // New: attach modern URL host menu for this specific row on iOS 14+.
    NSString *key = toggleData[@"key"];
    if (@available(iOS 14.0, *)) {
        if ([key isEqualToString:@"url_host_button"]) {
            [self configureURLHostMenuForCell:cell atIndexPath:indexPath];
        }
    }

    return cell;
}else if ([type isEqualToString:@"button"]) {
        ModernSettingsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ButtonCell" forIndexPath:indexPath];
        NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:toggleData[@"titleKey"]];
        NSString *subtitle = @"";
        NSString *prefKey = toggleData[@"prefKeyForSubtitle"];
        if (prefKey) {
            subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: toggleData[@"subtitleDefault"];
            if ([toggleData[@"isSecure"] boolValue] && subtitle.length > 0 && ![subtitle isEqualToString:toggleData[@"subtitleDefault"]]) {
                subtitle = @"••••••••••••••••";
            }
        }
        NSString *iconName = toggleData[@"icon"];
        [cell configureWithTitle:title subtitle:subtitle iconName:iconName];
        return cell;
    } else {
        ModernSettingsToggleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ToggleCell" forIndexPath:indexPath];
        NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:toggleData[@"titleKey"]];
        NSString *subtitleKey = toggleData[@"subtitleKey"];
        NSString *subtitle = (subtitleKey.length > 0) ? [[BHTBundle sharedBundle] localizedStringForKey:subtitleKey] : @"";
        [cell configureWithTitle:title subtitle:subtitle];
        NSString *key = toggleData[@"key"];
        BOOL isEnabled = [[[NSUserDefaults standardUserDefaults] objectForKey:key] ?: toggleData[@"default"] boolValue];
        cell.toggleSwitch.on = isEnabled;
        objc_setAssociatedObject(cell.toggleSwitch, @"prefKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [cell addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        return cell;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *data = self.visibleToggles[indexPath.row];

    // For the URL host row on iOS 14+, the cell itself shows the menu.
    if (@available(iOS 14.0, *)) {
        if ([data[@"key"] isEqualToString:@"url_host_button"]) {
            return;
        }
    }

    if ([data[@"type"] isEqualToString:@"button"] || [data[@"type"] isEqualToString:@"compactButton"]) {
        NSString *actionName = data[@"action"];
        if (actionName) {
            SEL action = NSSelectorFromString(actionName);
            if ([self respondsToSelector:action]) {
                NSMutableDictionary *payload = [data mutableCopy];
                payload[@"indexPath"] = indexPath;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [self performSelector:action withObject:payload];
#pragma clang diagnostic pop
            }
        }
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_WEB_SUBTITLE"];
    label.numberOfLines = 0;
    id fontGroup = [BHTManager sharedFontGroup];
    label.font = [fontGroup performSelector:@selector(subtext2Font)];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    UIColor *subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    label.textColor = subtitleColor;
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [label.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8]
    ]];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, @"prefKey");
    if (!key) {
        return;
    }

    BOOL isOn = sender.isOn;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:isOn forKey:key];
    [defaults synchronize];

    if ([key isEqualToString:@"strip_tracking_params"]) {
        // Find where the domain selector row was and will be
        NSInteger oldIndex = [self indexForToggleKey:@"url_host_button" inArray:self.visibleToggles];

        // Update the data model
        [self updateVisibleToggles];

        NSInteger newIndex = [self indexForToggleKey:@"url_host_button" inArray:self.visibleToggles];

        [self.tableView beginUpdates];

        if (oldIndex == NSNotFound && newIndex != NSNotFound) {
            // Row appeared
            NSIndexPath *ip = [NSIndexPath indexPathForRow:newIndex inSection:0];
            [self.tableView insertRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
        } else if (oldIndex != NSNotFound && newIndex == NSNotFound) {
            // Row disappeared
            NSIndexPath *ip = [NSIndexPath indexPathForRow:oldIndex inSection:0];
            [self.tableView deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
        }

        [self.tableView endUpdates];
    }

    if ([key isEqualToString:@"flex_twitter"]) {
        if (isOn) {
            [[objc_getClass("FLEXManager") sharedManager] showExplorer];
        } else {
            [[objc_getClass("FLEXManager") sharedManager] hideExplorer];
        }
    }

    if ([key isEqualToString:@"square_avatars"]) {
        [self showRestartRequiredAlert:@"RESTART_REQUIRED_ALERT_MESSAGE"];
    }
}

- (void)configureURLHostMenuForCell:(ModernSettingsCompactButtonCell *)cell
                        atIndexPath:(NSIndexPath *)indexPath {
    if (!cell) {
        return;
    }

    if (!@available(iOS 14.0, *)) {
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *currentHost = [defaults objectForKey:@"tweet_url_host"] ?: @"x.com";

    NSArray<NSString *> *hosts = @[
        @"x.com",
        @"twitter.com",
        @"fxtwitter.com",
        @"vxtwitter.com",
        @"fixvx.com"
    ];

    // Create or reuse a button that will host the menu.
    UIButton *menuButton = [cell.contentView viewWithTag:4242];
    if (!menuButton) {
        menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
        menuButton.tag = 4242;
        menuButton.backgroundColor = [UIColor clearColor];
        // No title or image, purely functional.
        [cell.contentView addSubview:menuButton];
    }

    // Place the button over the right half of the cell so the menu anchor
    // is near the domain text instead of the center of the cell.
    CGFloat width = cell.contentView.bounds.size.width;
    CGFloat height = cell.contentView.bounds.size.height;
    CGFloat buttonWidth = width * 0.5; // right half
    menuButton.frame = CGRectMake(width - buttonWidth, 0.0, buttonWidth, height);
    menuButton.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                  UIViewAutoresizingFlexibleHeight |
                                  UIViewAutoresizingFlexibleLeftMargin;
    [cell.contentView bringSubviewToFront:menuButton];

    NSMutableArray<UIAction *> *actions = [NSMutableArray array];

    for (NSString *host in hosts) {
        UIAction *action = [UIAction actionWithTitle:host
                                               image:nil
                                          identifier:nil
                                             handler:^(__kindof UIAction * _Nonnull a) {
            [defaults setObject:host forKey:@"tweet_url_host"];
            [defaults synchronize];

            if (indexPath) {
                [self.tableView reloadRowsAtIndexPaths:@[indexPath]
                                      withRowAnimation:UITableViewRowAnimationNone];
            }
        }];

        if ([host isEqualToString:currentHost]) {
            action.state = UIMenuElementStateOn;
        }

        [actions addObject:action];
    }

    UIMenu *menu = [UIMenu menuWithTitle:@"URL"
                                   image:nil
                              identifier:nil
                                 options:0
                                children:actions];

    menuButton.menu = menu;
    menuButton.showsMenuAsPrimaryAction = YES;
}

- (void)showRestartRequiredAlert:(NSString *)messageKey {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"RESTART_REQUIRED_ALERT_TITLE"]
                                                                   message:[[BHTBundle sharedBundle] localizedStringForKey:messageKey]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"NOT_NOW_BUTTON_TITLE"] style:UIAlertActionStyleDefault handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"RESTART_NOW_BUTTON_TITLE"] style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {exit(0);}]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

// ==============================
// DebugSettingsViewController (cleaned - translate removed)
// ==============================
@interface DebugSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TFNTwitterAccount *account;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *toggles;
@property (nonatomic, strong) NSArray<NSDictionary *> *visibleToggles;
@end

@implementation DebugSettingsViewController

- (instancetype)initWithAccount:(TFNTwitterAccount *)account {
    if ((self = [super init])) {
        self.account = account;
        [self buildSettingsList];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
    [self setupTable];
}

- (void)setupNav {
    NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_DEBUG_TITLE"];
    if (self.account) {
        self.navigationItem.titleView = [objc_getClass("TFNTitleView") titleViewWithTitle:title subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

- (void)setupTable {
    self.view.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.estimatedRowHeight = 80;
    [self.tableView registerClass:[ModernSettingsToggleCell class] forCellReuseIdentifier:@"ToggleCell"];
    [self.tableView registerClass:[ModernSettingsTableViewCell class] forCellReuseIdentifier:@"ButtonCell"];
    [self.tableView registerClass:[ModernSettingsCompactButtonCell class] forCellReuseIdentifier:@"CompactButtonCell"];
    [self.view addSubview:self.tableView];
}

- (void)buildSettingsList {
    self.toggles = @[ @{ @"key": @"flex_twitter", @"titleKey": @"FLEX_OPTION_TITLE", @"subtitleKey": @"FLEX_OPTION_DETAIL_TITLE", @"default": @NO, @"type": @"toggle" }
    ];
    [self updateVisibleToggles];
    [self.tableView reloadData];
}

- (void)updateVisibleToggles {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *visible = [NSMutableArray array];
    for (NSDictionary *toggleData in self.toggles) {
        NSString *parentKey = toggleData[@"parentKey"];
        if (parentKey) {
            BOOL parentEnabled = [[defaults objectForKey:parentKey] ?: toggleData[@"default"] boolValue];
            if (parentEnabled) {
                [visible addObject:toggleData];
            }
        } else {
            [visible addObject:toggleData];
        }
    }
    self.visibleToggles = [visible copy];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.visibleToggles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *toggleData = self.visibleToggles[indexPath.row];
    NSString *type = toggleData[@"type"];
    if ([type isEqualToString:@"compactButton"]) {
        ModernSettingsCompactButtonCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell" forIndexPath:indexPath];
        NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:toggleData[@"titleKey"]];
        NSString *subtitle = @"";
        NSString *prefKey = toggleData[@"prefKeyForSubtitle"];
        if (prefKey) {
            subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: toggleData[@"subtitleDefault"];
            if ([toggleData[@"isSecure"] boolValue] && subtitle.length > 0 && ![subtitle isEqualToString:toggleData[@"subtitleDefault"]]) {
                subtitle = @"••••••••••••••••";
            }
        }
        [cell configureWithTitle:title subtitle:subtitle];
        return cell;
    } else if ([type isEqualToString:@"button"]) {
        ModernSettingsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ButtonCell" forIndexPath:indexPath];
        NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:toggleData[@"titleKey"]];
        NSString *subtitle = @"";
        NSString *prefKey = toggleData[@"prefKeyForSubtitle"];
        if (prefKey) {
            subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: toggleData[@"subtitleDefault"];
            if ([toggleData[@"isSecure"] boolValue] && subtitle.length > 0 && ![subtitle isEqualToString:toggleData[@"subtitleDefault"]]) {
                subtitle = @"••••••••••••••••";
            }
        }
        NSString *iconName = toggleData[@"icon"];
        [cell configureWithTitle:title subtitle:subtitle iconName:iconName];
        return cell;
    } else {
        ModernSettingsToggleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ToggleCell" forIndexPath:indexPath];
        NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:toggleData[@"titleKey"]];
        NSString *subtitleKey = toggleData[@"subtitleKey"];
        NSString *subtitle = (subtitleKey.length > 0) ? [[BHTBundle sharedBundle] localizedStringForKey:subtitleKey] : @"";
        [cell configureWithTitle:title subtitle:subtitle];
        NSString *key = toggleData[@"key"];
        BOOL isEnabled = [[[NSUserDefaults standardUserDefaults] objectForKey:key] ?: toggleData[@"default"] boolValue];
        cell.toggleSwitch.on = isEnabled;
        objc_setAssociatedObject(cell.toggleSwitch, @"prefKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [cell addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        return cell;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *data = self.visibleToggles[indexPath.row];
    if ([data[@"type"] isEqualToString:@"button"] || [data[@"type"] isEqualToString:@"compactButton"]) {
        NSString *actionName = data[@"action"];
        if (actionName) {
            SEL action = NSSelectorFromString(actionName);
            if ([self respondsToSelector:action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [self performSelector:action withObject:data];
#pragma clang diagnostic pop
            }
        }
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_DEBUG_SUBTITLE"];
    label.numberOfLines = 0;
    id fontGroup = [BHTManager sharedFontGroup];
    label.font = [fontGroup performSelector:@selector(subtext2Font)];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    UIColor *subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    label.textColor = subtitleColor;
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [label.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8]
    ]];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, @"prefKey");
    if (key) {
        [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
        if ([key isEqualToString:@"flex_twitter"]) {
            if (sender.isOn) {
                [[objc_getClass("FLEXManager") sharedManager] showExplorer];
            } else {
                [[objc_getClass("FLEXManager") sharedManager] hideExplorer];
            }
        }
    }
}

- (void)showRestartRequiredAlert:(NSString *)messageKey {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"RESTART_REQUIRED_ALERT_TITLE"]
                                                                   message:[[BHTBundle sharedBundle] localizedStringForKey:messageKey]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"NOT_NOW_BUTTON_TITLE"] style:UIAlertActionStyleDefault handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"RESTART_NOW_BUTTON_TITLE"] style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {exit(0);}]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end


// ==============================
// GeneralSettingsViewController (cleaned - unused translate methods removed)
// ==============================
@interface GeneralSettingsViewController () <UITableViewDataSource, UITableViewDelegate, UIFontPickerViewControllerDelegate>
@property (nonatomic, strong) TFNTwitterAccount *account;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *toggles;
@property (nonatomic, strong) NSArray<NSDictionary *> *visibleToggles;
@end

@implementation GeneralSettingsViewController

- (void)refreshAllTabViewsWithTheming {
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow && window.rootViewController) {
            [self refreshTabViewsWithThemingInView:window.rootViewController.view];
        }
    }
}

- (void)refreshTabViewsWithThemingInView:(UIView *)view {
    if ([view isKindOfClass:NSClassFromString(@"T1TabView")]) {
        if ([view respondsToSelector:@selector(_t1_updateImageViewAnimated:)]) {
            [view performSelector:@selector(_t1_updateImageViewAnimated:) withObject:@(NO)];
        }
        if ([view respondsToSelector:@selector(_t1_updateTitleLabel)]) {
            [view performSelector:@selector(_t1_updateTitleLabel)];
        }
        if ([view respondsToSelector:@selector(_t1_layoutForTabBar)]) {
            [view performSelector:@selector(_t1_layoutForTabBar)];
        }
        if ([view respondsToSelector:@selector(_t1_layoutBadgeViewMaximized)]) {
            [view performSelector:@selector(_t1_layoutBadgeViewMaximized)];
        }
        if ([view respondsToSelector:@selector(_t1_layoutBadgeViewMinimized)]) {
            [view performSelector:@selector(_t1_layoutBadgeViewMinimized)];
        }

        if (![[[NSUserDefaults standardUserDefaults] objectForKey:@"tab_bar_theming"] boolValue]) {
            UILabel *titleLabel = [view valueForKey:@"titleLabel"];
            if (titleLabel) {
                titleLabel.textColor = nil;
            }
        }
    }

    for (UIView *subview in view.subviews) {
        [self refreshTabViewsWithThemingInView:subview];
    }
}

- (void)refreshAllTabViews {
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow && window.rootViewController) {
            [self refreshTabViewsInView:window.rootViewController.view];
        }
    }
}

- (void)refreshTabViewsInView:(UIView *)view {
    if ([view isKindOfClass:NSClassFromString(@"T1TabView")]) {
        if ([view respondsToSelector:@selector(_t1_updateTitleLabel)]) {
            [view performSelector:@selector(_t1_updateTitleLabel)];
        }
        if ([view respondsToSelector:@selector(_t1_layoutForTabBar)]) {
            [view performSelector:@selector(_t1_layoutForTabBar)];
        }
        if ([view respondsToSelector:@selector(_t1_layoutBadgeViewMaximized)]) {
            [view performSelector:@selector(_t1_layoutBadgeViewMaximized)];
        }

        if (![[[NSUserDefaults standardUserDefaults] objectForKey:@"tab_bar_theming"] boolValue]) {
            UILabel *titleLabel = [view valueForKey:@"titleLabel"];
            if (titleLabel) {
                titleLabel.textColor = nil;
            }
        }
    }

    for (UIView *subview in view.subviews) {
        [self refreshTabViewsInView:subview];
    }
}

- (instancetype)initWithAccount:(TFNTwitterAccount *)account {
    if ((self = [super init])) {
        self.account = account;
        [self buildToggleList];
        [self updateVisibleToggles];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
    [self setupTable];
}

- (void)setupNav {
    NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_LAYOUT_TITLE"];
    if (self.account) {
        self.navigationItem.titleView = [objc_getClass("TFNTitleView") titleViewWithTitle:title subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

- (void)setupTable {
    self.view.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [BHDimPalette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.estimatedRowHeight = 80;
    [self.tableView registerClass:[ModernSettingsToggleCell class] forCellReuseIdentifier:@"ToggleCell"];
    [self.tableView registerClass:[ModernSettingsTableViewCell class] forCellReuseIdentifier:@"ButtonCell"];
    [self.tableView registerClass:[ModernSettingsCompactButtonCell class] forCellReuseIdentifier:@"CompactButtonCell"];
    [self.view addSubview:self.tableView];
}

- (void)buildToggleList {
    self.toggles = @[
        @{ @"key": @"padlock", @"titleKey": @"PADLOCK_OPTION_TITLE", @"subtitleKey": @"PADLOCK_OPTION_DETAIL_TITLE", @"default": @NO },
        @{ @"key": @"hide_topics", @"titleKey": @"HIDE_TOPICS_OPTION_TITLE", @"subtitleKey": @"HIDE_TOPICS_OPTION_DETAIL_TITLE", @"default": @YES },
        @{ @"key": @"hide_topics_to_follow", @"titleKey": @"HIDE_TOPICS_TO_FOLLOW_OPTION", @"subtitleKey": @"HIDE_TOPICS_TO_FOLLOW_OPTION_DETAIL_TITLE", @"default": @YES },
        @{ @"key": @"hide_who_to_follow", @"titleKey": @"HIDE_WHO_FOLLOW_OPTION", @"subtitleKey": @"HIDE_WHO_FOLLOW_OPTION_DETAIL_TITLE", @"default": @YES },
        @{ @"key": @"hide_spaces", @"titleKey": @"HIDE_SPACE_OPTION_TITLE", @"subtitleKey": @"", @"default": @NO },
        @{ @"key": @"hide_custom_timelines", @"titleKey": @"HIDE_CUSTOM_TIMELINES_OPTION_TITLE", @"subtitleKey": @"HIDE_CUSTOM_TIMELINES_OPTION_DETAIL_TITLE", @"default": @NO },
        @{ @"key": @"hide_new_tweets", @"titleKey": @"HIDE_NEW_TWEETS_OPTION_TITLE", @"subtitleKey": @"HIDE_NEW_TWEETS_OPTION_DETAIL_TITLE", @"default": @NO },
        @{ @"key": @"no_tab_bar_hiding", @"titleKey": @"STOP_HIDING_TAB_BAR_TITLE", @"subtitleKey": @"STOP_HIDING_TAB_BAR_DETAIL_TITLE", @"default": @YES },
        @{ @"key": @"tab_bar_theming", @"titleKey": @"CLASSIC_TAB_BAR_SETTINGS_TITLE", @"subtitleKey": @"CLASSIC_TAB_BAR_SETTINGS_DETAIL", @"default": @NO },
        @{ @"key": @"restore_tab_labels", @"titleKey": @"RESTORE_TAB_LABELS_TITLE", @"subtitleKey": @"RESTORE_TAB_LABELS_DETAIL", @"default": @NO },
        @{ @"key": @"dis_rtl", @"titleKey": @"DISABLE_RTL_OPTION_TITLE", @"subtitleKey": @"DISABLE_RTL_OPTION_DETAIL_TITLE", @"default": @NO },
        @{ @"key": @"showScollIndicator", @"titleKey": @"SHOW_SCOLL_INDICATOR_OPTION_TITLE", @"subtitleKey": @"", @"default": @NO },
        @{ @"key": @"en_font", @"titleKey": @"FONT_OPTION_TITLE", @"subtitleKey": @"FONT_OPTION_DETAIL_TITLE", @"default": @NO },
        @{ @"type": @"compactButton", @"parentKey": @"en_font", @"key": @"regular_font_button", @"titleKey": @"REQULAR_FONTS_PICKER_OPTION_TITLE", @"action": @"showRegularFontPicker:", @"prefKeyForSubtitle": @"bhtwitter_font_1", @"subtitleDefault": @"System Default" },
        @{ @"type": @"compactButton", @"parentKey": @"en_font", @"key": @"bold_font_button", @"titleKey": @"BOLD_FONTS_PICKER_OPTION_TITLE", @"action": @"showBoldFontPicker:", @"prefKeyForSubtitle": @"bhtwitter_font_2", @"subtitleDefault": @"System Default" }
    ];
}

- (void)updateVisibleToggles {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *visible = [NSMutableArray array];
    for (NSDictionary *toggleData in self.toggles) {
        NSString *parentKey = toggleData[@"parentKey"];
        if (parentKey) {
            BOOL parentEnabled = [[defaults objectForKey:parentKey] ?: toggleData[@"default"] boolValue];
            if (parentEnabled) {
                [visible addObject:toggleData];
            }
        } else {
            [visible addObject:toggleData];
        }
    }
    self.visibleToggles = [visible copy];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.visibleToggles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *toggleData = self.visibleToggles[indexPath.row];
    NSString *type = toggleData[@"type"];
    if ([type isEqualToString:@"compactButton"]) {
        ModernSettingsCompactButtonCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell" forIndexPath:indexPath];
        NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:toggleData[@"titleKey"]];
        NSString *subtitle = @"";
        NSString *prefKey = toggleData[@"prefKeyForSubtitle"];
        if (prefKey) {
            subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: toggleData[@"subtitleDefault"];
            if ([toggleData[@"isSecure"] boolValue] && subtitle.length > 0 && ![subtitle isEqualToString:toggleData[@"subtitleDefault"]]) {
                subtitle = @"••••••••••••••••";
            }
        }
        [cell configureWithTitle:title subtitle:subtitle];
        return cell;
    } else if ([type isEqualToString:@"button"]) {
        ModernSettingsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ButtonCell" forIndexPath:indexPath];
        NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:toggleData[@"titleKey"]];
        NSString *subtitle = @"";
        NSString *prefKey = toggleData[@"prefKeyForSubtitle"];
        if (prefKey) {
            subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: toggleData[@"subtitleDefault"];
            if ([toggleData[@"isSecure"] boolValue] && subtitle.length > 0 && ![subtitle isEqualToString:toggleData[@"subtitleDefault"]]) {
                subtitle = @"••••••••••••••••";
            }
        }
        NSString *iconName = toggleData[@"icon"];
        [cell configureWithTitle:title subtitle:subtitle iconName:iconName];
        return cell;
    } else {
        ModernSettingsToggleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ToggleCell" forIndexPath:indexPath];
        NSString *title = [[BHTBundle sharedBundle] localizedStringForKey:toggleData[@"titleKey"]];
        NSString *subtitleKey = toggleData[@"subtitleKey"];
        NSString *subtitle = (subtitleKey.length > 0) ? [[BHTBundle sharedBundle] localizedStringForKey:subtitleKey] : @"";
        [cell configureWithTitle:title subtitle:subtitle];
        NSString *key = toggleData[@"key"];
        BOOL isEnabled = [[[NSUserDefaults standardUserDefaults] objectForKey:key] ?: toggleData[@"default"] boolValue];
        cell.toggleSwitch.on = isEnabled;
        objc_setAssociatedObject(cell.toggleSwitch, @"prefKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [cell addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        return cell;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *data = self.visibleToggles[indexPath.row];
    if ([data[@"type"] isEqualToString:@"button"] || [data[@"type"] isEqualToString:@"compactButton"]) {
        NSString *actionName = data[@"action"];
        if (actionName) {
            SEL action = NSSelectorFromString(actionName);
            if ([self respondsToSelector:action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [self performSelector:action withObject:data];
#pragma clang diagnostic pop
            }
        }
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_LAYOUT_SUBTITLE"];
    label.numberOfLines = 0;
    id fontGroup = [BHTManager sharedFontGroup];
    label.font = [fontGroup performSelector:@selector(subtext2Font)];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    UIColor *subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    label.textColor = subtitleColor;
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [label.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8]
    ]];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

- (void)updateAndAnimateChangesForKey:(NSString *)key {
    NSArray *oldVisibleToggles = self.visibleToggles;
    [self updateVisibleToggles];
    NSArray *newVisibleToggles = self.visibleToggles;
    [self.tableView beginUpdates];
    __block NSInteger toggleIndex = -1;
    [oldVisibleToggles enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj[@"key"] isEqualToString:key]) {
            toggleIndex = idx;
            *stop = YES;
        }
    }];
    if (toggleIndex == -1) {
        [self.tableView endUpdates];
        [self.tableView reloadData];
        return;
    }
    NSMutableArray *children = [NSMutableArray array];
    for (NSDictionary *toggleData in self.toggles) {
        if ([toggleData[@"parentKey"] isEqualToString:key]) {
            [children addObject:toggleData];
        }
    }
    if (children.count == 0) {
        [self.tableView endUpdates];
        return;
    }
    BOOL isAdding = newVisibleToggles.count > oldVisibleToggles.count;
    NSMutableArray *indexPaths = [NSMutableArray array];
    for (int i = 0; i < children.count; i++) {
        [indexPaths addObject:[NSIndexPath indexPathForRow:toggleIndex + 1 + i inSection:0]];
    }
    if (isAdding) {
        [self.tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
    } else {
        [self.tableView deleteRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    [self.tableView endUpdates];
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, @"prefKey");
    if (key) {
        [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
        [self updateAndAnimateChangesForKey:key];
        if ([key isEqualToString:@"tab_bar_theming"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self refreshAllTabViewsWithTheming];
            });
        } else if ([key isEqualToString:@"restore_tab_labels"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self refreshAllTabViews];
            });
        }
    }
}

- (void)showRegularFontPicker:(NSDictionary *)sender {
    UIFontPickerViewControllerConfiguration *configuration = [[UIFontPickerViewControllerConfiguration alloc] init];
    [configuration setFilteredTraits:UIFontDescriptorClassMask];
    [configuration setIncludeFaces:NO];
    UIFontPickerViewController *fontPicker = [[UIFontPickerViewController alloc] initWithConfiguration:configuration];
    fontPicker.delegate = (id<UIFontPickerViewControllerDelegate>)self;
    objc_setAssociatedObject(fontPicker, @"fontType", @"regular", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.account) {
        [fontPicker.navigationItem setTitleView:[objc_getClass("TFNTitleView") titleViewWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"REQULAR_FONTS_PICKER_OPTION_TITLE"] subtitle:self.account.displayUsername]];
    } else {
        fontPicker.title = [[BHTBundle sharedBundle] localizedStringForKey:@"REQULAR_FONTS_PICKER_OPTION_TITLE"];
    }
    [self.navigationController pushViewController:fontPicker animated:YES];
}

- (void)showBoldFontPicker:(NSDictionary *)sender {
    UIFontPickerViewControllerConfiguration *configuration = [[UIFontPickerViewControllerConfiguration alloc] init];
    [configuration setIncludeFaces:YES];
    [configuration setFilteredTraits:UIFontDescriptorClassModernSerifs];
    [configuration setFilteredTraits:UIFontDescriptorClassMask];
    UIFontPickerViewController *fontPicker = [[UIFontPickerViewController alloc] initWithConfiguration:configuration];
    fontPicker.delegate = (id<UIFontPickerViewControllerDelegate>)self;
    objc_setAssociatedObject(fontPicker, @"fontType", @"bold", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.account) {
        [fontPicker.navigationItem setTitleView:[objc_getClass("TFNTitleView") titleViewWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"BOLD_FONTS_PICKER_OPTION_TITLE"] subtitle:self.account.displayUsername]];
    } else {
        fontPicker.title = [[BHTBundle sharedBundle] localizedStringForKey:@"BOLD_FONTS_PICKER_OPTION_TITLE"];
    }
    [self.navigationController pushViewController:fontPicker animated:YES];
}

- (void)fontPickerViewControllerDidPickFont:(UIFontPickerViewController *)viewController {
    NSString *fontName = viewController.selectedFontDescriptor.fontAttributes[UIFontDescriptorNameAttribute];
    NSString *fontFamily = viewController.selectedFontDescriptor.fontAttributes[UIFontDescriptorFamilyAttribute];
    NSString *fontType = objc_getAssociatedObject(viewController, @"fontType");
    if ([fontType isEqualToString:@"bold"]) {
        [[NSUserDefaults standardUserDefaults] setObject:fontName forKey:@"bhtwitter_font_2"];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:fontFamily forKey:@"bhtwitter_font_1"];
    }
    [self updateVisibleToggles];
    [self.tableView reloadData];
    [viewController.navigationController popViewControllerAnimated:YES];
}

@end
