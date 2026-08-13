//
//  Theme.x
//  NeoFreeBird
//

#import "HookHelpers.h"
#import "Headers/UIHeaders.h"
#import <math.h>

// MARK: - Custom accent color

static NSNumber* selectedThemeColor(void) {
    return [NSUserDefaults.standardUserDefaults objectForKey:@"bh_color_theme_selectedColor"];
}

// Every apply path (launch re-apply, trait changes, both settings pickers)
// funnels through this setter, so coercing here keeps the custom color pinned.
%hook TAEColorSettings

- (void)setPrimaryColorOption:(NSInteger)colorOption {
    NSNumber* selectedColor = selectedThemeColor();
    %orig(selectedColor ? selectedColor.integerValue : colorOption);
}

- (NSInteger)primaryColorOption {
    NSNumber* selectedColor = selectedThemeColor();
    return selectedColor ? selectedColor.integerValue : %orig;
}

%end

void applySelectedThemeColor(void) {
    NSNumber* selectedColor = selectedThemeColor();
    if (selectedColor) {
        [[objc_getClass("TAEColorSettings") sharedSettings]
            setPrimaryColorOption:selectedColor.integerValue];
    }
}

// MARK: - Dim background recolor

// The app only ever renders Light or Dark now -- there's no native third
// option -- so Dim comes back by intercepting Dark's palette at its one
// choke point and swapping in a proxy that recolors just the background
// family, leaving Light untouched.
%hook TAETwitterColorPaletteSettingInfo

- (id<TAEColorPalette>)colorPalette {
    id<TAEColorPalette> realPalette = %orig;
    if (self.isDark && BHTDimThemeEnabled()) {
        return (id<TAEColorPalette>)[BHTDimPaletteProxy proxyWithPalette:realPalette];
    }
    return realPalette;
}

%end

// Headers, small containers, profile pages, and the boxes around some cells
// don't go through TAEColorPalette at all -- they're drawn with UIKit's own
// dynamic system background colors, which Apple defines as pure black (or
// near enough) in Dark. Re-point those at the same three Dim shades so
// nothing native-styled is left behind.
%hook UIColor

+ (UIColor*)systemBackgroundColor {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled()) {
        return original;
    }
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? BHTDimBackgroundColor()
                                                                       : original;
    }];
}

+ (UIColor*)secondarySystemBackgroundColor {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled()) {
        return original;
    }
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? BHTDimElevatedBackgroundColor()
                                                                       : original;
    }];
}

+ (UIColor*)tertiarySystemBackgroundColor {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled()) {
        return original;
    }
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? BHTDimHighlightBackgroundColor()
                                                                       : original;
    }];
}

+ (UIColor*)systemGroupedBackgroundColor {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled()) {
        return original;
    }
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? BHTDimBackgroundColor()
                                                                       : original;
    }];
}

+ (UIColor*)secondarySystemGroupedBackgroundColor {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled()) {
        return original;
    }
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? BHTDimElevatedBackgroundColor()
                                                                       : original;
    }];
}

+ (UIColor*)tertiarySystemGroupedBackgroundColor {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled()) {
        return original;
    }
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? BHTDimHighlightBackgroundColor()
                                                                       : original;
    }];
}

%end

%hook UIDynamicSystemColor

- (UIColor*)resolvedColorWithTraitCollection:(UITraitCollection*)traitCollection {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled() || traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return original;
    }
    UIColor* replacement = BHTDimReplacementForResolvedColor(original);
    return replacement ?: original;
}

%end

%hook UIDeviceRGBColor
- (UIColor*)resolvedColorWithTraitCollection:(UITraitCollection*)traitCollection {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled() || traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return original;
    }
    UIColor* replacement = BHTDimReplacementForResolvedColor(original);
    return replacement ?: original;
}

%end

%hook UIDynamicCatalogColor

- (UIColor*)resolvedColorWithTraitCollection:(UITraitCollection*)traitCollection {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled() || traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return original;
    }
    UIColor* replacement = BHTDimReplacementForResolvedColor(original);
    return replacement ?: original;
}

