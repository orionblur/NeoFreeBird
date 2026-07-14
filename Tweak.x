//
//  Tweak.x
//  BHTwitter/NeoFreeBird
//
//  Created by BandarHelal
//  Modified by nyaathea
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h> // For objc_msgSend and objc_msgSend_stret
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>
#import <dlfcn.h>
#import "SAMKeychain/AuthViewController.h"
#import "Colours/Colours.h"
#import "BHTManager.h"
#import "BHDimPalette.h"
#import <math.h>
#import "BHTBundle/BHTBundle.h"
#import "LegacyLogin/BHTLegacyLoginViewController.h"
#import "TWHeaders.h"
#import "SAMKeychain/SAMKeychain.h"
#import "CustomTabBar/BHCustomTabBarUtility.h"
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "ModernSettingsViewController.h"
#import "BHDownloadInlineButton.h"

@class T1SettingsViewController;

@interface DCAppAttestService : NSObject
+ (instancetype)sharedService;
- (BOOL)isSupported;
@end

@interface ASWebAuthenticationSession : NSObject
- (instancetype)initWithURL:(NSURL *)URL callbackURLScheme:(NSString *)callbackURLScheme completionHandler:(void(^)(NSURL *, NSError *))completionHandler;
@property(nonatomic) BOOL prefersEphemeralWebBrowserSession;
@end

// Forward declarations
static void BHT_UpdateAllTabBarIcons(void);
static void BHT_applyThemeToWindow(UIWindow *window);
static void BHT_ensureTheming(void);
static void BHT_forceRefreshAllWindowAppearances(void);
static void BHT_ensureThemingEngineSynchronized(BOOL forceSynchronize);
static UIViewController* getViewControllerForView(UIView *view);
static char kBHTSourceTapAddedKey;

// Theme state tracking
static BOOL BHT_themeManagerInitialized = NO;
static BOOL BHT_isInThemeChangeOperation = NO;

// Map to store timestamp labels for each player instance
static NSMapTable<T1ImmersiveFullScreenViewController *, UILabel *> *playerToTimestampMap = nil;

// Performance optimization: Cache for label searches to avoid repeated expensive traversals
static NSMapTable<T1ImmersiveFullScreenViewController *, NSNumber *> *labelSearchCache = nil;
static NSTimeInterval lastCacheInvalidation = 0;
static const NSTimeInterval CACHE_INVALIDATION_INTERVAL = 10.0; // 10 seconds

// Static helper function for recursive view traversal - OPTIMIZED VERSION
static void BH_EnumerateSubviewsRecursively(UIView *view, void (^block)(UIView *currentView)) {
    if (!view || !block) return;

    // Performance optimization: Skip hidden views and their subviews
    if (view.hidden || view.alpha <= 0.01) return;

    block(view);

    // Performance optimization: Limit recursion depth to prevent excessive traversal
    static NSInteger recursionDepth = 0;
    if (recursionDepth > 15) return; // Reasonable depth limit

    recursionDepth++;
    for (UIView *subview in view.subviews) {
        BH_EnumerateSubviewsRecursively(subview, block);
    }
    recursionDepth--;
}

// MARK: imports to hook into Twitters TAE color system

UIColor *BHTCurrentAccentColor(void) {
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    if (!TAEColorSettingsCls) {
        return [UIColor systemBlueColor];
    }

    id settings = [TAEColorSettingsCls sharedSettings];
    id current = [settings currentColorPalette];
    id palette = [current colorPalette];
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];

    if ([defs objectForKey:@"bh_color_theme_selectedColor"]) {
        NSInteger opt = [defs integerForKey:@"bh_color_theme_selectedColor"];
        return [palette primaryColorForOption:opt] ?: [UIColor systemBlueColor];
    }

    if ([defs objectForKey:@"T1ColorSettingsPrimaryColorOptionKey"]) {
        NSInteger opt = [defs integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"];
        return [palette primaryColorForOption:opt] ?: [UIColor systemBlueColor];
    }

    return [UIColor systemBlueColor];
}

// Helper function to get Twitter's current dark mode state
static BOOL BHT_isTwitterDarkThemeActive() {
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    if (!TAEColorSettingsCls) {
        if (@available(iOS 13.0, *)) {
            return UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        }
        return NO; // Default to light mode if essential classes are missing
    }

    id settings = [TAEColorSettingsCls sharedSettings];
    if (!settings || ![settings respondsToSelector:@selector(currentColorPalette)]) {
        if (@available(iOS 13.0, *)) {
            return UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        }
        return NO;
    }

    id currentPaletteContainer = [settings currentColorPalette]; // This is TAEThemeColorPalette
    // TAETwitterColorPaletteSettingInfo is returned by [TAEThemeColorPalette colorPalette]
    if (!currentPaletteContainer || ![currentPaletteContainer respondsToSelector:@selector(colorPalette)]) {
         if (@available(iOS 13.0, *)) {
            return UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        }
        return NO;
    }

    id actualPaletteInfo = [currentPaletteContainer colorPalette];
    if (actualPaletteInfo && [actualPaletteInfo respondsToSelector:@selector(isDark)]) {
        // Use objc_msgSend to call the isDark method
        return ((BOOL (*)(id, SEL))objc_msgSend)(actualPaletteInfo, @selector(isDark));
    }

    // Fallback to system trait if Twitter's internal state is inaccessible
    if (@available(iOS 13.0, *)) {
        return UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return NO;
}

// ===== Padlock helpers (new) =====

static const NSInteger BHTPadlockOverlayTag = 909;

static NSArray<UIWindow *> *BHT_allActiveWindows(void) {
    NSMutableArray<UIWindow *> *result = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (!w.hidden) [result addObject:w];
                }
            }
        }
    }
    if (result.count == 0) {
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            if (!w.hidden) [result addObject:w];
        }
    }
    return result;
}

static UIWindow *BHT_activeKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) return w;
                }
                for (UIWindow *w in ws.windows) {
                    if (!w.hidden) return w;
                }
            }
        }
    }
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (w.isKeyWindow) return w;
    }
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (!w.hidden) return w;
    }
    return nil;
}

static UIViewController *BHT_topViewController(UIViewController *root) {
    if (!root) return nil;
    UIViewController *vc = root;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    if ([vc isKindOfClass:[UINavigationController class]]) {
        vc = ((UINavigationController *)vc).visibleViewController ?: vc;
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        UIViewController *sel = ((UITabBarController *)vc).selectedViewController;
        if (sel) vc = sel;
    }
    return vc;
}

static void BHT_showPadlockOverlay(void) {
    UIWindow *window = BHT_activeKeyWindow();
    if (!window) return;

    for (UIWindow *w in BHT_allActiveWindows()) {
        for (UIView *v in w.subviews) {
            if (v.tag == BHTPadlockOverlayTag) [v removeFromSuperview];
        }
    }

    UIView *overlay = [[UIView alloc] initWithFrame:window.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = UIColor.systemBackgroundColor;
    overlay.userInteractionEnabled = YES;
    overlay.tag = BHTPadlockOverlayTag;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.fill"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = UIColor.labelColor;

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = @"Locked";
    label.textColor = UIColor.labelColor;
    label.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentCenter;

    [overlay addSubview:icon];
    [overlay addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [icon.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor constant:-20],
        [label.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:8]
    ]];

    [window addSubview:overlay];
}

static void BHT_removePadlockOverlay(void) {
    for (UIWindow *w in BHT_allActiveWindows()) {
        NSMutableArray<UIView *> *toRemove = [NSMutableArray array];
        for (UIView *v in w.subviews) {
            if (v.tag == BHTPadlockOverlayTag) [toRemove addObject:v];
        }
        for (UIView *v in toRemove) [v removeFromSuperview];
    }
}

static BOOL BHT_isAuthenticated(void) {
    NSDictionary *keychainData = [[keychain shared] getData];
    if (!keychainData) return NO;
    id val = keychainData[@"isAuthenticated"];
    return [val respondsToSelector:@selector(boolValue)] ? [val boolValue] : NO;
}

static void BHT_setAuthenticated(BOOL yes) {
    [[keychain shared] saveDictionary:@{@"isAuthenticated": @(yes)}];
}

static void BHT_presentAuthIfNeeded(void) {
    if (BHT_isAuthenticated()) {
        BHT_removePadlockOverlay();
        return;
    }

    UIWindow *window = BHT_activeKeyWindow();
    if (!window) {
        BHT_showPadlockOverlay();
        return;
    }

    UIViewController *root = window.rootViewController;
    if (!root) {
        window.rootViewController = [UIViewController new];
        root = window.rootViewController;
    }
    UIViewController *host = BHT_topViewController(root);

    AuthViewController *auth = [[AuthViewController alloc] init];
    auth.modalPresentationStyle = UIModalPresentationFullScreen;
    if ([auth respondsToSelector:@selector(setModalInPresentation:)]) {
        auth.modalInPresentation = YES;
    }

    if (host.presentedViewController == nil) {
        [host presentViewController:auth animated:NO completion:nil];
    } else {
        [host dismissViewControllerAnimated:NO completion:^{
            UIViewController *newTop = BHT_topViewController(root);
            [newTop presentViewController:auth animated:NO completion:nil];
        }];
    }
}

static UIFont * _Nullable TAEStandardFontGroupReplacement(UIFont *self, SEL _cmd, CGFloat arg1, CGFloat arg2) {
    BH_BaseImp orig  = originalFontsIMP[NSStringFromSelector(_cmd)].pointerValue;
    NSUInteger nArgs = [[self class] instanceMethodSignatureForSelector:_cmd].numberOfArguments;
    UIFont *origFont;
    switch (nArgs) {
        case 2:
            origFont = orig(self, _cmd);
            break;
        case 3:
            origFont = orig(self, _cmd, arg1);
            break;
        case 4:
            origFont = orig(self, _cmd, arg1, arg2);
            break;
        default:
            // Should not be reachable, as it was verified before swizzling
            origFont = orig(self, _cmd);
            break;
    };

    UIFont *newFont  = BH_getDefaultFont(origFont);
    return newFont != nil ? newFont : origFont;
}
static void batchSwizzlingOnClass(Class cls, NSArray<NSString*>*origSelectors, IMP newIMP){
    for (NSString *sel in origSelectors) {
        SEL origSel = NSSelectorFromString(sel);
        Method origMethod = class_getInstanceMethod(cls, origSel);
        if (origMethod != NULL) {
            IMP oldImp = class_replaceMethod(cls, origSel, newIMP, method_getTypeEncoding(origMethod));
            [originalFontsIMP setObject:[NSValue valueWithPointer:oldImp] forKey:sel];
        } else {
            NSLog(@"[BHTwitter] Can't find method (%@) in Class (%@)", sel, NSStringFromClass(cls));
        }
    }
}

// MARK: - Core TAE Color hooks
%hook TAEColorSettings

- (instancetype)init {
    id instance = %orig;
    if (instance && !BHT_themeManagerInitialized) {
        // Register for system theme and appearance related notifications
        [[NSNotificationCenter defaultCenter] addObserverForName:@"UITraitCollectionDidChangeNotification"
                                                         object:nil
                                                          queue:[NSOperationQueue mainQueue]
                                                     usingBlock:^(NSNotification * _Nonnull note) {
            if ([NSUserDefaults.standardUserDefaults objectForKey:@"bh_color_theme_selectedColor"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    BHT_ensureThemingEngineSynchronized(NO);
                });
            }
        }];

        // Also listen for app entering foreground
        [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationWillEnterForegroundNotification"
                                                         object:nil
                                                          queue:[NSOperationQueue mainQueue]
                                                     usingBlock:^(NSNotification * _Nonnull note) {
            if ([NSUserDefaults.standardUserDefaults objectForKey:@"bh_color_theme_selectedColor"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    BHT_ensureThemingEngineSynchronized(YES);
                });
            }
        }];

        BHT_themeManagerInitialized = YES;
    }
    return instance;
}

- (void)setPrimaryColorOption:(NSInteger)colorOption {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // If we have a BHTwitter theme selected, ensure it takes precedence
    if ([defaults objectForKey:@"bh_color_theme_selectedColor"]) {
        NSInteger ourSelectedOption = [defaults integerForKey:@"bh_color_theme_selectedColor"];

        // Only allow changes that match our selection (avoids fighting with Twitter's system)
        if (colorOption == ourSelectedOption || BHT_isInThemeChangeOperation) {
            %orig(colorOption);
        } else {
            // If not from our theme operation, apply our own theme instead
            %orig(ourSelectedOption);

            // Also ensure Twitter's defaults match our setting for consistency
            [defaults setObject:@(ourSelectedOption) forKey:@"T1ColorSettingsPrimaryColorOptionKey"];
        }
    } else {
        // No BHTwitter theme active, let Twitter handle it normally
        %orig(colorOption);
    }
}

- (void)applyCurrentColorPalette {
    %orig;

    // Signal UI to refresh after Twitter applies its palette
    if ([NSUserDefaults.standardUserDefaults objectForKey:@"bh_color_theme_selectedColor"] &&
        !BHT_isInThemeChangeOperation &&
        [BHTManager classicTabBarEnabled]) {
        // This call happens after Twitter has applied its color changes,
        // so we need to refresh our tab bar theming
        dispatch_async(dispatch_get_main_queue(), ^{
            BHT_UpdateAllTabBarIcons();
        });
    }
}

%end

%hook T1ColorSettings

+ (void)_t1_applyPrimaryColorOption {
    // Execute original implementation to let Twitter update its internal state
    %orig;

    // If we have an active theme, ensure it's properly applied
    if ([NSUserDefaults.standardUserDefaults objectForKey:@"bh_color_theme_selectedColor"]) {
        // Synchronize our theme if needed (without forcing)
        BHT_ensureThemingEngineSynchronized(NO);
    }
}

+ (void)_t1_updateOverrideUserInterfaceStyle {
    // Let Twitter update its UI style
    %orig;

    // Ensure our theme isn't lost during dark/light mode changes
    if ([NSUserDefaults.standardUserDefaults objectForKey:@"bh_color_theme_selectedColor"] &&
        [BHTManager classicTabBarEnabled]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            BHT_UpdateAllTabBarIcons();
        });
    }
}

%end

%hook NSUserDefaults

- (void)setObject:(id)value forKey:(NSString *)defaultName {
    // Protect our custom theme from being overwritten by Twitter
    if ([defaultName isEqualToString:@"T1ColorSettingsPrimaryColorOptionKey"]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        id selectedColor = [defaults objectForKey:@"bh_color_theme_selectedColor"];

        if (selectedColor != nil && !BHT_isInThemeChangeOperation) {
            // If our theme is active and this change isn't part of our operation,
            // only allow the change if it matches our selection
            if (![value isEqual:selectedColor]) {
                // Silently reject the change, our theme has priority
                return;
            }
        }
    }

    %orig;
}

%end

// MARK: App Delegate hooks

// Defined with the native CreateTweet -> web rewrite section further down.
static void BHT_prewarmWebCookiesIfNeeded(void);
static void BHT_maybeHandleHarvestWebView(__unsafe_unretained id webViewController);

%hook T1AppDelegate
- (_Bool)application:(UIApplication *)application didFinishLaunchingWithOptions:(id)arg2 {
    _Bool orig = %orig;


    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"FirstRun_4.3"]) {
        [[NSUserDefaults standardUserDefaults] setValue:@"1strun" forKey:@"FirstRun_4.3"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"dw_v"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"hide_promoted"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"voice"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"undo_tweet"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"TrustedFriends"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"bypass_age_verification"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"disableSensitiveTweetWarnings"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"disable_immersive_player"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"custom_voice_upload"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"hide_premium_offer"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"disableMediaTab"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"disableArticles"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"disableHighlights"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"hide_view_count"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"hide_grok_analyze"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"restore_reply_context"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"hide_topics"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"hide_topics_to_follow"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"hide_who_to_follow"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"no_tab_bar_hiding"];
        [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"attestation_bypass_enabled"];
    }
    [BHTManager cleanCache];
    if ([BHTManager FLEX]) {
        [[%c(FLEXManager) sharedManager] showExplorer];
    }

    // Apply theme immediately after launch - simplified version using our new system
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"bh_color_theme_selectedColor"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Force synchronize our theme with Twitter's internal theme system
            BHT_ensureThemingEngineSynchronized(YES);
        });
    }

    // Start the cookie initialization process with retry mechanism
    if ([BHTManager RestoreTweetLabels]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [TweetSourceHelper initializeCookiesWithRetry];
        });
    }

    return orig;
}

- (void)applicationDidBecomeActive:(id)arg1 {
    %orig;

    // Re-apply theming and other existing logic …
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"bh_color_theme_selectedColor"]) {
        BHT_ensureThemingEngineSynchronized(YES);
    }
    if ([BHTManager RestoreTweetLabels]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [TweetSourceHelper initializeCookiesWithRetry];
        });
    }

    BHT_prewarmWebCookiesIfNeeded();

    if ([BHTManager Padlock]) {
        if (BHT_isAuthenticated()) {
            BHT_removePadlockOverlay();
        } else {
            BHT_showPadlockOverlay();
            dispatch_async(dispatch_get_main_queue(), ^{
                BHT_presentAuthIfNeeded();
            });
        }

        // Safety recheck in case Face ID completes very quickly
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (BHT_isAuthenticated()) {
                BHT_removePadlockOverlay();
            }
        });
    } else {
        BHT_removePadlockOverlay();
    }
}

- (void)applicationWillResignActive:(id)arg1 {
    %orig;

    if ([BHTManager RestoreTweetLabels]) {
        [TweetSourceHelper cleanupTimersForBackground];
    }

    if ([BHTManager Padlock]) {
        // Cover UI immediately
        BHT_showPadlockOverlay();
        // Mark unauthenticated so a reopen from background will prompt again
        BHT_setAuthenticated(NO);
    }

    if ([BHTManager FLEX]) {
        [[%c(FLEXManager) sharedManager] showExplorer];
    }
}

- (void)applicationDidEnterBackground:(id)arg1 {
    %orig;

    if ([BHTManager Padlock]) {
        // Redundant, ensures state is locked while backgrounded
        BHT_setAuthenticated(NO);
        BHT_showPadlockOverlay();
    }
}

- (void)applicationWillEnterForeground:(id)arg1 {
    %orig;

    if ([BHTManager Padlock]) {
        // Keep UI covered during transition
        BHT_showPadlockOverlay();
    }
}

- (void)applicationWillTerminate:(id)arg1 {
    %orig;
    if ([BHTManager Padlock]) {
        BHT_setAuthenticated(NO);
        BHT_removePadlockOverlay();
    }
}

%end

%hook AuthViewController

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (BHT_isAuthenticated()) {
        BHT_removePadlockOverlay();
    }
}

%end

// MARK: prevent tab bar fade
%hook T1TabBarViewController

- (void)setTabBarScrolling:(BOOL)scrolling {
    if ([BHTManager stopHidingTabBar]) {
        %orig(NO); // Force scrolling to NO if fading is prevented
    } else {
        %orig(scrolling);
    }
}

- (void)loadView {
    %orig;
    NSArray <NSString *> *hiddenBars = [BHCustomTabBarUtility getHiddenTabBars];
    BOOL hideGrokByDefault = ![[NSUserDefaults standardUserDefaults] boolForKey:@"ios_tab_bar_default_show_grok"];
    for (T1TabView *tabView in self.tabViews) {
        if ([hiddenBars containsObject:tabView.scribePage] ||
            (hideGrokByDefault && [tabView.scribePage isEqualToString:@"grok"])) {
            [tabView setHidden:true];
        }
    }
}
%end

// Declare Twitter's vector loader.
@interface UIImage (TwitterVectors)
+ (UIImage *)tfn_vectorImageNamed:(NSString *)name
                         fitsSize:(CGSize)size
                        fillColor:(UIColor *)fillColor;
@end

static inline UIImage *BHTVectorIcon(NSString *name, CGFloat size) {
    if (!name.length) return nil;
    return [UIImage tfn_vectorImageNamed:name
                                fitsSize:CGSizeMake(size, size)
                               fillColor:UIColor.labelColor];
}

static inline NSString *BHTIconNameForKey(NSString *key) {
    if ([key isEqualToString:@"button"])   return @"copy_stroke";
    if ([key isEqualToString:@"bio"])      return @"news_stroke";
    if ([key isEqualToString:@"username"]) return @"at";
    if ([key isEqualToString:@"fullname"]) return @"account";
    if ([key isEqualToString:@"url"])      return @"link";
    if ([key isEqualToString:@"location"]) return @"location_stroke";
    return @"copy_stroke";
}

#pragma mark - Theme detection and style helpers

typedef NS_ENUM(NSInteger, BHTTwitterThemeVariant) {
    BHTTwitterThemeVariantLight = 0,
    BHTTwitterThemeVariantDim   = 1,
    BHTTwitterThemeVariantBlack = 2, // Lights out / pure black
};

// Decide between Light / Dim / Lights out using BHDimPalette for dim.
static BHTTwitterThemeVariant BHTCurrentTwitterThemeVariant(T1ProfileHeaderView *headerView) {
    UIUserInterfaceStyle style = UIUserInterfaceStyleLight;

    if (headerView) {
        if (@available(iOS 13.0, *)) {
            style = headerView.traitCollection.userInterfaceStyle;
        }
    }

    // System / Twitter light theme
    if (style == UIUserInterfaceStyleLight) {
        return BHTTwitterThemeVariantLight;
    }

    // Dark family: use BHDimPalette to distinguish Dim from Lights out.
    if ([BHDimPalette isDimMode]) {
        return BHTTwitterThemeVariantDim;
    }

    // Dark but not dim -> Lights out (black).
    return BHTTwitterThemeVariantBlack;
}

// Style using the logged RGBA values for each theme.
static void BHTApplyCopyButtonStyle(UIButton *copyButton, T1ProfileHeaderView *headerView) {
    if (!copyButton) return;

    BHTTwitterThemeVariant variant = BHTCurrentTwitterThemeVariant(headerView);

    copyButton.layer.cornerRadius = 16.0;
    copyButton.layer.masksToBounds = YES;
    copyButton.layer.borderWidth = 1.0;
    copyButton.backgroundColor = nil;

    switch (variant) {
        case BHTTwitterThemeVariantLight: {
            // Light mode logs:
            // tint:   0.000 0.533 1.000
            // border: 0.812 0.851 0.871
            copyButton.tintColor = [UIColor colorWithRed:0.000f
                                                   green:0.533f
                                                    blue:1.000f
                                                   alpha:1.0f];
            copyButton.layer.borderColor = [UIColor colorWithRed:0.812f
                                                           green:0.851f
                                                            blue:0.871f
                                                           alpha:1.0f].CGColor;
            break;
        }

        case BHTTwitterThemeVariantDim: {
            // Dim mode logs:
            // tint:   0.000 0.569 1.000
            // border: 0.259 0.325 0.392
            copyButton.tintColor = [UIColor colorWithRed:0.000f
                                                   green:0.569f
                                                    blue:1.000f
                                                   alpha:1.0f];
            copyButton.layer.borderColor = [UIColor colorWithRed:0.259f
                                                           green:0.325f
                                                            blue:0.392f
                                                           alpha:1.0f].CGColor;
            break;
        }

        case BHTTwitterThemeVariantBlack: {
            // Lights out logs:
            // tint:   0.000 0.569 1.000
            // border: 0.200 0.212 0.224
            copyButton.tintColor = [UIColor colorWithRed:0.000f
                                                   green:0.569f
                                                    blue:1.000f
                                                   alpha:1.0f];
            copyButton.layer.borderColor = [UIColor colorWithRed:0.200f
                                                           green:0.212f
                                                            blue:0.224f
                                                           alpha:1.0f].CGColor;
            break;
        }
    }
}

#pragma mark - Hook

%hook T1ProfileHeaderViewController

- (void)viewDidAppear:(_Bool)arg1 {
    %orig(arg1);

    if (![BHTManager CopyProfileInfo]) {
        return;
    }

    T1ProfileHeaderView *headerView = [self valueForKey:@"_headerView"];
    if (!headerView || ![headerView respondsToSelector:@selector(actionButtonsView)]) {
        return;
    }

    UIView *actionButtonsView = headerView.actionButtonsView;
    UIView *innerContentView = [actionButtonsView valueForKey:@"_innerContentView"];
    if (!innerContentView) innerContentView = actionButtonsView;

    // Reuse if it already exists.
    UIButton *copyButton = (UIButton *)[actionButtonsView viewWithTag:9001];
    if (!copyButton) {
        copyButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [copyButton setImage:BHTVectorIcon(BHTIconNameForKey(@"button"), 18.0)
                    forState:UIControlStateNormal];
        copyButton.tag = 9001;

        if (@available(iOS 14.0, *)) {
            [copyButton setShowsMenuAsPrimaryAction:true];

            UIAction *fullname = [UIAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_MENU_OPTION_3"]
                                                     image:BHTVectorIcon(BHTIconNameForKey(@"fullname"), 16.0)
                                                identifier:nil
                                                   handler:^(__kindof UIAction * _Nonnull action) {
                if (self.viewModel.fullName != nil) UIPasteboard.generalPasteboard.string = self.viewModel.fullName;
            }];

            UIAction *username = [UIAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_MENU_OPTION_2"]
                                                     image:BHTVectorIcon(BHTIconNameForKey(@"username"), 16.0)
                                                identifier:nil
                                                   handler:^(__kindof UIAction * _Nonnull action) {
                if (self.viewModel.username != nil) UIPasteboard.generalPasteboard.string = self.viewModel.username;
            }];

            UIAction *bio = [UIAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_MENU_OPTION_1"]
                                                image:BHTVectorIcon(BHTIconNameForKey(@"bio"), 16.0)
                                           identifier:nil
                                              handler:^(__kindof UIAction * _Nonnull action) {
                if (self.viewModel.bio != nil) UIPasteboard.generalPasteboard.string = self.viewModel.bio;
            }];

            UIAction *location = [UIAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_MENU_OPTION_5"]
                                                     image:BHTVectorIcon(BHTIconNameForKey(@"location"), 16.0)
                                                identifier:nil
                                                   handler:^(__kindof UIAction * _Nonnull action) {
                if (self.viewModel.location != nil) UIPasteboard.generalPasteboard.string = self.viewModel.location;
            }];

            UIAction *url = [UIAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_MENU_OPTION_4"]
                                                image:BHTVectorIcon(BHTIconNameForKey(@"url"), 16.0)
                                           identifier:nil
                                              handler:^(__kindof UIAction * _Nonnull action) {
                if (self.viewModel.url != nil) UIPasteboard.generalPasteboard.string = self.viewModel.url;
            }];

            [copyButton setMenu:[UIMenu menuWithTitle:@"" children:@[fullname, username, bio, location, url]]];
        } else {
            [copyButton addTarget:self
                           action:@selector(copyButtonHandler:)
                 forControlEvents:UIControlEventTouchUpInside];
        }

        copyButton.translatesAutoresizingMaskIntoConstraints = NO;
        [actionButtonsView addSubview:copyButton];

        [NSLayoutConstraint activateConstraints:@[
            [copyButton.centerYAnchor constraintEqualToAnchor:actionButtonsView.centerYAnchor],
            [copyButton.widthAnchor constraintEqualToConstant:32.0],
            [copyButton.heightAnchor constraintEqualToConstant:32.0],
        ]];

        if (isDeviceLanguageRTL()) {
            [NSLayoutConstraint activateConstraints:@[
                [copyButton.leadingAnchor constraintEqualToAnchor:innerContentView.trailingAnchor constant:7.0],
            ]];
        } else {
            [NSLayoutConstraint activateConstraints:@[
                [copyButton.trailingAnchor constraintEqualToAnchor:innerContentView.leadingAnchor constant:-7.0],
            ]];
        }
    } else {
        [copyButton setImage:BHTVectorIcon(BHTIconNameForKey(@"button"), 18.0)
                    forState:UIControlStateNormal];
    }

    // Style for current theme.
    BHTApplyCopyButtonStyle(copyButton, headerView);
}

