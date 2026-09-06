//
//  AuthViewController.m
//  BHTwitter
//
//  Created by BandarHelal on 25/09/2021.
//

#import "AuthViewController.h"
#import "Core/BHTBundle.h"
#import <LocalAuthentication/LocalAuthentication.h>

@implementation AuthViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    LAContext* context = [[LAContext alloc] init];

    if ([self canEvaluateBiometrics]) {
        [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
                localizedReason:[[BHTBundle sharedBundle]
                                    localizedStringForKey:@"PADLOCK_BIOMETRICS_REASON"]
                          reply:^(BOOL success, NSError* _Nullable error) {
                              [self finishWithResult:success error:error];
                          }];
    } else if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:nil]) {
        [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication
                localizedReason:[[BHTBundle sharedBundle]
                                    localizedStringForKey:@"PADLOCK_PASSCODE_REASON"]
                          reply:^(BOOL success, NSError* _Nullable error) {
                              [self finishWithResult:success error:error];
                          }];
    } else {
        [self finishWithResult:NO error:nil];
    }
}

- (void)finishWithResult:(BOOL)success error:(NSError*)error {
    if (error) {
        NSLog(@"%@", error);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (success) {
            [self dismissViewControllerAnimated:true
                                     completion:^{
                                         if (self.completion) self.completion(YES);
                                     }];
        } else {
            if (self.completion) self.completion(NO);
        }
    });
}

// Biometric prompts require NSFaceIDUsageDescription in the host app's Info.plist.
- (BOOL)canEvaluateBiometrics {
    return [[NSBundle mainBundle] infoDictionary][@"NSFaceIDUsageDescription"] != nil;
}

@end