%end

%hook UIExtendedSRGBColorSpace

- (UIColor*)resolvedColorWithTraitCollection:(UITraitCollection*)traitCollection {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled() || traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return original;
    }
    UIColor* replacement = BHTDimReplacementForResolvedColor(original);
    return replacement ?: original;
}

%end

// X 12.9 sometimes assigns backgroundPrimary (or a literal black color) to a
// view after the palette has already been resolved. Reused timeline rows and
// conversation/detail surfaces take this path while scrolling, so the palette
// proxy and private UIColor resolution hooks above never get another chance to
// recolor them. Normalize only UIView background assignments, and repeat the
// normalization when a view enters a window so colors assigned before traits
// were available are covered as well.
static UIColor* BHTDimNormalizedViewBackground(UIView* view, UIColor* color) {
    if (!view || !color || !BHTDimThemeEnabled() ||
        view.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return color;
    }

    UIColor* resolved = [color resolvedColorWithTraitCollection:view.traitCollection];
    UIColor* replacement = BHTDimReplacementForResolvedColor(resolved);
    if (replacement) {
        return replacement;
    }

    // The UIColor hooks may already have resolved a catalog background to a
    // Dim shade. Pin that resolved value on the view so later reuse cannot
    // fall back to the catalog's original pure-black dark variant.
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    if ([resolved getRed:&red green:&green blue:&blue alpha:&alpha] && alpha >= 0.99) {
        BOOL isDimShade =
            (fabs(red - 21.0 / 255.0) < 0.002 && fabs(green - 32.0 / 255.0) < 0.002 &&
             fabs(blue - 43.0 / 255.0) < 0.002) ||
            (fabs(red - 25.0 / 255.0) < 0.002 && fabs(green - 39.0 / 255.0) < 0.002 &&
             fabs(blue - 52.0 / 255.0) < 0.002) ||
            (fabs(red - 28.0 / 255.0) < 0.002 && fabs(green - 40.0 / 255.0) < 0.002 &&
             fabs(blue - 54.0 / 255.0) < 0.002);
        if (isDimShade) {
            return resolved;
        }
    }

    return color;
}

%hook UIView

- (void)setBackgroundColor:(UIColor*)color {
    %orig(BHTDimNormalizedViewBackground(self, color));
}

- (void)didMoveToWindow {
    %orig;
    if (self.window && self.backgroundColor) {
        UIColor* normalized = BHTDimNormalizedViewBackground(self, self.backgroundColor);
        if (normalized != self.backgroundColor) {
            self.backgroundColor = normalized;
        }
    }
}

%end

%hook TFNSolidColorView

-(void) didMoveToWindow {
    %orig;
    if (BHTDimThemeEnabled()) {
        self.hidden = TRUE;
    }
}

%end

// X 12.9's Explore search pill is a background image owned by UISearchBar's
// private _UITextFieldImageBackgroundView. It never asks TAEColorPalette for
// pillDefaultBackgroundColor, so recolor it through UISearchBar's public image
// API and preserve the native pill geometry with stretchable round caps.
static UIImage* BHTDimSearchPillImage(void) {
    static UIImage* image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const CGFloat diameter = 44.0;
        UIGraphicsImageRenderer* renderer =
            [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(diameter, diameter)];
        UIImage* base = [renderer imageWithActions:^(UIGraphicsImageRendererContext* context) {
            [BHTDimSearchPillColor() setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, diameter, diameter)
                                        cornerRadius:diameter / 2.0] fill];
        }];
        image = [base resizableImageWithCapInsets:UIEdgeInsetsMake(diameter / 2.0,
                                                                   diameter / 2.0,
                                                                   diameter / 2.0,
                                                                   diameter / 2.0)
                                         resizingMode:UIImageResizingModeStretch];
    });
    return image;
}

static void BHTApplyDimSearchPill(UISearchBar* searchBar) {
    if (!BHTDimThemeEnabled() ||
        searchBar.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return;
    }
    [searchBar setSearchFieldBackgroundImage:BHTDimSearchPillImage()
                                    forState:UIControlStateNormal];
}