%new - (void)copyButtonHandler:(UIButton *)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"hi"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    if (is_iPad()) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = sender.frame;
    }

    UIAlertAction *fullname = [UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_MENU_OPTION_3"]
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
        if (self.viewModel.fullName != nil) UIPasteboard.generalPasteboard.string = self.viewModel.fullName;
    }];

    UIAlertAction *username = [UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_MENU_OPTION_2"]
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
        if (self.viewModel.username != nil) UIPasteboard.generalPasteboard.string = self.viewModel.username;
    }];

    UIAlertAction *bio = [UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_MENU_OPTION_1"]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
        if (self.viewModel.bio != nil) UIPasteboard.generalPasteboard.string = self.viewModel.bio;
    }];

    UIAlertAction *location = [UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_MENU_OPTION_5"]
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
        if (self.viewModel.location != nil) UIPasteboard.generalPasteboard.string = self.viewModel.location;
    }];

    UIAlertAction *url = [UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_MENU_OPTION_4"]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
        if (self.viewModel.url != nil) UIPasteboard.generalPasteboard.string = self.viewModel.url;
    }];

    if (@available(iOS 13.0, *)) {
        [bio setValue:BHTVectorIcon(BHTIconNameForKey(@"bio"), 16.0) forKey:@"image"];
        [username setValue:BHTVectorIcon(BHTIconNameForKey(@"username"), 16.0) forKey:@"image"];
        [fullname setValue:BHTVectorIcon(BHTIconNameForKey(@"fullname"), 16.0) forKey:@"image"];
        [url setValue:BHTVectorIcon(BHTIconNameForKey(@"url"), 16.0) forKey:@"image"];
        [location setValue:BHTVectorIcon(BHTIconNameForKey(@"location"), 16.0) forKey:@"image"];
    }

    [alert addAction:fullname];
    [alert addAction:username];
    [alert addAction:bio];
    [alert addAction:location];
    [alert addAction:url];
    [alert addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"CANCEL_BUTTON_TITLE"]
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:true completion:nil];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig(previousTraitCollection);

    if (![BHTManager CopyProfileInfo]) {
        return;
    }

    T1ProfileHeaderView *headerView = [self valueForKey:@"_headerView"];
    if (!headerView || ![headerView respondsToSelector:@selector(actionButtonsView)]) {
        return;
    }

    UIButton *copyButton = (UIButton *)[headerView.actionButtonsView viewWithTag:9001];
    if (!copyButton) {
        return;
    }

    [copyButton setImage:BHTVectorIcon(BHTIconNameForKey(@"button"), 18.0)
                forState:UIControlStateNormal];

    if (@available(iOS 14.0, *)) {
        UIAction *fullname = [UIAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_MENU_OPTION_3"]
                                                 image:BHTVectorIcon(BHTIconNameForKey(@"fullname"), 16.0)
                                            identifier:nil
                                               handler:^(__kindof UIAction * _Nonnull action) {
            if (self.viewModel.fullName != nil) UIPasteboard.generalPasteboard.string = self.viewModel.fullName;
        }];
        UIAction *username = [UIAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_MENU_OPTION_2"]
                                                 image:BHTVectorIcon(BHTIconNameForKey(@"username"), 16.0)
                                            identifier:nil
                                               handler:^(__kindof UIAction * _Nonnull action) {
            if (self.viewModel.username != nil) UIPasteboard.generalPasteboard.string = self.viewModel.username;
        }];
        UIAction *bio = [UIAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_MENU_OPTION_1"]
                                            image:BHTVectorIcon(BHTIconNameForKey(@"bio"), 16.0)
                                       identifier:nil
                                          handler:^(__kindof UIAction * _Nonnull action) {
            if (self.viewModel.bio != nil) UIPasteboard.generalPasteboard.string = self.viewModel.bio;
        }];
        UIAction *location = [UIAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_MENU_OPTION_5"]
                                                 image:BHTVectorIcon(BHTIconNameForKey(@"location"), 16.0)
                                            identifier:nil
                                               handler:^(__kindof UIAction * _Nonnull action) {
            if (self.viewModel.location != nil) UIPasteboard.generalPasteboard.string = self.viewModel.location;
        }];
        UIAction *url = [UIAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_MENU_OPTION_4"]
                                            image:BHTVectorIcon(BHTIconNameForKey(@"url"), 16.0)
                                       identifier:nil
                                          handler:^(__kindof UIAction * _Nonnull action) {
            if (self.viewModel.url != nil) UIPasteboard.generalPasteboard.string = self.viewModel.url;
        }];
        [copyButton setMenu:[UIMenu menuWithTitle:@"" children:@[fullname, username, bio, location, url]]];
    }

    // Reapply style so border/tint match the updated theme.
    BHTApplyCopyButtonStyle(copyButton, headerView);
}

%end

%hook T1ProfileSummaryView
- (BOOL)shouldShowGetVerifiedButton {
    return [BHTManager hidePremiumOffer] ? false : %orig;
}
%end

// MARK: Show unrounded follower/following counts
%hook T1ProfileFriendsFollowingViewModel
- (id)_t1_followCountTextWithLabel:(id)label singularLabel:(id)singularLabel count:(id)count highlighted:(_Bool)highlighted {
    // First get the original result to understand the expected return type
    id originalResult = %orig;

    // Only proceed if we have a valid count that's an NSNumber
    if (count && [count isKindOfClass:[NSNumber class]]) {
        NSNumber *number = (NSNumber *)count;

        // Only show full numbers for counts under 10,000
        if ([number integerValue] >= 10000) {
            return originalResult;
        }

        // Format the number with the current locale's formatting
        NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
        [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
        [formatter setUsesGroupingSeparator:YES];
        NSString *formattedCount = [formatter stringFromNumber:number];

        // If original result is an NSString, find and replace abbreviated numbers
        if ([originalResult isKindOfClass:[NSString class]]) {
            NSString *originalString = (NSString *)originalResult;
            // Updated regex to match patterns like "1.7K", "1,7K", "6.2K", "6,2K", etc.
            // This handles both period and comma as decimal separators
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\d+[.,]\\d+[KMB]|\\d+[KMB]" options:0 error:nil];
            NSString *result = [regex stringByReplacingMatchesInString:originalString options:0 range:NSMakeRange(0, originalString.length) withTemplate:formattedCount];
            return result;
        }
        // If original result is an NSAttributedString, modify that
        else if ([originalResult isKindOfClass:[NSAttributedString class]]) {
            NSMutableAttributedString *mutableResult = [[NSMutableAttributedString alloc] initWithAttributedString:(NSAttributedString *)originalResult];
            NSString *originalText = mutableResult.string;

            // Updated regex to match patterns like "1.7K", "1,7K", "6.2K", "6,2K", etc.
            // This handles both period and comma as decimal separators
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\d+[.,]\\d+[KMB]|\\d+[KMB]" options:0 error:nil];
            NSArray *matches = [regex matchesInString:originalText options:0 range:NSMakeRange(0, originalText.length)];

            // Replace matches in reverse order to maintain correct indices
            for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
                [mutableResult replaceCharactersInRange:match.range withString:formattedCount];
            }
            return [mutableResult copy];
        }
    }
    return originalResult;
}
%end

// MARK: hide ADS - New Implementation
%hook TFNItemsDataViewAdapterRegistry
- (id)dataViewAdapterForItem:(id)item {
    if ([BHTManager HidePromoted]) {
        //Old Ads
        if ([item isKindOfClass:objc_getClass("T1URTTimelineStatusItemViewModel")] && ((T1URTTimelineStatusItemViewModel *)item).isPromoted) {
            return nil;
        }
        //New Ads
        if ([item isKindOfClass:objc_getClass("TwitterURT.URTTimelineGoogleNativeAdViewModel")]) {
            return nil;
        }
    }
    return %orig;
}
%end

%hook TFNItemsDataViewController
- (id)tableViewCellForItem:(id)arg1 atIndexPath:(id)arg2 {
    UITableViewCell *_orig = %orig;
    id tweet = [self itemAtIndexPath:arg2];
    NSString *class_name = NSStringFromClass([tweet classForCoder]);



    if ([BHTManager HidePromoted] && [tweet respondsToSelector:@selector(isPromoted)] && [tweet performSelector:@selector(isPromoted)]) {
        [_orig setHidden:YES];
    }

    if ([self.adDisplayLocation isEqualToString:@"PROFILE_TWEETS"]) {
        if ([BHTManager hideWhoToFollow]) {
            if ([class_name isEqualToString:@"T1URTTimelineUserItemViewModel"] || [class_name isEqualToString:@"T1TwitterSwift.URTTimelineCarouselViewModel"] || [class_name isEqualToString:@"TwitterURT.URTModuleHeaderViewModel"] || [class_name isEqualToString:@"TwitterURT.URTModuleFooterViewModel"]) {
                [_orig setHidden:true];
            }
        }

        if ([BHTManager hideTopicsToFollow]) {
            if ([class_name isEqualToString:@"T1TwitterSwift.URTTimelineTopicCollectionViewModel"] || [class_name isEqualToString:@"TwitterURT.URTModuleHeaderViewModel"] || [class_name isEqualToString:@"TwitterURT.URTModuleFooterViewModel"] || [class_name isEqualToString:@"TwitterURT.URTTimelineCarouselViewModel"]) {
                [_orig setHidden:true];
            }
        }
    }

    if ([self.adDisplayLocation isEqualToString:@"OTHER"]) {
        if ([BHTManager HidePromoted] && ([class_name isEqualToString:@"TwitterURT.URTModuleHeaderViewModel"] || [class_name isEqualToString:@"TwitterURT.URTModuleFooterViewModel"] || [class_name isEqualToString:@"T1URTTimelineMessageItemViewModel"])) {
            [_orig setHidden:true];
        }

        if ([BHTManager HidePromoted] && [class_name isEqualToString:@"TwitterURT.URTTimelineEventSummaryViewModel"]) {
            // Hide all EventSummaryViewModel items, not just promoted ones
            [_orig setHidden:true];
        }
        if ([BHTManager HidePromoted] && [class_name isEqualToString:@"TwitterURT.URTTimelineTrendViewModel"]) {
            _TtC10TwitterURT25URTTimelineTrendViewModel *trendModel = tweet;
            if ([[trendModel.scribeItem allKeys] containsObject:@"promoted_id"]) {
                [_orig setHidden:true];
            }
        }
        if ([BHTManager hideTrendVideos] && ([class_name isEqualToString:@"TwitterURT.URTModuleHeaderViewModel"] || [class_name isEqualToString:@"T1TwitterSwift.URTTimelineCarouselViewModel"])) {
            [_orig setHidden:true];
        }
    }

    if ([self.adDisplayLocation isEqualToString:@"TIMELINE_HOME"]) {
        if ([tweet isKindOfClass:%c(T1URTTimelineStatusItemViewModel)]) {
            T1URTTimelineStatusItemViewModel *fullTweet = tweet;
            if ([BHTManager HideTopics]) {
                if ((fullTweet.banner != nil) && [fullTweet.banner isKindOfClass:%c(TFNTwitterURTTimelineStatusTopicBanner)]) {
                    [_orig setHidden:true];
                }
            }
        }

        if ([BHTManager HideTopics]) {
            if ([tweet isKindOfClass:%c(_TtC10TwitterURT26URTTimelinePromptViewModel)]) {
                [_orig setHidden:true];
            }
        }

        if ([BHTManager hideWhoToFollow]) {
            if ([class_name isEqualToString:@"T1URTTimelineUserItemViewModel"] || [class_name isEqualToString:@"T1TwitterSwift.URTTimelineCarouselViewModel"] || [class_name isEqualToString:@"TwitterURT.URTModuleHeaderViewModel"] || [class_name isEqualToString:@"TwitterURT.URTModuleFooterViewModel"]) {
                [_orig setHidden:true];
            }
        }

        if ([BHTManager hidePremiumOffer]) {
            if ([class_name isEqualToString:@"T1URTTimelineMessageItemViewModel"]) {
                [_orig setHidden:true];
            }
        }
    }



    return _orig;
}
- (double)tableView:(id)arg1 heightForRowAtIndexPath:(id)arg2 {
    id tweet = [self itemAtIndexPath:arg2];
    NSString *class_name = NSStringFromClass([tweet classForCoder]);

    if ([BHTManager HidePromoted] && [tweet respondsToSelector:@selector(isPromoted)] && [tweet performSelector:@selector(isPromoted)]) {
        return 0;
    }

    if ([self.adDisplayLocation isEqualToString:@"PROFILE_TWEETS"]) {
        if ([BHTManager hideWhoToFollow]) {
            if ([class_name isEqualToString:@"T1URTTimelineUserItemViewModel"] || [class_name isEqualToString:@"T1TwitterSwift.URTTimelineCarouselViewModel"] || [class_name isEqualToString:@"TwitterURT.URTModuleHeaderViewModel"] || [class_name isEqualToString:@"TwitterURT.URTModuleFooterViewModel"]) {
                return 0;
            }
        }
        if ([BHTManager hideTopicsToFollow]) {
            if ([class_name isEqualToString:@"T1TwitterSwift.URTTimelineTopicCollectionViewModel"] || [class_name isEqualToString:@"TwitterURT.URTModuleHeaderViewModel"] || [class_name isEqualToString:@"TwitterURT.URTModuleFooterViewModel"] || [class_name isEqualToString:@"TwitterURT.URTTimelineCarouselViewModel"]) {
                return 0;
            }
        }
    }

    if ([self.adDisplayLocation isEqualToString:@"OTHER"]) {
        if ([BHTManager HidePromoted] && ([class_name isEqualToString:@"TwitterURT.URTModuleHeaderViewModel"] || [class_name isEqualToString:@"TwitterURT.URTModuleFooterViewModel"] || [class_name isEqualToString:@"T1URTTimelineMessageItemViewModel"])) {
            return 0;
        }

        if ([BHTManager HidePromoted] && [class_name isEqualToString:@"TwitterURT.URTTimelineEventSummaryViewModel"]) {
            // Hide all EventSummaryViewModel items, not just promoted ones
            return 0;
        }
        if ([BHTManager HidePromoted] && [class_name isEqualToString:@"TwitterURT.URTTimelineTrendViewModel"]) {
            _TtC10TwitterURT25URTTimelineTrendViewModel *trendModel = tweet;
            if ([[trendModel.scribeItem allKeys] containsObject:@"promoted_id"]) {
                return 0;
            }
        }

        if ([BHTManager hideTrendVideos] && ([class_name isEqualToString:@"TwitterURT.URTModuleHeaderViewModel"] || [class_name isEqualToString:@"TwitterURT.URTModuleFooterViewModel"] || [class_name isEqualToString:@"T1TwitterSwift.URTTimelineCarouselViewModel"])) {
            return 0;
        }
    }

    if ([self.adDisplayLocation isEqualToString:@"TIMELINE_HOME"]) {
        if ([tweet isKindOfClass:%c(T1URTTimelineStatusItemViewModel)]) {
            T1URTTimelineStatusItemViewModel *fullTweet = tweet;

            if ([BHTManager HideTopics]) {
                if ((fullTweet.banner != nil) && [fullTweet.banner isKindOfClass:%c(TFNTwitterURTTimelineStatusTopicBanner)]) {
                    return 0;
                }
            }
        }

        if ([BHTManager HideTopics]) {
            if ([tweet isKindOfClass:%c(_TtC10TwitterURT26URTTimelinePromptViewModel)]) {
                return 0;
            }
        }

        if ([BHTManager hideWhoToFollow]) {
            if ([class_name isEqualToString:@"T1URTTimelineUserItemViewModel"] || [class_name isEqualToString:@"T1TwitterSwift.URTTimelineCarouselViewModel"] || [class_name isEqualToString:@"TwitterURT.URTModuleHeaderViewModel"] || [class_name isEqualToString:@"TwitterURT.URTModuleFooterViewModel"]) {
                return 0;
            }
        }

        if ([BHTManager hidePremiumOffer]) {
            if ([class_name isEqualToString:@"T1URTTimelineMessageItemViewModel"]) {
                return 0;
            }
        }
    }



    return %orig;
}

- (double)tableView:(id)arg1 heightForHeaderInSection:(long long)arg2 {
    if (self.sections && self.sections[arg2] && ((NSArray* )self.sections[arg2]).count && self.sections[arg2][0]) {
        NSString *sectionClassName = NSStringFromClass([self.sections[arg2][0] classForCoder]);
        if ([sectionClassName isEqualToString:@"TFNTwitterUser"]) {
            return 0;
        }
    }
    return %orig;
}
%end

%hook TFNTwitterStatus
- (_Bool)isCardHidden {
    return ([BHTManager HidePromoted] && [self isPromoted]) ? true : %orig;
}
%end

// MARK: DM download
%hook T1DirectMessageEntryMediaCell
%property (nonatomic, strong) JGProgressHUD *hud;
- (void)setEntryViewModel:(id)arg1 {
    %orig;
    if ([BHTManager DownloadingVideos]) {
        UIContextMenuInteraction *menuInteraction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [self setUserInteractionEnabled:true];

        if ([BHTManager isDMVideoCell:self.inlineMediaView]) {
            [self addInteraction:menuInteraction];
        }
    }
}
%new - (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location {
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        UIAction *saveAction = [UIAction actionWithTitle:@"Download" image:[UIImage systemImageNamed:@"square.and.arrow.down"] identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
            [self DownloadHandler];
        }];
        return [UIMenu menuWithTitle:@"" children:@[saveAction]];
    }];
}
%new - (void)DownloadHandler {
    NSAttributedString *AttString = [[NSAttributedString alloc] initWithString:[[BHTBundle sharedBundle] localizedStringForKey:@"DOWNLOAD_MENU_TITLE"] attributes:@{
        NSFontAttributeName: [BHTManager menuTitleFont],
        NSForegroundColorAttributeName: UIColor.labelColor
    }];
    TFNActiveTextItem *title = [[%c(TFNActiveTextItem) alloc] initWithTextModel:[[%c(TFNAttributedTextModel) alloc] initWithAttributedString:AttString] activeRanges:nil];

    NSMutableArray *actions = [[NSMutableArray alloc] init];
    [actions addObject:title];

    T1PlayerMediaEntitySessionProducible *session = self.inlineMediaView.viewModel.playerSessionProducer.sessionProducible;
    for (TFSTwitterEntityMediaVideoVariant *i in session.mediaEntity.videoInfo.variants) {
        if ([i.contentType isEqualToString:@"video/mp4"]) {
            TFNActionItem *download = [%c(TFNActionItem) actionItemWithTitle:[BHTManager getVideoQuality:i.url] imageName:@"arrow_down_circle_stroke" action:^{
                BHDownload *DownloadManager = [[BHDownload alloc] init];
                self.hud = [JGProgressHUD progressHUDWithStyle:JGProgressHUDStyleDark];
                self.hud.textLabel.text = [[BHTBundle sharedBundle] localizedStringForKey:@"PROGRESS_DOWNLOADING_STATUS_TITLE"];
                [DownloadManager downloadFileWithURL:[NSURL URLWithString:i.url]];
                [DownloadManager setDelegate:self];
                [self.hud showInView:topMostController().view];
            }];
            [actions addObject:download];
        }

        if ([i.contentType isEqualToString:@"application/x-mpegURL"]) {
            TFNActionItem *option = [objc_getClass("TFNActionItem") actionItemWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"FFMPEG_DOWNLOAD_OPTION_TITLE"] imageName:@"arrow_down_circle_stroke" action:^{

                self.hud = [JGProgressHUD progressHUDWithStyle:JGProgressHUDStyleDark];
                self.hud.textLabel.text = [[BHTBundle sharedBundle] localizedStringForKey:@"FETCHING_PROGRESS_TITLE"];
                [self.hud showInView:topMostController().view];

                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    MediaInformation *mediaInfo = [BHTManager getM3U8Information:[NSURL URLWithString:i.url]];
                    dispatch_async(dispatch_get_main_queue(), ^(void) {
                        [self.hud dismiss];

                        TFNMenuSheetViewController *alert2 = [BHTManager newFFmpegDownloadSheet:mediaInfo downloadingURL:[NSURL URLWithString:i.url] progressView:self.hud];
                        [alert2 tfnPresentedCustomPresentFromViewController:topMostController() animated:YES completion:nil];
                    });
                });

            }];

            [actions addObject:option];
        }
    }

    TFNMenuSheetViewController *alert = [[%c(TFNMenuSheetViewController) alloc] initWithActionItems:[NSArray arrayWithArray:actions]];
    [alert tfnPresentedCustomPresentFromViewController:topMostController() animated:YES completion:nil];
}
%new - (void)downloadProgress:(float)progress {
    self.hud.detailTextLabel.text = [BHTManager getDownloadingPersent:progress];
}

%new - (void)downloadDidFinish:(NSURL *)filePath Filename:(NSString *)fileName {
    NSString *DocPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true).firstObject;
    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *newFilePath = [[NSURL fileURLWithPath:DocPath] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4", NSUUID.UUID.UUIDString]];
    [manager moveItemAtURL:filePath toURL:newFilePath error:nil];
    [self.hud dismiss];
    [BHTManager showSaveVC:newFilePath];
}
%new - (void)downloadDidFailureWithError:(NSError *)error {
    if (error) {
        [self.hud dismiss];
    }
}
%end

// upload custom voice
%hook T1MediaAttachmentsViewCell
%property (nonatomic, strong) UIButton *uploadButton;
- (void)updateCellElements {
    %orig;

    if ([BHTManager customVoice]) {
        TFNButton *removeButton = [self valueForKey:@"_removeButton"];

        if ([self.attachment isKindOfClass:%c(TTMAssetVoiceRecording)]) {
            if (self.uploadButton == nil) {
                self.uploadButton = [UIButton buttonWithType:UIButtonTypeCustom];
                UIImageSymbolConfiguration *smallConfig = [UIImageSymbolConfiguration configurationWithScale:UIImageSymbolScaleSmall];
                UIImage *arrowUpImage = [UIImage systemImageNamed:@"arrow.up" withConfiguration:smallConfig];
                [self.uploadButton setImage:arrowUpImage forState:UIControlStateNormal];
                [self.uploadButton addTarget:self action:@selector(handleUploadButton:) forControlEvents:UIControlEventTouchUpInside];
                [self.uploadButton setTintColor:UIColor.labelColor];
                [self.uploadButton setBackgroundColor:[UIColor blackColor]];
                [self.uploadButton.layer setCornerRadius:29/2];
                [self.uploadButton setTranslatesAutoresizingMaskIntoConstraints:false];

                if (self.uploadButton.superview == nil) {
                    [self addSubview:self.uploadButton];
                    [NSLayoutConstraint activateConstraints:@[
                        [self.uploadButton.trailingAnchor constraintEqualToAnchor:removeButton.leadingAnchor constant:-10],
                        [self.uploadButton.topAnchor constraintEqualToAnchor:removeButton.topAnchor],
                        [self.uploadButton.widthAnchor constraintEqualToConstant:29],
                        [self.uploadButton.heightAnchor constraintEqualToConstant:29],
                    ]];
                }
            }
        }
    }
}
%new - (void)handleUploadButton:(UIButton *)sender {
    UIImagePickerController *videoPicker = [[UIImagePickerController alloc] init];
    videoPicker.mediaTypes = @[(NSString*)kUTTypeMovie];
    videoPicker.delegate = self;

    [topMostController() presentViewController:videoPicker animated:YES completion:nil];
}
%new - (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    NSURL *videoURL = info[UIImagePickerControllerMediaURL];
    TTMAssetVoiceRecording *attachment = self.attachment;
    NSURL *recorder_url = [NSURL fileURLWithPath:attachment.filePath];

    if (recorder_url != nil) {
        NSFileManager *fileManager = [NSFileManager defaultManager];

        NSError *error = nil;
        if ([fileManager fileExistsAtPath:[recorder_url path]]) {
            [fileManager removeItemAtURL:recorder_url error:&error];
            if (error) {
                NSLog(@"[BHTwitter] Error removing existing file: %@", error);
            }
        }

        [fileManager copyItemAtURL:videoURL toURL:recorder_url error:&error];
        if (error) {
            NSLog(@"[BHTwitter] Error copying file: %@", error);
        }
    }

    [picker dismissViewControllerAnimated:true completion:nil];
}
%new - (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:true completion:nil];
}
%end

// MARK: Open reply in webview

static id BHT_accountForAuthenticatedWebView(void) {
    Class hostClass = %c(T1HostViewController);
    if ([hostClass respondsToSelector:@selector(sharedHostViewController)]) {
        id host = [hostClass sharedHostViewController];
        if ([host respondsToSelector:@selector(currentAccount)]) {
            id account = [host currentAccount];
            if (account) {
                return account;
            }
        }
    }

    return nil;
}

static TFNTwitterStatus *BHT_statusFromObject(id object) {
    if (!object) {
        return nil;
    }

    if ([object isKindOfClass:%c(TFNTwitterStatus)]) {
        return (TFNTwitterStatus *)object;
    }

    @try {
        id tweet = [object valueForKey:@"tweet"];
        if ([tweet isKindOfClass:%c(TFNTwitterStatus)]) {
            return (TFNTwitterStatus *)tweet;
        }
    } @catch (__unused NSException *exception) {}

    @try {
        id status = [object valueForKey:@"status"];
        if ([status isKindOfClass:%c(TFNTwitterStatus)]) {
            return (TFNTwitterStatus *)status;
        }
    } @catch (__unused NSException *exception) {}

    return nil;
}

static TFNTwitterStatus *BHT_statusFromTweetView(T1StatusCell *tweetView) {
    @try {
        return BHT_statusFromObject([tweetView valueForKey:@"viewModel"]);
    } @catch (__unused NSException *exception) {}

    return nil;
}

static const void *BHTKeepReplyInWebViewKey = &BHTKeepReplyInWebViewKey;
static const void *BHTReplyWebViewDismissingKey = &BHTReplyWebViewDismissingKey;

// Injected into the reply webview via -evaluateJavaScript
// Grabs the ID of the new post
static NSString *const BHTReplyCaptureScript =
    @"(function(){"
    "if(window.__bhtReplyHook)return;window.__bhtReplyHook=true;"
    "var save=function(j){try{if(j&&j.data){"
    "var r=(j.data.create_tweet&&j.data.create_tweet.tweet_results&&j.data.create_tweet.tweet_results.result)||"
    "(j.data.notetweet_create&&j.data.notetweet_create.tweet_results&&j.data.notetweet_create.tweet_results.result);"
    "if(r&&r.rest_id)sessionStorage.setItem('__bhtNewReply',String(r.rest_id));}}catch(e){}};"
    "var isCreate=function(u){return typeof u==='string'&&u.indexOf('CreateTweet')!==-1;};"
    "var of=window.fetch;"
    "if(of){window.fetch=function(){var a=arguments;var u=(a[0]&&a[0].url)||a[0];"
    "return of.apply(this,a).then(function(res){try{if(isCreate(u))res.clone().json().then(save).catch(function(){});}catch(e){}return res;});};}"
    "var oo=XMLHttpRequest.prototype.open;var os=XMLHttpRequest.prototype.send;"
    "XMLHttpRequest.prototype.open=function(m,u){this.__bhtURL=u;return oo.apply(this,arguments);};"
    "XMLHttpRequest.prototype.send=function(){var x=this;try{if(isCreate(x.__bhtURL)){"
    "x.addEventListener('load',function(){try{save(JSON.parse(x.responseText));}catch(e){}});}}catch(e){}return os.apply(this,arguments);};"
    "})();";

static NSString *const BHTReplyReadScript =
    @"(function(){var v=sessionStorage.getItem('__bhtNewReply')||'';sessionStorage.removeItem('__bhtNewReply');return v;})();";

static void BHT_openStatusNatively(NSString *statusID) {
    if (statusID.length == 0) {
        return;
    }

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"twitter://status?id=%@", statusID]];
    if (!url) {
        return;
    }

    id delegate = [UIApplication sharedApplication].delegate;
    if ([delegate respondsToSelector:@selector(openURL:options:)]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(delegate, @selector(openURL:options:), url, @{});
    }
}

static void BHT_showPostSentAlert(NSString *statusID) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = topMostController();
        if (!top) {
            return;
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Post sent"
                                                                      message:nil
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Open" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            BHT_openStatusNatively(statusID);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleCancel handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    });
}

static BOOL BHT_openAuthenticatedTweetWebView(NSString *statusID) {
    if (statusID.length == 0) {
        return NO;
    }

    NSString *urlString = [NSString stringWithFormat:@"https://x.com/intent/tweet?in_reply_to=%@", statusID];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        return NO;
    }

    Class webViewControllerClass = %c(T1WebViewController);
    SEL initSel = @selector(initWithRootURL:account:shouldAuthenticate:shouldPresentAsNativePage:sourceStatus:scribeComponent:scribeParameters:);
    if (!webViewControllerClass || ![webViewControllerClass instancesRespondToSelector:initSel]) {
        return NO;
    }

    id account = BHT_accountForAuthenticatedWebView();
    if (!account) {
        return NO;
    }

    UIViewController *presentingController = topMostController();
    if (!presentingController) {
        return NO;
    }

    T1WebViewController *webViewController =
        [[webViewControllerClass alloc] initWithRootURL:url
                                                account:account
                                     shouldAuthenticate:YES
                              shouldPresentAsNativePage:NO
                                           sourceStatus:nil
                                        scribeComponent:nil
                                       scribeParameters:nil];
    if (!webViewController) {
        return NO;
    }

    // Mark this instance so our -doesURLResultTypeOpenInWebview: and -setCurrentURL:
    // hooks know to keep the reply in-webview and auto-close it on /home.
    objc_setAssociatedObject(webViewController, BHTKeepReplyInWebViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    Class navigationControllerClass = NSClassFromString(@"T1WebNavigationController")
        ?: %c(TFNNavigationController)
        ?: UINavigationController.class;
    UINavigationController *modalNavigationController = [[navigationControllerClass alloc] initWithRootViewController:webViewController];

    [presentingController presentViewController:modalNavigationController animated:YES completion:nil];

    return YES;
}

static T1StatusCell *BHT_tweetViewFromInlineActionsView(TTAStatusInlineActionsView *actionsView) {
    if ([actionsView.superview isKindOfClass:%c(T1StandardStatusView)]) {
        return (T1StatusCell *)[(T1StandardStatusView *)actionsView.superview eventHandler];
    }

    if ([actionsView.superview isKindOfClass:%c(T1TweetDetailsFocalStatusView)]) {
        return (T1StatusCell *)[(T1TweetDetailsFocalStatusView *)actionsView.superview eventHandler];
    }

    if ([actionsView.superview isKindOfClass:%c(T1ConversationFocalStatusView)]) {
        return (T1StatusCell *)[(T1ConversationFocalStatusView *)actionsView.superview eventHandler];
    }

    return nil;
}

