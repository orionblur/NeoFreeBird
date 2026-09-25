//
//  Ads.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// Timeline items are removed from the section data before it reaches the data
// view controller, so no empty cells or gaps are left behind. This covers every
// timeline surface (home, profile, search, conversations) regardless of whether
// it renders through a table view or the newer diffable collection view path.

// The promoted state of a status item is only reachable through its Swift-side
// `status` stored property, which is still registered as an ObjC ivar.
static BOOL StatusItemIsPromoted(id item) {
    Ivar statusIvar = class_getInstanceVariable([item class], "status");
    if (!statusIvar) {
        return NO;
    }

    TFNTwitterStatus* status = object_getIvar(item, statusIvar);
    return [status respondsToSelector:@selector(isPromoted)] && status.isPromoted;
}

// Promoted trends and event summary heroes (the image ads at the top of
// explore) carry their promotion in the Swift-side `promotedContent` stored
// property, which isn't always reflected in the scribe item.
static BOOL ItemHasPromotedContent(id item) {
    Ivar promotedIvar =
        class_getInstanceVariable([item class], "promotedContent");
    return promotedIvar && object_getIvar(item, promotedIvar) != nil;
}

static BOOL ScribeItemIsPromoted(id item) {
    if (![item respondsToSelector:@selector(scribeItem)]) {
        return NO;
    }

    NSDictionary* scribeItem = [item performSelector:@selector(scribeItem)];
    return [scribeItem isKindOfClass:[NSDictionary class]] &&
           scribeItem[@"promoted_id"] != nil;
}

static BOOL ShouldHideItem(id item, NSString* location) {
    item = unwrapDataViewItem(item);
    NSString* className = NSStringFromClass([item classForCoder]);

    if ([BHTSettings boolForKey:@"hide_promoted"]) {
        if ([item
                isKindOfClass:objc_getClass("T1URTTimelineStatusItemViewModel")] &&
            StatusItemIsPromoted(item)) {
            return YES;
        }

        if ([className
                isEqualToString:@"TwitterURT.URTTimelineGoogleNativeAdViewModel"]) {
            return YES;
        }

        if (([className isEqualToString:@"TwitterURT.URTTimelineTrendViewModel"] ||
             [className
                 isEqualToString:@"TwitterURT.URTTimelineEventSummaryViewModel"]) &&
            (ScribeItemIsPromoted(item) || ItemHasPromotedContent(item))) {
            return YES;
        }
    }

    if ([BHTSettings boolForKey:@"hide_premium_offer"]) {
        if ([className
                isEqualToString:@"TwitterURT.URTTimelineMessageItemViewModel"]) {
            return YES;
        }
    }

    if ([BHTSettings boolForKey:@"hide_trend_videos"] &&
        [location isEqualToString:@"OTHER"]) {
        if ([className
                isEqualToString:@"T1TwitterSwift.URTTimelineCarouselViewModel"]) {
            return YES;
        }
    }

    return NO;
}

static NSArray* FilteredSections(TFNItemsDataViewController* dataViewController,
                                 NSArray* sections) {
    if (!([BHTSettings boolForKey:@"hide_promoted"] ||
          [BHTSettings boolForKey:@"hide_premium_offer"] ||
          [BHTSettings boolForKey:@"hide_trend_videos"])) {
        return sections;
    }

    NSString* location =
        [dataViewController respondsToSelector:@selector(adDisplayLocation)]
            ? dataViewController.adDisplayLocation
            : nil;

    BOOL modified = NO;
    NSMutableArray* filteredSections =
        [NSMutableArray arrayWithCapacity:sections.count];

    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            [filteredSections addObject:section];
            continue;
        }

        NSArray* items = section;
        NSUInteger count = items.count;
        NSMutableIndexSet* removed = [NSMutableIndexSet indexSet];

        for (NSUInteger i = 0; i < count; i++) {
            if (ShouldHideItem(items[i], location)) {
                [removed addIndex:i];
            }
        }

        if (removed.count == 0) {
            [filteredSections addObject:section];
            continue;
        }

        MarkEmptiedModuleChrome(items, removed);

        NSMutableArray* keptItems = [items mutableCopy];
        [keptItems removeObjectsAtIndexes:removed];
        modified = YES;

        if (keptItems.count > 0) {
            [filteredSections addObject:keptItems];
        }
    }

    return modified ? filteredSections : sections;
}

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections
    restoreScrollPosition:(BOOL)restoreScrollPosition {
    %orig(FilteredSections(self, sections), restoreScrollPosition);
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    %orig(FilteredSections(self, sections), identifiers, animation,
              completion);
}

%end

%hook TFNTwitterStatus

- (_Bool)isCardHidden {
    return ([BHTSettings boolForKey:@"hide_promoted"] && [self isPromoted])
               ? true
               : %orig;
}

%end

// MARK: - Immersive video feed

// The vertical video feed keeps its own card list and never goes through
// TFNItemsDataViewController, so promoted cards are dropped from that list
// before they become pages.

static BOOL ImmersiveCardIsPromoted(id card) {
    if ([card isKindOfClass:objc_getClass("_TtC14T1TwitterSwift36ImmersiveGoogleNativeAdCardViewModel")]) {
        return YES;
    }

    Ivar itemIvar =
        class_getInstanceVariable([card class], "statusItemViewModel");
    return itemIvar && StatusItemIsPromoted(object_getIvar(card, itemIvar));
}

// The coordinator's `items` is a Swift [ImmersiveCardViewModelProtocol]. Its
// buffer has the count at +16 and the elements from +32, two words each: the
// card and its protocol witness table.
static void RemovePromotedImmersiveCards(id viewController) {
    if (!viewController || ![BHTSettings boolForKey:@"hide_promoted"]) {
        return;
    }

    Ivar coordinatorIvar =
        class_getInstanceVariable([viewController class], "timelineCoordinator");
    id coordinator =
        coordinatorIvar ? object_getIvar(viewController, coordinatorIvar) : nil;
    Ivar itemsIvar = class_getInstanceVariable([coordinator class], "items");
    if (!itemsIvar) {
        return;
    }

    uint8_t* buffer = *(uint8_t**)((uint8_t*)(__bridge void*)coordinator +
                                   ivar_getOffset(itemsIvar));
    int64_t* count = (int64_t*)(buffer + 16);
    void** elements = (void**)(buffer + 32);

    int64_t first = 0;
    while (first < *count &&
           !ImmersiveCardIsPromoted((__bridge id)elements[first * 2])) {
        first++;
    }
    if (first == *count) {
        return;
    }

    static bool (*isUniquelyReferenced)(const void*);
    static void (*unknownObjectRelease)(void*);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        isUniquelyReferenced =
            dlsym(RTLD_DEFAULT, "swift_isUniquelyReferenced_nonNull_native");
        unknownObjectRelease = dlsym(RTLD_DEFAULT, "swift_unknownObjectRelease");
    });

    // Editing a buffer that another array still shares would change that
    // array too.
    if (!isUniquelyReferenced || !unknownObjectRelease ||
        !isUniquelyReferenced(buffer)) {
        return;
    }

    int64_t kept = first;
    for (int64_t i = first; i < *count; i++) {
        void* card = elements[i * 2];
        if (ImmersiveCardIsPromoted((__bridge id)card)) {
            unknownObjectRelease(card);
            continue;
        }

        elements[kept * 2] = card;
        elements[kept * 2 + 1] = elements[i * 2 + 1];
        kept++;
    }
    *count = kept;
}

%hook T1ImmersiveViewController

- (void)viewWillLayoutSubviews {
    RemovePromotedImmersiveCards(self);
    %orig;
}

%end
