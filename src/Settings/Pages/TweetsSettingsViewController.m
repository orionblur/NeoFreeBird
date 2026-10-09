//
//  TweetsSettingsViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/TweetsSettingsViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Headers/TWHeaders.h"
#import "Settings/ModernSettingsCells.h"

static char kTweetSoundPickerPurposeKey;
static NSString* const kTweetSoundPickerPurpose = @"tweetSound";
static NSString* const kCustomSendSoundPathKey = @"custom_send_sound_path";
static NSString* const kCustomSendSoundNameKey = @"custom_send_sound_name";

@interface TweetsSettingsViewController () <UIDocumentPickerDelegate>
@end

@implementation TweetsSettingsViewController

- (NSString*)pageKey {
    return @"tweets";
}

- (void)showAlertWithTitleKey:(NSString*)titleKey message:(NSString*)message {
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:titleKey]
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle]
                                                        localizedStringForKey:@"OK_ACTION_LABEL"]
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    NSDictionary* settingData = self.visibleToggles[indexPath.row];
    if ([settingData[@"key"] isEqualToString:@"undo_tweet_timeout"]) {
        ModernSettingsCompactButtonCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell"
                                            forIndexPath:indexPath];
        NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:settingData[@"titleKey"]];
        [cell configureWithTitle:title subtitle:[self undoTimeoutSubtitle]];
        return cell;
    }
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}

// A timeout of 0 reads as "Off"; any positive value shows its seconds.
- (NSString*)labelForTimeout:(NSInteger)seconds {
    if (seconds <= 0) {
        return [[BHTBundle sharedBundle] localizedStringForKey:@"GENERIC_OFF_LABEL"];
    }
    NSString* format = [[BHTBundle sharedBundle]
        localizedStringForKey:@"SUBSCRIPTION_UNDO_SEND_DURATION_LABEL"];
    return [NSString stringWithFormat:format, (long)seconds];
}

- (NSString*)undoTimeoutSubtitle {
    return [self labelForTimeout:[BHTSettings integerForKey:@"undo_tweet_timeout"]];
}

- (void)importTweetSound:(NSDictionary*)sender {
    UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeAudio]
                            asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    objc_setAssociatedObject(picker, &kTweetSoundPickerPurposeKey,
                             kTweetSoundPickerPurpose,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)applyTweetSoundFromURL:(NSURL*)url {
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSError* playerError = nil;
    AVAudioPlayer* player = [[AVAudioPlayer alloc] initWithContentsOfURL:url
                                                                    error:&playerError];
    if (scoped) {
        [url stopAccessingSecurityScopedResource];
    }
    if (!player) {
        [self showAlertWithTitleKey:@"CUSTOM_SEND_SOUND_FAILED_TITLE"
                            message:playerError.localizedDescription];
        return;
    }
    if (player.duration > 7.0) {
        [self showAlertWithTitleKey:@"CUSTOM_SEND_SOUND_FAILED_TITLE"
                            message:[[BHTBundle sharedBundle]
                                        localizedStringForKey:@"CUSTOM_SEND_SOUND_TOO_LONG"]];
        return;
    }

    NSString* directoryPath = [NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSURL* directoryURL = [[NSURL fileURLWithPath:directoryPath isDirectory:YES]
        URLByAppendingPathComponent:@"NeoFreeBird" isDirectory:YES];
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSError* error = nil;
    if (![fileManager createDirectoryAtURL:directoryURL
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:&error]) {
        [self showAlertWithTitleKey:@"CUSTOM_SEND_SOUND_FAILED_TITLE"
                            message:error.localizedDescription];
        return;
    }

    NSString* extension = url.pathExtension.lowercaseString;
    NSString* fileName = extension.length > 0 ? [NSString stringWithFormat:@"%@.%@", url.lastPathComponent.stringByDeletingPathExtension, extension]
                                           : @"custom_send_sound";
    NSURL* destinationURL = [directoryURL URLByAppendingPathComponent:fileName];
    scoped = [url startAccessingSecurityScopedResource];
    NSURL* temporaryURL = [directoryURL URLByAppendingPathComponent:
        [NSString stringWithFormat:@".%@.tmp", NSUUID.UUID.UUIDString]];
    BOOL copied = [fileManager copyItemAtURL:url toURL:temporaryURL error:&error];
    if (scoped) {
        [url stopAccessingSecurityScopedResource];
    }
    if (!copied) {
        [self showAlertWithTitleKey:@"CUSTOM_SEND_SOUND_FAILED_TITLE"
                            message:error.localizedDescription];
        return;
    }

    [fileManager removeItemAtURL:destinationURL error:nil];
    if (![fileManager moveItemAtURL:temporaryURL toURL:destinationURL error:&error]) {
        [self showAlertWithTitleKey:@"CUSTOM_SEND_SOUND_FAILED_TITLE"
                            message:error.localizedDescription];
        return;
    }

    [[NSUserDefaults standardUserDefaults] setObject:destinationURL.path
                                               forKey:kCustomSendSoundPathKey];
    [[NSUserDefaults standardUserDefaults] setObject:fileName
                                               forKey:kCustomSendSoundNameKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self.tableView reloadData];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller
    didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
    NSString* purpose = objc_getAssociatedObject(controller, &kTweetSoundPickerPurposeKey);
    if (![purpose isEqualToString:kTweetSoundPickerPurpose] || urls.firstObject == nil) {
        return;
    }
    [self applyTweetSoundFromURL:urls.firstObject];
}

// Off plus the same durations Twitter offers in its own premium undo settings.
- (void)showUndoTimeoutPicker:(NSDictionary*)sender {
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"UNDO_TWEET_TITLE"]
                         message:nil
                  preferredStyle:UIAlertControllerStyleAlert];

    for (NSNumber* seconds in @[@0, @5, @10, @20, @30, @60]) {
        [alert addAction:[UIAlertAction actionWithTitle:[self labelForTimeout:seconds.integerValue]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction* action) {
                                                    [[NSUserDefaults standardUserDefaults]
                                                        setInteger:seconds.integerValue
                                                            forKey:@"undo_tweet_timeout"];
                                                    [self.tableView reloadData];
                                                }]];
    }

    [alert addAction:[UIAlertAction
                         actionWithTitle:[[BHTBundle sharedBundle]
                                             localizedStringForKey:@"CANCEL_ACTION_LABEL"]
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