%hook TTAStatusInlineReplyButton
- (void)didTap {
    if (![BHTManager replyInWebView]) {
        return %orig;
    }

    id delegate = self.delegate;
    if (![delegate isKindOfClass:%c(TTAStatusInlineActionsView)]) {
        return %orig;
    }

    TTAStatusInlineActionsView *actionsView = (TTAStatusInlineActionsView *)delegate;
    TFNTwitterStatus *status = BHT_statusFromTweetView(BHT_tweetViewFromInlineActionsView(actionsView));
    if (!status) {
        status = BHT_statusFromObject(actionsView.viewModel);
    }

    NSInteger statusID = status.statusID;
    if (statusID <= 0) {
        return %orig;
    }

    NSString *statusIDString = @(statusID).stringValue;
    if (!BHT_openAuthenticatedTweetWebView(statusIDString)) {
        return %orig;
    }
}
%end

%hook T1PersistentComposeViewController
- (void)persistentComposeViewDidTap:(id)composeView {
    if (![BHTManager replyInWebView]) {
        return %orig;
    }

    TFNTwitterStatus *status = BHT_statusFromObject(self.statusViewModel);
    NSInteger statusID = status.statusID;
    if (statusID <= 0) {
        return %orig;
    }

    NSString *statusIDString = @(statusID).stringValue;
    if (!BHT_openAuthenticatedTweetWebView(statusIDString)) {
        return %orig;
    }
}
%end

%hook T1WebViewController
- (void)didFinishLoadingWithError:(id)error {
    %orig;

    BHT_maybeHandleHarvestWebView(self);

    if (!objc_getAssociatedObject(self, BHTKeepReplyInWebViewKey)) {
        return;
    }

    WKWebView *webView = [self webView];
    if ([webView isKindOfClass:%c(WKWebView)]) {
        [webView evaluateJavaScript:BHTReplyCaptureScript completionHandler:nil];
    }
}

- (BOOL)doesURLResultTypeOpenInWebview:(long long)resultType {
    if (objc_getAssociatedObject(self, BHTKeepReplyInWebViewKey)) {
        return YES;
    }
    return %orig;
}

- (void)setCurrentURL:(NSURL *)url {
    %orig;

    if (!objc_getAssociatedObject(self, BHTKeepReplyInWebViewKey) || ![url.path isEqualToString:@"/home"]) {
        return;
    }

    // setCurrentURL: can fire more than once for the same navigation; only act once.
    if (objc_getAssociatedObject(self, BHTReplyWebViewDismissingKey)) {
        return;
    }
    objc_setAssociatedObject(self, BHTReplyWebViewDismissingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    __weak T1WebViewController *weakSelf = self;

    void (^finish)(NSString *) = ^(NSString *newReplyID) {
        [weakSelf dismissViewControllerAnimated:YES completion:^{
            if (newReplyID.length > 0) {
                BHT_showPostSentAlert(newReplyID);
            }
        }];
    };

    WKWebView *webView = [self webView];
    if ([webView isKindOfClass:%c(WKWebView)]) {
        [webView evaluateJavaScript:BHTReplyReadScript completionHandler:^(id result, NSError *jsError) {
            NSString *newReplyID = [result isKindOfClass:[NSString class]] ? (NSString *)result : nil;
            finish(newReplyID);
        }];
    } else {
        finish(nil);
    }
}
%end

// MARK: Web authentication for tweeting

static NSString *const BHTWebBearer =
    @"Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA";
static NSString *const BHTWebQueryIDDefaultsKey = @"nfb_createtweet_queryid";
static NSString *BHTWebCreateTweetQueryID = @"vwzfnq1lLOa1Nfx7htM2mw";

static NSString *BHTWebCT0 = nil;
static NSString *BHTWebAuthToken = nil;
static NSString *BHTWebTwid = nil;
static NSString *BHTWebAuthMulti = nil;

static NSMutableDictionary<NSString *, NSDictionary *> *BHTWebAccountCookies = nil;
static const void *BHTWebPostingUIDKey = &BHTWebPostingUIDKey;
static const void *BHTCreateTweetWatcherKey = &BHTCreateTweetWatcherKey;

static dispatch_queue_t BHT_accountCacheQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.nfb.webaccountcache", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSDictionary *BHT_cachedPair(NSString *userID) {
    if (userID.length == 0) {
        return nil;
    }
    __block NSDictionary *pair = nil;
    dispatch_sync(BHT_accountCacheQueue(), ^{
        pair = BHTWebAccountCookies[userID];
    });
    return pair;
}

static void BHT_setCachedPair(NSString *userID, NSDictionary *pair) {
    if (userID.length == 0) {
        return;
    }
    dispatch_sync(BHT_accountCacheQueue(), ^{
        if (!BHTWebAccountCookies) {
            BHTWebAccountCookies = [NSMutableDictionary dictionary];
        }
        if (pair) {
            BHTWebAccountCookies[userID] = pair;
        } else {
            [BHTWebAccountCookies removeObjectForKey:userID];
        }
    });
}
static BOOL BHTWebCookieHarvestInFlight = NO;
static UIWindow *BHTWebHarvestWindow = nil;
static BOOL BHTWebBootstrapInFlight = NO;

// The authenticated web helper webview is kept alive so we can generate a fresh
// x-client-transaction-id per send to avoid rate limiting
static WKWebView *BHTWebHelperWebView = nil;
static BOOL BHTWebHelperReady = NO;
static NSString *BHTWebXTID = nil;
static BOOL BHTWebXTIDInFlight = NO;

static const void *BHTWebHarvestWebViewKey = &BHTWebHarvestWebViewKey;

static void BHT_teardownWebHarvestWindow(void);
static void BHT_refreshXTID(void);
static void BHT_refreshWebCookiesViaWebView(void);

@interface WKWebView (BHTAsyncJavaScript)
- (void)callAsyncJavaScript:(NSString *)functionBody
                  arguments:(NSDictionary<NSString *, id> *)arguments
                    inFrame:(WKFrameInfo *)frame
             inContentWorld:(WKContentWorld *)contentWorld
          completionHandler:(void (^)(id result, NSError *error))completionHandler;
@end

static BOOL BHT_nativeCreateTweetInterceptEnabled(void) {
    return ![BHTManager replyInWebView];
}

#pragma mark - Web session cookie harvesting

static void BHT_storeWebCookies(NSArray<NSHTTPCookie *> *cookies) {
    if (![cookies isKindOfClass:[NSArray class]]) {
        return;
    }
    for (NSHTTPCookie *cookie in cookies) {
        NSString *domain = cookie.domain ?: @"";
        if (![domain containsString:@"x.com"] && ![domain containsString:@"twitter.com"]) {
            continue;
        }
        if ([cookie.name isEqualToString:@"ct0"] && cookie.value.length) {
            BHTWebCT0 = [cookie.value copy];
        } else if ([cookie.name isEqualToString:@"auth_token"] && cookie.value.length) {
            BHTWebAuthToken = [cookie.value copy];
        } else if ([cookie.name isEqualToString:@"twid"] && cookie.value.length) {
            BHTWebTwid = [cookie.value copy];
        } else if ([cookie.name isEqualToString:@"auth_multi"] && cookie.value.length) {
            BHTWebAuthMulti = [cookie.value copy];
        }
    }

    NSString *liveUserID = nil;
    if (BHTWebTwid.length) {
        NSString *decoded = [BHTWebTwid stringByRemovingPercentEncoding] ?: BHTWebTwid;
        NSRange eq = [decoded rangeOfString:@"="];
        NSString *idPart = eq.location != NSNotFound ? [decoded substringFromIndex:NSMaxRange(eq)] : decoded;
        NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        NSString *digits = [[idPart componentsSeparatedByCharactersInSet:nonDigits] componentsJoinedByString:@""];
        liveUserID = digits.length ? digits : nil;
    }
    if (liveUserID.length && BHTWebAuthToken.length && BHTWebCT0.length) {
        BHT_setCachedPair(liveUserID, @{
            @"auth_token": BHTWebAuthToken,
            @"ct0": BHTWebCT0,
            @"twid": BHTWebTwid,
        });
    }
}

static void BHT_harvestWebCookiesFromSharedStorage(void) {
    NSMutableArray<NSHTTPCookie *> *all = [NSMutableArray array];
    for (NSString *domain in @[@"https://api.twitter.com", @"https://twitter.com", @"https://x.com"]) {
        NSArray *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:[NSURL URLWithString:domain]];
        if (cookies) {
            [all addObjectsFromArray:cookies];
        }
    }
    BHT_storeWebCookies(all);
}

static void BHT_onHelperWebViewLoaded(WKWebView *webView);

@interface BHTWebHelperDelegate : NSObject <WKNavigationDelegate>
@end
@implementation BHTWebHelperDelegate
- (void)webView:(WKWebView *)webView didFinishNavigation:(__unused WKNavigation *)navigation {
    BHT_onHelperWebViewLoaded(webView);
}
- (void)webView:(__unused WKWebView *)webView didFailProvisionalNavigation:(__unused WKNavigation *)navigation withError:(__unused NSError *)error {
    BHTWebHelperWebView = nil;
    BHTWebHelperReady = NO;
    BHTWebCookieHarvestInFlight = NO;
}
@end

static BHTWebHelperDelegate *BHTWebHelperDelegateInstance = nil;

// Seed the helper webview's cookie store with the harvested web-session cookies so it
// loads authenticated
static void BHT_seedHelperCookies(WKWebView *webView, void (^done)(void)) {
    if (@available(iOS 11.0, *)) {
        NSMutableArray<NSHTTPCookie *> *cookies = [NSMutableArray array];
        NSDictionary *pairs = @{ @"auth_token": BHTWebAuthToken ?: @"",
                                 @"ct0": BHTWebCT0 ?: @"",
                                 @"twid": BHTWebTwid ?: @"" };
        for (NSString *name in pairs) {
            NSString *value = pairs[name];
            if (value.length == 0) continue;
            NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:@{
                NSHTTPCookieName: name,
                NSHTTPCookieValue: value,
                NSHTTPCookieDomain: @".x.com",
                NSHTTPCookiePath: @"/",
            }];
            if (cookie) [cookies addObject:cookie];
        }
        if (cookies.count == 0) {
            done();
            return;
        }
        WKHTTPCookieStore *store = webView.configuration.websiteDataStore.httpCookieStore;
        __block NSUInteger remaining = cookies.count;
        for (NSHTTPCookie *cookie in cookies) {
            [store setCookie:cookie completionHandler:^{
                if (--remaining == 0) done();
            }];
        }
    } else {
        done();
    }
}

// Stand up an offscreen raw WKWebView on x.com
static void BHT_refreshWebCookiesViaWebView(void) {
    if (BHTWebHelperWebView) {
        BHT_refreshXTID();
        return;
    }
    if (BHTWebCookieHarvestInFlight) {
        return;
    }
    BHTWebCookieHarvestInFlight = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        BHT_harvestWebCookiesFromSharedStorage();

        WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
        configuration.allowsInlineMediaPlayback = YES;
        configuration.allowsPictureInPictureMediaPlayback = NO;
        configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
        WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 390, 844)
                                                configuration:configuration];
        BHTWebHelperDelegateInstance = [[BHTWebHelperDelegate alloc] init];
        webView.navigationDelegate = BHTWebHelperDelegateInstance;
        webView.customUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
        webView.userInteractionEnabled = NO;
        BHTWebHelperWebView = webView;
        BHTWebHelperReady = NO;

        UIWindow *keyWindow = nil;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { keyWindow = w; break; }
        }
        if (!keyWindow) {
            keyWindow = [UIApplication sharedApplication].windows.firstObject;
        }
        if (keyWindow) {
            webView.frame = CGRectMake(-3000, -3000, 390, 844);
            webView.alpha = 0.01;
            [keyWindow addSubview:webView];
        }

        BHT_seedHelperCookies(webView, ^{
            [webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://x.com/settings/account"]]];
        });
    });
}

static void BHT_onHelperWebViewLoaded(WKWebView *webView) {
    BHTWebCookieHarvestInFlight = NO;

    [webView.configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        BHT_storeWebCookies(cookies);
    }];

    NSString *script = nil;
    NSURL *scriptURL = [[BHTBundle sharedBundle] pathForFile:@"BHTWebXTID.js"];
    if (scriptURL) {
        script = [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:nil];
    }
    if (script.length) {
        [webView evaluateJavaScript:script completionHandler:^(__unused id result, __unused NSError *error) {
            BHTWebHelperReady = YES;
            BHT_refreshXTID();
        }];
    }
}

static void BHT_teardownWebHarvestWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (BHTWebHarvestWindow) {
            BHTWebHarvestWindow.hidden = YES;
            BHTWebHarvestWindow.rootViewController = nil;
            BHTWebHarvestWindow = nil;
        }
        BHTWebBootstrapInFlight = NO;
    });
}

static UIWindowScene *BHT_activeWindowScene(void) {
    if (@available(iOS 13.0, *)) {
        UIWindowScene *fallback = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                return (UIWindowScene *)scene;
            }
            if (!fallback) {
                fallback = (UIWindowScene *)scene;
            }
        }
        return fallback;
    }
    return nil;
}

static NSString *BHT_userIDStringForAccount(id account) {
    if (!account || ![account respondsToSelector:@selector(userID)]) {
        return nil;
    }
    long long uid = ((long long (*)(id, SEL))objc_msgSend)(account, @selector(userID));
    return uid ? [@(uid) stringValue] : nil;
}

static id BHT_accountForUserID(NSString *userID) {
    if (userID.length == 0) {
        return nil;
    }
    @try {
        Class twitterClass = %c(TFNTwitter);
        if (![twitterClass respondsToSelector:@selector(sharedTwitter)]) {
            return nil;
        }
        id twitter = ((id (*)(id, SEL))objc_msgSend)((id)twitterClass, @selector(sharedTwitter));
        if (![twitter respondsToSelector:@selector(accounts)]) {
            return nil;
        }
        NSArray *accounts = ((id (*)(id, SEL))objc_msgSend)(twitter, @selector(accounts));
        for (id account in accounts) {
            if ([BHT_userIDStringForAccount(account) isEqualToString:userID]) {
                return account;
            }
        }
    } @catch (__unused NSException *exception) {}
    return nil;
}

static void BHT_bootstrapAccount(id account, NSString *userID) {
    if (!account || userID.length == 0) {
        return;
    }

    if (BHTWebBootstrapInFlight) {
        return;
    }

    BHTWebBootstrapInFlight = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (BHTWebHarvestWindow) {
            BHTWebHarvestWindow.hidden = YES;
            BHTWebHarvestWindow.rootViewController = nil;
            BHTWebHarvestWindow = nil;
        }

        Class webViewControllerClass = %c(T1WebViewController);
        SEL initSel = @selector(initWithRootURL:account:shouldAuthenticate:shouldPresentAsNativePage:sourceStatus:scribeComponent:scribeParameters:);
        UIWindowScene *scene = BHT_activeWindowScene();
        if (!webViewControllerClass || !scene ||
            ![webViewControllerClass instancesRespondToSelector:initSel]) {
            BHTWebBootstrapInFlight = NO;
            return;
        }

        NSURL *url = [NSURL URLWithString:@"https://x.com/settings/account"];
        T1WebViewController *webViewController =
            [[webViewControllerClass alloc] initWithRootURL:url
                                                    account:account
                                         shouldAuthenticate:YES
                                  shouldPresentAsNativePage:NO
                                               sourceStatus:nil
                                            scribeComponent:nil
                                           scribeParameters:nil];
        if (!webViewController) {
            BHTWebBootstrapInFlight = NO;
            return;
        }

        objc_setAssociatedObject(webViewController, BHTWebHarvestWebViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
        window.frame = CGRectMake(-3000, -3000, 390, 844);
        window.windowLevel = UIWindowLevelNormal - 1000;
        window.userInteractionEnabled = NO;
        window.rootViewController = webViewController;
        window.hidden = NO;
        BHTWebHarvestWindow = window;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            BHT_teardownWebHarvestWindow();
        });
    });
}

static void BHT_refreshXTID(void) {
    if (BHTWebXTIDInFlight) {
        return;
    }
    WKWebView *webView = BHTWebHelperWebView;
    if (![webView isKindOfClass:[WKWebView class]]) {
        return;
    }
    if (@available(iOS 14.0, *)) {
        BHTWebXTIDInFlight = YES;
        NSString *path = [NSString stringWithFormat:@"/graphql/%@/CreateTweet", BHTWebCreateTweetQueryID];
        dispatch_async(dispatch_get_main_queue(), ^{
            [webView callAsyncJavaScript:@"return await window.__bhtTransactionId(path, method);"
                               arguments:@{ @"method": @"POST", @"path": path }
                             inFrame:nil
                          inContentWorld:WKContentWorld.pageWorld
                       completionHandler:^(id result, NSError *error) {
                BHTWebXTIDInFlight = NO;
                BOOL ok = [result isKindOfClass:[NSString class]] &&
                          [(NSString *)result length] > 10 &&
                          ![(NSString *)result hasPrefix:@"BHTERR:"];
                if (ok) {
                    BHTWebXTID = [result copy];
                }
            }];
        });
    }
}

static void BHT_prewarmWebCookiesIfNeeded(void) {
    if (!BHT_nativeCreateTweetInterceptEnabled()) {
        return;
    }

    NSString *savedQueryID = [[NSUserDefaults standardUserDefaults] stringForKey:BHTWebQueryIDDefaultsKey];
    if (savedQueryID.length) {
        BHTWebCreateTweetQueryID = [savedQueryID copy];
    }

    if (BHTWebHelperWebView) {
        BHT_refreshXTID();
    } else {
        BHT_refreshWebCookiesViaWebView();
    }

    BHT_harvestWebCookiesFromSharedStorage();

    id current = BHT_accountForAuthenticatedWebView();
    NSString *currentUserID = BHT_userIDStringForAccount(current);
    if (current && currentUserID.length && !BHT_cachedPair(currentUserID)) {
        BHT_bootstrapAccount(current, currentUserID);
    }
}

#pragma mark - Request / response transforms

static void BHT_applyWebAuth(NSMutableURLRequest *request, NSString *authToken, NSString *ct0, NSString *userID) {
    request.HTTPShouldHandleCookies = NO;

    for (NSString *header in @[@"Authorization", @"X-Twitter-Client-DeviceID", @"X-Twitter-Client-Version",
                               @"X-Twitter-Client", @"X-Twitter-API-Version", @"X-Twitter-Client-Limit-Ad-Tracking",
                               @"X-B3-TraceId", @"Timezone", @"kdt", @"X-Client-UUID"]) {
        [request setValue:nil forHTTPHeaderField:header];
    }

    [request setValue:BHTWebBearer forHTTPHeaderField:@"authorization"];
    [request setValue:@"OAuth2Session" forHTTPHeaderField:@"x-twitter-auth-type"];
    [request setValue:@"yes" forHTTPHeaderField:@"x-twitter-active-user"];
    if (ct0.length) {
        [request setValue:ct0 forHTTPHeaderField:@"x-csrf-token"];
    }

    NSMutableArray<NSString *> *cookiePairs = [NSMutableArray array];
    if (authToken.length) {
        [cookiePairs addObject:[NSString stringWithFormat:@"auth_token=%@", authToken]];
    }
    if (ct0.length) {
        [cookiePairs addObject:[NSString stringWithFormat:@"ct0=%@", ct0]];
    }
    if (userID.length) {
        [cookiePairs addObject:[NSString stringWithFormat:@"twid=u%%3D%@", userID]];
    }
    [request setValue:[cookiePairs componentsJoinedByString:@"; "] forHTTPHeaderField:@"Cookie"];
}

#pragma mark - Hooks

static void BHT_maybeHandleHarvestWebView(__unsafe_unretained id webViewController) {
    if (!webViewController || !objc_getAssociatedObject(webViewController, BHTWebHarvestWebViewKey)) {
        return;
    }

    WKWebView *webView = nil;
    @try {
        if ([webViewController respondsToSelector:@selector(webView)]) {
            webView = ((WKWebView *(*)(id, SEL))objc_msgSend)(webViewController, @selector(webView));
        }
    } @catch (__unused NSException *exception) {}

    void (^finish)(void) = ^{
        BHT_harvestWebCookiesFromSharedStorage();
        BHT_refreshWebCookiesViaWebView();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            BHT_teardownWebHarvestWindow();
        });
    };

    if ([webView isKindOfClass:%c(WKWebView)]) {
        [webView.configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
            BHT_storeWebCookies(cookies);
            finish();
        }];
    } else {
        finish();
    }
}

static BOOL BHT_isCreateTweetURL(NSURL *url) {
    return url && [url.path hasSuffix:@"/CreateTweet"];
}

// The queryId sits in the request path: .../graphql/<queryId>/CreateTweet
static NSString *BHT_queryIDFromCreateTweetURL(NSURL *url) {
    NSArray<NSString *> *components = url.path.pathComponents;
    if (components.count >= 2 && [components.lastObject isEqualToString:@"CreateTweet"]) {
        return components[components.count - 2];
    }
    return nil;
}

static NSString *BHT_postingUserIDFromRequest(NSURLRequest *request) {
    NSString *auth = [request valueForHTTPHeaderField:@"Authorization"];
    if (![auth isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSRange marker = [auth rangeOfString:@"oauth_token=\""];
    if (marker.location == NSNotFound) {
        return nil;
    }
    NSString *rest = [auth substringFromIndex:NSMaxRange(marker)];
    NSRange endQuote = [rest rangeOfString:@"\""];
    if (endQuote.location == NSNotFound) {
        return nil;
    }
    NSString *token = [rest substringToIndex:endQuote.location]; // "<userID>-<secret>"
    NSRange dash = [token rangeOfString:@"-"];
    return dash.location != NSNotFound ? [token substringToIndex:dash.location] : nil;
}

static NSString *BHT_harvestedUserID(void) {
    if (BHTWebTwid.length == 0) {
        return nil;
    }
    NSString *decoded = [BHTWebTwid stringByRemovingPercentEncoding] ?: BHTWebTwid;
    NSRange eq = [decoded rangeOfString:@"="];
    NSString *idPart = eq.location != NSNotFound ? [decoded substringFromIndex:NSMaxRange(eq)] : decoded;
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    NSString *digits = [[idPart componentsSeparatedByCharactersInSet:nonDigits] componentsJoinedByString:@""];
    return digits.length ? digits : nil;
}

static NSString *BHT_authTokenForUserID(NSString *userID) {
    if (userID.length == 0) {
        return nil;
    }

    NSString *primaryUID = BHT_harvestedUserID();
    if (primaryUID.length && [primaryUID isEqualToString:userID] && BHTWebAuthToken.length) {
        return BHTWebAuthToken;
    }

    if (BHTWebAuthMulti.length == 0) {
        return nil;
    }
    NSString *decoded = [BHTWebAuthMulti stringByRemovingPercentEncoding] ?: BHTWebAuthMulti;
    decoded = [decoded stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@"|,"];
    for (NSString *entry in [decoded componentsSeparatedByCharactersInSet:separators]) {
        NSRange colon = [entry rangeOfString:@":"];
        if (colon.location == NSNotFound) {
            continue;
        }
        NSString *uid = [entry substringToIndex:colon.location];
        NSString *token = [entry substringFromIndex:NSMaxRange(colon)];
        if ([uid isEqualToString:userID] && token.length) {
            return token;
        }
    }
    return nil;
}

static void BHT_waitUntilReady(BOOL (^ready)(void), void (^kick)(void)) {
    if (ready() || [NSThread isMainThread]) {
        return;
    }
    NSUInteger tick = 0;
    while (![NSThread isMainThread] && !ready()) {
        if (kick && (tick % 60 == 0)) { // ~every 3s
            dispatch_async(dispatch_get_main_queue(), kick);
        }
        [NSThread sleepForTimeInterval:0.05];
        tick++;
    }
}

static BOOL BHT_waitUntilReadyBounded(BOOL (^ready)(void), void (^kick)(void), NSTimeInterval maxSeconds) {
    if (ready()) {
        return YES;
    }
    if ([NSThread isMainThread]) {
        return NO;
    }
    NSUInteger tick = 0;
    NSUInteger maxTicks = (NSUInteger)(maxSeconds / 0.05);
    while (![NSThread isMainThread] && !ready() && tick < maxTicks) {
        if (kick && (tick % 60 == 0)) { // ~every 3s
            dispatch_async(dispatch_get_main_queue(), kick);
        }
        [NSThread sleepForTimeInterval:0.05];
        tick++;
    }
    return ready();
}

static BOOL BHT_resolveWebCreds(NSString *userID, NSString **outAuthToken, NSString **outCt0) {
    NSDictionary *cached = BHT_cachedPair(userID);
    NSString *authToken = cached[@"auth_token"];
    NSString *ct0 = cached[@"ct0"];
    if (outAuthToken) {
        *outAuthToken = authToken;
    }
    if (outCt0) {
        *outCt0 = ct0;
    }
    return userID.length > 0 && authToken.length > 0 && ct0.length > 0;
}

@interface BHTCt0Fetcher : NSObject <NSURLSessionTaskDelegate>
@property (nonatomic, copy) NSString *ct0;
@property (nonatomic, copy) NSString *twid;
@property (nonatomic, assign) BOOL loggedOut;
- (void)captureFromResponse:(NSURLResponse *)response;
@end

@implementation BHTCt0Fetcher
- (void)captureFromResponse:(NSURLResponse *)response {
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
        return;
    }
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    NSArray<NSHTTPCookie *> *cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:http.allHeaderFields
                                                                             forURL:http.URL ?: response.URL];
    for (NSHTTPCookie *cookie in cookies) {
        if ([cookie.name isEqualToString:@"ct0"] && cookie.value.length) {
            self.ct0 = [cookie.value copy];
        } else if ([cookie.name isEqualToString:@"twid"] && cookie.value.length) {
            self.twid = [cookie.value copy];
        }
    }
}
- (void)noteRedirectTarget:(NSURL *)url {
    NSString *path = url.absoluteString.lowercaseString ?: @"";
    if ([path containsString:@"login"] || [path containsString:@"logout"] ||
        [path containsString:@"/i/flow/"] || [path containsString:@"account/access"]) {
        self.loggedOut = YES;
    }
}
- (void)URLSession:(__unused NSURLSession *)session
              task:(__unused NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    [self captureFromResponse:response];
    [self noteRedirectTarget:request.URL];
    completionHandler(request);
}
@end

static NSString *BHT_userIDDigitsFromTwid(NSString *twid) {
    if (twid.length == 0) {
        return nil;
    }
    NSString *decoded = [twid stringByRemovingPercentEncoding] ?: twid;
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    NSString *digits = [[decoded componentsSeparatedByCharactersInSet:nonDigits] componentsJoinedByString:@""];
    return digits.length ? digits : nil;
}

static NSString *BHT_fetchCt0Sync(NSString *authToken, NSString *expectedUserID) {
    if (authToken.length == 0 || [NSThread isMainThread]) {
        return nil;
    }

    BHTCt0Fetcher *fetcher = [BHTCt0Fetcher new];
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.HTTPCookieStorage = nil;
    config.HTTPShouldSetCookies = NO;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:fetcher delegateQueue:nil];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://x.com/"]];
    request.HTTPShouldHandleCookies = NO;
    [request setValue:[NSString stringWithFormat:@"auth_token=%@", authToken] forHTTPHeaderField:@"Cookie"];
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
   forHTTPHeaderField:@"User-Agent"];

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[session dataTaskWithRequest:request completionHandler:^(__unused NSData *data,
                                                              NSURLResponse *response,
                                                              __unused NSError *error) {
        [fetcher captureFromResponse:response];
        dispatch_semaphore_signal(done);
    }] resume];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)));
    [session finishTasksAndInvalidate];

    if (fetcher.loggedOut) {
        return nil;
    }

    NSString *responseUserID = BHT_userIDDigitsFromTwid(fetcher.twid);
    if (expectedUserID.length && responseUserID.length && ![responseUserID isEqualToString:expectedUserID]) {
        return nil;
    }
    return fetcher.ct0;
}

