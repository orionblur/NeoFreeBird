//
//  BHDownloadInlineButton.m
//  NeoFreeBird
//
//  Original author: BandarHelal at 09/04/2022
//  Modified by: actuallyaridan at 27/04/2025
//

#import "BHDownloadInlineButton.h"
#import <objc/runtime.h>
#import "BHTBundle/BHTBundle.h"

#pragma mark - Helpers
static inline UIViewController *BHTopMostController(void) {
    UIViewController *top = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

#pragma mark - BHDownloadInlineButton
@interface BHDownloadInlineButton () <BHDownloadDelegate>
@property (nonatomic, strong) JGProgressHUD *hud;
@property (nonatomic, assign) BOOL bht_isGIFDownload;
@end

@implementation BHDownloadInlineButton

- (void)bht_presentDownloadFailureAlertWithMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.hud dismiss];

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"ERROR_TITLE"]
                                                                       message:message ?: [[BHTBundle sharedBundle] localizedStringForKey:@"UNKNOWN_ERROR"]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"OK_BUTTON"]
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [BHTopMostController() presentViewController:alert animated:YES completion:nil];

        if (@available(iOS 10.0, *)) {
            UINotificationFeedbackGenerator *g = [UINotificationFeedbackGenerator new];
            [g prepare];
            [g notificationOccurred:UINotificationFeedbackTypeError];
        }
    });
}

#pragma mark ••• Download handler
- (void)presentDownloadOptionsForMediaEntities:(NSArray *)mediaEntities {
    @try {
        self.bht_isGIFDownload = NO;

        NSAttributedString *titleString = [[NSAttributedString alloc] initWithString:[[BHTBundle sharedBundle] localizedStringForKey:@"DOWNLOAD_MENU_TITLE"]
                                                                         attributes:@{ NSFontAttributeName : [BHTManager menuTitleFont],
                                                                                       NSForegroundColorAttributeName : UIColor.labelColor }];
        TFNActiveTextItem *title = [[objc_getClass("TFNActiveTextItem") alloc] initWithTextModel:[[objc_getClass("TFNAttributedTextModel") alloc] initWithAttributedString:titleString] activeRanges:nil];

        NSMutableArray *actions      = [NSMutableArray arrayWithObject:title];
        NSMutableArray *innerActions = [NSMutableArray arrayWithObject:title];

        // HUD helpers
        void (^startHUD)(NSString *) = ^(NSString *key) {
            if ([BHTManager DirectSave]) return;
            self.hud = [JGProgressHUD progressHUDWithStyle:JGProgressHUDStyleDark];
            self.hud.textLabel.text = [[BHTBundle sharedBundle] localizedStringForKey:key];
            [self.hud showInView:BHTopMostController().view];
        };
        void (^dismissHUD)(void) = ^{ [self.hud dismiss]; };

        // Variant builders
        TFNActionItem* (^makeMP4Item)(NSURL *, BOOL) = ^TFNActionItem*(NSURL *url, BOOL isGIF) {
            NSString *title = isGIF ? @"GIF" : [BHTManager getVideoQuality:url.absoluteString];
            return [objc_getClass("TFNActionItem") actionItemWithTitle:title
                                                               imageName:@"arrow_down_circle_stroke" action:^{
                self.bht_isGIFDownload = isGIF;
                BHDownload *dwManager = [[BHDownload alloc] init];
                [dwManager setDelegate:self];
                [dwManager downloadFileWithURL:url];
                startHUD(@"PROGRESS_DOWNLOADING_STATUS_TITLE");
            }];
        };

        TFNActionItem* (^makeM3U8Item)(NSURL *, BOOL) = ^TFNActionItem*(NSURL *url, BOOL isGIF) {
            return [objc_getClass("TFNActionItem") actionItemWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"FFMPEG_DOWNLOAD_OPTION_TITLE"]
                                                               imageName:@"arrow_down_circle_stroke" action:^{
                self.bht_isGIFDownload = isGIF;
                startHUD(@"FETCHING_PROGRESS_TITLE");
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                    MediaInformation *info = [BHTManager getM3U8Information:url];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        dismissHUD();
                        TFNMenuSheetViewController *sheet = [BHTManager newFFmpegDownloadSheet:info downloadingURL:url progressView:self.hud];
                        [sheet tfnPresentedCustomPresentFromViewController:BHTopMostController() animated:YES completion:nil];
                    });
                });
            }];
        };

        // Media enumeration
        if (mediaEntities.count > 1) {
            [mediaEntities enumerateObjectsUsingBlock:^(TFSTwitterEntityMedia *obj, NSUInteger idx, BOOL *stop) {
                BOOL isGIF = (obj.mediaType == 2);
                if (obj.mediaType == 2 || obj.mediaType == 3) {
                    NSString *groupTitle = isGIF ? @"GIF" : [NSString stringWithFormat:@"Video %lu", (unsigned long)idx + 1];
                    TFNActionItem *videoGroup = [objc_getClass("TFNActionItem") actionItemWithTitle:groupTitle
                                                                                       imageName:@"arrow_down_circle_stroke" action:^{
                        for (TFSTwitterEntityMediaVideoVariant *variant in obj.videoInfo.variants) {
                            if ([variant.contentType isEqualToString:@"video/mp4"])          [innerActions addObject:makeMP4Item([NSURL URLWithString:variant.url], isGIF)];
                            if ([variant.contentType isEqualToString:@"application/x-mpegURL"]) [innerActions addObject:makeM3U8Item([NSURL URLWithString:variant.url], isGIF)];
                        }
                        TFNMenuSheetViewController *inner = [[objc_getClass("TFNMenuSheetViewController") alloc] initWithActionItems:innerActions.copy];
                        [inner tfnPresentedCustomPresentFromViewController:BHTopMostController() animated:YES completion:nil];
                    }];
                    [actions addObject:videoGroup];
                }
            }];
        } else if (mediaEntities.firstObject) {
            TFSTwitterEntityMedia *first = mediaEntities.firstObject;
            BOOL isGIF = (first.mediaType == 2);
            for (TFSTwitterEntityMediaVideoVariant *variant in first.videoInfo.variants) {
                if ([variant.contentType isEqualToString:@"video/mp4"])          [actions addObject:makeMP4Item([NSURL URLWithString:variant.url], isGIF)];
                if ([variant.contentType isEqualToString:@"application/x-mpegURL"]) [actions addObject:makeM3U8Item([NSURL URLWithString:variant.url], isGIF)];
            }
        }

        TFNMenuSheetViewController *sheet = [[objc_getClass("TFNMenuSheetViewController") alloc] initWithActionItems:actions.copy];
        [sheet tfnPresentedCustomPresentFromViewController:BHTopMostController() animated:YES completion:nil];
    } @catch (__unused NSException *ex) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"ERROR_TITLE"]
                                                                       message:[[BHTBundle sharedBundle] localizedStringForKey:@"UNKNOWN_ERROR"]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"OK_BUTTON"] style:UIAlertActionStyleDefault handler:nil]];
        [BHTopMostController() presentViewController:alert animated:YES completion:nil];
    }
}