%hook TFNSearchBar

- (void)layoutSubviews {
    %orig;
    BHTApplyDimSearchPill((UISearchBar*)self);
}

- (void)didMoveToWindow {
    %orig;
    BHTApplyDimSearchPill((UISearchBar*)self);
}

%end

static BOOL BHTIsExploreSearchBackgroundView(UIView* view) {
    Class searchBarClass = objc_getClass("TFNSearchBar");
    for (UIView* ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
        if (searchBarClass && [ancestor isKindOfClass:searchBarClass]) {
            return YES;
        }
    }
    return NO;
}

// TFNSearchBar reapplies its stock image after -layoutSubviews, so the public
// setter above alone does not survive X's final configuration pass. Intercept
// the concrete UIKit image owner, but only when it belongs to TFNSearchBar.
%hook _UITextFieldImageBackgroundView

- (void)setImage:(UIImage*)image {
    if (BHTDimThemeEnabled() && BHTIsExploreSearchBackgroundView((UIView*)self) &&
        ((UIView*)self).traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        %orig(BHTDimSearchPillImage());
    } else {
        %orig(image);
    }
}

- (void)didMoveToWindow {
    %orig;
    if (((UIView*)self).window && BHTDimThemeEnabled() &&
        BHTIsExploreSearchBackgroundView((UIView*)self) &&
        ((UIView*)self).traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        ((UIImageView*)self).image = BHTDimSearchPillImage();
    }
}

%end

%hook _TtC10TFNUISwift25SegmentedHighlightBarView

- (void)setBackgroundColor:(UIColor*)color {
    // A nil assignment is the bar hiding its caret -- leave that alone.
    if (color && [BHTSettings boolForKey:@"tab_bar_theming"] && [BHTSettings boolForKey:@"enable_custom_tab_bar"]) {
        %orig(CurrentAccentColor());
        return;
    }
    %orig(color);
}

%end

// MARK: - Custom tab bar order and visibility

static NSString* scribePageForEntry(id<T1AppNavigationTabEntry> entry) {
    if (![entry respondsToSelector:@selector(tabView)]) {
        return nil;
    }
    return [entry tabView].scribePage;
}

// Operates on the tab ENTRIES, not the button views: the app derives both the
// buttons and their content view controllers from this one array.
static NSArray* orderedTabEntries(NSArray* entries) {
    // Allow disabling the custom tab bar features when they trigger crashes on
    // certain OS/theme combinations (e.g. Liquid Glass on 11.84).
    if (![BHTSettings boolForKey:@"enable_custom_tab_bar"]) {
        return entries;
    }

    // Record the underlying tab views so the editor can show real titles and icons.
    NSMutableArray* tabViews = [NSMutableArray new];
    for (id<T1AppNavigationTabEntry> entry in entries) {
        T1TabView* tabView = [entry respondsToSelector:@selector(tabView)] ? [entry tabView] : nil;
        if (tabView) {
            [tabViews addObject:tabView];
        }
    }
    [CustomTabBarUtility recordTabViews:tabViews];

    NSArray<NSString*>* visibleOrder = [CustomTabBarUtility visiblePageIDsInOrder];

    NSMutableDictionary<NSString*, id>* entriesByPage = [NSMutableDictionary new];
    for (id<T1AppNavigationTabEntry> entry in entries) {
        NSString* page = scribePageForEntry(entry);
        if (page && !entriesByPage[page]) {
            entriesByPage[page] = entry;
        }
    }

    // Not customised yet: show the default set (Home, Search, Notifications, Chats)
    // in that order, hiding everything else the app builds.
    if (!visibleOrder) {
        NSMutableArray* defaultEntries = [NSMutableArray new];
        for (NSString* pageID in [CustomTabBarUtility defaultVisiblePageIDs]) {
            id entry = entriesByPage[pageID];
            if (entry) {
                [defaultEntries addObject:entry];
            }
        }
        return defaultEntries;
    }

    // Only the chosen tabs show; anything the editor hasn't been told to show
    // (including tabs unlocked after the user last saved) stays hidden.
    NSMutableArray* orderedEntries = [NSMutableArray new];
    NSMutableSet* placed = [NSMutableSet new];
    for (NSString* pageID in visibleOrder) {
        id entry = entriesByPage[pageID];
        if (entry && ![placed containsObject:pageID]) {
            [orderedEntries addObject:entry];
            [placed addObject:pageID];
        }
    }

    return orderedEntries;
}