static NSMutableURLRequest *BHT_webRequestFromNativeSend(NSURLRequest *request) {
    if (!BHT_isCreateTweetURL(request.URL)) {
        return nil;
    }

    if (!BHT_nativeCreateTweetInterceptEnabled()) {
        return nil;
    }

    NSString *queryID = BHT_queryIDFromCreateTweetURL(request.URL);
    if (queryID.length && ![queryID isEqualToString:BHTWebCreateTweetQueryID]) {
        BHTWebCreateTweetQueryID = [queryID copy];
        [[NSUserDefaults standardUserDefaults] setObject:queryID forKey:BHTWebQueryIDDefaultsKey];
    }

    if (BHTWebXTID.length == 0) {
        BHT_waitUntilReady(^BOOL{ return BHTWebXTID.length > 0; }, ^{
            if (!BHTWebHelperWebView) {
                BHT_refreshWebCookiesViaWebView();
            } else if (BHTWebHelperReady) {
                BHT_refreshXTID();
            }
        });
        if (BHTWebXTID.length == 0) {
            return nil;
        }
    }

    BHT_harvestWebCookiesFromSharedStorage();

    NSString *postingUserID = BHT_postingUserIDFromRequest(request);
    if (postingUserID.length == 0) {
        return nil;
    }

    NSString *authToken = nil, *ct0 = nil;

    if (!BHT_resolveWebCreds(postingUserID, &authToken, &ct0)) {
        NSString *token = BHT_authTokenForUserID(postingUserID);

        for (int attempt = 0; attempt < 2 && ct0.length == 0; attempt++) {
            if (token.length == 0) {
                id account = BHT_accountForUserID(postingUserID);
                if (!account) {
                    break;
                }
                NSString *waitUserID = postingUserID;
                __block id waitAccount = account;
                BHT_waitUntilReadyBounded(^BOOL{
                    BHT_harvestWebCookiesFromSharedStorage();
                    return BHT_authTokenForUserID(waitUserID).length > 0;
                }, ^{
                    BHT_bootstrapAccount(waitAccount, waitUserID);
                }, 30.0);
                token = BHT_authTokenForUserID(postingUserID);
                if (token.length == 0) {
                    break;
                }
            }

            NSString *fresh = BHT_fetchCt0Sync(token, postingUserID);
            if (fresh.length) {
                authToken = token;
                ct0 = fresh;
                BHT_setCachedPair(postingUserID, @{
                    @"auth_token": token,
                    @"ct0": fresh,
                    @"twid": [NSString stringWithFormat:@"u=%@", postingUserID],
                });
            } else {
                BHT_setCachedPair(postingUserID, nil);
                token = nil;
            }
        }

        if (authToken.length == 0 || ct0.length == 0) {
            return nil;
        }
    }

    NSMutableURLRequest *outgoing = [request mutableCopy];
    BHT_applyWebAuth(outgoing, authToken, ct0, postingUserID);
    [outgoing setValue:BHTWebXTID forHTTPHeaderField:@"x-client-transaction-id"];
    BHT_refreshXTID();
    // Tag the request with the account it's posting as so the task observer can invalidate the
    // right account's cached ct0 if the send comes back 4xx.
    objc_setAssociatedObject(outgoing, BHTWebPostingUIDKey, postingUserID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return outgoing;
}

// Watches a rewritten CreateTweet task and, if it finishes with a 4xx, it drops the ct0
// from the cache
@interface BHTCreateTweetWatcher : NSObject
@property (nonatomic, copy) NSString *userID;
@end

@implementation BHTCreateTweetWatcher
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(__unused NSDictionary *)change
                       context:(__unused void *)context {
    NSURLSessionTask *task = object;
    if (![keyPath isEqualToString:@"state"] || task.state != NSURLSessionTaskStateCompleted) {
        return;
    }

    BHTCreateTweetWatcher *keepAlive = self; // survive detaching our own retainer below
    @try {
        [task removeObserver:self forKeyPath:@"state"];
    } @catch (__unused NSException *exception) {}
    objc_setAssociatedObject(task, BHTCreateTweetWatcherKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSInteger code = [task.response isKindOfClass:[NSHTTPURLResponse class]]
        ? [(NSHTTPURLResponse *)task.response statusCode] : 0;
    NSString *userID = keepAlive.userID;
    if (code >= 400 && code < 500 && userID.length) {
        BHT_setCachedPair(userID, nil);
    }
    (void)keepAlive;
}
@end

static void BHT_watchCreateTweetTask(id task, NSString *userID) {
    if (![task isKindOfClass:[NSURLSessionTask class]] || userID.length == 0) {
        return;
    }
    BHTCreateTweetWatcher *watcher = [BHTCreateTweetWatcher new];
    watcher.userID = userID;
    objc_setAssociatedObject(task, BHTCreateTweetWatcherKey, watcher, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        [task addObserver:watcher forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:NULL];
    } @catch (__unused NSException *exception) {}
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NSMutableURLRequest *outgoing = BHT_webRequestFromNativeSend(request);
    if (outgoing) {
        NSURLSessionDataTask *task = %orig(outgoing);
        BHT_watchCreateTweetTask(task, objc_getAssociatedObject(outgoing, BHTWebPostingUIDKey));
        return task;
    }
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(id)completionHandler {
    NSMutableURLRequest *outgoing = BHT_webRequestFromNativeSend(request);
    if (outgoing) {
        NSURLSessionDataTask *task = %orig(outgoing, completionHandler);
        BHT_watchCreateTweetTask(task, objc_getAssociatedObject(outgoing, BHTWebPostingUIDKey));
        return task;
    }
    return %orig;
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData {
    NSMutableURLRequest *outgoing = BHT_webRequestFromNativeSend(request);
    if (outgoing) {
        NSURLSessionUploadTask *task = %orig(outgoing, bodyData);
        BHT_watchCreateTweetTask(task, objc_getAssociatedObject(outgoing, BHTWebPostingUIDKey));
        return task;
    }
    return %orig;
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(NSURL *)fileURL {
    NSMutableURLRequest *outgoing = BHT_webRequestFromNativeSend(request);
    if (outgoing) {
        NSURLSessionUploadTask *task = %orig(outgoing, fileURL);
        BHT_watchCreateTweetTask(task, objc_getAssociatedObject(outgoing, BHTWebPostingUIDKey));
        return task;
    }
    return %orig;
}

%end

// MARK: Save tweet as an image

%hook TTAStatusInlineShareButton
- (void)didLongPressActionButton:(UILongPressGestureRecognizer *)gestureRecognizer {
    if ([BHTManager tweetToImage]) {
        if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
            id delegate = self.delegate;
            if (![delegate isKindOfClass:%c(TTAStatusInlineActionsView)]) {
                return %orig;
            }
            TTAStatusInlineActionsView *actionsView = (TTAStatusInlineActionsView *)delegate;
            T1StatusCell *tweetView;

            if ([actionsView.superview isKindOfClass:%c(T1StandardStatusView)]) { // normal tweet in the time line
                tweetView = (T1StatusCell *)[(T1StandardStatusView *)actionsView.superview eventHandler];
            } else if ([actionsView.superview isKindOfClass:%c(T1TweetDetailsFocalStatusView)]) { // Focus tweet
                tweetView = (T1StatusCell *)[(T1TweetDetailsFocalStatusView *)actionsView.superview eventHandler];
            } else if ([actionsView.superview isKindOfClass:%c(T1ConversationFocalStatusView)]) { // Focus tweet
                tweetView = (T1StatusCell *)[(T1ConversationFocalStatusView *)actionsView.superview eventHandler];
            } else {
                return %orig;
            }

            UIImage *tweetImage = BH_imageFromView(tweetView);
            NSData *pngData = UIImagePNGRepresentation(tweetImage);
            NSURL *pngURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", [[NSUUID UUID] UUIDString]]];
            [pngData writeToURL:pngURL atomically:YES];
            UIActivityViewController *acVC = [[UIActivityViewController alloc] initWithActivityItems:@[pngURL] applicationActivities:nil];
            if (is_iPad()) {
                acVC.popoverPresentationController.sourceView = self;
                acVC.popoverPresentationController.sourceRect = self.frame;
            }
            [topMostController() presentViewController:acVC animated:true completion:nil];
            return;
        }
    }
    return %orig;
}
%end

// MARK: Hide Blue verified checkmark

%hook T1CompositionStatusViewModel
- (BOOL)isFromUserVerified {
    return [BHTManager hideBlueVerified] ? NO : %orig;
}
- (BOOL)isFromUserBlueVerified {
    return [BHTManager hideBlueVerified] ? NO : %orig;
}
%end

%hook TFNTwitterStatus
- (BOOL)isFromUserVerified {
    return [BHTManager hideBlueVerified] ? NO : %orig;
}
- (BOOL)isFromUserBlueVerified {
    return [BHTManager hideBlueVerified] ? NO : %orig;
}
%end

%hook T1StandardUserViewModel
- (BOOL)verified {
    return [BHTManager hideBlueVerified] ? NO : %orig;
}
- (BOOL)isBlueVerified {
    return [BHTManager hideBlueVerified] ? NO : %orig;
}
%end

%hook T1ProfileUserViewModel
- (BOOL)isVerifiedAccount {
    return [BHTManager hideBlueVerified] ? NO : %orig;
}
%end

%hook T1TwitterCoreStatusViewModelAdapter
- (BOOL)isFromUserVerified {
    return [BHTManager hideBlueVerified] ? NO : %orig;
}
- (BOOL)isFromUserBlueVerified {
    return [BHTManager hideBlueVerified] ? NO : %orig;
}
%end

// MARK: Timeline download

static NSArray *BHT_inlineActionViewClassesForViewModel(NSArray *classes, id viewModel) {
    if (![classes isKindOfClass:NSArray.class]) {
        return classes;
    }

    NSMutableArray *newClasses = [classes mutableCopy];

    Class analyticsButtonClass = %c(TTAStatusInlineAnalyticsButton);
    if (analyticsButtonClass &&
        [newClasses containsObject:analyticsButtonClass] &&
        [BHTManager hideViewCount]) {
        [newClasses removeObject:analyticsButtonClass];
    }

    Class bookmarkButtonClass = %c(TTAStatusInlineBookmarkButton);
    if (bookmarkButtonClass &&
        [newClasses containsObject:bookmarkButtonClass] &&
        [BHTManager hideBookmarkButton]) {
        [newClasses removeObject:bookmarkButtonClass];
    }

    Class downvoteButtonClass = %c(TTAStatusInlineDownvoteButton);
    if (downvoteButtonClass &&
        [newClasses containsObject:downvoteButtonClass] &&
        [BHTManager hideDownvoteButton]) {
        [newClasses removeObject:downvoteButtonClass];
    }

    return [newClasses copy];
}

%hook T1StatusInlineActionsView
+ (NSArray *)_t1_inlineActionViewClassesForViewModel:(id)arg1 options:(NSUInteger)arg2 displayType:(NSUInteger)arg3 account:(id)arg4 {
    NSArray *origClasses = %orig;
    return BHT_inlineActionViewClassesForViewModel(origClasses, arg1);
}
%end

%hook TTAStatusInlineActionsView
+ (NSArray *)_t1_inlineActionViewClassesForViewModel:(id)arg1 options:(NSUInteger)arg2 displayType:(NSUInteger)arg3 account:(id)arg4 {
    NSArray *origClasses = %orig;
    return BHT_inlineActionViewClassesForViewModel(origClasses, arg1);
}
// The downvote (dislike) button shown on replies/comments is gated by this
// method rather than being unconditionally present in the class list above.
// The array filter alone misses it, so intercept the gate directly: forcing
// NO prevents the button being built in every context (timeline and comments).
+ (BOOL)t1_shouldShowDownvoteButtonForViewModel:(id)arg1 options:(NSUInteger)arg2 anatomyFeatures:(id)arg3 displayType:(NSUInteger)arg4 account:(id)arg5 {
    if ([BHTManager hideDownvoteButton]) {
        return NO;
    }
    return %orig;
}
%end

// The reply/comment downvote button is created unconditionally and its actual
// display is driven by -visibility: the actions view lays out only buttons whose
// visibility is non-zero and calls setHidden:YES on the rest. Filtering the class
// list doesn't remove it from the hierarchy, so force its visibility to 0 — this
// excludes it from layout (no gap) and gets it hidden like any collapsed action.
%hook TTAStatusInlineDownvoteButton
- (NSUInteger)visibility {
    if ([BHTManager hideDownvoteButton]) {
        return 0;
    }
    return %orig;
}
%end

// Add a "Download media" item to the tweet overflow (3-dot) menu
%hook UIViewController
- (NSArray *)_t1_actionItemsForStatus:(__unsafe_unretained id)status account:(__unsafe_unretained id)account shareableEntity:(__unsafe_unretained id)shareableEntity entityURL:(__unsafe_unretained id)entityURL source:(__unsafe_unretained id)source options:(NSUInteger)options scribeComponent:(__unsafe_unretained id)scribeComponent doneBlock:(__unsafe_unretained id)doneBlock {
    NSArray *origItems = %orig;

    if (![BHTManager DownloadingVideos] || ![status respondsToSelector:@selector(entities)]) {
        return origItems;
    }

    NSArray *mediaEntities = [[status entities] media];
    BOOL hasVideo = NO;
    for (TFSTwitterEntityMedia *media in mediaEntities) {
        if ([media isKindOfClass:%c(TFSTwitterEntityMedia)] && (media.mediaType == 2 || media.mediaType == 3)) {
            hasVideo = YES;
            break;
        }
    }
    if (!hasVideo) {
        return origItems;
    }

    static char downloaderKey;
    BHDownloadInlineButton *downloader = objc_getAssociatedObject(self, &downloaderKey);
    if (!downloader) {
        downloader = [%c(BHDownloadInlineButton) new];
        objc_setAssociatedObject(self, &downloaderKey, downloader, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    TFNActionItem *downloadItem = [%c(TFNActionItem) actionItemWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"DOWNLOAD_VIDEOS_OPTION_TITLE"]
                                                              imageName:@"arrow_down_circle_stroke" action:^{
        [downloader presentDownloadOptionsForMediaEntities:mediaEntities];
    }];

    NSMutableArray *newItems = origItems ? [origItems mutableCopy] : [NSMutableArray array];
    NSUInteger insertIndex = newItems.count > 0 ? newItems.count - 1 : 0;
    [newItems insertObject:downloadItem atIndex:insertIndex];
    return newItems;
}
%end

// MARK: Always open in Safari

%hook SFSafariViewController
- (void)viewWillAppear:(BOOL)animated {
    if (![BHTManager alwaysOpenSafari]) {
        return %orig;
    }

    NSURL *url = [self initialURL];
    NSString *urlStr = [url absoluteString];

    // In-app browser is used for two-factor authentication with security key,
    // login will not complete successfully if it's redirected to Safari
    if ([urlStr containsString:@"twitter.com/account/"] || [urlStr containsString:@"twitter.com/i/flow/"]) {
        return %orig;
    }

    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    [self dismissViewControllerAnimated:NO completion:nil];
}

- (instancetype)initWithURL:(NSURL *)URL configuration:(SFSafariViewControllerConfiguration *)configuration {
    if (![BHTManager alwaysOpenSafari]) {
        return %orig;
    }

    NSString *urlStr = [URL absoluteString];

    // In-app browser is used for two-factor authentication with security key,
    // login will not complete successfully if it's redirected to Safari
    if ([urlStr containsString:@"twitter.com/account/"] || [urlStr containsString:@"twitter.com/i/flow/"]) {
        return %orig;
    }

    // Open in Safari instead and return nil to prevent SFSafariViewController creation
    [[UIApplication sharedApplication] openURL:URL options:@{} completionHandler:nil];
    return nil;
}

- (instancetype)initWithURL:(NSURL *)URL {
    if (![BHTManager alwaysOpenSafari]) {
        return %orig;
    }

    NSString *urlStr = [URL absoluteString];

    // In-app browser is used for two-factor authentication with security key,
    // login will not complete successfully if it's redirected to Safari
    if ([urlStr containsString:@"twitter.com/account/"] || [urlStr containsString:@"twitter.com/i/flow/"]) {
        return %orig;
    }

    // Open in Safari instead and return nil to prevent SFSafariViewController creation
    [[UIApplication sharedApplication] openURL:URL options:@{} completionHandler:nil];
    return nil;
}
%end

%hook SFInteractiveDismissController
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext {
    if (![BHTManager alwaysOpenSafari]) {
        return %orig;
    }
    [transitionContext completeTransition:NO];
}
%end

%hook TFSTwitterEntityURL
- (NSString *)url {
    // https://github.com/haoict/twitter-no-ads/blob/master/Tweak.xm#L195
    return self.expandedURL;
}
%end

// MARK: Disable RTL
%hook NSParagraphStyle
+ (NSWritingDirection)defaultWritingDirectionForLanguage:(id)lang {
    return [BHTManager disableRTL] ? NSWritingDirectionLeftToRight : %orig;
}
+ (NSWritingDirection)_defaultWritingDirection {
    return [BHTManager disableRTL] ? NSWritingDirectionLeftToRight : %orig;
}
%end

// MARK: Bio Translate
%hook TFNTwitterCanonicalUser
- (_Bool)isProfileBioTranslatable {
    return [BHTManager BioTranslate] ? true : %orig;
}
%end

// MARK: No search history
%hook T1SearchTypeaheadViewController // for old Twitter versions
- (void)viewDidLoad {
    if ([BHTManager NoHistory]) { // thanks @CrazyMind90
        if ([self respondsToSelector:@selector(clearActionControlWantsClear:)]) {
            [self performSelector:@selector(clearActionControlWantsClear:)];
        }
    }
    %orig;
}
%end

%hook TTSSearchTypeaheadViewController
- (void)viewDidLoad {
    if ([BHTManager NoHistory]) { // thanks @CrazyMind90
        if ([self respondsToSelector:@selector(clearActionControlWantsClear:)]) {
            [self performSelector:@selector(clearActionControlWantsClear:)];
        }
    }
    %orig;
}
%end

static NSString *BHTFeatureSwitchKeyForFeature(id feature) {
    if (!feature || ![feature respondsToSelector:@selector(key)]) {
        return nil;
    }

    NSString *(*keyMessage)(id, SEL) = (NSString *(*)(id, SEL))objc_msgSend;
    NSString *key = keyMessage(feature, @selector(key));
    return [key isKindOfClass:[NSString class]] ? key : nil;
}

static NSNumber *BHTFeatureSwitchOverrideValueForKey(NSString *key) {
    if (![key isKindOfClass:[NSString class]]) {
        return nil;
    }

    // Custom timelines overrides
    BOOL hideCustomTimelines = [BHTManager hideCustomTimelines];
    if ([key isEqualToString:@"hometimeline_pinned_tabs_topics_enabled"] ||
        [key isEqualToString:@"hometimeline_pinned_tabs_generic_timelines_enabled"] ||
        [key isEqualToString:@"hometimeline_pinned_tabs_sticky_warm_start_enabled"] ||
        [key isEqualToString:@"home_timeline_sticky_pinned_tab_enabled"] ||
        [key isEqualToString:@"super_follow_subscriptions_home_timeline_tab_sticky_enabled"]) {
        return hideCustomTimelines ? @NO : @YES;
    }

    if ([key isEqualToString:@"home_timeline_non_sticky_tab_on_new_session_enabled"]) {
        return @NO;
    }

    if ([key isEqualToString:@"hometimeline_pinned_tabs_limit"] ||
        [key isEqualToString:@"hometimeline_pinned_tabs_management_pinnedsection_inline_limit"] ||
        [key isEqualToString:@"hometimeline_pinned_tabs_management_topics_inline_limit"]) {
        return hideCustomTimelines ? @0 : @100;
    }

    // Edit tweet
    if ([key isEqualToString:@"edit_tweet_enabled"] ||
        [key isEqualToString:@"edit_tweet_ga_composition_enabled"] ||
        [key isEqualToString:@"edit_tweet_pdp_dialog_enabled"] ||
        [key isEqualToString:@"edit_tweet_upsell_enabled"]) {
        return @YES;
    }

    // Grok translations
    if ([key isEqualToString:@"grok_translations_bio_inline_translation_is_enabled"] ||
        [key isEqualToString:@"grok_translations_bio_translation_is_enabled"]) {
        return @([BHTManager BioTranslate]);
    }

    if ([key isEqualToString:@"grok_translations_post_inline_translation_is_enabled"] ||
        [key isEqualToString:@"grok_translations_post_translation_is_enabled"]) {
        return @YES;
    }

    // Profile tabs
    if ([key isEqualToString:@"articles_timeline_profile_tab_enabled"]) {
        return @(![BHTManager disableArticles]);
    }

    if ([key isEqualToString:@"highlights_tweets_tab_ui_enabled"]) {
        return @(![BHTManager disableHighlights]);
    }

    if ([key isEqualToString:@"media_tab_profile_videos_tab_enabled"] ||
        [key isEqualToString:@"media_tab_profile_photos_tab_enabled"] ||
        [key isEqualToString:@"media_tab_enabled"] ||
        [key isEqualToString:@"media_tab_profile_videos_tab_new_design_enabled"]) {
        return @(![BHTManager disableMediaTab]);
    }

    // Age verification bypass
    if ([key hasPrefix:@"ios_age_assurance"] || [key isEqualToString:@"grok_settings_age_restriction_enabled"]) {
        if ([BHTManager bypassAgeVerification]) {
            return @NO;
        }
    }

    // Conversation / tweet detail
    if ([key isEqualToString:@"conversational_replies_ios_minimal_detail_enabled"]) {
        return @(![BHTManager OldStyle]);
    }

    if ([key isEqualToString:@"reply_sorting_enabled"]) {
        return @(![BHTManager replySorting]);
    }

    if ([key isEqualToString:@"ios_tweet_detail_overflow_in_navigation_enabled"]) {
        return @NO;
    }

    if ([key isEqualToString:@"ios_tweet_detail_conversation_context_removal_enabled"]) {
        return @(![BHTManager restoreReplyContext]);
    }

    // Tab bar configuration
    if ([key isEqualToString:@"ios_tab_bar_default_show_grok"]) {
        return @([[NSUserDefaults standardUserDefaults] boolForKey:@"ios_tab_bar_default_show_grok"]);
    }

    if ([key isEqualToString:@"ios_tab_bar_default_show_profile"]) {
        return @([[NSUserDefaults standardUserDefaults] boolForKey:@"ios_tab_bar_default_show_profile"]);
    }

    if ([key isEqualToString:@"ios_tab_bar_default_show_communities"]) {
        return @([[NSUserDefaults standardUserDefaults] boolForKey:@"ios_tab_bar_default_show_communities"]);
    }

    // In-app article webview
    if ([key isEqualToString:@"ios_in_app_article_webview_enabled"]) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        if ([d objectForKey:key] != nil) {
            return @([d boolForKey:key]);
        }
        return @YES;
    }

    // Premium / subscription upsell disables
    if ([key isEqualToString:@"creator_purchases_dashboard_enabled"] ||
        [key isEqualToString:@"subscriptions_settings_item_enabled"] ||
        [key isEqualToString:@"grok_ios_profile_summary_enabled"] ||
        [key isEqualToString:@"creator_monetization_dashboard_enabled"] ||
        [key isEqualToString:@"creator_monetization_profile_subscription_tweets_tab_enabled"] ||
        [key isEqualToString:@"ios_subscription_journey_enabled"] ||
        [key isEqualToString:@"subscriptions_upsells_get_verified_profile"] ||
        [key isEqualToString:@"ios_profile_analytics_upsell_possible_enabled"] ||
        [key isEqualToString:@"ios_profile_analytics_upsell_enabled"] ||
        [key isEqualToString:@"subscriptions_verification_info_is_identity_verified"] ||
        [key isEqualToString:@"subscriptions_verification_info_reason_enabled"] ||
        [key isEqualToString:@"subscriptions_verification_info_verified_since_enabled"] ||
        [key isEqualToString:@"communities_enable_explore_tab"] ||
        [key isEqualToString:@"dash_items_download_grok_enabled"]) {
        return @NO;
    }

    return nil;
}

// MARK: Voice, SensitiveTweetWarnings, autoHighestLoad, VideoZoom, VODCaptions, disableSpacesBar feature
%hook TPSTwitterFeatureSwitches
// Twitter save all the features and keys in side JSON file in bundle of application fs_embedded_defaults_production.json, and use it in TFNTwitterAccount class but with DM voice maybe developers forget to add boolean variable in the class, so i had to change it from the file.
// also, you can find every key for every feature i used in this tweak, i can remove all the codes below and find every key for it but I'm lazy to do that, :)
- (BOOL)boolForKey:(NSString *)key {
    NSNumber *override = BHTFeatureSwitchOverrideValueForKey(key);
    if (override) {
        return override.boolValue;
    }

    return %orig;
}

- (id)featureSwitchValueForKey:(NSString *)key {
    NSNumber *override = BHTFeatureSwitchOverrideValueForKey(key);
    if (override) {
        return override;
    }

    return %orig;
}

- (NSInteger)integerForKey:(NSString *)key {
    NSNumber *override = BHTFeatureSwitchOverrideValueForKey(key);
    if (override) {
        return override.integerValue;
    }

    return %orig;
}

- (NSNumber *)numberForKey:(NSString *)key {
    NSNumber *override = BHTFeatureSwitchOverrideValueForKey(key);
    if (override) {
        return override;
    }

    return %orig;
}

- (id)rawValueForKey:(NSString *)key {
    NSNumber *override = BHTFeatureSwitchOverrideValueForKey(key);
    if (override) {
        return override;
    }

    return %orig;
}

- (BOOL)unsafePeekBoolForKey:(NSString *)key {
    NSNumber *override = BHTFeatureSwitchOverrideValueForKey(key);
    if (override) {
        return override.boolValue;
    }

    return %orig;
}

- (NSInteger)unsafePeekIntegerForKey:(NSString *)key {
    NSNumber *override = BHTFeatureSwitchOverrideValueForKey(key);
    if (override) {
        return override.integerValue;
    }

    return %orig;
}
%end

%hook TFSAccountFeatureSwitches
- (BOOL)boolForKey:(NSString *)key {
    NSNumber *override = BHTFeatureSwitchOverrideValueForKey(key);
    if (override) {
        return override.boolValue;
    }

    return %orig;
}

- (id)featureSwitchValueForFeature:(id)feature {
    NSString *key = BHTFeatureSwitchKeyForFeature(feature);
    NSNumber *override = BHTFeatureSwitchOverrideValueForKey(key);
    if (override) {
        return override;
    }

    return %orig;
}

- (NSNumber *)numberValueForFeature:(id)feature {
    NSString *key = BHTFeatureSwitchKeyForFeature(feature);
    NSNumber *override = BHTFeatureSwitchOverrideValueForKey(key);
    if (override) {
        return override;
    }

    return %orig;
}
%end

%hook TFSFeatureSwitches
- (BOOL)boolForKey:(NSString *)key {
    NSNumber *override = BHTFeatureSwitchOverrideValueForKey(key);
    if (override) {
        return override.boolValue;
    }

    return %orig;
}

- (id)featureSwitchValueForKey:(NSString *)key {
    NSNumber *override = BHTFeatureSwitchOverrideValueForKey(key);
    if (override) {
        return override;
    }

    return %orig;
}

- (NSInteger)integerForKey:(NSString *)key {
    NSNumber *override = BHTFeatureSwitchOverrideValueForKey(key);
    if (override) {
        return override.integerValue;
    }

    return %orig;
}

- (NSNumber *)numberForKey:(NSString *)key {
    NSNumber *override = BHTFeatureSwitchOverrideValueForKey(key);
    if (override) {
        return override;
    }

    return %orig;
}

- (id)rawValueForKey:(NSString *)key {
    NSNumber *override = BHTFeatureSwitchOverrideValueForKey(key);
    if (override) {
        return override;
    }

    return %orig;
}

- (BOOL)unsafePeekBoolForKey:(NSString *)key {
    NSNumber *override = BHTFeatureSwitchOverrideValueForKey(key);
    if (override) {
        return override.boolValue;
    }

    return %orig;
}

- (NSInteger)unsafePeekIntegerForKey:(NSString *)key {
    NSNumber *override = BHTFeatureSwitchOverrideValueForKey(key);
    if (override) {
        return override.integerValue;
    }

    return %orig;
}
%end

// MARK: Override the login screens
%hook T1AccountsViewController
- (void)private_startLoginFlowWithSender:(id)sender {
    [BHTLegacyLoginViewController presentLoginFrom:(UIViewController *)self];
}
%end

%hook T1HostViewController
- (void)makeOnboardingViewControllerWithCompletion:(void (^)(id))completion {
    if (completion == nil) {
        %orig;
        return;
    }
    completion([BHTLegacyLoginViewController loginRootNavigationController]);
}
%end


static NSTimeInterval BHTPinnedTabsLaunchUptime = 0;

static id BHTPinnedTabsPersistenceCoordinator(void) {
    static id coordinator = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [NSObject new];
    });
    return coordinator;
}

static NSArray *BHTPinnedTimelinesSnapshot(id repository) {
    if (!repository || ![repository respondsToSelector:@selector(pinnedTimelines)]) {
        return nil;
    }
    id value = ((id (*)(id, SEL))objc_msgSend)(repository, @selector(pinnedTimelines));
    return [value isKindOfClass:[NSArray class]] ? value : nil;
}

static void BHTRecordPinnedTimelineUnpin(void) {
    @synchronized (BHTPinnedTabsPersistenceCoordinator()) {
        [[NSUserDefaults standardUserDefaults] setDouble:CFAbsoluteTimeGetCurrent() forKey:@"BHTCustomTimelinesUnpinTime"];
    }
}

%hook _TtC32TwitterHomeFeatureImplementation31CachedPinnedTimelinesRepository
- (void)unpinTimelineWithTimeline:(id)timeline completion:(id)completion {
    BHTRecordPinnedTimelineUnpin();
    %orig;
}

- (void)unpinTimelineWithTimelineInput:(id)input completion:(id)completion {
    BHTRecordPinnedTimelineUnpin();
    %orig;
}

- (void)updatePinnedTimelines:(id)timelines {
    if ([BHTManager hideCustomTimelines]) {
        %orig;
        return;
    }

    BOOL block = NO;
    @synchronized (BHTPinnedTabsPersistenceCoordinator()) {
        BOOL isArray = [timelines isKindOfClass:[NSArray class]];
        NSUInteger incomingCount = isArray ? [timelines count] : 0;
        NSTimeInterval now = CFAbsoluteTimeGetCurrent();
        NSTimeInterval lastUnpin = [[NSUserDefaults standardUserDefaults] doubleForKey:@"BHTCustomTimelinesUnpinTime"];

        if ((now - lastUnpin < 120.0) || (isArray && incomingCount != 0)) {
            block = NO;
        } else {
            NSArray *snapshot = BHTPinnedTimelinesSnapshot(self);
            if (snapshot.count == 0) {
                block = NO;
            } else {
                NSTimeInterval uptime = [[NSProcessInfo processInfo] systemUptime];
                BOOL withinStartupWindow = (BHTPinnedTabsLaunchUptime > 0) && ((uptime - BHTPinnedTabsLaunchUptime) < 20.0);
                block = withinStartupWindow;
            }
        }
    }

    if (!block) {
        %orig;
    }
}
%end

static void BHTHideHomeAddTabButton(id container) {
    if (![BHTManager hideCustomTimelines]) {
        return;
    }
    @try {
        id button = [container valueForKey:@"addTabButton"];
        if ([button isKindOfClass:[UIView class]]) {
            ((UIView *)button).hidden = YES;
        }
    } @catch (__unused NSException *exception) {

		}
}

%hook _TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController
- (id)tfn_navigationBarAccessoryView {
    id accessory = %orig;
    BHTHideHomeAddTabButton(self);
    return accessory;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    BHTHideHomeAddTabButton(self);
}
%end

// MARK: Force Tweets to show images as Full frame: https://github.com/BandarHL/BHTwitter/issues/101
%hook T1StandardStatusAttachmentViewAdapter
- (NSUInteger)displayType {
    if (self.attachmentType == 2) {
        return [BHTManager forceTweetFullFrame] ? 1 : %orig;
    }
    return %orig;
}
%end

%hook T1HomeTimelineItemsViewController
- (void)_t1_initializeFleets {
    if ([BHTManager hideSpacesBar]) {
        return;
    }
    return %orig;
}
%end

%hook THFHomeTimelineItemsViewController
- (void)_t1_initializeFleets {
    if ([BHTManager hideSpacesBar]) {
        return;
    }
    return %orig;
}
%end


%hook THFHomeTimelineContainerViewController
- (void)_t1_showPremiumUpsellIfNeeded {
    if ([BHTManager hidePremiumOffer]) {
        return;
    }
    return %orig;
}
- (void)_t1_showPremiumUpsellIfNeededWithScribing:(BOOL)arg1 {
    if ([BHTManager hidePremiumOffer]) {
        return;
    }
    return %orig;
}
%end

%hook TFNTwitterMediaUploadConfiguration
- (_Bool)photoUploadHighQualityImagesSettingIsVisible {
    return [BHTManager autoHighestLoad] ? true : %orig;
}
%end

%hook T1SlideshowViewController
- (_Bool)_t1_shouldDisplayLoadHighQualityImageItemForImageDisplayView:(id)arg1 highestQuality:(_Bool)arg2 {
    return [BHTManager autoHighestLoad] ? true : %orig;
}
- (id)_t1_loadHighQualityActionItemWithTitle:(id)arg1 forImageDisplayView:(id)arg2 highestQuality:(_Bool)arg3 {
    if ([BHTManager autoHighestLoad]) {
        arg3 = true;
    }
    return %orig(arg1, arg2, arg3);
}
%end

%hook T1ImageDisplayView
- (_Bool)_tfn_shouldUseHighestQualityImage {
    return [BHTManager autoHighestLoad] ? true : %orig;
}
- (_Bool)_tfn_shouldUseHighQualityImage {
    return [BHTManager autoHighestLoad] ? true : %orig;
}
%end

%hook T1HighQualityImagesUploadSettings
- (_Bool)shouldUploadHighQualityImages {
    return [BHTManager autoHighestLoad] ? true : %orig;
}
%end

%hook TFSTwitterAPICommandAccountStateProvider
- (BOOL)allowPromotedContent {
    return [BHTManager HidePromoted] ? NO : %orig;
}
%end

%hook TFNTwitterAccount
- (BOOL)_isSubscriptionsGatingBypassEnabled {
    return YES;
}

- (BOOL)canAccessXPayments {
    return YES;
}

- (BOOL)isGrokAskGrokButtonUnderPostFocalEnabled {
    return YES;
}

- (BOOL)isGrokAskGrokButtonUnderPostPreviewEnabled {
    return YES;
}

- (BOOL)isGrokEditWithGrokButtonUnderPostFocalEnabled {
    return YES;
}

- (BOOL)isGrokEditWithGrokButtonUnderPostPreviewEnabled {
    return YES;
}

- (BOOL)isPremiumTierUser {
    return YES;
}

- (BOOL)isXPaymentsEnrolled {
    return YES;
}

- (_Bool)isEditProfileUsernameEnabled {
    return true;
}
- (_Bool)isEditTweetConsumptionEnabled {
    return true;
}
- (_Bool)isSensitiveTweetWarningsComposeEnabled {
    return [BHTManager disableSensitiveTweetWarnings] ? false : %orig;
}
- (_Bool)isSensitiveTweetWarningsConsumeEnabled {
    return [BHTManager disableSensitiveTweetWarnings] ? false : %orig;
}
- (BOOL)isAgeAssuranceAgeVerificationFlowEnabled {
    return [BHTManager bypassAgeVerification] ? NO : %orig;
}
- (_Bool)isVideoDynamicAdEnabled {
    return [BHTManager HidePromoted] ? false : %orig;
}

- (_Bool)isVODCaptionsEnabled {
    return [BHTManager DisableVODCaptions] ? false : %orig;
}
- (_Bool)photoUploadHighQualityImagesSettingIsVisible {
    return [BHTManager autoHighestLoad] ? true : %orig;
}
- (_Bool)loadingHighestQualityImageVariantPermitted {
    return [BHTManager autoHighestLoad] ? true : %orig;
}
- (_Bool)isDoubleMaxZoomFor4KImagesEnabled {
    return [BHTManager autoHighestLoad] ? true : %orig;
}
%end

%hook _TtCV4Grok12GrokRootView9ViewModel
- (BOOL)_isPremiumUser {
    return YES;
}
%end

%hook TFNTwitterStatus
- (BOOL)hasImageInterstitial {
    return [BHTManager disableSensitiveTweetWarnings] ? false : %orig;
}

- (id)imageInterstitial {
    return [BHTManager disableSensitiveTweetWarnings] ? nil : %orig;
}

- (id)innerImageInterstitial {
    return [BHTManager disableSensitiveTweetWarnings] ? nil : %orig;
}

- (BOOL)isPossiblySensitiveViewModelForAccount:(id)account {
    return [BHTManager disableSensitiveTweetWarnings] ? false : %orig;
}
%end

%hook HFHealthSafetyFeature
+ (BOOL)isTweetMedialInterstitialEnabled:(id)featureSwitches {
    return [BHTManager disableSensitiveTweetWarnings] ? false : %orig;
}
%end

// MARK: Tweet confirm
%hook T1TweetComposeViewController
- (void)_t1_didTapSendButton:(UIButton *)tweetButton {
    if ([BHTManager TweetConfirm]) {
        [%c(FLEXAlert) makeAlert:^(FLEXAlert *make) {
            make.message([[BHTBundle sharedBundle] localizedStringForKey:@"CONFIRM_ALERT_MESSAGE"]);
            make.button([[BHTBundle sharedBundle] localizedStringForKey:@"YES_BUTTON_TITLE"]).handler(^(NSArray<NSString *> *strings) {
                %orig;
            });
            make.button([[BHTBundle sharedBundle] localizedStringForKey:@"NO_BUTTON_TITLE"]).cancelStyle();
        } showFrom:topMostController()];
    } else {
        return %orig;
    }
}
- (void)_t1_handleTweet {
    if ([BHTManager TweetConfirm]) {
        [%c(FLEXAlert) makeAlert:^(FLEXAlert *make) {
            make.message([[BHTBundle sharedBundle] localizedStringForKey:@"CONFIRM_ALERT_MESSAGE"]);
            make.button([[BHTBundle sharedBundle] localizedStringForKey:@"YES_BUTTON_TITLE"]).handler(^(NSArray<NSString *> *strings) {
                %orig;
            });
            make.button([[BHTBundle sharedBundle] localizedStringForKey:@"NO_BUTTON_TITLE"]).cancelStyle();
        } showFrom:topMostController()];
    } else {
        return %orig;
    }
}
%end

// MARK: Follow confirm
%hook TUIFollowControl
- (void)_followUser:(id)arg1 event:(id)arg2 {
    if ([BHTManager FollowConfirm]) {
        [%c(FLEXAlert) makeAlert:^(FLEXAlert *make) {
            make.message([[BHTBundle sharedBundle] localizedStringForKey:@"CONFIRM_ALERT_MESSAGE"]);
            make.button([[BHTBundle sharedBundle] localizedStringForKey:@"YES_BUTTON_TITLE"]).handler(^(NSArray<NSString *> *strings) {
                %orig;
            });
            make.button([[BHTBundle sharedBundle] localizedStringForKey:@"NO_BUTTON_TITLE"]).cancelStyle();
        } showFrom:topMostController()];
    } else {
        return %orig;
    }
}
%end

// MARK: Like confirm
%hook TTAStatusInlineFavoriteButton
- (void)didTap {
    if ([BHTManager LikeConfirm]) {
        [%c(FLEXAlert) makeAlert:^(FLEXAlert *make) {
            make.message([[BHTBundle sharedBundle] localizedStringForKey:@"CONFIRM_ALERT_MESSAGE"]);
            make.button([[BHTBundle sharedBundle] localizedStringForKey:@"YES_BUTTON_TITLE"]).handler(^(NSArray<NSString *> *strings) {
                %orig;
            });
            make.button([[BHTBundle sharedBundle] localizedStringForKey:@"NO_BUTTON_TITLE"]).cancelStyle();
        } showFrom:topMostController()];
    } else {
        return %orig;
    }
}
%end

%hook T1StatusInlineFavoriteButton
- (void)didTap {
    if ([BHTManager LikeConfirm]) {
        [%c(FLEXAlert) makeAlert:^(FLEXAlert *make) {
            make.message([[BHTBundle sharedBundle] localizedStringForKey:@"CONFIRM_ALERT_MESSAGE"]);
            make.button([[BHTBundle sharedBundle] localizedStringForKey:@"YES_BUTTON_TITLE"]).handler(^(NSArray<NSString *> *strings) {
                %orig;
            });
            make.button([[BHTBundle sharedBundle] localizedStringForKey:@"NO_BUTTON_TITLE"]).cancelStyle();
        } showFrom:topMostController()];
    } else {
        return %orig;
    }
}
%end

// MARK: - Hide the trending/explore content on the Explore tab (keep the search bar)
static void BHT_hideExploreTabBar(UIView *view) {
    if (!view) return;
    if ([view isKindOfClass:NSClassFromString(@"TFNScrollingHorizontalLabelView")]) {
        view.hidden = YES;
        return;
    }
    for (UIView *subview in view.subviews) {
        BHT_hideExploreTabBar(subview);
    }
}

%hook T1GuideNavigationController
- (void)viewDidLayoutSubviews {
    %orig;
    if (![BHTManager hideTrends]) return;
    @try {
        UINavigationController *nav = (UINavigationController *)self;

        UIViewController *guideVC = nav.viewControllers.firstObject;
        if (!guideVC) return;

        Class chromeClass = NSClassFromString(@"T1TwitterSwift.URTChromeViewController");
        UIViewController *chrome = nil;
        for (UIViewController *child in guideVC.childViewControllers) {
            BOOL isChrome = chromeClass ? [child isKindOfClass:chromeClass]
                                        : [child respondsToSelector:@selector(tfn_navigationBarAccessoryView)];
            if (isChrome) { chrome = child; break; }
        }
        if (!chrome) return;

        if (chrome.isViewLoaded) chrome.view.hidden = YES;

        if ([chrome respondsToSelector:@selector(tfn_navigationBarAccessoryView)]) {
            UIView *accessory = ((UIView *(*)(id, SEL))objc_msgSend)(chrome, @selector(tfn_navigationBarAccessoryView));
            BHT_hideExploreTabBar(accessory);
        }
    } @catch (NSException *exception) {
        NSLog(@"[BHTwitter] hideTrends exception: %@", exception);
    }
}
%end

%hook T1ImmersiveExploreCardView
- (void)handleDoubleTap:(id)arg1 {
    if ([BHTManager LikeConfirm]) {
        [%c(FLEXAlert) makeAlert:^(FLEXAlert *make) {
            make.message([[BHTBundle sharedBundle] localizedStringForKey:@"CONFIRM_ALERT_MESSAGE"]);
            make.button([[BHTBundle sharedBundle] localizedStringForKey:@"YES_BUTTON_TITLE"]).handler(^(NSArray<NSString *> *strings) {
                %orig;
            });
            make.button([[BHTBundle sharedBundle] localizedStringForKey:@"NO_BUTTON_TITLE"]).cancelStyle();
        } showFrom:topMostController()];
    } else {
        return %orig;
    }
}
%end

%hook T1TweetDetailsViewController
- (void)_t1_toggleFavoriteOnCurrentStatus {
    if ([BHTManager LikeConfirm]) {
        [%c(FLEXAlert) makeAlert:^(FLEXAlert *make) {
            make.message([[BHTBundle sharedBundle] localizedStringForKey:@"CONFIRM_ALERT_MESSAGE"]);
            make.button([[BHTBundle sharedBundle] localizedStringForKey:@"YES_BUTTON_TITLE"]).handler(^(NSArray<NSString *> *strings) {
                %orig;
            });
            make.button([[BHTBundle sharedBundle] localizedStringForKey:@"NO_BUTTON_TITLE"]).cancelStyle();
        } showFrom:topMostController()];
    } else {
        return %orig;
    }
}
%end

// MARK: Undo tweet
%hook TFNTwitterToastNudgeExperimentModel
- (BOOL)shouldShowShowUndoTweetSentToast {
    return [BHTManager UndoTweet] ? true : %orig;
}
%end

// MARK: BHTwitter settings
%hook TFNActionItem
%new + (instancetype)actionItemWithTitle:(NSString *)arg1 systemImageName:(NSString *)arg2 action:(void (^)(void))arg3 {
    TFNActionItem *_self = [%c(TFNActionItem) actionItemWithTitle:arg1 imageName:nil action:arg3];
    [_self setValue:[UIImage systemImageNamed:arg2] forKey:@"_image"];
    return _self;
}
%end

%hook TFNSettingsNavigationItem
%new - (instancetype)initWithTitle:(NSString *)arg1 detail:(NSString *)arg2 systemIconName:(NSString *)arg3 controllerFactory:(UIViewController* (^)(void))arg4 {
    TFNSettingsNavigationItem *_self = [[%c(TFNSettingsNavigationItem) alloc] initWithTitle:arg1 detail:arg2 iconName:arg3 controllerFactory:arg4];
    [_self setValue:[UIImage systemImageNamed:arg3] forKey:@"_icon"];
    return _self;
}
%end

%hook T1GenericSettingsViewController
- (void)viewWillAppear:(BOOL)arg1 {
    %orig;
    if ([self.sections count] == 1) {
        TFNItemsDataViewControllerBackingStore *backingStore = self.backingStore;

        // Use Twitter's internal vector image system to get the Twitter bird icon
        UIImage *twitterIcon = nil;

        // Choose color based on interface style
        UIColor *iconColor;
        if (@available(iOS 12.0, *)) {
            if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                iconColor = [UIColor systemGray2Color];
            } else {
                iconColor = [UIColor secondaryLabelColor];
            }
        } else {
            iconColor = [UIColor secondaryLabelColor];
        }

        // Twitter vector image
        twitterIcon = [UIImage tfn_vectorImageNamed:@"twitter" fitsSize:CGSizeMake(20, 20) fillColor:iconColor];

        // Create the settings item
        TFNSettingsNavigationItem *bhtwitter = [[%c(TFNSettingsNavigationItem) alloc] initWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_TITLE"] detail:[[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_DETAIL"] iconName:nil controllerFactory:^UIViewController *{
            return [BHTManager BHTSettingsWithAccount:self.account];
        }];

        // Set our Twitter icon
        if (twitterIcon) {
            [bhtwitter setValue:twitterIcon forKey:@"_icon"];
        }

        if ([backingStore respondsToSelector:@selector(insertSection:atIndex:)]) {
            [backingStore insertSection:0 atIndex:1];
        } else {
            [backingStore _tfn_insertSection:0 atIndex:1];
        }
        if ([backingStore respondsToSelector:@selector(insertItem:atIndexPath:)]) {
            [backingStore insertItem:bhtwitter atIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        } else {
            [backingStore _tfn_insertItem:bhtwitter atIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        }
    }
}
%end

%hook T1SettingsViewController
- (void)viewWillAppear:(BOOL)arg1 {
    %orig;
    if ([self.sections count] == 2) {
        TFNItemsDataViewControllerBackingStore *DataViewControllerBackingStore = self.backingStore;
        [DataViewControllerBackingStore insertSection:0 atIndex:1];
        [DataViewControllerBackingStore insertItem:@"Row 0 " atIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        [DataViewControllerBackingStore insertItem:@"Row1" atIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 1) {

        TFNTextCell *Tweakcell = [[%c(TFNTextCell) alloc] init];
        [Tweakcell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        [Tweakcell.textLabel setText:[[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_DETAIL"]];
        return Tweakcell;
    } else if (indexPath.section == 0 && indexPath.row == 0) {

        TFNTextCell *Settingscell = [[%c(TFNTextCell) alloc] init];
        [Settingscell setBackgroundColor:[UIColor clearColor]];
        Settingscell.textLabel.textColor = [UIColor colorWithRed:0.40 green:0.47 blue:0.53 alpha:1.0];
        [Settingscell.textLabel setText:[[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_TITLE"]];
        return Settingscell;
    }


    return %orig;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([indexPath section]== 0 && [indexPath row]== 1) {
        [self.navigationController pushViewController:[BHTManager BHTSettingsWithAccount:self.account] animated:true];
    } else {
        return %orig;
    }
}
%end

// MARK: Change font
%hook UIFontPickerViewController
- (void)viewWillAppear:(BOOL)arg1 {
    %orig(arg1);
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"CUSTOM_FONTS_NAVIGATION_BUTTON_TITLE"] style:UIBarButtonItemStylePlain target:self action:@selector(customFontsHandler)];
}
%new - (void)customFontsHandler {
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/Library/Fonts/AddedFontCache.plist"]) {
        NSAttributedString *AttString = [[NSAttributedString alloc] initWithString:[[BHTBundle sharedBundle] localizedStringForKey:@"CUSTOM_FONTS_MENU_TITLE"] attributes:@{
            NSFontAttributeName: [BHTManager menuTitleFont],
            NSForegroundColorAttributeName: UIColor.labelColor
        }];
        TFNActiveTextItem *title = [[%c(TFNActiveTextItem) alloc] initWithTextModel:[[%c(TFNAttributedTextModel) alloc] initWithAttributedString:AttString] activeRanges:nil];

        NSMutableArray *actions = [[NSMutableArray alloc] init];
        [actions addObject:title];

        NSPropertyListFormat plistFormat;
        NSMutableDictionary *plistDictionary = [NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfURL:[NSURL fileURLWithPath:@"/var/mobile/Library/Fonts/AddedFontCache.plist"]] options:NSPropertyListImmutable format:&plistFormat error:nil];
        [plistDictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            @try {
                NSString *fontName = ((NSMutableArray *)[[plistDictionary valueForKey:key] valueForKey:@"psNames"]).firstObject;
                TFNActionItem *fontAction = [%c(TFNActionItem) actionItemWithTitle:fontName action:^{
                    if (self.configuration.includeFaces) {
                        [self setSelectedFontDescriptor:[UIFontDescriptor fontDescriptorWithFontAttributes:@{
                            UIFontDescriptorNameAttribute: fontName
                        }]];
                    } else {
                        [self setSelectedFontDescriptor:[UIFontDescriptor fontDescriptorWithFontAttributes:@{
                            UIFontDescriptorFamilyAttribute: fontName
                        }]];
                    }
                    [self.delegate fontPickerViewControllerDidPickFont:self];
                }];
                [actions addObject:fontAction];
            } @catch (NSException *exception) {
                NSLog(@"Unable to find installed fonts /n reason: %@", exception.reason);
            }
        }];

        TFNMenuSheetViewController *alert = [[%c(TFNMenuSheetViewController) alloc] initWithActionItems:[NSArray arrayWithArray:actions]];
        [alert tfnPresentedCustomPresentFromViewController:self animated:YES completion:nil];
    } else {
        UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"BHTwitter" message:[[BHTBundle sharedBundle] localizedStringForKey:@"CUSTOM_FONTS_TUT_ALERT_MESSAGE"] preferredStyle:UIAlertControllerStyleAlert];

        [errAlert addAction:[UIAlertAction actionWithTitle:@"iFont application" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://apps.apple.com/sa/app/ifont-find-install-any-font/id1173222289"] options:@{} completionHandler:nil];
        }]];
        [errAlert addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"OK_BUTTON_TITLE"] style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:errAlert animated:true completion:nil];
    }
}
%end

%hook TAEStandardFontGroup
+ (TAEStandardFontGroup *)sharedFontGroup {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray *fontsMethods = [NSMutableArray arrayWithArray:@[]];

        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList([self class], &methodCount);
        for (unsigned int i = 0; i < methodCount; ++i) {
            Method method = methods[i];
            SEL sel = method_getName(method);
            NSString *selStr = NSStringFromSelector(sel);

            NSMethodSignature *methodSig = [self instanceMethodSignatureForSelector:sel];
            if (strcmp(methodSig.methodReturnType, @encode(void)) == 0) {
                // Only add methods that return an object
                continue;
            } else if (methodSig.numberOfArguments == 2) {
                // - (id)bodyFont; ...
                [fontsMethods addObject:selStr];
            } else if (methodSig.numberOfArguments == 3
                       && strcmp([methodSig getArgumentTypeAtIndex:2], @encode(CGFloat)) == 0) {
                // - (id)fontOfSize:(CGFloat); ...
                [fontsMethods addObject:selStr];
            } else if (methodSig.numberOfArguments == 4
                       && strcmp([methodSig getArgumentTypeAtIndex:2], @encode(CGFloat)) == 0
                       && strcmp([methodSig getArgumentTypeAtIndex:3], @encode(CGFloat)) == 0) {
                // - (id)monospacedDigitalFontOfSize:(CGFloat) weight:(CGFloat); ...
                [fontsMethods addObject:selStr];
            } else {
                NSLog(@"[BHTwitter] Method (%@) with unknown signiture (%@) in TAEStandardFontGroup", selStr, methodSig);
            }
        }
        free(methods);

        originalFontsIMP = [NSMutableDictionary new];
        batchSwizzlingOnClass([self class], [fontsMethods copy], (IMP)TAEStandardFontGroupReplacement);
    });
    return %orig;
}
%end

%hook HBForceCepheiPrefs
+ (BOOL)forceCepheiPrefsWhichIReallyNeedToAccessAndIKnowWhatImDoingISwear {
    return YES;
}
%end

// MARK: Show Scroll Bar
%hook TFNTableView
- (void)setShowsVerticalScrollIndicator:(BOOL)arg1 {
    %orig([BHTManager showScrollIndicator]);
}
%end

// start of NFB features

// MARK: Restore Source Labels - This is still pretty experimental and may break. This restores Tweet Source Labels by using an Legacy API. by: @nyaathea

static NSMutableDictionary *tweetSources      = nil;
static NSMutableDictionary *viewToTweetID     = nil;
static NSMutableDictionary *fetchTimeouts     = nil;
static NSMutableDictionary *viewInstances     = nil;
static NSMutableDictionary *fetchRetries      = nil;
static NSMutableDictionary *updateRetries      = nil;
static NSMutableDictionary *updateCompleted   = nil;
static NSMutableDictionary *fetchPending      = nil;
static NSMutableDictionary *cookieCache       = nil;
static NSDate *lastCookieRefresh              = nil;

// Add a dispatch queue for thread-safe access to shared data
static dispatch_queue_t sourceLabelDataQueue = nil;

// Constants for cookie refresh interval (reduced to 1 day in seconds for more frequent refresh)
#define COOKIE_REFRESH_INTERVAL (24 * 60 * 60)
#define COOKIE_FORCE_REFRESH_RETRY_COUNT 1 // Force cookie refresh after this many consecutive failures

// --- Networking & Helper Implementation ---
// Full interface already declared at the top of the file

#define MAX_SOURCE_CACHE_SIZE 200 // Reduced cache size to prevent memory issues
#define MAX_CONSECUTIVE_FAILURES 3 // Maximum consecutive failures before backing off

// Static variables for cookie retry mechanism
static BOOL isInitializingCookies = NO;
static NSTimer *cookieRetryTimer = nil;

@implementation TweetSourceHelper

+ (void)logDebugInfo:(NSString *)message {
    // Only log in debug mode to reduce log spam
#if BHT_DEBUG
    if (message) {
    }
#endif
}

+ (void)initializeCookiesWithRetry {
    // Simplified initialization - just load hardcoded cookies
    isInitializingCookies = YES;

    NSDictionary *hardcodedCookies = [self fetchCookies];
    [self cacheCookies:hardcodedCookies];

    isInitializingCookies = NO;
}

+ (void)retryFetchCookies {
    // No need to retry with hardcoded cookies - just call initialize
    [self initializeCookiesWithRetry];
}

+ (void)pruneSourceCachesIfNeeded {
    // This is a write operation, use a barrier
    dispatch_barrier_async(sourceLabelDataQueue, ^{
        if (!tweetSources) return;

        __block NSUInteger count = 0;
        count = tweetSources.count;

        if (count > MAX_SOURCE_CACHE_SIZE) {
            [self logDebugInfo:[NSString stringWithFormat:@"Pruning cache with %ld entries", (long)count]];

            NSMutableArray *keysToRemove = [NSMutableArray array];

            [tweetSources enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                if (!obj || [obj isEqualToString:@""] || [obj isEqualToString:@"Source Unavailable"]) {
                    [keysToRemove addObject:key];
                    if (keysToRemove.count >= count / 4) *stop = YES;
                }
            }];

            if (keysToRemove.count < count / 5) {
                NSArray *allKeys = [tweetSources allKeys];
                for (int i = 0; i < 20 && keysToRemove.count < count / 4; i++) {
                    NSString *randomKey = allKeys[arc4random_uniform((uint32_t)allKeys.count)];
                    if (![keysToRemove containsObject:randomKey]) {
                        [keysToRemove addObject:randomKey];
                    }
                }
            }

            [self logDebugInfo:[NSString stringWithFormat:@"Removing %ld cache entries", (long)keysToRemove.count]];

            for (NSString *key in keysToRemove) {
                [tweetSources removeObjectForKey:key];

                NSTimer *timeoutTimer = fetchTimeouts[key];
                if (timeoutTimer) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [timeoutTimer invalidate];
                    });
                    [fetchTimeouts removeObjectForKey:key];
                }
                [fetchRetries removeObjectForKey:key];
                [updateRetries removeObjectForKey:key];
                [updateCompleted removeObjectForKey:key];
                [fetchPending removeObjectForKey:key];
            }
        }
    });
}