#pragma mark ••• BHDownloadDelegate
- (void)downloadProgress:(float)pct {
    self.hud.detailTextLabel.text = [BHTManager getDownloadingPersent:pct];
}

- (void)downloadDidFinish:(NSURL *)tmpURL Filename:(NSString *)name {
    NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSURL *dst = [[NSURL fileURLWithPath:doc]
                  URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", NSUUID.UUID.UUIDString, self.bht_isGIFDownload ? @"gif" : @"mp4"]];

    if (!self.bht_isGIFDownload) {
        NSError *copyError = nil;
        [[NSFileManager defaultManager] copyItemAtURL:tmpURL toURL:dst error:&copyError];
        if (copyError) {
            [self bht_presentDownloadFailureAlertWithMessage:copyError.localizedDescription];
            return;
        }

        if (![BHTManager DirectSave]) {
            [self.hud dismiss];
            [BHTManager showSaveVC:dst];
        } else {
            [BHTManager save:dst];
        }
        return;
    }

    // URLSession only guarantees tmpURL exists for the duration of this delegate
    // callback; it deletes it as soon as we return. FFmpegKit's executor runs
    // asynchronously on a later run-loop turn, so we must stage the file at a
    // stable path first, or ffmpeg finds nothing at -i.
    NSURL *stagedInput = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                          URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4", NSUUID.UUID.UUIDString]];
    NSError *stageError = nil;
    [[NSFileManager defaultManager] copyItemAtURL:tmpURL toURL:stagedInput error:&stageError];
    if (stageError) {
        [self bht_presentDownloadFailureAlertWithMessage:stageError.localizedDescription];
        return;
    }

    self.hud.textLabel.text = @"Converting GIF";
    NSString *inputPath = stagedInput.path;
    NSString *outputPath = dst.path;
    NSString *command = [NSString stringWithFormat:@"-y -i \"%@\" -filter_complex \"[0:v]fps=15,scale=trunc(iw/2)*2:trunc(ih/2)*2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse=dither=bayer:bayer_scale=5\" -loop 0 \"%@\"", inputPath, outputPath];

    [FFmpegKit executeAsync:command withCompleteCallback:^(FFmpegSession *session) {
        ReturnCode *returnCode = [session getReturnCode];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSFileManager defaultManager] removeItemAtURL:stagedInput error:nil];
            BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:dst.path];
            if ([ReturnCode isSuccess:returnCode] && exists) {
                [self.hud dismiss];
                if ([BHTManager DirectSave]) {
                    [BHTManager save:dst];
                } else {
                    [BHTManager showSaveVC:dst];
                }
            } else {
                [self bht_presentDownloadFailureAlertWithMessage:@"GIF conversion failed. Please try again."];
            }
        });
    }];
}

- (void)downloadDidFailureWithError:(NSError *)error {
    NSLog(@"BHDownload failed: %@", error);
    NSLog(@"Domain: %@ Code: %ld UserInfo: %@",
          error.domain,
          (long)error.code,
          error.userInfo);

    NSString *errorMessage = [NSString stringWithFormat:@"Error Code: %ld\nDescription: %@", (long)error.code, error.localizedDescription];

    [self bht_presentDownloadFailureAlertWithMessage:errorMessage];
}

@end