// The single ordered spine that feeds both the tab buttons and their content, so
// filtering/reordering here keeps taps mapped to the right panel.
%hook T1TabbedAppNavigationViewController

- (void)setVisibleTabEntries:(NSArray*)entries {
    %orig(orderedTabEntries(entries));
}

%end

// MARK: - Keep tab bar visible

%hook T1TabBarViewController

// The scroll-driven hide only reaches the tab bar as a collapse ratio, so
// clamping it spares the deliberate hides (fullscreen media, immersive player).
- (void)setTabBarCollapseRatio:(double)ratio {
    if ([BHTSettings boolForKey:@"no_tab_bar_hiding"]) {
        %orig(0.0);
    } else {
        %orig(ratio);
    }
}

%end

// MARK: - Tab bar icon and label theming

static BOOL updatingTabIconColor = NO;

static UIColor* tabItemColor(BOOL selected) {
    return selected ? CurrentAccentColor() : [UIColor secondaryLabelColor];
}

%hook T1TabView

- (void)_t1_updateImageViewAnimated:(BOOL)animated {
    // setIconColor: re-enters this method, so swallow the inner call and let
    // %orig below render once with the new color
    if (updatingTabIconColor) {
        return;
    }

    updatingTabIconColor = YES;
    if ([BHTSettings boolForKey:@"tab_bar_theming"] && [BHTSettings boolForKey:@"enable_custom_tab_bar"]) {
        self.iconColor = tabItemColor(self.selected);
    } else if (self.iconColor) {
        self.iconColor = nil;
    }
    updatingTabIconColor = NO;

    %orig(animated);
}

- (void)_t1_updateTitleLabel {
    %orig;

    if ([BHTSettings boolForKey:@"tab_bar_theming"] && [BHTSettings boolForKey:@"enable_custom_tab_bar"]) {
        self.titleLabel.textColor = tabItemColor(self.selected);
    }
}

- (BOOL)showsTitleInDisplayMode:(long long)displayMode {
    if ([BHTSettings boolForKey:@"restore_tab_labels"] && [BHTSettings boolForKey:@"enable_custom_tab_bar"]) {
        return YES;
    }
    return %orig;
}

- (void)didMoveToWindow {
    %orig;

    if (self.window && [BHTSettings boolForKey:@"restore_tab_labels"] && [BHTSettings boolForKey:@"enable_custom_tab_bar"] &&
        [self respondsToSelector:@selector(_t1_layoutForTabBar)]) {
        [self performSelector:@selector(_t1_layoutForTabBar)];
    }
}

%new
- (void)applyCurrentThemeToIcon {
    [self _t1_updateImageViewAnimated:NO];
    [self _t1_updateTitleLabel];
}

%end

// MARK: - Top bar logo theming

%hook _TtC11TwitterHome39HomeDefaultNavigationBarTitleViewPlugin

- (UIView*)titleView {
    UIView* titleView = %orig;

    if ([titleView isKindOfClass:[UIImageView class]]) {
        UIImageView* logoView = (UIImageView*)titleView;
        // Prefer a custom replacement image named "x-logo" in the bundle.
        UIImage* customLogo = [UIImage imageNamed:@"x-logo"];
        if (customLogo) {
            // Show provided logo with original colors.
            logoView.image = [customLogo imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        } else if ([BHTSettings boolForKey:@"color_twitter_icon_in_top_bar"] && logoView.image) {
            // Fall back to tinting the existing image (previous behavior).
            logoView.image = [logoView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            logoView.tintColor = CurrentAccentColor();
        }
    }

    return titleView;
}

%end