+ (NSDictionary *)fetchCookies {
    // First try to get real cookies from the user's actual account
    NSMutableDictionary *realCookies = [NSMutableDictionary dictionary];
    NSArray *domains = @[@"api.twitter.com", @".twitter.com", @"x.com", @"api.x.com"];
    NSArray *requiredCookies = @[@"ct0", @"auth_token"];

    for (NSString *domain in domains) {
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@", domain]];
        NSArray *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:url];
        for (NSHTTPCookie *cookie in cookies) {
            if ([requiredCookies containsObject:cookie.name]) {
                realCookies[cookie.name] = cookie.value;
            }
        }
    }

    // Check if we have valid real cookies
    BOOL hasValidRealCookies = realCookies.count > 0 &&
                               realCookies[@"ct0"] && realCookies[@"auth_token"] &&
                               [realCookies[@"ct0"] length] > 10 &&
                               [realCookies[@"auth_token"] length] > 10;

    if (hasValidRealCookies) {
        [self logDebugInfo:@"Using real user cookies"];
        return [realCookies copy];
    } else {
        // Fall back to hardcoded cookies for reliability
        [self logDebugInfo:@"Falling back to hardcoded alt cookies"];
        return @{
            @"ct0": @"91cc6876b96a35f91adeedc4ef149947c4d58907ca10fc2b17f64b17db0cccfb714ae61ede34cf34866166dcaf8e1c3a86085fa35c41aacc3e3927f7aa1f9b850b49139ad7633344059ff04af302d5d3",
            @"auth_token": @"71fc90d6010d76ec4473b3e42c6802a8f1185316",
            @"twid": @"u%3D1930115366878871552"
        };
    }
}

+ (void)cacheCookies:(NSDictionary *)cookies {
    // Simplified caching - just store in memory since we're using hardcoded values
    cookieCache = [cookies mutableCopy];
    lastCookieRefresh = [NSDate date];
}

+ (NSDictionary *)loadCachedCookies {
    // Always return hardcoded cookies
    NSDictionary *hardcodedCookies = [self fetchCookies];
    cookieCache = [hardcodedCookies mutableCopy];
    lastCookieRefresh = [NSDate date];
    return hardcodedCookies;
}

+ (BOOL)shouldRefreshCookies {
    // Allow refresh if we don't have cookies cached, or if we're using real cookies that might expire
    if (!cookieCache || cookieCache.count == 0) {
        return YES;
    }

    // Check if we're using real cookies (not hardcoded)
    BOOL usingRealCookies = ![cookieCache[@"ct0"] isEqualToString:@"91cc6876b96a35f91adeedc4ef149947c4d58907ca10fc2b17f64b17db0cccfb714ae61ede34cf34866166dcaf8e1c3a86085fa35c41aacc3e3927f7aa1f9b850b49139ad7633344059ff04af302d5d3"];

    if (usingRealCookies && lastCookieRefresh) {
        // Refresh real cookies every 4 hours
        NSTimeInterval timeSinceRefresh = [[NSDate date] timeIntervalSinceDate:lastCookieRefresh];
        return timeSinceRefresh >= (4 * 60 * 60);
    }

    // Never refresh hardcoded cookies
    return NO;
}

+ (void)fetchSourceForTweetID:(NSString *)tweetID {
    if (!tweetID) return;

    // Defer the entire operation to our concurrent queue to handle state checks and request creation safely
    dispatch_async(sourceLabelDataQueue, ^{
        @try {
            // Initialize dictionaries if needed
            if (!tweetSources) tweetSources = [NSMutableDictionary dictionary];
            if (!fetchTimeouts) fetchTimeouts = [NSMutableDictionary dictionary];
            if (!fetchRetries) fetchRetries = [NSMutableDictionary dictionary];
            if (!fetchPending) fetchPending = [NSMutableDictionary dictionary];

            // Simple cache size management
            if (tweetSources.count > MAX_SOURCE_CACHE_SIZE) {
                // Pruning is now async, so we just call it
                [self pruneSourceCachesIfNeeded];
            }

        // Skip if already pending or has valid result
        if ([fetchPending[tweetID] boolValue] ||
            (tweetSources[tweetID] && ![tweetSources[tweetID] isEqualToString:@""] && ![tweetSources[tweetID] isEqualToString:@"Source Unavailable"])) {
            return;
        }

        // Check retry limit
        NSInteger retryCount = [fetchRetries[tweetID] integerValue];
        if (retryCount >= MAX_CONSECUTIVE_FAILURES) {
            tweetSources[tweetID] = @"Source Unavailable";
            return;
        }

        fetchPending[tweetID] = @(YES);
        fetchRetries[tweetID] = @(retryCount + 1);

                // Set simple timeout on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            NSTimer *timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:8.0
                                                                    target:self
                                                                  selector:@selector(timeoutFetchForTweetID:)
                                                                  userInfo:@{@"tweetID": tweetID}
                                                                   repeats:NO];
            dispatch_barrier_async(sourceLabelDataQueue, ^{
                fetchTimeouts[tweetID] = timeoutTimer;
            });
        });

        // Build request
        NSString *urlString = [NSString stringWithFormat:@"https://api.twitter.com/2/timeline/conversation/%@.json?include_ext_alt_text=true&include_reply_count=true&tweet_mode=extended", tweetID];
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) {
            [self handleFetchFailure:tweetID];
            return;
        }

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"GET";
        request.timeoutInterval = 7.0;

        // Get cookies
        if (!cookieCache) {
            [self loadCachedCookies];
        }
        NSDictionary *cookiesToUse = cookieCache;

        // Check if using real cookies
        BOOL usingRealCookies = cookiesToUse &&
                               ![cookiesToUse[@"ct0"] isEqualToString:@"91cc6876b96a35f91adeedc4ef149947c4d58907ca10fc2b17f64b17db0cccfb714ae61ede34cf34866166dcaf8e1c3a86085fa35c41aacc3e3927f7aa1f9b850b49139ad7633344059ff04af302d5d3"];

        // Build headers
        NSMutableArray *cookieStrings = [NSMutableArray array];
        for (NSString *cookieName in cookiesToUse) {
            [cookieStrings addObject:[NSString stringWithFormat:@"%@=%@", cookieName, cookiesToUse[cookieName]]];
        }

        [request setValue:@"Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA" forHTTPHeaderField:@"Authorization"];
        [request setValue:@"OAuth2Session" forHTTPHeaderField:@"x-twitter-auth-type"];
        [request setValue:@"CFNetwork/1331.0.7 Darwin/25.2.0" forHTTPHeaderField:@"User-Agent"];
        [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
        [request setValue:cookiesToUse[@"ct0"] forHTTPHeaderField:@"x-csrf-token"];
        [request setValue:[cookieStrings componentsJoinedByString:@"; "] forHTTPHeaderField:@"Cookie"];

        // Execute request
        NSURLSession *session = [NSURLSession sharedSession];
        NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            // The completion handler runs on a background thread
            // We must use our queue to modify shared state
            dispatch_barrier_async(sourceLabelDataQueue, ^{
                @try {
                    // Cleanup timeout
                    NSTimer *timer = fetchTimeouts[tweetID];
                    if (timer) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [timer invalidate];
                        });
                        [fetchTimeouts removeObjectForKey:tweetID];
                    }
                    fetchPending[tweetID] = @(NO);

                // Handle errors
                if (error || !data) {
                    [self handleFetchFailure:tweetID];
                    return;
                }

                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

                // Handle auth errors with fallback
                if ((httpResponse.statusCode == 401 || httpResponse.statusCode == 403) && usingRealCookies && retryCount == 1) {
                    // Try hardcoded cookies once
                    NSDictionary *hardcodedCookies = @{
                        @"ct0": @"91cc6876b96a35f91adeedc4ef149947c4d58907ca10fc2b17f64b17db0cccfb714ae61ede34cf34866166dcaf8e1c3a86085fa35c41aacc3e3927f7aa1f9b850b49139ad7633344059ff04af302d5d3",
                        @"auth_token": @"71fc90d6010d76ec4473b3e42c6802a8f1185316",
                        @"twid": @"u%3D1930115366878871552"
                    };
                                            [self cacheCookies:hardcodedCookies];
                        [self fetchSourceForTweetID:tweetID]; // Re-call, which will be queued
                        return;
                }

                if (httpResponse.statusCode != 200) {
                    [self handleFetchFailure:tweetID];
                    return;
                }

                // Parse JSON
                NSError *jsonError;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                if (jsonError || !json) {
                    [self handleFetchFailure:tweetID];
                    return;
                }

                // Extract source
                NSDictionary *tweets = json[@"globalObjects"][@"tweets"];
                NSDictionary *tweetData = tweets[tweetID];

                // Try alternate ID format if not found
                if (!tweetData) {
                    for (NSString *key in tweets) {
                        if ([key longLongValue] == [tweetID longLongValue]) {
                            tweetData = tweets[key];
                            break;
                        }
                    }
                }

                NSString *sourceHTML = tweetData[@"source"];
                NSString *sourceText = @"Unknown Source";

                if (sourceHTML) {
                    NSRange startRange = [sourceHTML rangeOfString:@">"];
                    NSRange endRange = [sourceHTML rangeOfString:@"</a>"];
                    if (startRange.location != NSNotFound && endRange.location != NSNotFound && startRange.location + 1 < endRange.location) {
                        sourceText = [sourceHTML substringWithRange:NSMakeRange(startRange.location + 1, endRange.location - startRange.location - 1)];
                        sourceText = [sourceText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    }
                    }

                // Store and notify
                    tweetSources[tweetID] = sourceText;
                fetchRetries[tweetID] = @(0); // Reset on success

                dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"TweetSourceUpdated" object:nil userInfo:@{@"tweetID": tweetID}];
                    [self updateFooterTextViewsForTweetID:tweetID];
                });

                            } @catch (NSException *e) {
                    [self handleFetchFailure:tweetID];
                }
            });
        }];
        [task resume];

        } @catch (NSException *e) {
            [self handleFetchFailure:tweetID];
        }
    });
}

+ (void)handleFetchFailure:(NSString *)tweetID {
    if (!tweetID) return;

    // This is a write operation, but it's called from other synchronized blocks
    // So we don't need to wrap it again, but the caller must be synchronized
    fetchPending[tweetID] = @(NO);
    NSTimer *timer = fetchTimeouts[tweetID];
    if (timer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [timer invalidate];
        });
        [fetchTimeouts removeObjectForKey:tweetID];
    }

    NSInteger retryCount = [fetchRetries[tweetID] integerValue];
    if (retryCount < MAX_CONSECUTIVE_FAILURES) {
        // Simple retry after delay
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), sourceLabelDataQueue, ^{
            [self fetchSourceForTweetID:tweetID];
        });
    } else {
        // Mark as unavailable
        tweetSources[tweetID] = @"Source Unavailable";
        dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"TweetSourceUpdated" object:nil userInfo:@{@"tweetID": tweetID}];
        });
    }
}

+ (void)timeoutFetchForTweetID:(NSTimer *)timer {
    NSString *tweetID = timer.userInfo[@"tweetID"];
    if (!tweetID) return;

    dispatch_barrier_async(sourceLabelDataQueue, ^{
        // Safely invalidate timer on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([timer isValid]) {
                [timer invalidate];
            }
        });
        [fetchTimeouts removeObjectForKey:tweetID];
        [self handleFetchFailure:tweetID];
    });
}

+ (void)retryUpdateForTweetID:(NSString *)tweetID {
    // Removed complex retry mechanism
}

+ (void)pollForPendingUpdates {
    // Removed complex polling mechanism
}

+ (void)handleAppForeground:(NSNotification *)notification {
    // Removed complex app foreground handling
}

+ (void)handleClearCacheNotification:(NSNotification *)notification {
    // Simplified cache clearing - just clear the source cache
    if (tweetSources) [tweetSources removeAllObjects];
}

+ (void)cleanupTimersForBackground {
    // Clean up timers to prevent crashes when app resumes
    if (fetchTimeouts) {
        dispatch_barrier_async(sourceLabelDataQueue, ^{
            for (NSTimer *timer in [fetchTimeouts allValues]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([timer isValid]) {
                        [timer invalidate];
                    }
                });
            }
            [fetchTimeouts removeAllObjects];
        });
    }
}

+ (void)updateFooterTextViewsForTweetID:(NSString *)tweetID {
    // Removed notification-based updates
}

@end

%hook TFNTwitterStatus

- (id)init {
    id originalSelf = %orig;
    @try {
        NSInteger statusID = self.statusID;
        if (statusID > 0) {
            NSString *tweetIDStr = @(statusID).stringValue;
            // Write operation
            dispatch_barrier_async(sourceLabelDataQueue, ^{
                if (!tweetSources) tweetSources = [NSMutableDictionary dictionary];
                if (!tweetSources[tweetIDStr]) {
                    [TweetSourceHelper pruneSourceCachesIfNeeded]; // This is async now
                    tweetSources[tweetIDStr] = @"";
                    [TweetSourceHelper fetchSourceForTweetID:tweetIDStr];
                }
            });
        }
    } @catch (__unused NSException *e) {}
    return originalSelf;
}

%end

// Declare the category interface first
@interface TweetSourceHelper (Notifications)
+ (void)handleCookiesReadyNotification:(NSNotification *)notification;
@end

// Simplified implementation without notifications
@implementation TweetSourceHelper (Notifications)
+ (void)handleCookiesReadyNotification:(NSNotification *)notification {
    // Removed complex notification handling - now handled directly in fetchSourceForTweetID
}
@end

%hook T1ConversationFocalStatusView

- (void)setViewModel:(id)viewModel {
    %orig;
    @try {
        if (viewModel) {
            id status = nil;
            @try { status = [viewModel valueForKey:@"tweet"]; } @catch (__unused NSException *e) {}
            if (status) {
                NSInteger statusID = 0;
                @try {
                    statusID = [[status valueForKey:@"statusID"] integerValue];
                    if (statusID > 0) {
                        if (!tweetSources)   tweetSources   = [NSMutableDictionary dictionary];
                        if (!viewToTweetID)  viewToTweetID  = [NSMutableDictionary dictionary];
                        if (!viewInstances)  viewInstances  = [NSMutableDictionary dictionary];

                        NSString *tweetIDStr = @(statusID).stringValue;

                        if (!tweetSources[tweetIDStr]) {
                            tweetSources[tweetIDStr] = @"";
                            [TweetSourceHelper fetchSourceForTweetID:tweetIDStr];
                        }
                    }
                } @catch (__unused NSException *e) {}

                if (statusID <= 0) {
                    @try {
                        NSString *altID = [status valueForKey:@"rest_id"] ?: [status valueForKey:@"id_str"] ?: [status valueForKey:@"id"];
                        if (altID) {
                            if (!tweetSources)   tweetSources   = [NSMutableDictionary dictionary];
                            if (!viewToTweetID)  viewToTweetID  = [NSMutableDictionary dictionary];
                            if (!viewInstances)  viewInstances  = [NSMutableDictionary dictionary];

                            if (!tweetSources[altID]) {
                                [TweetSourceHelper pruneSourceCachesIfNeeded]; // ADDING THIS CALL HERE
                                tweetSources[altID] = @"";
                                [TweetSourceHelper fetchSourceForTweetID:altID];
                            }
                        }
                    } @catch (__unused NSException *e) {}
                }
            }
        }
    } @catch (__unused NSException *e) {}
}

- (void)dealloc {
    // Removed complex view tracking cleanup
    %orig;
}

- (void)handleTweetSourceUpdated:(NSNotification *)notification {
    @try {
        NSDictionary *userInfo = notification.userInfo;
        NSString *tweetID      = userInfo[@"tweetID"];
        if (tweetID && tweetSources[tweetID] && ![tweetSources[tweetID] isEqualToString:@""]) {
            NSValue *viewValue = viewInstances[tweetID];
            UIView  *targetView    = viewValue ? [viewValue nonretainedObjectValue] : nil; // Renamed to targetView for clarity
            if (targetView && targetView == self) { // Ensure we are updating the correct instance
                NSString *currentTweetID = viewToTweetID[@((uintptr_t)targetView)];
                if (currentTweetID && [currentTweetID isEqualToString:tweetID]) {
                    BH_EnumerateSubviewsRecursively(targetView, ^(UIView *subview) { // Use the static helper
                        if ([subview isKindOfClass:%c(TFNAttributedTextView)]) {
                            TFNAttributedTextView *textView = (TFNAttributedTextView *)subview;
                            TFNAttributedTextModel *model = [textView valueForKey:@"_textModel"];
                            if (model && model.attributedString.string) {
                                NSString *text = model.attributedString.string;
                                // Check for typical timestamp patterns or if the source might need to be appended/updated
                                if ([text containsString:@"PM"] || [text containsString:@"AM"] ||
                                    [text rangeOfString:@"\\\\d{1,2}[:.]\\\\d{1,2}" options:NSRegularExpressionSearch].location != NSNotFound) {

                                    // Check if this specific TFNAttributedTextView is NOT part of a quoted status view
                                    BOOL isSafeToUpdate = YES;
                                    UIView *parentCheck = textView;
                                    while(parentCheck && parentCheck != targetView) { // Traverse up to the main focal view
                                        if ([NSStringFromClass([parentCheck class]) isEqualToString:@"T1QuotedStatusView"]) {
                                            isSafeToUpdate = NO;
                                            break;
                                        }
                                        parentCheck = parentCheck.superview;
                                    }

                                    if (isSafeToUpdate) {
                                        // Force a refresh of the text model.
                                        // This will trigger setTextModel: again, where the source appending logic resides.
                                    [textView setTextModel:nil];
                                    [textView setTextModel:model];
                                }
                            }
                        }
                        }
                    });
                }
            }
        }
    } @catch (NSException *e) {
         NSLog(@"TweetSourceTweak: Exception in handleTweetSourceUpdated for T1ConversationFocalStatusView: %@", e);
    }
}

// %new - (void)enumerateSubviewsRecursively:(void (^)(UIView *))block {
// This method is now replaced by the static C function BH_EnumerateSubviewsRecursively
// }

// Method now implemented in the TweetSourceHelper (Notifications) category

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Observe for our own update notifications
        [[NSNotificationCenter defaultCenter] addObserver:self // Target is the class itself for class methods
                                                 selector:@selector(handleTweetSourceUpdatedNotificationDispatch:) // A new dispatcher
                                                     name:@"TweetSourceUpdated"
                                                   object:nil];
        // Removed all notification observers - they were causing crashes
    });
}

// New class method to dispatch instance method calls
%new + (void)handleTweetSourceUpdatedNotificationDispatch:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *tweetID = userInfo[@"tweetID"];
    if (tweetID) {
        NSValue *viewValue = viewInstances[tweetID]; // viewInstances is a global static
        T1ConversationFocalStatusView *targetInstance = viewValue ? [viewValue nonretainedObjectValue] : nil;
        if (targetInstance && [targetInstance isKindOfClass:[self class]]) { // Check if it's an instance of T1ConversationFocalStatusView
            // Use performSelector for %new instance method from %new class method
            if ([targetInstance respondsToSelector:@selector(handleTweetSourceUpdated:)]) {
                [targetInstance performSelector:@selector(handleTweetSourceUpdated:) withObject:notification];
            } else {
                NSLog(@"TweetSourceTweak: ERROR - T1ConversationFocalStatusView instance does not respond to handleTweetSourceUpdated:");
            }
        }
    }
}


%end

// MARK: - Source Labels via T1ConversationFocalStatusView (Clean Approach)

@interface T1ConversationFocalStatusView (BHTSourceLabels)
- (void)BHT_updateFooterTextWithSource:(NSString *)sourceText tweetID:(NSString *)tweetID;
- (void)BHT_applyColoredTextToFooterTextView:(id)footerTextView timeAgoText:(NSString *)timeAgoText sourceText:(NSString *)sourceText;
- (id)footerTextView;
@end

%hook T1ConversationFocalStatusView

- (void)setViewModel:(id)viewModel options:(unsigned long long)options account:(id)account {
    %orig(viewModel, options, account);

    if (![BHTManager RestoreTweetLabels] || !viewModel) {
        return;
    }

    // Get the TFNTwitterStatus - it might be the viewModel itself or a property
    TFNTwitterStatus *status = nil;

    if ([viewModel isKindOfClass:%c(TFNTwitterStatus)]) {
        status = (TFNTwitterStatus *)viewModel;
    } else if ([viewModel respondsToSelector:@selector(status)]) {
        status = [viewModel performSelector:@selector(status)];
    }

    if (!status) {
        return;
    }

    // Get the tweet ID
    long long statusID = [status statusID];
    if (statusID <= 0) {
        return;
    }

    NSString *tweetIDStr = [NSString stringWithFormat:@"%lld", statusID];
    if (!tweetIDStr || tweetIDStr.length == 0) {
        return;
    }

    // Initialize tweet sources if needed
    if (!tweetSources) {
        tweetSources = [NSMutableDictionary dictionary];
    }

    // Fetch source if not cached
    if (!tweetSources[tweetIDStr]) {
        tweetSources[tweetIDStr] = @""; // Placeholder
        [TweetSourceHelper fetchSourceForTweetID:tweetIDStr];
    }

    // Update footer text immediately if we have the source
    NSString *sourceText = tweetSources[tweetIDStr];
    if (sourceText && sourceText.length > 0 && ![sourceText isEqualToString:@"Source Unavailable"] && ![sourceText isEqualToString:@""]) {
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf BHT_updateFooterTextWithSource:sourceText tweetID:tweetIDStr];
            }
        });
    }
}

%new
- (void)BHT_handleSourceLabelTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateEnded) {
        return;
    }

    NSURL *url = [NSURL URLWithString:@"https://help.twitter.com/using-twitter/how-to-tweet#source-labels"];
    if (!url) {
        return;
    }

    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [app openURL:url
             options:@{}
   completionHandler:nil];
    } else {
        [app openURL:url];
    }
}

%new
- (void)BHT_updateFooterTextWithSource:(NSString *)sourceText tweetID:(NSString *)tweetID {
    // Look for T1ConversationFooterItem in the view hierarchy
    __block id footerItem = nil;
    BH_EnumerateSubviewsRecursively(self, ^(UIView *view) {
        if (footerItem) return;

        // Check if this view has a footerItem property
        if ([view respondsToSelector:@selector(footerItem)]) {
            id item = [view performSelector:@selector(footerItem)];
            if (item && [item isKindOfClass:%c(T1ConversationFooterItem)]) {
                footerItem = item;
            }
        }
    });

    if (!footerItem || ![footerItem respondsToSelector:@selector(timeAgo)]) {
        return;
    }

    NSString *currentTimeAgo = [footerItem performSelector:@selector(timeAgo)];
    if (!currentTimeAgo || currentTimeAgo.length == 0) {
                return;
            }

    // Don't append if source is already there
    if ([currentTimeAgo containsString:sourceText] || [currentTimeAgo containsString:@"Twitter for"] || [currentTimeAgo containsString:@"via "]) {
        return;
    }

    // Create new timeAgo with source appended
    NSString *newTimeAgo = [NSString stringWithFormat:@"%@ · %@", currentTimeAgo, sourceText];

// Set the new timeAgo and hide view count
if ([footerItem respondsToSelector:@selector(setTimeAgo:)]) {
    [footerItem performSelector:@selector(setTimeAgo:) withObject:newTimeAgo];

    // Now update the footer text view to refresh the display
    id footerTextView = [self footerTextView];
    if (footerTextView && [footerTextView respondsToSelector:@selector(updateFooterTextView)]) {
        [footerTextView performSelector:@selector(updateFooterTextView)];
    }

    // Make the footer tappable to open the source label help page
    if ([footerTextView isKindOfClass:[UIView class]]) {
        UIView *footerView = (UIView *)footerTextView;
        footerView.userInteractionEnabled = YES;

NSNumber *alreadyAdded = objc_getAssociatedObject(footerView, &kBHTSourceTapAddedKey);
        if (![alreadyAdded boolValue]) {
            UITapGestureRecognizer *tap =
                [[UITapGestureRecognizer alloc] initWithTarget:self
                                                        action:@selector(BHT_handleSourceLabelTap:)];
            [footerView addGestureRecognizer:tap];
objc_setAssociatedObject(footerView,
                         &kBHTSourceTapAddedKey,
                         @(YES),
                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}
}



%end

// MARK: Restore Twitter terminology, controlled by "restore_twitter_names"
// Two layers, both driven by locale files in the tweak bundle:
//   1. RenameOverrides.strings — Twitter localization key -> exact replacement,
//      a missing key falls through to the generic replacement
//   2. RenameWords.strings — generic word replacements ("X" -> "Twitter",
//      "Post" -> "Tweet", etc.) applied to localized and server-side strings
// Both are strictly per-language: a language without its own copy of a file gets no
// renaming from that layer, rather than English rules applied to non-English text.

static NSDictionary<NSString *, NSString *> *BHTRenameTable(NSString *name) {
    NSBundle *bundle = [BHTBundle sharedBundle].mainBundle;
    NSString *appLanguage = [[NSBundle mainBundle] preferredLocalizations].firstObject ?: @"en";
    NSString *localization = [NSBundle preferredLocalizationsFromArray:bundle.localizations
                                                        forPreferences:@[appLanguage]].firstObject;

    // preferredLocalizationsFromArray: if there's no match, it silently
    // returns the development region (en) instead, and rejects that so unsupported
    // languages skip renaming rather than getting English rules
    NSString *appCode = [appLanguage componentsSeparatedByString:@"-"].firstObject;
    NSString *lprojCode = [[localization stringByReplacingOccurrencesOfString:@"_" withString:@"-"]
                              componentsSeparatedByString:@"-"].firstObject;
    if (![appCode isEqualToString:lprojCode]) {
        return @{};
    }

    NSString *path = [bundle pathForResource:name ofType:@"strings" inDirectory:nil forLocalization:localization];
    NSString *contents = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    NSDictionary *table = [contents propertyListFromStringsFileFormat];
    return [table isKindOfClass:[NSDictionary class]] ? table : @{};
}

static NSDictionary<NSString *, NSString *> *BHTRenameKeyOverrides(void) {
    static NSDictionary *overrides = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ overrides = BHTRenameTable(@"RenameOverrides"); });
    return overrides;
}

static NSDictionary<NSString *, NSString *> *BHTwitterWordMap(void) {
    static NSDictionary *map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ map = BHTRenameTable(@"RenameWords"); });
    return map;
}

// Builds \b(word|word…)\b from the map keys of one sensitivity class, longest word
// first so inflections win over their stems ("reposts" before "repost").
static NSRegularExpression *BHTRenameRegex(BOOL caseSensitive) {
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (NSString *word in BHTwitterWordMap()) {
        BOOL hasUpper = [word rangeOfCharacterFromSet:[NSCharacterSet uppercaseLetterCharacterSet]].location != NSNotFound;
        if (hasUpper == caseSensitive) {
            [words addObject:[NSRegularExpression escapedPatternForString:word]];
        }
    }
    if (words.count == 0) {
        return nil;
    }

    [words sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        if (a.length > b.length) return NSOrderedAscending;
        if (a.length < b.length) return NSOrderedDescending;
        return [a compare:b];
    }];
    NSString *pattern = [NSString stringWithFormat:@"\\b(%@)\\b", [words componentsJoinedByString:@"|"]];
    return [NSRegularExpression regularExpressionWithPattern:pattern
                                                     options:(caseSensitive ? 0 : NSRegularExpressionCaseInsensitive)
                                                       error:nil];
}

// Applies the capitalisation style of `token` (all-caps or leading-capital) to `base`.
static NSString *BHMatchCapitalisation(NSString *token, NSString *base) {
    if (token.length == 0 || base.length == 0) {
        return base;
    }

    NSString *lower = token.lowercaseString;
    if (token.length > 1 && [token isEqualToString:token.uppercaseString] && ![token isEqualToString:lower]) {
        return base.uppercaseString;
    }

    unichar first = [token characterAtIndex:0];
    if ([[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:first]) {
        return [base stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                             withString:[base substringToIndex:1].uppercaseString];
    }
    return base;
}

// Returns the ordered list of edits (@"range" -> NSValue, @"repl" -> NSString) to apply
// to `input`, sorted last-match-first so applying them never invalidates a later range.
// Returns nil when there is nothing to change.
static NSArray<NSDictionary *> *BHRenameEdits(NSString *input) {
    if (input.length == 0) {
        return nil;
    }

    static NSRegularExpression *insensitiveRegex = nil;
    static NSRegularExpression *sensitiveRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        insensitiveRegex = BHTRenameRegex(NO);
        sensitiveRegex = BHTRenameRegex(YES);
    });

    NSDictionary *wordMap = BHTwitterWordMap();
    NSRange full = NSMakeRange(0, input.length);
    NSMutableArray<NSDictionary *> *edits = [NSMutableArray array];

    for (NSTextCheckingResult *match in [sensitiveRegex matchesInString:input options:0 range:full]) {
        NSString *repl = wordMap[[input substringWithRange:match.range]];
        if (repl) {
            [edits addObject:@{@"range": [NSValue valueWithRange:match.range], @"repl": repl}];
        }
    }

    for (NSTextCheckingResult *match in [insensitiveRegex matchesInString:input options:0 range:full]) {
        NSString *token = [input substringWithRange:match.range];
        NSString *base = wordMap[token.lowercaseString];
        if (base) {
            [edits addObject:@{@"range": [NSValue valueWithRange:match.range],
                               @"repl": BHMatchCapitalisation(token, base)}];
        }
    }

    if (edits.count == 0) {
        return nil;
    }

    [edits sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSUInteger la = [a[@"range"] rangeValue].location;
        NSUInteger lb = [b[@"range"] rangeValue].location;
        if (la > lb) return NSOrderedAscending;
        if (la < lb) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return edits;
}

static NSString *BHRestoreTwitterTerminology(NSString *input) {
    // Memoise: labels re-set the same handful of strings over and over.
    static NSCache<NSString *, NSString *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [NSCache new]; });

    NSString *cached = [cache objectForKey:input];
    if (cached) {
        return cached;
    }

    NSArray<NSDictionary *> *edits = BHRenameEdits(input);
    NSString *output = input;
    if (edits) {
        NSMutableString *result = [input mutableCopy];
        for (NSDictionary *edit in edits) {
            [result replaceCharactersInRange:[edit[@"range"] rangeValue] withString:edit[@"repl"]];
        }
        output = [result copy];
    }

    [cache setObject:output forKey:input];
    return output;
}

static NSAttributedString *BHRestoreTwitterAttributed(NSAttributedString *input) {
    NSArray<NSDictionary *> *edits = BHRenameEdits(input.string);
    if (!edits) {
        return input;
    }

    NSMutableAttributedString *result = [input mutableCopy];
    for (NSDictionary *edit in edits) {
        NSRange range = [edit[@"range"] rangeValue];
        NSDictionary *attrs = [result attributesAtIndex:range.location effectiveRange:NULL];
        NSAttributedString *piece = [[NSAttributedString alloc] initWithString:edit[@"repl"] attributes:attrs];
        [result replaceCharactersInRange:range withAttributedString:piece];
    }
    return result;
}

%hook NSBundle
- (NSString *)localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)tableName {
    NSString *result = %orig;
    if (![BHTManager restoreTwitterNames] || self == [BHTBundle sharedBundle].mainBundle) {
        return result;
    }

    NSString *override = key ? BHTRenameKeyOverrides()[key] : nil;
    if (override) {
        return override;
    }
    return result.length > 0 ? BHRestoreTwitterTerminology(result) : result;
}
%end

%hook TFNAttributedTextView
- (void)setTextModel:(TFNAttributedTextModel *)model {
    if (!model || !model.attributedString) {
        %orig(model);
        return;
    }

    NSString *currentText = model.attributedString.string;
    NSMutableAttributedString *newString = nil;
    BOOL modified = NO;
    BOOL textChanged = NO;

    // --- Tweet source label coloring ---
    if ([BHTManager RestoreTweetLabels] && tweetSources.count > 0) {
        NSString *unavailable = [[BHTBundle sharedBundle] localizedStringForKey:@"SOURCE_UNAVAILABLE"];
        for (NSString *sourceText in tweetSources.allValues) {
            if (sourceText.length > 0 &&
                ![sourceText isEqualToString:unavailable] &&
                [currentText containsString:sourceText]) {

                NSRange sourceRange = [currentText rangeOfString:sourceText];
                if (sourceRange.location != NSNotFound) {
                    UIColor *existingColor = [model.attributedString attribute:NSForegroundColorAttributeName
                                                                       atIndex:sourceRange.location
                                                                effectiveRange:NULL];
                    UIColor *accentColor = BHTCurrentAccentColor();

                    if (!existingColor || ![existingColor isEqual:accentColor]) {
                        if (!newString) {
                            newString = [[NSMutableAttributedString alloc] initWithAttributedString:model.attributedString];
                        }
                        // Add only the color attribute, do not overwrite the run
                        [newString addAttribute:NSForegroundColorAttributeName
                                          value:accentColor
                                          range:sourceRange];
                        modified = YES;
                        // attributes only, textChanged stays NO
                    }
                }
                break; // Only color the first matching source
            }
        }
    }

    // --- Restore Twitter terminology ---
    // TFNAttributedTextView renders interface chrome (notification headers, footers,
    // timestamps, counts…). Tweet bodies use T1StatusBodyTextView /
    // TTAStatusBodySelectableContentTextView, so they never reach this hook and are
    // left untouched. The rewrite is driven by the shared word-boundary transform, so
    // it changes the actual rendered text rather than a hardcoded list of phrases.
    if ([BHTManager restoreTwitterNames]) {
        NSAttributedString *source = newString ?: model.attributedString;
        NSAttributedString *renamed = BHRestoreTwitterAttributed(source);
        if (renamed != source) {
            newString = [renamed mutableCopy];
            modified = YES;
            textChanged = YES;
        }
    }

    // --- Apply modifications if needed ---
    if (modified && newString) {
        if (textChanged) {
            // Text changed, use a new model so length-related state is rebuilt
            TFNAttributedTextModel *newModel =
                [[%c(TFNAttributedTextModel) alloc] initWithAttributedString:newString];
            %orig(newModel);
        } else if ([model respondsToSelector:@selector(setAttributedString:)]) {
            // Attributes only, keep model to preserve layout metadata
            [model setAttributedString:newString];
            %orig(model);
        } else {
            TFNAttributedTextModel *newModel =
                [[%c(TFNAttributedTextModel) alloc] initWithAttributedString:newString];
            %orig(newModel);
        }
    } else {
        %orig(model);
    }
}
%end

// Helper for the Twitter icon theming setting
static BOOL BHColorTwitterIconEnabled(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    if ([defaults objectForKey:@"color_twitter_icon_in_top_bar"] == nil) {
        return [BHTManager isTwitterBranded];
    }

    return [defaults boolForKey:@"color_twitter_icon_in_top_bar"];
}

// MARK: Bird Icon Theming, controlled by "color_twitter_icon_in_top_bar"

%hook UIImageView

- (void)setImage:(UIImage *)image {
    // If the setting is off, keep the original behavior
    if (!BHColorTwitterIconEnabled()) {
        %orig(image);
        return;
    }

    %orig(image);

    if (!image) return;

    // Check if this is the Twitter bird icon by examining the image's dynamic color name
    if ([image respondsToSelector:@selector(tfn_dynamicColorImageName)]) {
        NSString *imageName = [image performSelector:@selector(tfn_dynamicColorImageName)];
        if ([imageName isEqualToString:@"twitter"]) {
            if (image.renderingMode != UIImageRenderingModeAlwaysTemplate) {
                UIImage *templateImage = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                self.image = templateImage;
                self.tintColor = BHTCurrentAccentColor();
            }
        }
    }
}

%end

// MARK: - Hide Grok Analyze Button
// The analyze button (timeline author view and post detail nav bar) is gated by a per-tweet
// boolean the API returns via the includeGrokAnalysisButton request field. Both
// shouldShowGrokAnalyzeButtonForAuthorView and shouldShowGrokAnalyzeButtonForPostDetailNavBar
// ultimately return this flag, so reporting it as absent at the model level suppresses the
// button on every surface without any view-level hiding or navigation-context guessing.
%hook TFNTwitterCanonicalStatus
- (BOOL)grokAnalysisButton {
    if ([BHTManager hideGrokAnalyze]) return NO;
    return %orig;
}
%end

%hook TFSTwitterStatus
- (BOOL)grokAnalysisButton {
    if ([BHTManager hideGrokAnalyze]) return NO;
    return %orig;
}
%end

// MARK: - Hide Subscribe Button on Detail View

// Minimal interface for TFNButton, used by UIControl hook and FollowButton logic
@class TFNButton;

%hook UIControl
// Subscribe button
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)controlEvents {
    if (action == @selector(_didTapSubscribe)) {
        if ([self isKindOfClass:NSClassFromString(@"TFNButton")] && [BHTManager restoreFollowButton]) {
            self.alpha = 0.0;
            self.userInteractionEnabled = NO;
        }
    }
    %orig(target, action, controlEvents);
}

%end

// MARK: - Hide Follow Button (T1ConversationFocalStatusView)

// Minimal interface for T1ConversationFocalStatusView
@class T1ConversationFocalStatusView;

// Helper function to recursively find and hide a TFNButton by accessibilityIdentifier
static BOOL findAndHideButtonWithAccessibilityId(UIView *viewToSearch, NSString *targetAccessibilityId) {
    @try {
        // Safety check: Ensure view and target are valid
        if (!viewToSearch || !targetAccessibilityId || !viewToSearch.superview) {
            return NO;
        }

        if ([viewToSearch isKindOfClass:NSClassFromString(@"TFNButton")]) {
            TFNButton *button = (TFNButton *)viewToSearch;
            if ([button.accessibilityIdentifier isEqualToString:targetAccessibilityId]) {
                button.hidden = YES;
                return YES;
            }
        }

        // Create a copy of subviews to avoid mutation during iteration
        NSArray *subviews = [viewToSearch.subviews copy];
        for (UIView *subview in subviews) {
            if (findAndHideButtonWithAccessibilityId(subview, targetAccessibilityId)) {
                return YES;
            }
        }
        return NO;
    } @catch (NSException *exception) {
        NSLog(@"[BHTwitter] Exception in findAndHideButtonWithAccessibilityId: %@", exception);
        return NO;
    }
}

%hook T1ConversationFocalStatusView

- (void)didMoveToWindow {
    %orig;
    if ([BHTManager hideFollowButton]) {
        findAndHideButtonWithAccessibilityId(self, @"FollowButton");
    }
}

%end

// MARK: - Hide Follow Button (T1ImmersiveViewController)

// Minimal interface for T1ImmersiveViewController
@interface T1ImmersiveViewController : UIViewController
@end

%hook T1ImmersiveViewController

- (void)viewDidLoad {
    %orig;
    @try {
        if ([BHTManager hideFollowButton] && self.view) {
            findAndHideButtonWithAccessibilityId(self.view, @"FollowButton");
        }
    } @catch (NSException *exception) {
        NSLog(@"[BHTwitter] Exception in T1ImmersiveViewController viewDidLoad: %@", exception);
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    @try {
        if ([BHTManager hideFollowButton] && self.view) {
            findAndHideButtonWithAccessibilityId(self.view, @"FollowButton");
        }
    } @catch (NSException *exception) {
        NSLog(@"[BHTwitter] Exception in T1ImmersiveViewController viewWillAppear: %@", exception);
    }
}

%end

// MARK: - Restore Follow Button (TUIFollowControl)

@interface TUIFollowControl : UIControl
- (void)setVariant:(NSUInteger)variant;
- (NSUInteger)variant; // Ensure getter is declared
@end

%hook TUIFollowControl

- (void)setVariant:(NSUInteger)variant {
    if ([BHTManager restoreFollowButton]) {
        NSUInteger subscribeVariantID = 1;
        NSUInteger desiredFollowVariantID = 32;
        if (variant == subscribeVariantID) {
            %orig(desiredFollowVariantID);
        } else {
            %orig(variant);
        }
    } else {
        %orig;
    }
}

// NOTE: We intentionally do NOT override -variant. Forcing it to a constant 32
// made every TUIFollowControl report "Follow" regardless of the real account
// relationship, which hid the Follow button on every tweet (NeoFreeBird#2).
// The setVariant: remap above already converts Subscribe (1) -> Follow (32).

%end

// Forward declare T1SuperFollowControl if its interface is not fully defined yet
@class T1SuperFollowControl;

// Helper function to recursively find and hide T1SuperFollowControl instances
static void findAndHideSuperFollowControl(UIView *viewToSearch) {
    if ([viewToSearch isKindOfClass:NSClassFromString(@"T1SuperFollowControl")]) {
        viewToSearch.hidden = YES;
        viewToSearch.alpha = 0.0;
    }
    for (UIView *subview in viewToSearch.subviews) {
        findAndHideSuperFollowControl(subview);
    }
}

@class T1ProfileHeaderViewController; // Forward declaration instead of interface definition

// It's good practice to also declare the class we are looking for, even if just minimally
@interface T1SuperFollowControl : UIView
@property(retain, nonatomic) UIButton *button;
@end

// Add global class pointer for T1ProfileHeaderViewController
static Class gT1ProfileHeaderViewControllerClass = nil;
// Add global class pointers for Dash specific views
static Class gDashAvatarImageViewClass = nil;
static Class gDashDrawerAvatarImageViewClass = nil;
static Class gDashHostingControllerClass = nil;
static Class gGuideContainerVCClass = nil;
static Class gTombstoneCellClass = nil;
static Class gExploreHeroCellClass = nil;

// Helper function to find the UIViewController managing a UIView
static UIViewController* getViewControllerForView(UIView *view) {
    @try {
        // Safety check: Ensure view is valid
        if (!view) {
            return nil;
        }

        UIResponder *responder = view;
        NSInteger maxIterations = 20; // Prevent infinite loops
        NSInteger currentIteration = 0;

        while ((responder = [responder nextResponder]) && currentIteration < maxIterations) {
            currentIteration++;

            // Safety check: Ensure responder is still valid
            if (!responder) {
                break;
            }

            if ([responder isKindOfClass:[UIViewController class]]) {
                return (UIViewController *)responder;
            }
            // Stop if we reach top-level objects like UIWindow or UIApplication without finding a VC
            if ([responder isKindOfClass:[UIWindow class]] || [responder isKindOfClass:[UIApplication class]]) {
                break;
            }
        }
        return nil;
    } @catch (NSException *exception) {
        NSLog(@"[BHTwitter] Exception in getViewControllerForView: %@", exception);
        return nil;
    }
}

// Helper function to check if a view is inside T1ProfileHeaderViewController
static BOOL isViewInsideT1ProfileHeaderViewController(UIView *view) {
    if (!gT1ProfileHeaderViewControllerClass) {
        return NO;
    }
    UIViewController *vc = getViewControllerForView(view);
    if (!vc) return NO;

    UIViewController *parent = vc; // Start with the direct VC
    while (parent) {
        if ([parent isKindOfClass:gT1ProfileHeaderViewControllerClass]) return YES;
        parent = parent.parentViewController;
    }
    UIViewController *presenting = vc.presentingViewController; // Check presenting chain from direct VC
    while(presenting){
        if([presenting isKindOfClass:gT1ProfileHeaderViewControllerClass]) return YES;
        if(presenting.presentingViewController){
            // Check containers in the presenting chain
            if([presenting isKindOfClass:[UINavigationController class]]){
                UINavigationController *nav = (UINavigationController*)presenting;
                for(UIViewController *childVc in nav.viewControllers){
                    if([childVc isKindOfClass:gT1ProfileHeaderViewControllerClass]) return YES;
                }
            }
            presenting = presenting.presentingViewController;
        } else {
            // Final check on the root of the presenting chain for container
            if([presenting isKindOfClass:[UINavigationController class]]){
                 UINavigationController *nav = (UINavigationController*)presenting;
                 for(UIViewController *childVc in nav.viewControllers){
                     if([childVc isKindOfClass:gT1ProfileHeaderViewControllerClass]) return YES;
                 }
            }
            break;
        }
    }
    return NO;
}

// Helper function to check if a view is inside the Dash Hosting Controller
static BOOL isViewInsideDashHostingController(UIView *view) {
    if (!gDashHostingControllerClass) {
        return NO;
    }
    UIViewController *vc = getViewControllerForView(view);
    if (!vc) return NO;

    UIViewController *parent = vc; // Start with the direct VC
    while (parent) {
        if ([parent isKindOfClass:gDashHostingControllerClass]) return YES;
        parent = parent.parentViewController;
    }
    UIViewController *presenting = vc.presentingViewController; // Check presenting chain from direct VC
    while(presenting){
        if([presenting isKindOfClass:gDashHostingControllerClass]) return YES;
        if(presenting.presentingViewController){
            // Check containers in the presenting chain
            if([presenting isKindOfClass:[UINavigationController class]]){
                UINavigationController *nav = (UINavigationController*)presenting;
                for(UIViewController *childVc in nav.viewControllers){
                    if([childVc isKindOfClass:gDashHostingControllerClass]) return YES;
                }
            }
            presenting = presenting.presentingViewController;
        } else {
             // Final check on the root of the presenting chain for container
             if([presenting isKindOfClass:[UINavigationController class]]){
                 UINavigationController *nav = (UINavigationController*)presenting;
                 for(UIViewController *childVc in nav.viewControllers){
                     if([childVc isKindOfClass:gDashHostingControllerClass]) return YES;
                 }
            }
            break;
        }
    }
    return NO;
}

// MARK: - Immersive Player Timestamp

%hook T1ImmersiveFullScreenViewController

// Forward declare the new helper method for visibility within this hook block
- (BOOL)BHT_findAndPrepareTimestampLabelForVC:(T1ImmersiveFullScreenViewController *)activePlayerVC;

// Helper method to find, style, and map the timestamp label for a given VC instance
%new - (BOOL)BHT_findAndPrepareTimestampLabelForVC:(T1ImmersiveFullScreenViewController *)activePlayerVC {
    if (!playerToTimestampMap || !activePlayerVC || !activePlayerVC.isViewLoaded) {
        return NO;
    }

    // Performance optimization: Check cache first to avoid repeated expensive searches
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    if (currentTime - lastCacheInvalidation > CACHE_INVALIDATION_INTERVAL) {
        if (labelSearchCache) {
            [labelSearchCache removeAllObjects];
        }
        lastCacheInvalidation = currentTime;
    }

    // Initialize cache if needed
    if (!labelSearchCache) {
        labelSearchCache = [NSMapTable weakToStrongObjectsMapTable];
    }

    UILabel *timestampLabel = [playerToTimestampMap objectForKey:activePlayerVC];

    // Performance optimization: Only do fresh find if really necessary
    BOOL needsFreshFind = (!timestampLabel || !timestampLabel.superview || ![timestampLabel.superview isDescendantOfView:activePlayerVC.view]);
    if (timestampLabel && timestampLabel.superview &&
        (![timestampLabel.text containsString:@":"] || ![timestampLabel.text containsString:@"/"])) {
        needsFreshFind = YES;
        [playerToTimestampMap removeObjectForKey:activePlayerVC];
        timestampLabel = nil;
    }

    if (needsFreshFind) {
        // Performance optimization: Check if we recently failed to find a label for this VC
        NSNumber *lastSearchResult = [labelSearchCache objectForKey:activePlayerVC];
        if (lastSearchResult && ![lastSearchResult boolValue]) {
            return NO;
        }
        __block UILabel *foundCandidate = nil;
        UIView *searchView = activePlayerVC.view;

        // Performance optimization: Limit search scope to likely container views
        __block NSInteger searchCount = 0;
        const NSInteger MAX_SEARCH_COUNT = 100; // Prevent excessive searching

        BH_EnumerateSubviewsRecursively(searchView, ^(UIView *currentView) {
            if (foundCandidate || ++searchCount > MAX_SEARCH_COUNT) return;

            // Performance optimization: Skip views that are unlikely to contain timestamp labels
            NSString *currentViewClass = NSStringFromClass([currentView class]);
            if ([currentViewClass containsString:@"Button"] ||
                [currentViewClass containsString:@"Image"] ||
                [currentViewClass containsString:@"Scroll"]) {
                return;
            }

            if ([currentView isKindOfClass:[UILabel class]]) {
                UILabel *label = (UILabel *)currentView;

                // Performance optimization: Quick text validation before hierarchy check
                if (!label.text || label.text.length < 3 ||
                    ![label.text containsString:@":"] || ![label.text containsString:@"/"]) {
                    return;
                }

                UIView *v = label.superview;
                BOOL inImmersiveCardViewContext = NO;
                NSInteger hierarchyDepth = 0;

                while(v && v != searchView.window && v != searchView && hierarchyDepth < 10) {
                    NSString *className = NSStringFromClass([v class]);
                    if ([className isEqualToString:@"T1TwitterSwift.ImmersiveCardView"] || [className hasSuffix:@".ImmersiveCardView"]) {
                        inImmersiveCardViewContext = YES;
                        break;
                    }
                    v = v.superview;
                    hierarchyDepth++;
                }

                if (inImmersiveCardViewContext) {
                    foundCandidate = label;
                }
            }
        });

        if (foundCandidate) {
            timestampLabel = foundCandidate;

            // Don't set the visibility directly - let the player handle it
            // Just style the label for proper appearance

            // Now store it in our map
            [playerToTimestampMap setObject:timestampLabel forKey:activePlayerVC];
            [labelSearchCache setObject:@YES forKey:activePlayerVC];
        } else {
            // Performance optimization: Cache negative results to avoid repeated searches
            [labelSearchCache setObject:@NO forKey:activePlayerVC];
            if ([playerToTimestampMap objectForKey:activePlayerVC]) {
                [playerToTimestampMap removeObjectForKey:activePlayerVC];
            }
            return NO;
        }
    }

    if (timestampLabel && ![objc_getAssociatedObject(timestampLabel, "BHT_StyledTimestamp") boolValue]) {
        timestampLabel.font = [UIFont systemFontOfSize:14.0];
        timestampLabel.textColor = [UIColor whiteColor];
        timestampLabel.textAlignment = NSTextAlignmentCenter;
        timestampLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];

        [timestampLabel sizeToFit];
        CGRect currentFrame = timestampLabel.frame;
        CGFloat horizontalPadding = 2.0; // Padding on EACH side
        CGFloat verticalPadding = 12.0; // TOTAL vertical padding (6.0 on each side)

        CGRect newFrame = CGRectMake(
            currentFrame.origin.x - horizontalPadding,
            currentFrame.origin.y - (verticalPadding / 2.0f),
            currentFrame.size.width + (horizontalPadding * 2),
                currentFrame.size.height + verticalPadding
            );

        if (newFrame.size.height < 22.0f) {
            CGFloat heightDiff = 22.0f - newFrame.size.height;
            newFrame.size.height = 22.0f;
            newFrame.origin.y -= heightDiff / 2.0f;
        }
        timestampLabel.frame = newFrame;
        timestampLabel.layer.cornerRadius = newFrame.size.height / 2.0f;
        timestampLabel.layer.masksToBounds = YES;
        objc_setAssociatedObject(timestampLabel, "BHT_StyledTimestamp", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return (timestampLabel != nil && timestampLabel.superview != nil); // Ensure it's also in a superview
}

- (void)immersiveViewController:(id)passedImmersiveViewController showHideNavigationButtons:(_Bool)showButtons {
    // Store the original value for "showButtons"
    BOOL originalShowButtons = showButtons;

    // No longer forcing controls to be visible on first load
    // Let Twitter's player handle everything normally

    // Always pass the original parameter - no overriding
    %orig(passedImmersiveViewController, originalShowButtons);

    T1ImmersiveFullScreenViewController *activePlayerVC = self;

    // The rest of the method remains unchanged
    if (![BHTManager restoreVideoTimestamp]) {
        if (playerToTimestampMap) {
            UILabel *labelToManage = [playerToTimestampMap objectForKey:activePlayerVC];
            if (labelToManage) {
                labelToManage.hidden = YES;

            }
        }
        return;
    }

    SEL findAndPrepareSelector = NSSelectorFromString(@"BHT_findAndPrepareTimestampLabelForVC:");
    BOOL labelReady = NO;

    if ([self respondsToSelector:findAndPrepareSelector]) {
        NSMethodSignature *signature = [self methodSignatureForSelector:findAndPrepareSelector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setSelector:findAndPrepareSelector];
        [invocation setTarget:self];
        [invocation setArgument:&activePlayerVC atIndex:2]; // Arguments start at index 2 (0 = self, 1 = _cmd)
        [invocation invoke];
        [invocation getReturnValue:&labelReady];
    } else {

    }

    if (labelReady) {
        UILabel *timestampLabel = [playerToTimestampMap objectForKey:activePlayerVC];
        if (timestampLabel) {
            // Let the timestamp follow the controls visibility, but ensure it matches
            BOOL isVisible = showButtons;


            // Only adjust if there's a mismatch
            if (isVisible && timestampLabel.hidden) {
                // Controls are visible but label is hidden - fix it
                timestampLabel.hidden = NO;
                NSLog(@"[BHTwitter Timestamp] VC %@: Fixing hidden label to match visible controls", activePlayerVC);
            } else if (!isVisible && !timestampLabel.hidden) {
                // Controls are hidden but label is visible - fix it
                NSLog(@"[BHTwitter Timestamp] VC %@: Label is incorrectly visible, will be hidden by player", activePlayerVC);
            }
        } else {
            NSLog(@"[BHTwitter Timestamp] VC %@: Label was ready but map returned nil.", activePlayerVC);
        }
    } else {
        NSLog(@"[BHTwitter Timestamp] VC %@: Label not ready after findAndPrepare.", activePlayerVC);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    T1ImmersiveFullScreenViewController *activePlayerVC = self;

    if ([BHTManager restoreVideoTimestamp]) {
        if (!playerToTimestampMap) {
            playerToTimestampMap = [NSMapTable weakToStrongObjectsMapTable];
        }

        // Ensure the label is found and prepared if the view appears.
        [self BHT_findAndPrepareTimestampLabelForVC:activePlayerVC];

        // REMOVED: BHT_FirstLoadDone and related logic for forced first-load visibility.
        // BOOL isFirstLoad = ![objc_getAssociatedObject(activePlayerVC, "BHT_FirstLoadDone") boolValue];
        // if (isFirstLoad) {
            // dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                // if (self && self.view.window) {
                    // objc_setAssociatedObject(self, "BHT_FirstLoadDone", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                // }
            // });
        // }
    }
}

- (void)playerViewController:(id)playerViewController playerStateDidChange:(NSInteger)state {
    %orig(playerViewController, state);
    T1ImmersiveFullScreenViewController *activePlayerVC = self;

    if (![BHTManager restoreVideoTimestamp] || !playerToTimestampMap) {
        return;
    }

    // Always try to find/prepare the label for the current video content.
    // This is crucial if the VC is reused and new video content has loaded.
    BOOL labelFoundAndPrepared = [self BHT_findAndPrepareTimestampLabelForVC:activePlayerVC];

    if (labelFoundAndPrepared) {
        UILabel *timestampLabel = [playerToTimestampMap objectForKey:activePlayerVC];
        if (timestampLabel && timestampLabel.superview && [timestampLabel isDescendantOfView:activePlayerVC.view]) {
            // Determine current intended visibility of controls.
            BOOL controlsShouldBeVisible = NO;
            UIView *playerControls = nil;
            if ([activePlayerVC respondsToSelector:@selector(playerControlsView)]) {
                playerControls = [activePlayerVC valueForKey:@"playerControlsView"];
                if (playerControls && [playerControls respondsToSelector:@selector(alpha)]) {
                    controlsShouldBeVisible = playerControls.alpha > 0.0f;
                }
            }

            // Directly set the label's visibility based on controls
            timestampLabel.hidden = !controlsShouldBeVisible;
        }
    }
}

%end

// MARK: - Square Avatars (TFNAvatarImageView)

@interface TFNAvatarImageView : UIView // Assuming it's a UIView subclass, adjust if necessary
- (void)setStyle:(NSInteger)style;
- (NSInteger)style;
@end

// MARK: - Blur Handler

@interface TFNBlurHandler : NSObject
@property(retain, nonatomic) UIView *blurBackgroundView;
@end

%hook TFNAvatarImageView

- (void)setStyle:(NSInteger)style {
    if ([BHTManager squareAvatars]) {
        CGFloat activeCornerRadius;
        NSString *selfClassName = NSStringFromClass([self class]); // Get class name as string

        BOOL isDashAvatar = [selfClassName isEqualToString:@"TwitterDash.DashAvatarImageView"];
        BOOL isDashDrawerAvatar = [selfClassName isEqualToString:@"TwitterDash.DashDrawerAvatarImageView"];

        BOOL inDashHostingContext = isViewInsideDashHostingController(self);

        if (isDashDrawerAvatar) {
            // DashDrawerAvatarImageView always gets 8.0f regardless of context
            activeCornerRadius = 8.0f;
        } else if (isDashAvatar && inDashHostingContext) {
            // Regular DashAvatarImageView in hosting context gets 8.0f
            activeCornerRadius = 8.0f;
        } else if (isViewInsideT1ProfileHeaderViewController(self)) {
            // Avatars in profile header get 8.0f
            activeCornerRadius = 8.0f;
        } else {
            // Default for all other avatars is 12.0f
            activeCornerRadius = 12.0f;
        }

        %orig(3); // Call original with forced style 3

        // Force slightly rounded square on the main TFNAvatarImageView layer
        self.layer.cornerRadius = activeCornerRadius;
        self.layer.masksToBounds = YES; // Ensure the main view clips

        // Find TIPImageViewObserver and force it to be slightly rounded
        for (NSUInteger i = 0; i < self.subviews.count; i++) {
            UIView *subview = [self.subviews objectAtIndex:i];
            NSString *subviewClassString = NSStringFromClass([subview class]);
            if ([subviewClassString isEqualToString:@"TIPImageViewObserver"]) {
                subview.layer.cornerRadius = activeCornerRadius;
                subview.layer.mask = nil;
                subview.clipsToBounds = YES;        // View property
                subview.layer.masksToBounds = YES;  // Layer property
                subview.contentMode = UIViewContentModeScaleAspectFill; // Set contentMode

                // Check for subviews of TIPImageViewObserver
                if (subview.subviews.count > 0) {
                    for (NSUInteger j = 0; j < subview.subviews.count; j++) {
                        UIView *tipSubview = [subview.subviews objectAtIndex:j];
                        tipSubview.layer.cornerRadius = activeCornerRadius;
                        tipSubview.layer.mask = nil;
                        tipSubview.clipsToBounds = YES;
                        tipSubview.layer.masksToBounds = YES;
                        tipSubview.contentMode = UIViewContentModeScaleAspectFill; // Set contentMode
                    }
                }
                break; // Assuming only one TIPImageViewObserver, exit loop
            }
        }
    } else {
        %orig;
    }
}

- (NSInteger)style {
    if ([BHTManager squareAvatars]) {
        return 3;
    }
    return %orig;
}

%end

%hook UIImage

// Hook the specific TFN rounding method
- (UIImage *)tfn_roundImageWithTargetDimensions:(CGSize)targetDimensions targetContentMode:(UIViewContentMode)targetContentMode {
    if ([BHTManager squareAvatars]) {
        if (targetDimensions.width <= 0 || targetDimensions.height <= 0) {
            return self; // Avoid issues with zero/negative size
        }

        CGFloat cornerRadius = 12.0f;
        CGRect imageRect = CGRectMake(0, 0, targetDimensions.width, targetDimensions.height);

        // Ensure cornerRadius is not too large for the dimensions
        CGFloat minSide = MIN(targetDimensions.width, targetDimensions.height);
        if (cornerRadius > minSide / 2.0f) {
            cornerRadius = minSide / 2.0f; // Cap radius to avoid weird shapes
        }

        UIGraphicsBeginImageContextWithOptions(targetDimensions, NO, self.scale); // Use self.scale for retina, NO for opaque if image has alpha
        if (!UIGraphicsGetCurrentContext()) {
            UIGraphicsEndImageContext(); // Defensive call
            return self;
        }

        [[UIBezierPath bezierPathWithRoundedRect:imageRect cornerRadius:cornerRadius] addClip];
        [self drawInRect:imageRect];

        UIImage *roundedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        if (roundedImage) {
            return roundedImage;
        } else {
            return self; // Fallback to original image if rounding fails
        }
    } else {
        return %orig;
    }
}

%end

%hook TFNCircularAvatarShadowLayer

- (void)setHidden:(BOOL)hidden {
    if ([BHTManager squareAvatars]) {
        %orig(YES); // Always hide this layer when square avatars are enabled
    } else {
        %orig;
    }
}

%end

// MARK: - Hide Screenshot Container Views

%hook TFNCustomScreenshotContainerView
- (void)didMoveToWindow {
    if ([BHTManager hideScreenshotContainer]) {
        self.hidden = true;
        self.alpha = 0.0;
        self.userInteractionEnabled = false;
    } else {
        %orig;
    }
}
%end

%hook TUIFollowControlCustomScreenshot
- (void)didMoveToWindow {
    if ([BHTManager hideScreenshotContainer]) {
        self.hidden = true;
        self.alpha = 0.0;
        self.userInteractionEnabled = false;
    } else {
        %orig;
    }
}
%end

// MARK: - Restore Pull-To-Refresh Sounds

// Helper function to play sounds since we can't directly call methods on TFNPullToRefreshControl
static void PlayRefreshSound(int soundType) {
    static SystemSoundID sounds[2] = {0, 0};
    static BOOL soundsInitialized[2] = {NO, NO};

    // Ensure the sounds are only initialized once per type
    if (!soundsInitialized[soundType]) {
        NSString *soundFile = nil;
        if (soundType == 0) {
            // Sound when pulling down
            soundFile = @"psst2.aac";
        } else if (soundType == 1) {
            // Sound when refresh completes
            soundFile = @"pop.aac";
        }

        if (soundFile) {
            NSURL *soundURL = [[BHTBundle sharedBundle] pathForFile:soundFile];
            if (soundURL) {
                OSStatus status = AudioServicesCreateSystemSoundID((__bridge CFURLRef)soundURL, &sounds[soundType]);
                if (status == kAudioServicesNoError) {
                    soundsInitialized[soundType] = YES;
                } else {
                    NSLog(@"[BHTwitter] Failed to initialize sound %@ (type %d), status: %d", soundFile, soundType, (int)status);
                }
            } else {
                NSLog(@"[BHTwitter] Could not find sound file: %@", soundFile);
            }
        }
    }

    // Play the sound if it was successfully initialized
    if (soundsInitialized[soundType]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            AudioServicesPlaySystemSound(sounds[soundType]);
        });
    }
}

%hook TFNPullToRefreshControl

// Track state with instance-specific variables using associated objects
static char kPreviousLoadingStateKey;
static char kManualRefreshInProgressKey;

// Always enable sound effects
+ (_Bool)_areSoundEffectsEnabled {
    return YES;
}

// Hook the simple loading property setter
- (void)setLoading:(_Bool)loading {
    static BOOL previousLoading = NO;
    static BOOL manualRefresh = NO;

    if (!loading && previousLoading && manualRefresh) {
        PlayRefreshSound(1);
        manualRefresh = NO;
    }

    if (!loading && previousLoading) {
        manualRefresh = NO;
    } else if (loading && !previousLoading) {
        // This is likely a manual refresh
        manualRefresh = YES;
    }

    previousLoading = loading;
    %orig;
}

// Hook the completion-based loading setter
- (void)setLoading:(_Bool)loading completion:(void(^)(void))completion {
    // Get previous loading state
    NSNumber *previousLoadingState = objc_getAssociatedObject(self, &kPreviousLoadingStateKey);
    BOOL wasLoading = previousLoadingState ? [previousLoadingState boolValue] : NO;

    // Check if we're in a manual refresh
    NSNumber *manualRefresh = objc_getAssociatedObject(self, &kManualRefreshInProgressKey);
    BOOL isManualRefresh = manualRefresh ? [manualRefresh boolValue] : NO;

    %orig;

    // Store the new state AFTER calling original
    objc_setAssociatedObject(self, &kPreviousLoadingStateKey, @(loading), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // If loading went from YES to NO AND we're in a manual refresh, play pop sound
    if (wasLoading && !loading && isManualRefresh) {
        PlayRefreshSound(1);
        // Clear the manual refresh flag
        objc_setAssociatedObject(self, &kManualRefreshInProgressKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (!wasLoading && loading) {
        NSLog(@"[BHTwitter] Loading changed from NO to YES (completion) - refresh started");
    }
}

// Detect manual pull-to-refresh and play pull sound
- (void)_setStatus:(unsigned long long)status fromScrolling:(_Bool)fromScrolling {
    %orig;

    if (status == 1 && fromScrolling) {
        PlayRefreshSound(0);

        // Mark that we're in a manual refresh
        objc_setAssociatedObject(self, &kManualRefreshInProgressKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // Mark that loading started (even though setLoading: might not be called with loading=1)
        objc_setAssociatedObject(self, &kPreviousLoadingStateKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%end

// MARK: - Bypass attestation
// Spoof DCAppAttestService.isSupported as NO so Twitter falls back to a non-attested path,
// avoiding key exchange failures on jailbroken/sideloaded devices.
%hook DCAppAttestService

- (BOOL)isSupported {
    if ([BHTManager isAttestationBypassEnabled]) {
        return NO;
    }
    return %orig;
}

%end

// Strip attestation headers from Twitter/X requests so the server doesn't reject
// the key exchange when the client cannot produce a valid attestation token.
%hook NSMutableURLRequest

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if ([BHTManager isAttestationBypassEnabled]) {
        NSString *host = self.URL.host;
        if (host && ([host containsString:@"twitter.com"] || [host containsString:@"x.com"])) {
            if ([field isEqualToString:@"X-Twitter-Client-Attest"] || [field isEqualToString:@"X-Client-UUID"]) {
                return;
            }
        }
    }
    %orig;
}

%end

// Force ephemeral sessions so web flows doesn't share cookies with
// a persistent browser session that might expose attestation state.
%hook ASWebAuthenticationSession

- (instancetype)initWithURL:(NSURL *)URL callbackURLScheme:(NSString *)callbackURLScheme completionHandler:(void(^)(NSURL *, NSError *))completionHandler {
    id result = %orig;
    if (result && [BHTManager isAttestationBypassEnabled]) {
        __weak ASWebAuthenticationSession *weakSession = result;
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSession.prefersEphemeralWebBrowserSession = YES;
        });
    }
    return result;
}

%end

%ctor {
    BHTPinnedTabsLaunchUptime = [[NSProcessInfo processInfo] systemUptime];

    // Import AudioServices framework
    dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox", RTLD_LAZY);

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];
    // Someone needs to hold reference the to Notification
    _PasteboardChangeObserver = [center addObserverForName:UIPasteboardChangedNotification object:nil queue:mainQueue usingBlock:^(NSNotification * _Nonnull note){

        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            trackingParams = @{
                @"twitter.com" : @[@"s", @"t"],
                @"x.com" : @[@"s", @"t"],
            };
        });

        if ([BHTManager stripTrackingParams]) {
            if (UIPasteboard.generalPasteboard.hasURLs) {
                NSURL *pasteboardURL = UIPasteboard.generalPasteboard.URL;
                NSArray<NSString*>* params = trackingParams[pasteboardURL.host];

                if ([pasteboardURL.absoluteString isEqualToString:_lastCopiedURL] == NO && params != nil && pasteboardURL.query != nil) {
                    // to prevent endless copy loop
                    _lastCopiedURL = pasteboardURL.absoluteString;
                    NSURLComponents *cleanedURL = [NSURLComponents componentsWithURL:pasteboardURL resolvingAgainstBaseURL:NO];
                    NSMutableArray<NSURLQueryItem*> *safeParams = [NSMutableArray arrayWithCapacity:0];

                    for (NSURLQueryItem *item in cleanedURL.queryItems) {
                        if ([params containsObject:item.name] == NO) {
                            [safeParams addObject:item];
                        }
                    }
                    cleanedURL.queryItems = safeParams.count > 0 ? safeParams : nil;

                    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"tweet_url_host"]) {
                        NSString *selectedHost = [[NSUserDefaults standardUserDefaults] objectForKey:@"tweet_url_host"];
                        cleanedURL.host = selectedHost;
                    }
                    UIPasteboard.generalPasteboard.URL = cleanedURL.URL;
                }
            }
        }
    }];

    // Initialize global Class pointers here when the tweak loads
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gGuideContainerVCClass = NSClassFromString(@"T1TwitterSwift.GuideContainerViewController");
        if (!gGuideContainerVCClass) gGuideContainerVCClass = NSClassFromString(@"T1TwitterSwift_GuideContainerViewController");

        gTombstoneCellClass = NSClassFromString(@"T1TwitterSwift.ConversationTombstoneCell");
        if (!gTombstoneCellClass) gTombstoneCellClass = NSClassFromString(@"T1TwitterSwift_ConversationTombstoneCell");

        gExploreHeroCellClass = NSClassFromString(@"T1ExploreEventSummaryHeroTableViewCell");

        // Initialize T1ProfileHeaderViewController class pointer
        gT1ProfileHeaderViewControllerClass = NSClassFromString(@"T1ProfileHeaderViewController");

        // Initialize Dash specific class pointers
        gDashAvatarImageViewClass = NSClassFromString(@"TwitterDash.DashAvatarImageView");
        gDashDrawerAvatarImageViewClass = NSClassFromString(@"TwitterDash.DashDrawerAvatarImageView");

        // The full name for the hosting controller is very long and specific.
        gDashHostingControllerClass = NSClassFromString(@"_TtGC7SwiftUI19UIHostingControllerGV10TFNUISwift22HostingEnvironmentViewV11TwitterDash18DashNavigationView__");

        // Initialize the concurrent queue for source label data access
        sourceLabelDataQueue = dispatch_queue_create("com.bandarhelal.bhtwitter.sourceLabelQueue", DISPATCH_QUEUE_CONCURRENT);
    });

    // Initialize dictionaries for Tweet Source Labels restoration
    dispatch_barrier_async(sourceLabelDataQueue, ^{
        if (!tweetSources)      tweetSources      = [NSMutableDictionary dictionary];
        if (!fetchTimeouts)     fetchTimeouts     = [NSMutableDictionary dictionary];
        if (!fetchRetries)      fetchRetries      = [NSMutableDictionary dictionary];
        if (!updateRetries)     updateRetries     = [NSMutableDictionary dictionary];
        if (!updateCompleted)   updateCompleted   = [NSMutableDictionary dictionary];
        if (!fetchPending)      fetchPending      = [NSMutableDictionary dictionary];
        if (!cookieCache)       cookieCache       = [NSMutableDictionary dictionary];
    });
    // These dictionaries are UI-related and should only be accessed on the main thread
    if (!viewToTweetID)     viewToTweetID     = [NSMutableDictionary dictionary];
    if (!viewInstances)     viewInstances     = [NSMutableDictionary dictionary];

    // Load cached cookies at initialization
    [TweetSourceHelper loadCachedCookies];

    %init;
    // Add observers for both window and theme changes
    [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeVisibleNotification
                                                    object:nil
                                                     queue:[NSOperationQueue mainQueue]
                                                usingBlock:^(NSNotification * _Nonnull note) {
        UIWindow *window = note.object;
        if (window && [[NSUserDefaults standardUserDefaults] objectForKey:@"bh_color_theme_selectedColor"]) {
            BHT_applyThemeToWindow(window);
        }
    }];

    static dispatch_once_t onceTokenPlayerMap;
    dispatch_once(&onceTokenPlayerMap, ^{
        playerToTimestampMap = [NSMapTable weakToStrongObjectsMapTable];
    });
}

// MARK: - Classic Tab Bar Icon Theming
%hook T1TabView

%new
- (void)bh_applyCurrentThemeToIcon {
    UIImageView *imageView = [self valueForKey:@"imageView"];
    UILabel *titleLabel = [self valueForKey:@"titleLabel"];
    if (!imageView) return;

    BOOL isSelected = [[self valueForKey:@"selected"] boolValue];

    if ([BHTManager classicTabBarEnabled]) {
        // Apply custom theming
        UIColor *targetColor = isSelected ? BHTCurrentAccentColor() : [UIColor secondaryLabelColor];

        // Ensure image is in template mode for proper tinting
        if (imageView.image && imageView.image.renderingMode != UIImageRenderingModeAlwaysTemplate) {
            imageView.image = [imageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }

        // Apply tint color to icon
        imageView.tintColor = targetColor;

        // Apply color to label
        if (titleLabel) {
            titleLabel.textColor = targetColor;
        }
    } else {
        // Revert to default Twitter appearance
        imageView.tintColor = nil;

        // Reset image rendering mode to automatic
        if (imageView.image) {
            imageView.image = [imageView.image imageWithRenderingMode:UIImageRenderingModeAutomatic];
        }

        // Reset label color to default
        if (titleLabel) {
            titleLabel.textColor = nil;
        }
    }
}

- (BOOL)_t1_showsTitle {
    if ([BHTManager restoreTabLabels]) {
        return true;
    }
    return %orig;
}

- (void)_t1_updateTitleLabel {
    %orig;

    // Ensure titleLabel is not hidden when restore tab labels is enabled
    if ([BHTManager restoreTabLabels]) {
        UILabel *titleLabel = [self valueForKey:@"titleLabel"];
        if (titleLabel) {
            titleLabel.hidden = NO;
        }
    }
}

- (void)_t1_updateImageViewAnimated:(_Bool)animated {
    %orig(animated);

    // Always apply theming logic (handles both enabled and disabled cases)
    [self performSelector:@selector(bh_applyCurrentThemeToIcon)];
}

- (void)setSelected:(_Bool)selected {
    %orig(selected);

    // Always apply theming logic (handles both enabled and disabled cases)
    [self performSelector:@selector(bh_applyCurrentThemeToIcon)];
}

%end



// MARK: - Tab Bar Controller Theme Integration
%hook T1TabBarViewController

- (void)_t1_updateTabBarAppearance {
    %orig;

    // Apply our custom theming after Twitter updates the tab bar
    if ([BHTManager classicTabBarEnabled]) {
        NSArray *tabViews = [self valueForKey:@"tabViews"];
        for (id tabView in tabViews) {
            if ([tabView respondsToSelector:@selector(bh_applyCurrentThemeToIcon)]) {
                [tabView performSelector:@selector(bh_applyCurrentThemeToIcon)];
            }
        }
    }
}

%end

// Helper: Update all tab bar icons using Twitter's internal methods
static void BHT_UpdateAllTabBarIcons(void) {
    // Use Twitter's notification system to refresh tab bars
    [[NSNotificationCenter defaultCenter] postNotificationName:@"T1TabBarAppearanceDidChangeNotification" object:nil];

    // Also trigger a direct refresh on visible tab bar controllers
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.isKeyWindow && window.rootViewController) {
            UIViewController *rootVC = window.rootViewController;

            if ([rootVC isKindOfClass:NSClassFromString(@"T1TabBarViewController")]) {
                // Use Twitter's internal tab bar refresh method if available
                if ([rootVC respondsToSelector:@selector(_t1_updateTabBarAppearance)]) {
                    [rootVC performSelector:@selector(_t1_updateTabBarAppearance)];
                }
            }
        }
    }
}

static void BHT_applyThemeToWindow(UIWindow *window) {
    if (!window || !window.rootViewController) return;

    // Simply trigger Twitter's internal appearance update
    if ([window.rootViewController isKindOfClass:NSClassFromString(@"T1TabBarViewController")]) {
        if ([window.rootViewController respondsToSelector:@selector(_t1_updateTabBarAppearance)]) {
            [window.rootViewController performSelector:@selector(_t1_updateTabBarAppearance)];
        }
    }
}

// Helper to synchronize theme engine and ensure our theme is active
static void BHT_ensureThemingEngineSynchronized(BOOL forceSynchronize) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id selectedColorObj = [defaults objectForKey:@"bh_color_theme_selectedColor"];

    if (!selectedColorObj) return;

    NSInteger selectedColor = [selectedColorObj integerValue];
    id twitterColorObj = [defaults objectForKey:@"T1ColorSettingsPrimaryColorOptionKey"];

    // Check if Twitter's color setting matches our desired color
    if (forceSynchronize || !twitterColorObj || ![twitterColorObj isEqual:selectedColorObj]) {
        // Mark that we're performing our own theme change to avoid recursion
        BHT_isInThemeChangeOperation = YES;

        // Apply our theme color through Twitter's system
        TAEColorSettings *taeSettings = [%c(TAEColorSettings) sharedSettings];
        if ([taeSettings respondsToSelector:@selector(setPrimaryColorOption:)]) {
            [taeSettings setPrimaryColorOption:selectedColor];
        }

        // Set Twitter's user defaults key to match our selection
        [defaults setObject:selectedColorObj forKey:@"T1ColorSettingsPrimaryColorOptionKey"];

        // Call Twitter's internal theme application methods
        if ([%c(T1ColorSettings) respondsToSelector:@selector(_t1_applyPrimaryColorOption)]) {
            [%c(T1ColorSettings) _t1_applyPrimaryColorOption];
        }

        // Refresh only tab bar icons when classic theming is enabled
        if ([BHTManager classicTabBarEnabled]) {
            BHT_UpdateAllTabBarIcons();
        }

        // Reset our operation flag
        BHT_isInThemeChangeOperation = NO;
    }
}

// Legacy method for backward compatibility, now just calls our new function
static void BHT_ensureTheming(void) {
    BHT_ensureThemingEngineSynchronized(YES);
}

// Comprehensive UI refresh - used when we need to force a UI update
static void BHT_forceRefreshAllWindowAppearances(void) {
    // Only update tab bar icons if classic theming is enabled
    if ([BHTManager classicTabBarEnabled]) {
        BHT_UpdateAllTabBarIcons();
    }

    // Trigger system-wide appearance updates
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow && window.rootViewController) {
            [window.rootViewController.view setNeedsLayout];
        }
    }
}

// MARK: - Timestamp Label Styling via UILabel -setText:

// Helper method to determine if a text is likely a timestamp
static BOOL isTimestampText(NSString *text) {
    if (!text || text.length == 0) {
        return NO;
    }

    // Check for common timestamp patterns like "0:01/0:05" or "00:20/01:30"
    NSRange colonRange = [text rangeOfString:@":"];
    NSRange slashRange = [text rangeOfString:@"/"];

    // Must have both colon and slash
    if (colonRange.location == NSNotFound || slashRange.location == NSNotFound) {
        return NO;
    }

    // Slash should come after colon in a timestamp (e.g., "0:01/0:05")
    if (slashRange.location < colonRange.location) {
        return NO;
    }

    // Should have another colon after the slash
    NSRange secondColonRange = [text rangeOfString:@":" options:0 range:NSMakeRange(slashRange.location, text.length - slashRange.location)];
    if (secondColonRange.location == NSNotFound) {
        return NO;
    }

    return YES;
}

// Helper to find player controls in view hierarchy
static UIView *findPlayerControlsInHierarchy(UIView *startView) {
    if (!startView) return nil;

    __block UIView *playerControls = nil;
    BH_EnumerateSubviewsRecursively(startView, ^(UIView *view) {
        if (playerControls) return;

        NSString *className = NSStringFromClass([view class]);
        if ([className containsString:@"PlayerControlsView"] ||
            [className containsString:@"VideoControls"]) {
            playerControls = view;
        }
    });

    return playerControls;
}

%hook UILabel

- (void)setText:(NSString *)text {
    %orig(text);

    // Skip processing if feature is disabled
    if (![BHTManager restoreVideoTimestamp]) {
        return;
    }

    // Skip if text doesn't match timestamp pattern
    if (!isTimestampText(self.text)) {
        return;
    }

    // Check if already styled
    if ([objc_getAssociatedObject(self, "BHT_StyledTimestamp") boolValue]) {
        return;
    }

    // Find if we're in the correct view context
    UIView *parentView = self.superview;
    BOOL isInImmersiveContext = NO;

    while (parentView) {
        NSString *className = NSStringFromClass([parentView class]);
        if ([className isEqualToString:@"T1TwitterSwift.ImmersiveCardView"] ||
            [className hasSuffix:@".ImmersiveCardView"]) {
            isInImmersiveContext = YES;
            break;
        }
        parentView = parentView.superview;
    }

    if (isInImmersiveContext) {

        // Apply styling - ONLY styling, not visibility
        self.font = [UIFont systemFontOfSize:14.0];
        self.textColor = [UIColor whiteColor];
        self.textAlignment = NSTextAlignmentCenter;
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];

        // Calculate size and apply padding
        [self sizeToFit];
        CGRect frame = self.frame;
        CGFloat horizontalPadding = 4.0;
        CGFloat verticalPadding = 12.0;

        frame = CGRectMake(
            frame.origin.x - horizontalPadding / 2.0f,
            frame.origin.y - verticalPadding / 2.0f,
            frame.size.width + horizontalPadding,
            frame.size.height + verticalPadding
        );

        // Ensure minimum height
        if (frame.size.height < 22.0f) {
            CGFloat diff = 22.0f - frame.size.height;
            frame.size.height = 22.0f;
            frame.origin.y -= diff / 2.0f;
        }

        self.frame = frame;
        self.layer.cornerRadius = frame.size.height / 2.0f;
        self.layer.masksToBounds = YES;

        // Mark as styled and store reference
        objc_setAssociatedObject(self, "BHT_StyledTimestamp", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // gVideoTimestampLabel = self; // REMOVED
    }
}

// For first-load mode, prevent hiding the timestamp
- (void)setHidden:(BOOL)hidden {
    // Only check labels that might be our timestamp
    // if (self == gVideoTimestampLabel && [BHTManager restoreVideoTimestamp]) { // REMOVED gVideoTimestampLabel logic
        // If trying to hide a fixed label, prevent it
        // if (hidden) {
            // BOOL isFixedForFirstLoad = [objc_getAssociatedObject(self, "BHT_FixedForFirstLoad") boolValue];
            // if (isFixedForFirstLoad) {
                // Let the original method run but with "NO" instead of "YES"
                // return %orig(NO);
            // }
        // }
    // }

    // Default behavior
    %orig(hidden);
}

// Also prevent changing alpha to 0 for first-load labels
- (void)setAlpha:(CGFloat)alpha {
    // Only check our timestamp label
    // if (self == gVideoTimestampLabel && [BHTManager restoreVideoTimestamp]) { // REMOVED gVideoTimestampLabel logic
        // If trying to make a fixed label transparent, prevent it
        // if (alpha == 0.0) {
            // BOOL isFixedForFirstLoad = [objc_getAssociatedObject(self, "BHT_FixedForFirstLoad") boolValue];
            // if (isFixedForFirstLoad) {
                // Keep it fully opaque during protected period
                // return %orig(1.0);
            // }
        // }
    // }

    // Default behavior
    %orig(alpha);
}

%end

// MARK: Restore Launch Animation

%hook T1AppDelegate
+ (id)launchTransitionProvider {
    Class T1AppLaunchTransitionClass = NSClassFromString(@"T1AppLaunchTransition");
    if (T1AppLaunchTransitionClass) {
        return [[T1AppLaunchTransitionClass alloc] init];
    }
    return nil;
}
%end

// MARK: Remove the X-shaped reveal mask from the animated launch screen
// The animated launch screen masks its container layer with an X-shaped hole
// and grows it to reveal the app through an X-shaped portal. Detach that mask
// so the logo zoom is kept but the splash simply fades out instead.

%hook T1AnimatedLaunchScreenView

- (void)layoutSubviews {
    %orig;

    for (UIView *sub in ((UIView *)self).subviews) {
        sub.layer.mask = nil;
    }
}

- (void)animateRevealWithCompletion:(id)completion {
    for (UIView *sub in ((UIView *)self).subviews) {
        sub.layer.mask = nil;
    }

    [UIView animateWithDuration:0.5 animations:^{
        for (UIView *sub in ((UIView *)self).subviews) {
            sub.backgroundColor = [UIColor clearColor];
        }
    }];

    %orig;
}

%end

// MARK: Source Label using T1ConversationFooterTextView

%hook T1ConversationFooterTextView

- (void)updateFooterTextView {
    %orig;

    // Add source label to footer text view
    if ([BHTManager RestoreTweetLabels] && self.viewModel) {
        @try {
            // Get the tweet object from the view model
            id tweetObject = nil;
            if ([self.viewModel respondsToSelector:@selector(tweet)]) {
                tweetObject = [self.viewModel performSelector:@selector(tweet)];
            } else if ([self.viewModel respondsToSelector:@selector(status)]) {
                tweetObject = [self.viewModel performSelector:@selector(status)];
            }

            if (tweetObject) {
                // Get tweet ID
                NSString *tweetIDStr = nil;
                @try {
                    id statusIDVal = [tweetObject valueForKey:@"statusID"];
                    if (statusIDVal && [statusIDVal respondsToSelector:@selector(longLongValue)] && [statusIDVal longLongValue] > 0) {
                        tweetIDStr = [statusIDVal stringValue];
                    }
                } @catch (NSException *e) {}

                if (!tweetIDStr || tweetIDStr.length == 0) {
                    @try {
                        tweetIDStr = [tweetObject valueForKey:@"rest_id"];
                        if (!tweetIDStr || tweetIDStr.length == 0) {
                            tweetIDStr = [tweetObject valueForKey:@"id_str"];
                        }
                        if (!tweetIDStr || tweetIDStr.length == 0) {
                            id genericID = [tweetObject valueForKey:@"id"];
                            if (genericID) tweetIDStr = [genericID description];
                        }
                    } @catch (NSException *e) {}
                }

                if (tweetIDStr && tweetIDStr.length > 0) {
                    // Initialize source tracking if needed
                    if (!tweetSources) tweetSources = [NSMutableDictionary dictionary];

                    // Fetch source if not already available
                    if (!tweetSources[tweetIDStr]) {
                        tweetSources[tweetIDStr] = @""; // Placeholder
                        [TweetSourceHelper fetchSourceForTweetID:tweetIDStr];
                    }

                    // Legacy source code removed
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[BHTwitter] Exception in T1ConversationFooterTextView updateFooterTextView: %@", e);
        }
    }
}

%end

// Helper for the refresh pill setting
static BOOL BHPillLabelOverrideEnabled(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    if ([defaults objectForKey:@"refresh_pill_label"] == nil) {
        return [BHTManager isTwitterBranded];
    }

    return [defaults boolForKey:@"refresh_pill_label"];
}

// Only the "new posts/Tweets" refresh pill should be relabelled. TFNPillControl
// is used for other pills too ("Back to top", counts, …); the old code forced
// every pill's text to "Tweeted" and corrupted their reads. Gate on the pill's
// own text mentioning posts/tweets.
static BOOL BHPillTextIsNewContent(id text) {
    if (![text isKindOfClass:[NSString class]]) return NO;
    NSString *s = [(NSString *)text lowercaseString];
    return [s containsString:@"post"] || [s containsString:@"tweet"];
}

// MARK: Change Pill text, controlled by "refresh_pill_label"
%hook TFNPillControl

- (id)text {
    id origText = %orig;
    if (!BHPillLabelOverrideEnabled() || !BHPillTextIsNewContent(origText)) {
        // Setting off, or not the new-content pill: keep original behavior
        return origText;
    }

    NSString *localizedText = [[BHTBundle sharedBundle] localizedStringForKey:@"REFRESH_PILL_TEXT"];
    NSString *fallback = @"Tweeted";
    return localizedText ?: fallback;
}

- (void)setText:(id)arg1 {
    if (!BHPillLabelOverrideEnabled() || !BHPillTextIsNewContent(arg1)) {
        // Setting off, or not the new-content pill: pass through original argument
        return %orig(arg1);
    }

    NSString *localizedText = [[BHTBundle sharedBundle] localizedStringForKey:@"REFRESH_PILL_TEXT"];
    NSString *fallback = arg1 ?: @"Tweeted";
    %orig(localizedText ?: fallback);
}

%end

// Helper function to check if we're in the T1ConversationContainerViewController hierarchy
static BOOL BHT_isInConversationContainerHierarchy(UIViewController *viewController) {
    if (!viewController) return NO;

    // Check all view controllers up the hierarchy
    UIViewController *currentVC = viewController;
    while (currentVC) {
        NSString *className = NSStringFromClass([currentVC class]);

        // Check for T1ConversationContainerViewController
        if ([className isEqualToString:@"T1ConversationContainerViewController"]) {
            return YES;
        }

        // Move up the hierarchy
        if (currentVC.parentViewController) {
            currentVC = currentVC.parentViewController;
        } else if (currentVC.navigationController) {
            currentVC = currentVC.navigationController;
        } else if (currentVC.presentingViewController) {
            currentVC = currentVC.presentingViewController;
        } else {
            break;
        }
    }

    return NO;
}

// MARK : Remove "Discover More" section
%hook T1URTViewController

- (void)setSections:(NSArray *)sections {

    // Only filter if we're in the T1ConversationContainerViewController hierarchy
    BOOL inConversationHierarchy = BHT_isInConversationContainerHierarchy((UIViewController *)self);

    if (inConversationHierarchy) {
        // Remove entry 1 (index 1) from sections array
        if (sections.count > 1) {
            NSMutableArray *filteredSections = [NSMutableArray arrayWithArray:sections];
            [filteredSections removeObjectAtIndex:1];
            sections = [filteredSections copy];
        }
    }

    %orig(sections);
}

%end

%hook T1SuperFollowControl

- (id)initWithSizeClass:(long long)arg1 {
    id result = %orig;
    if ([BHTManager restoreFollowButton] && result) {
        [self setHidden:YES];
        [self setAlpha:0.0];
    }
    return result;
}

- (void)_t1_configureButton {
    %orig;
    if ([BHTManager restoreFollowButton]) {
        [self setHidden:YES];
        [self setAlpha:0.0];
        if (self.button) {
            [self.button setHidden:YES];
            [self.button setAlpha:0.0];
        }
    }
}
%end

// MARK : fix for super follower profiles.
%hook T1ProfileActionButtonsView

// Method that creates the overflow button
- (id)_t1_overflowButtonForItems:(id)arg1 {
    if ([BHTManager restoreFollowButton]) {
        return nil; // Return nil to prevent the overflow button from appearing
    }
    return %orig;
}

// Override the method that determines which buttons to show based on width
- (void)_t1_updateArrangedButtonItemsForContentWidth:(double)arg1 {
    if ([BHTManager restoreFollowButton]) {
        %orig(10000.0);
    } else {
        %orig(arg1);
    }
}

%end

static NSBundle *BHBundle() {
    return [NSBundle bundleWithIdentifier:@"com.bandarhelal.BHTwitter"];
}

// MARK: Theme TFNBarButtonItemButtonV1
%hook TFNBarButtonItemButtonV1

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        // Trigger our setTintColor logic
        self.tintColor = [UIColor blackColor];
    }
}

- (void)setTintColor:(UIColor *)tintColor {
    BOOL isDark = BHT_isTwitterDarkThemeActive();
    UIColor *correctColor = isDark ? [UIColor whiteColor] : [UIColor blackColor];
    %orig(correctColor);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig(previousTraitCollection);
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            // Trigger our setTintColor logic
            self.tintColor = [UIColor blackColor];
        }
    }
%end
