/**
 * Modified MIT License
 *
 * Copyright 2018 Kontext
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * 1. The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * 2. All copies of substantial portions of the Software may only be used in connection
 * with services provided by Kontext.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import <XCTest/XCTest.h>

#import <objc/runtime.h>

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>
#import <UserNotifications/UserNotifications.h>


#import "UncaughtExceptionHandler.h"


#import "Kontext.h"

#import "KontextHelper.h"
#import "KontextTracker.h"
#import "KontextSelectorHelpers.h"
#import "NSString+Kontext.h"
#import "UIApplicationDelegate+Kontext.h"
#import "UNUserNotificationCenter+Kontext.h"
#import "KontextNotificationSettingsIOS10.h"
#import "KontextPermission.h"
#import "KontextNotificationPayload+Internal.h"

#include <pthread.h>
#include <mach/mach.h>

#include "TestHelperFunctions.h"

#import "UnitTestAppDelegate.h"

// Shadows
#import "NSObjectOverrider.h"
#import "NSUserDefaultsOverrider.h"
#import "NSDateOverrider.h"
#import "NSBundleOverrider.h"
#import "UNUserNotificationCenterOverrider.h"
#import "UIApplicationOverrider.h"
#import "KontextHelperOverrider.h"
#import "NSLocaleOverrider.h"
#import "UIAlertViewOverrider.h"
#import "KontextTrackFirebaseAnalyticsOverrider.h"
#import "KontextClientOverrider.h"

// Networking
#import "KontextClient.h"
#import "Requests.h"
#import "KontextClientOverrider.h"

@interface Kontext (UN_extra)
+ (dispatch_queue_t) getRegisterQueue;
@end

// START - Start Observers

@interface KontextPermissionStateTestObserver : NSObject<KontextPermissionObserver>
@end

@implementation KontextPermissionStateTestObserver {
    @package KontextPermissionStateChanges* last;
    @package int fireCount;
}

- (void)onKontextPermissionChanged:(KontextPermissionStateChanges*)stateChanges {
    NSLog(@"UnitTest:onKontextPermissionChanged :\n%@", stateChanges);
    last = stateChanges;
    fireCount++;
}
@end


@interface KontextSubscriptionStateTestObserver : NSObject<KontextSubscriptionObserver>
@end

@implementation KontextSubscriptionStateTestObserver {
    @package KontextSubscriptionStateChanges* last;
    @package int fireCount;
}
- (void)onKontextSubscriptionChanged:(KontextSubscriptionStateChanges*)stateChanges {
    NSLog(@"UnitTest:onKontextSubscriptionChanged:\n%@", stateChanges);
    last = stateChanges;
    fireCount++;
}
@end

// END - Observers


@interface UnitTests : XCTestCase
@end

@implementation UnitTests

- (void)beforeAllTest {
    static var setupUIApplicationDelegate = false;
    if (setupUIApplicationDelegate)
        return;
    
    // Normally this just loops internally, overwrote _run to work around this.
    UIApplicationMain(0, nil, nil, NSStringFromClass([UnitTestAppDelegate class]));
    
    setupUIApplicationDelegate = true;
    
    // InstallUncaughtExceptionHandler();
    
    // Force swizzle in all methods for tests.
    KontextHelperOverrider.mockIOSVersion = 8;
    [KontextAppDelegate sizzlePreiOS10MethodsPhase1];
    [KontextAppDelegate sizzlePreiOS10MethodsPhase2];
    KontextHelperOverrider.mockIOSVersion = 10;
}

- (void)clearStateForAppRestart {
    NSLog(@"=======  APP RESTART ======\n\n");
    
    NSDateOverrider.timeOffset = 0;
    [KontextClientOverrider reset:self];
    [UNUserNotificationCenterOverrider reset:self];
    [UIApplicationOverrider reset];
    [KontextTrackFirebaseAnalyticsOverrider reset];
    
    NSLocaleOverrider.preferredLanguagesArray = @[@"en-US"];

    [KontextHelper performSelector:NSSelectorFromString(@"resetLocals")];
    
    [Kontext setValue:nil forKeyPath:@"lastAppActiveMessageId"];
    [Kontext setValue:nil forKeyPath:@"lastnonActiveMessageId"];
    [Kontext setValue:@0 forKeyPath:@"mSubscriptionStatus"];
    
    [KontextTracker performSelector:NSSelectorFromString(@"resetLocals")];
    
    [NSObjectOverrider reset];
    
    [Kontext performSelector:NSSelectorFromString(@"clearStatics")];
    
    [UIAlertViewOverrider reset];
    
    [Kontext setLogLevel:KON_TEXT_LL_VERBOSE visualLevel:KON_TEXT_LL_NONE];
}

// Called before each test.
- (void)setUp {
    [super setUp];
    
    KontextHelperOverrider.mockIOSVersion = 10;
    
    [KontextUNUserNotificationCenter setUseiOS10_2_workaround:true];
    
    UNUserNotificationCenterOverrider.notifTypesOverride = 7;
    UNUserNotificationCenterOverrider.authorizationStatus = [NSNumber numberWithInteger:UNAuthorizationStatusAuthorized];
    
    NSBundleOverrider.nsbundleDictionary = @{@"UIBackgroundModes": @[@"remote-notification"]};
    
    [NSUserDefaultsOverrider clearInternalDictionary];
    
    [self clearStateForAppRestart];

    [self beforeAllTest];
    
    // Uncomment to simulate slow travis-CI runs.
    /*float minRange = 0, maxRange = 15;
    float random = ((float)arc4random() / 0x100000000 * (maxRange - minRange)) + minRange;
    NSLog(@"Sleeping for debugging: %f", random);
    [NSThread sleepForTimeInterval:random];*/
}

// Called after each test.
- (void)tearDown {
    [super tearDown];
    [self runBackgroundThreads];
}

- (void)backgroundModesDisabledInXcode {
    NSBundleOverrider.nsbundleDictionary = @{};
}

- (void)setCurrentNotificationPermissionAsUnanswered {
    UNUserNotificationCenterOverrider.notifTypesOverride = 0;
    UNUserNotificationCenterOverrider.authorizationStatus = [NSNumber numberWithInteger:UNAuthorizationStatusNotDetermined];
}

- (void)setCurrentNotificationPermission:(BOOL)accepted {
    if (accepted) {
        UNUserNotificationCenterOverrider.notifTypesOverride = 7;
        UNUserNotificationCenterOverrider.authorizationStatus = [NSNumber numberWithInteger:UNAuthorizationStatusAuthorized];
    }
    else {
        UNUserNotificationCenterOverrider.notifTypesOverride = 0;
        UNUserNotificationCenterOverrider.authorizationStatus = [NSNumber numberWithInteger:UNAuthorizationStatusDenied];
    }
}

- (void)registerForPushNotifications {
    [Kontext registerForPushNotifications];
    [self backgroundApp];
}

- (void)answerNotifiationPrompt:(BOOL)accept {
    // iOS 10.2.1 Real device obserserved sequence of events:
    //   1. Call requestAuthorizationWithOptions to prompt for notifications.
    ///  2. App goes out of focus when the prompt is shown.
    //   3. User press ACCPET! and focus event fires.
    //   4. *(iOS bug?)* We check permission with currentNotificationCenter.getNotificationSettingsWithCompletionHandler and it show up as UNAuthorizationStatusDenied!?!?!
    //   5. Callback passed to getNotificationSettingsWithCompletionHandler then fires with Accpeted as TRUE.
    //   6. Check getNotificationSettingsWithCompletionHandler and it is then correctly reporting UNAuthorizationStatusAuthorized
    //   7. Note: If remote notification background modes are on then application:didRegisterForRemoteNotificationsWithDeviceToken: will fire after #5 on it's own.
    BOOL triggerDidRegisterForRemoteNotfications = (UNUserNotificationCenterOverrider.authorizationStatus == [NSNumber numberWithInteger:UNAuthorizationStatusNotDetermined] && accept);
    if (triggerDidRegisterForRemoteNotfications)
        [self setCurrentNotificationPermission:false];
    
    [self resumeApp];
    [self setCurrentNotificationPermission:accept];
    
    if (triggerDidRegisterForRemoteNotfications && NSBundleOverrider.nsbundleDictionary[@"UIBackgroundModes"])
        [UIApplicationOverrider helperCallDidRegisterForRemoteNotificationsWithDeviceToken];
    
    if (KontextHelperOverrider.mockIOSVersion > 9)
        [UNUserNotificationCenterOverrider fireLastRequestAuthorizationWithGranted:accept];
    else if (KontextHelperOverrider.mockIOSVersion > 7) {
        UIApplication *sharedApp = [UIApplication sharedApplication];
        [sharedApp.delegate application:sharedApp didRegisterUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:UNUserNotificationCenterOverrider.notifTypesOverride categories:nil]];
    }
    else // iOS 7 - Only support accepted for now.
        [UIApplicationOverrider helperCallDidRegisterForRemoteNotificationsWithDeviceToken];
}

- (void)backgroundApp {
    UIApplicationOverrider.currentUIApplicationState = UIApplicationStateBackground;
    UIApplication *sharedApp = [UIApplication sharedApplication];
    [sharedApp.delegate applicationWillResignActive:sharedApp];
}

- (void)resumeApp {
    UIApplicationOverrider.currentUIApplicationState = UIApplicationStateActive;
    UIApplication *sharedApp = [UIApplication sharedApplication];
    [sharedApp.delegate applicationDidBecomeActive:sharedApp];
}

// Runs any blocks passed to dispatch_async()
- (void)runBackgroundThreads {
    NSLog(@"START runBackgroundThreads");
    
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    
    dispatch_queue_t registerUserQueue, notifSettingsQueue;
    for(int i = 0; i < 10; i++) {
        [KontextHelperOverrider runBackgroundThreads];
        
        notifSettingsQueue = [KontextNotificationSettingsIOS10 getQueue];
        if (notifSettingsQueue)
            dispatch_sync(notifSettingsQueue, ^{});
        
        registerUserQueue = [Kontext getRegisterQueue];
        if (registerUserQueue)
            dispatch_sync(registerUserQueue, ^{});
        
        [UNUserNotificationCenterOverrider runBackgroundThreads];
        
        dispatch_barrier_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{});
        
        [UIApplicationOverrider runBackgroundThreads];
    }
    
    NSLog(@"END runBackgroundThreads");
}

- (UNNotificationResponse*)createBasiciKontextNotificationResponseWithPayload:(NSDictionary*)userInfo {
    // Mocking an iOS 10 notification
    // Setting response.notification.request.content.userInfo
    UNNotificationResponse *notifResponse = [UNNotificationResponse alloc];
    
    // Normal tap on notification
    [notifResponse setValue:@"com.apple.UNNotificationDefaultActionIdentifier" forKeyPath:@"actionIdentifier"];
    
    UNNotificationContent *unNotifContent = [UNNotificationContent alloc];
    UNNotification *unNotif = [UNNotification alloc];
    UNNotificationRequest *unNotifRequqest = [UNNotificationRequest alloc];
    // Set as remote push type
    [unNotifRequqest setValue:[UNPushNotificationTrigger alloc] forKey:@"trigger"];
    
    [unNotif setValue:unNotifRequqest forKeyPath:@"request"];
    [notifResponse setValue:unNotif forKeyPath:@"notification"];
    [unNotifRequqest setValue:unNotifContent forKeyPath:@"content"];
    [unNotifContent setValue:userInfo forKey:@"userInfo"];
    
    return notifResponse;
}
                                                                          
- (UNNotificationResponse*)createBasiciKontextNotificationResponse {
  id userInfo = @{@"custom":
                      @{@"i": @"b2f7f966-d8cc-11e4-bed1-df8f05be55bb"}
                  };
  
  return [self createBasiciKontextNotificationResponseWithPayload:userInfo];
}

// Helper used to simpify tests below.
- (void)initKontext {
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"];
    
    // iOS fires the resume event when app is cold started.
    [self resumeApp];
}

-(void)initKontextAndThreadWait {
    [self initKontext];
    [self runBackgroundThreads];
}

- (void)testBasicInitTest {
    NSLog(@"iOS VERSION: %@", [[UIDevice currentDevice] systemVersion]);
    
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        [self initKontext];
        [self runBackgroundThreads];
        
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"app_id"], @"b2f7f966-d8cc-11e4-bed1-df8f05be55ba");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"identifier"], @"0000000000000000000000000000000000000000000000000000000000000000");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"notification_types"], @15);
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"device_model"], @"x86_64");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"device_type"], @0);
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"language"], @"en-US");
        
        KontextPermissionSubscriptionState* status = [Kontext getPermissionSubscriptionState];
        XCTAssertTrue(status.permissionStatus.accepted);
        XCTAssertTrue(status.permissionStatus.hasPrompted);
        XCTAssertTrue(status.permissionStatus.answeredPrompt);
        
        XCTAssertEqual(status.subscriptionStatus.subscribed, true);
        XCTAssertEqual(status.subscriptionStatus.userSubscriptionSetting, true);
        XCTAssertEqual(status.subscriptionStatus.userId, @"1234");
        XCTAssertEqualObjects(status.subscriptionStatus.pushToken, @"0000000000000000000000000000000000000000000000000000000000000000");
        
        // 2nd init call should not fire another on_session call.
        KontextClientOverrider.lastHTTPRequest = nil;
        [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"];
        XCTAssertNil(KontextClientOverrider.lastHTTPRequest);
        
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 1);
    }
}

- (void)testVersionStringLength {
	XCTAssertEqual(KONTEXT_VERSION.length, 6, @"KONTEXT_VERSION length is not 6: length is %lu", (unsigned long)KONTEXT_VERSION.length);
	XCTAssertEqual([Kontext sdk_version_raw].length, 6, @"Kontext sdk_version_raw length is not 6: length is %lu", (unsigned long)[Kontext sdk_version_raw].length);
}

- (void)testSymanticVersioning {
	NSDictionary *versions = @{@"011303" : @"1.13.3",
                               @"020000" : @"2.0.0",
                               @"020116" : @"2.1.16",
                               @"020400" : @"2.4.0",
                               @"000400" : @"0.4.0",
                               @"000000" : @"0.0.0"};

	[versions enumerateKeysAndObjectsUsingBlock:^(NSString* raw, NSString* semantic, BOOL* stop) {
		XCTAssertEqualObjects([raw one_getSemanticVersion], semantic, @"Strings are not equal %@ %@", semantic, [raw one_getSemanticVersion] );
	}];

	NSDictionary *versionsThatFail = @{ @"011001" : @"1.0.1",
                                        @"011086" : @"1.10.6",
                                        @"011140" : @"1.11.0",
                                        @"011106" : @"1.11.1",
                                        @"091103" : @"1.11.3"};

	[versionsThatFail enumerateKeysAndObjectsUsingBlock:^(NSString* raw, NSString* semantic, BOOL* stop) {
		XCTAssertNotEqualObjects([raw one_getSemanticVersion], semantic, @"Strings are equal %@ %@", semantic, [raw one_getSemanticVersion] );
	}];

}

- (void)testRegisterationOniOS7 {
    
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        KontextHelperOverrider.mockIOSVersion = 7;
        
        [self initKontextAndThreadWait];
        
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"app_id"], @"b2f7f966-d8cc-11e4-bed1-df8f05be55ba");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"identifier"], @"0000000000000000000000000000000000000000000000000000000000000000");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"notification_types"], @7);
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"device_model"], @"x86_64");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"device_type"], @0);
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"language"], @"en-US");
        
        // 2nd init call should not fire another on_session call.
        KontextClientOverrider.lastHTTPRequest = nil;
        [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"];
        XCTAssertNil(KontextClientOverrider.lastHTTPRequest);
        
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 1);
        
        // Make the following methods were not called as they are not available on iOS 7
        XCTAssertFalse(UIApplicationOverrider.calledRegisterForRemoteNotifications);
        XCTAssertFalse(UIApplicationOverrider.calledCurrentUserNotificationSettings);
    }
    
}

// Test exists since we've seen a few rare crash reports where
//   [NSLocale preferredLanguages] resturns an empty array
- (void)testInitWithEmptyPreferredLanguages {
    NSLocaleOverrider.preferredLanguagesArray = @[];
    [self initKontextAndThreadWait];
}

- (void)testInitOnSimulator {
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        [self setCurrentNotificationPermissionAsUnanswered];
        [self backgroundModesDisabledInXcode];
        UIApplicationOverrider.didFailRegistarationErrorCode = 3010;
        
        [self initKontextAndThreadWait];
        
        [self answerNotifiationPrompt:true];
        [self runBackgroundThreads];
        
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"app_id"], @"b2f7f966-d8cc-11e4-bed1-df8f05be55ba");
        XCTAssertNil(KontextClientOverrider.lastHTTPRequest[@"identifier"]);
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"notification_types"], @-15);
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"device_model"], @"x86_64");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"device_type"], @0);
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"language"], @"en-US");
        
        // 2nd init call should not fire another on_session call.
        KontextClientOverrider.lastHTTPRequest = nil;
        [self initKontextAndThreadWait];
        XCTAssertNil(KontextClientOverrider.lastHTTPRequest);
        
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 1);
    }
}


- (void)testFocusSettingsOnInit {
    // Test old kKontextSettingsKeyInFocusDisplayOption
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
            handleNotificationAction:nil
                            settings:@{kKontextSettingsKeyInFocusDisplayOption: @(KontextNotificationDisplayTypeNone)}];
    
    XCTAssertEqual(Kontext.inFocusDisplayType, KontextNotificationDisplayTypeNone);
    
    [self clearStateForAppRestart];

    // Test old very old kKontextSettingsKeyInAppAlerts
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
            handleNotificationAction:nil
                            settings:@{kKontextSettingsKeyInAppAlerts: @(false)}];
    XCTAssertEqual(Kontext.inFocusDisplayType, KontextNotificationDisplayTypeNone);
}

- (void)testCallingMethodsBeforeInit {
    
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        [self setCurrentNotificationPermission:true];
        
        [Kontext sendEvent:@"key" value:@"value"];
        [Kontext setSubscription:true];
        [Kontext promptLocation];
        [Kontext promptForPushNotificationsWithUserResponse:nil];
        [self runBackgroundThreads];
        
        [self initKontextAndThreadWait];
        
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"app_id"], @"b2f7f966-d8cc-11e4-bed1-df8f05be55ba");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"tags"][@"key"], @"value");
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 1);
        
        [self clearStateForAppRestart];
        
        [Kontext sendEvent:@"key" value:@"value"];
        [Kontext setSubscription:true];
        [Kontext promptLocation];
        [Kontext promptForPushNotificationsWithUserResponse:nil];
        [self runBackgroundThreads];
        
        [self initKontextAndThreadWait];
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 0);
    }
}

- (void)testPermissionChangeObserverIOS10 {
    KontextHelperOverrider.mockIOSVersion = 10;
    [self sharedTestPermissionChangeObserver];
}
- (void)testPermissionChangeObserverIOS8 {
    KontextHelperOverrider.mockIOSVersion = 8;
    [self sharedTestPermissionChangeObserver];
}
- (void)testPermissionChangeObserverIOS7 {
    KontextHelperOverrider.mockIOSVersion = 7;
    [self sharedTestPermissionChangeObserver];
}
- (void)sharedTestPermissionChangeObserver {
    
    [self setCurrentNotificationPermissionAsUnanswered];
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
            handleNotificationAction:nil
                            settings:@{kKontextSettingsKeyAutoPrompt: @false}];
    
    KontextPermissionStateTestObserver* observer = [KontextPermissionStateTestObserver new];
    [Kontext addPermissionObserver:observer];
    
    [self registerForPushNotifications];
    [self runBackgroundThreads];
    
    XCTAssertEqual(observer->last.from.hasPrompted, false);
    XCTAssertEqual(observer->last.from.answeredPrompt, false);
    XCTAssertEqual(observer->last.to.hasPrompted, true);
    XCTAssertEqual(observer->last.to.answeredPrompt, false);
    XCTAssertEqual(observer->fireCount, 1);
    
    [self answerNotifiationPrompt:true];
    [self runBackgroundThreads];
    
    XCTAssertEqual(observer->last.from.accepted, false);
    XCTAssertEqual(observer->last.to.answeredPrompt, true);
    XCTAssertEqual(observer->last.to.accepted, true);
    
    // Make sure it doesn't fire for answeredPrompt then again right away for accepted
    XCTAssertEqual(observer->fireCount, 2);
    
    XCTAssertEqualObjects([observer->last description], @"<KontextSubscriptionStateChanges:\nfrom: <KontextPermissionState: hasPrompted: 1, status: NotDetermined>,\nto:   <KontextPermissionState: hasPrompted: 1, status: Authorized>\n>");
}


- (void)testPermissionChangeObserverWhenAlreadyAccepted {
    [self initKontextAndThreadWait];
    
    KontextPermissionStateTestObserver* observer = [KontextPermissionStateTestObserver new];
    [Kontext addPermissionObserver:observer];
    [self runBackgroundThreads];
    
    XCTAssertEqual(observer->last.from.hasPrompted, false);
    XCTAssertEqual(observer->last.from.answeredPrompt, false);
    XCTAssertEqual(observer->last.from.accepted, false);
    XCTAssertEqual(observer->last.to.accepted, true);
    XCTAssertEqual(observer->fireCount, 1);
}

- (void)testPermissionChangeObserverFireAfterAppRestart {
    // Setup app as accepted.
    [self initKontextAndThreadWait];
    KontextPermissionStateTestObserver* observer = [KontextPermissionStateTestObserver new];
    [Kontext addPermissionObserver:observer];
    
    // User kills app, turns off notifications, then opnes it agian.
    [self clearStateForAppRestart];
    [self setCurrentNotificationPermission:false];
    [self initKontextAndThreadWait];
    
    // Added Observer should be notified of the change right away.
    observer = [KontextPermissionStateTestObserver new];
    [Kontext addPermissionObserver:observer];
    [self runBackgroundThreads];
    
    XCTAssertEqual(observer->last.from.accepted, true);
    XCTAssertEqual(observer->last.to.accepted, false);
}


- (void)testPermissionObserverDontFireIfNothingChangedAfterAppRestartiOS10 {
    KontextHelperOverrider.mockIOSVersion = 10;
    [self sharedPermissionObserverDontFireIfNothingChangedAfterAppRestart];
}
- (void)testPermissionObserverDontFireIfNothingChangedAfterAppRestartiOS8 {
    KontextHelperOverrider.mockIOSVersion = 8;
    [self sharedPermissionObserverDontFireIfNothingChangedAfterAppRestart];
}
- (void)testPermissionObserverDontFireIfNothingChangedAfterAppRestartiOS7 {
    KontextHelperOverrider.mockIOSVersion = 7;
    [self sharedPermissionObserverDontFireIfNothingChangedAfterAppRestart];
}
- (void)sharedPermissionObserverDontFireIfNothingChangedAfterAppRestart {
    [self setCurrentNotificationPermissionAsUnanswered];
    
    KontextPermissionStateTestObserver* observer = [KontextPermissionStateTestObserver new];
    [Kontext addPermissionObserver:observer];
    
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
            handleNotificationAction:nil
                            settings:@{kKontextSettingsKeyAutoPrompt: @false}];
    [self runBackgroundThreads];
    
    
    [self answerNotifiationPrompt:true];
    [self runBackgroundThreads];
    
    // Restart App
    [self clearStateForAppRestart];
    
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
            handleNotificationAction:nil
                            settings:@{kKontextSettingsKeyAutoPrompt: @false}];
    
    observer = [KontextPermissionStateTestObserver new];
    [Kontext addPermissionObserver:observer];
    
    [self runBackgroundThreads];
    
    XCTAssertNil(observer->last);
}




- (void)testPermissionChangeObserverDontLoseFromChanges {
    [self setCurrentNotificationPermissionAsUnanswered];
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
            handleNotificationAction:nil
                            settings:@{kKontextSettingsKeyAutoPrompt: @false}];
    [self runBackgroundThreads];
    
    [self registerForPushNotifications];
    [self answerNotifiationPrompt:true];
    [self runBackgroundThreads];
    
    KontextPermissionStateTestObserver* observer = [KontextPermissionStateTestObserver new];
    [Kontext addPermissionObserver:observer];
    [self runBackgroundThreads];

    XCTAssertEqual(observer->last.from.hasPrompted, false);
    XCTAssertEqual(observer->last.from.answeredPrompt, false);
    XCTAssertEqual(observer->last.from.accepted, false);
    XCTAssertEqual(observer->last.to.accepted, true);
}

- (void)testSubscriptionChangeObserverWhenAlreadyAccepted {
    [self initKontextAndThreadWait];
    
    KontextSubscriptionStateTestObserver* observer = [KontextSubscriptionStateTestObserver new];
    [Kontext addSubscriptionObserver:observer];
    [self runBackgroundThreads];
    
    XCTAssertEqual(observer->last.from.subscribed, false);
    XCTAssertEqual(observer->last.to.subscribed, true);
    XCTAssertEqual(observer->fireCount, 1);
}

- (void)testSubscriptionChangeObserverFireAfterAppRestart {
    // Setup app as accepted.
    [self initKontextAndThreadWait];
    KontextSubscriptionStateTestObserver* observer = [KontextSubscriptionStateTestObserver new];
    [Kontext addSubscriptionObserver:observer];
    
    
    // User kills app, turns off notifications, then opnes it agian.
    [self clearStateForAppRestart];
    [self setCurrentNotificationPermission:false];
    [self initKontextAndThreadWait];
    
    // Added Observer should be notified of the change right away.
    observer = [KontextSubscriptionStateTestObserver new];
    [Kontext addSubscriptionObserver:observer];
    [self runBackgroundThreads];
    
    XCTAssertEqual(observer->last.from.subscribed, true);
    XCTAssertEqual(observer->last.to.subscribed, false);
}


- (void)testPermissionChangeObserverWithNativeiOS10PromptCall {
    [self setCurrentNotificationPermissionAsUnanswered];
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
            handleNotificationAction:nil
                            settings:@{kKontextSettingsKeyAutoPrompt: @false}];
    
    KontextPermissionStateTestObserver* observer = [KontextPermissionStateTestObserver new];
    [Kontext addPermissionObserver:observer];
    
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert + UNAuthorizationOptionSound + UNAuthorizationOptionBadge)
                          completionHandler:^(BOOL granted, NSError* error) {}];
    [self backgroundApp];
    [self runBackgroundThreads];
    
    XCTAssertEqual(observer->fireCount, 1);
    XCTAssertEqualObjects([observer->last description],
                          @"<KontextSubscriptionStateChanges:\nfrom: <KontextPermissionState: hasPrompted: 0, status: NotDetermined>,\nto:   <KontextPermissionState: hasPrompted: 1, status: NotDetermined>\n>");
    
    [self answerNotifiationPrompt:true];
    [self runBackgroundThreads];
    
    // Make sure it doesn't fire for answeredPrompt then again right away for accepted
    XCTAssertEqual(observer->fireCount, 2);
    XCTAssertEqualObjects([observer->last description],
                          @"<KontextSubscriptionStateChanges:\nfrom: <KontextPermissionState: hasPrompted: 1, status: NotDetermined>,\nto:   <KontextPermissionState: hasPrompted: 1, status: Authorized>\n>");
}

// Yes, this starts with testTest, we are testing our Unit Test behavior!
//  Making sure our simulated methods using swizzling can reproduce an iOS 10.2.1 bug.
- (void)testTestPermissionChangeObserverWithNativeiOS10PromptCall {
    [KontextUNUserNotificationCenter setUseiOS10_2_workaround:false];
    
    [self setCurrentNotificationPermissionAsUnanswered];
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
            handleNotificationAction:nil
                            settings:@{kKontextSettingsKeyAutoPrompt: @false}];
    
    KontextPermissionStateTestObserver* observer = [KontextPermissionStateTestObserver new];
    [Kontext addPermissionObserver:observer];
    
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert + UNAuthorizationOptionSound + UNAuthorizationOptionBadge)
                          completionHandler:^(BOOL granted, NSError* error) {}];
    [self backgroundApp];
    // Full bug details explained in answerNotifiationPrompt
    [self answerNotifiationPrompt:true];
    [self runBackgroundThreads];
    
    XCTAssertEqual(observer->fireCount, 3);
    
    XCTAssertEqualObjects([observer->last description],
                          @"<KontextSubscriptionStateChanges:\nfrom: <KontextPermissionState: hasPrompted: 1, status: Denied>,\nto:   <KontextPermissionState: hasPrompted: 1, status: Authorized>\n>");
}

- (void)testPermissionChangeObserverWithDecline {
    [self setCurrentNotificationPermissionAsUnanswered];
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
            handleNotificationAction:nil
                            settings:@{kKontextSettingsKeyAutoPrompt: @false}];
    
    KontextPermissionStateTestObserver* observer = [KontextPermissionStateTestObserver new];
    [Kontext addPermissionObserver:observer];
    
    [self registerForPushNotifications];
    [self runBackgroundThreads];
    
    XCTAssertEqual(observer->last.from.hasPrompted, false);
    XCTAssertEqual(observer->last.from.answeredPrompt, false);
    XCTAssertEqual(observer->last.to.hasPrompted, true);
    XCTAssertEqual(observer->last.to.answeredPrompt, false);
    XCTAssertEqual(observer->fireCount, 1);
    
    [self answerNotifiationPrompt:false];
    [self runBackgroundThreads];
    
    XCTAssertEqual(observer->last.from.accepted, false);
    XCTAssertEqual(observer->last.to.answeredPrompt, true);
    XCTAssertEqual(observer->last.to.accepted, false);
    XCTAssertEqual(observer->fireCount, 2);
}


- (void)testPermissionAndSubscriptionChangeObserverRemove {
    [self setCurrentNotificationPermissionAsUnanswered];
    [self backgroundModesDisabledInXcode];
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
            handleNotificationAction:nil
                            settings:@{kKontextSettingsKeyAutoPrompt: @false}];
    
    KontextPermissionStateTestObserver* permissionObserver = [KontextPermissionStateTestObserver new];
    [Kontext addPermissionObserver:permissionObserver];
    [Kontext removePermissionObserver:permissionObserver];
    
    KontextSubscriptionStateTestObserver* subscriptionObserver = [KontextSubscriptionStateTestObserver new];
    [Kontext addSubscriptionObserver:subscriptionObserver];
    [Kontext removeSubscriptionObserver:subscriptionObserver];
    
    [self registerForPushNotifications];
    [self answerNotifiationPrompt:true];
    [self runBackgroundThreads];
    
    XCTAssertNil(permissionObserver->last);
    XCTAssertNil(subscriptionObserver->last);
}

- (void)testSubscriptionChangeObserverBasic {
    [self setCurrentNotificationPermissionAsUnanswered];
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
            handleNotificationAction:nil
                            settings:@{kKontextSettingsKeyAutoPrompt: @false}];
    
    KontextSubscriptionStateTestObserver* observer = [KontextSubscriptionStateTestObserver new];
    [Kontext addSubscriptionObserver:observer];
    [self registerForPushNotifications];
    [self answerNotifiationPrompt:true];
    [self runBackgroundThreads];
    
    XCTAssertEqual(observer->last.from.subscribed, false);
    XCTAssertEqual(observer->last.to.subscribed, true);
    
    [Kontext setSubscription:false];
    
    XCTAssertEqual(observer->last.from.subscribed, true);
    XCTAssertEqual(observer->last.to.subscribed, false);
    
    XCTAssertEqualObjects([observer->last description], @"<KontextSubscriptionStateChanges:\nfrom: <KontextSubscriptionState: userId: 1234, pushToken: 0000000000000000000000000000000000000000000000000000000000000000, userSubscriptionSetting: 1, subscribed: 1>,\nto:   <KontextSubscriptionState: userId: 1234, pushToken: 0000000000000000000000000000000000000000000000000000000000000000, userSubscriptionSetting: 0, subscribed: 0>\n>");
    NSLog(@"Test description: %@", observer->last);
}

- (void)testSubscriptionChangeObserverWhenPromptNotShown {
    [self setCurrentNotificationPermissionAsUnanswered];
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
            handleNotificationAction:nil
                            settings:@{kKontextSettingsKeyAutoPrompt: @false}];
    
    KontextSubscriptionStateTestObserver* observer = [KontextSubscriptionStateTestObserver new];
    [Kontext addSubscriptionObserver:observer];
    
    // Triggers the 30 fallback to register device right away.
    [self runBackgroundThreads];
    [NSObjectOverrider runPendingSelectors];
    [self runBackgroundThreads];
    
    XCTAssertNil(observer->last.from.userId);
    XCTAssertEqualObjects(observer->last.to.userId, @"1234");
    XCTAssertFalse(observer->last.to.subscribed);
    
    [Kontext setSubscription:false];
    [self runBackgroundThreads];
    
    XCTAssertTrue(observer->last.from.userSubscriptionSetting);
    XCTAssertFalse(observer->last.to.userSubscriptionSetting);
    // Device registered with Kontext so now make pushToken available.
    XCTAssertEqualObjects(observer->last.to.pushToken, @"0000000000000000000000000000000000000000000000000000000000000000");
    
    XCTAssertFalse(observer->last.from.subscribed);
    XCTAssertFalse(observer->last.to.subscribed);
    
    // Prompt and accept notifications
    [self registerForPushNotifications];
    [self answerNotifiationPrompt:true];
    [self runBackgroundThreads];
    
    // Shouldn't be subscribed yet as we called setSubscription:false before
    XCTAssertFalse(observer->last.from.subscribed);
    XCTAssertFalse(observer->last.to.subscribed);
    
    // Device should be reported a subscribed now as all condiditions are true.
    [Kontext setSubscription:true];
    XCTAssertFalse(observer->last.from.subscribed);
    XCTAssertTrue(observer->last.to.subscribed);
}

- (void)testInitAcceptingNotificationsWithoutCapabilitesSet {
    
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        [self backgroundModesDisabledInXcode];
        UIApplicationOverrider.didFailRegistarationErrorCode = 3000;
        [self setCurrentNotificationPermissionAsUnanswered];
        
        [self initKontext];
        XCTAssertNil(KontextClientOverrider.lastHTTPRequest);
        
        [self answerNotifiationPrompt:true];
        [self runBackgroundThreads];
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"app_id"], @"b2f7f966-d8cc-11e4-bed1-df8f05be55ba");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"notification_types"], @-13);
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 1);
    }
}


- (void)testPromptForPushNotificationsWithUserResponse {
    [self setCurrentNotificationPermissionAsUnanswered];
    
    [self initKontext];
    
    __block BOOL didAccept;
    [Kontext promptForPushNotificationsWithUserResponse:^(BOOL accepted) {
        didAccept = accepted;
    }];
    [self backgroundApp];
    [self answerNotifiationPrompt:true];
    [self runBackgroundThreads];
    XCTAssertTrue(didAccept);
}

- (void)testPromptForPushNotificationsWithUserResponseOnIOS8 {
    [self setCurrentNotificationPermissionAsUnanswered];
    KontextHelperOverrider.mockIOSVersion = 8;
    
    [self initKontext];
    
    __block BOOL didAccept;
    [Kontext promptForPushNotificationsWithUserResponse:^(BOOL accepted) {
        didAccept = accepted;
    }];
    [self backgroundApp];
    [self answerNotifiationPrompt:true];
    [self runBackgroundThreads];
    XCTAssertTrue(didAccept);
}

- (void)testPromptForPushNotificationsWithUserResponseOnIOS7 {
    [self setCurrentNotificationPermissionAsUnanswered];
    KontextHelperOverrider.mockIOSVersion = 7;
    
    [self initKontext];
    
    __block BOOL didAccept;
    [Kontext promptForPushNotificationsWithUserResponse:^(BOOL accepted) {
        didAccept = accepted;
    }];
    [self backgroundApp];
    [self answerNotifiationPrompt:true];
    [self runBackgroundThreads];
    XCTAssertTrue(didAccept);
}


- (void)testPromptedButNeveranswerNotificationPrompt {
    
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        [self setCurrentNotificationPermissionAsUnanswered];
        
        [self initKontextAndThreadWait];
        
        // Don't make a network call right away.
        XCTAssertNil(KontextClientOverrider.lastHTTPRequest);
        
        // Triggers the 30 fallback to register device right away.
        [Kontext performSelector:NSSelectorFromString(@"registerUser")];
        [self runBackgroundThreads];
        
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"app_id"], @"b2f7f966-d8cc-11e4-bed1-df8f05be55ba");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"notification_types"], @-19);
    }
}

- (void)testNotificationTypesWhenAlreadyAcceptedWithAutoPromptOffOnFristStartPreIos10 {
    
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        KontextHelperOverrider.mockIOSVersion = 8;
        [self setCurrentNotificationPermission:true];
        
        [Kontext initWithLaunchOptions:nil
                                   appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
                handleNotificationAction:nil
                                settings:@{kKontextSettingsKeyAutoPrompt: @false}];
        
        [self runBackgroundThreads];
        
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"notification_types"], @7);
    }
}


- (void)testNeverPromptedStatus {
    
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        [self setCurrentNotificationPermissionAsUnanswered];
        
        [Kontext initWithLaunchOptions:nil
                                   appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
                handleNotificationAction:nil
                                settings:@{kKontextSettingsKeyAutoPrompt: @false}];
        
        [self runBackgroundThreads];
        // Triggers the 30 fallback to register device right away.
        [NSObjectOverrider runPendingSelectors];
        [self runBackgroundThreads];
        
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"app_id"], @"b2f7f966-d8cc-11e4-bed1-df8f05be55ba");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"notification_types"], @-18);
    }
}

- (void)testNotAcceptingNotificationsWithoutBackgroundModes {
    
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        [self setCurrentNotificationPermissionAsUnanswered];
        [self backgroundModesDisabledInXcode];
        
        [self initKontext];
        
        // Don't make a network call right away.
        XCTAssertNil(KontextClientOverrider.lastHTTPRequest);
        
        [self answerNotifiationPrompt:false];
        [self runBackgroundThreads];
        
        XCTAssertEqualObjects(KontextClientOverrider.lastUrl, @"https://api.kontext.in/api/v1/players");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"app_id"], @"b2f7f966-d8cc-11e4-bed1-df8f05be55ba");
        XCTAssertNil(KontextClientOverrider.lastHTTPRequest[@"identifier"]);
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"notification_types"], @0);
    }
}

- (void)testIdsAvailableNotAcceptingNotifications {
    [self setCurrentNotificationPermissionAsUnanswered];
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
            handleNotificationAction:nil
                            settings:@{kKontextSettingsKeyAutoPrompt: @false}];
    
    __block BOOL idsAvailable1Called = false;
    [Kontext IdsAvailable:^(NSString *userId, NSString *pushToken) {
        idsAvailable1Called = true;
    }];
    
    [self runBackgroundThreads];
    
    [self registerForPushNotifications];
    
    [self answerNotifiationPrompt:false];
    
    [self runBackgroundThreads];
    XCTAssertTrue(idsAvailable1Called);
    
    
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
            handleNotificationAction:nil
                            settings:@{kKontextSettingsKeyAutoPrompt: @false}];
    
    __block BOOL idsAvailable2Called = false;
    [Kontext IdsAvailable:^(NSString *userId, NSString *pushToken) {
        idsAvailable2Called = true;
    }];
    
    [self runBackgroundThreads];
    XCTAssertTrue(idsAvailable2Called);
}

// Tests that a normal notification opened on iOS 10 triggers the handleNotificationAction.
- (void)testNotificationOpen {
    
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        __block BOOL openedWasFire = false;
        
        [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba" handleNotificationAction:^(KontextNotificationOpenedResult *result) {
            XCTAssertNil(result.notification.payload.additionalData);
            XCTAssertEqual(result.action.type, KontextNotificationActionTypeOpened);
            XCTAssertNil(result.action.actionID);
            openedWasFire = true;
        }];
        [self runBackgroundThreads];
        
        id notifResponse = [self createBasiciKontextNotificationResponse];
        UNUserNotificationCenter *notifCenter = [UNUserNotificationCenter currentNotificationCenter];
        id notifCenterDelegate = notifCenter.delegate;
        // UNUserNotificationCenterDelegate method iOS 10 calls directly when a notification is opened.
        [notifCenterDelegate userNotificationCenter:notifCenter didReceiveNotificationResponse:notifResponse withCompletionHandler:^() {}];
        
        // Make sure open tracking network call was made.
        XCTAssertEqual(openedWasFire, true);
        XCTAssertEqualObjects(KontextClientOverrider.lastUrl, @"https://api.kontext.in/api/v1/notifications/b2f7f966-d8cc-11e4-bed1-df8f05be55bb");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"app_id"], @"b2f7f966-d8cc-11e4-bed1-df8f05be55ba");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"opened"], @1);
        
        // Make sure if the device recieved a duplicate we don't fire the open network call again.
        KontextClientOverrider.lastUrl = nil;
        KontextClientOverrider.lastHTTPRequest = nil;
        [notifCenterDelegate userNotificationCenter:notifCenter didReceiveNotificationResponse:notifResponse withCompletionHandler:^() {}];
        
        XCTAssertNil(KontextClientOverrider.lastUrl);
        XCTAssertNil(KontextClientOverrider.lastHTTPRequest);
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 2);
    }
}


- (UNNotificationResponse*)createNotificationResponseForAnalyticsTests {
    id userInfo = @{@"custom":
                        @{@"i": @"b2f7f966-d8cc-11e4-bed1-df8f05be55bb",
                          @"ti": @"1117f966-d8cc-11e4-bed1-df8f05be55bb",
                          @"tn": @"Template Name"
                          }
                    };
    
    return [self createBasiciKontextNotificationResponseWithPayload:userInfo];
}

- (void)testFirebaseAnalyticsNotificationOpen {
    KontextTrackFirebaseAnalyticsOverrider.hasFIRAnalytics = true;
    [self initKontextAndThreadWait];
    
    UNUserNotificationCenter *notifCenter = [UNUserNotificationCenter currentNotificationCenter];
    [notifCenter.delegate userNotificationCenter:notifCenter
                 didReceiveNotificationResponse:[self createNotificationResponseForAnalyticsTests]
                          withCompletionHandler:^() {}];
    
    // Make sure we track the notification open event
    XCTAssertEqual(KontextTrackFirebaseAnalyticsOverrider.loggedEvents.count, 1);
    id event =  @{
                  @"os_notification_opened": @{
                      @"campaign": @"Template Name - 1117f966-d8cc-11e4-bed1-df8f05be55bb",
                      @"medium": @"notification",
                      @"notification_id": @"b2f7f966-d8cc-11e4-bed1-df8f05be55bb",
                      @"source": @"Kontext"}
                  };
    XCTAssertEqualObjects(KontextTrackFirebaseAnalyticsOverrider.loggedEvents[0], event);
}

- (void)testFirebaseAnalyticsInfluenceNotificationOpen {
    // Start App once to download params
    KontextTrackFirebaseAnalyticsOverrider.hasFIRAnalytics = true;
    [self initKontextAndThreadWait];
    
    // Notification is recieved.
    // The Notification Service Extension runs where the notification received id tracked.
    //   Note: This is normally a separate process but can't emulate that here.
    UNNotificationResponse *response = [self createNotificationResponseForAnalyticsTests];
    [Kontext didReceiveNotificationExtensionRequest:response.notification.request
                       withMutableNotificationContent:nil];
    
    // Make sure we are tracking the notification received event to firebase.
    XCTAssertEqual(KontextTrackFirebaseAnalyticsOverrider.loggedEvents.count, 1);
    id received_event = @{
         @"os_notification_received": @{
              @"campaign": @"Template Name - 1117f966-d8cc-11e4-bed1-df8f05be55bb",
              @"medium": @"notification",
              @"notification_id": @"b2f7f966-d8cc-11e4-bed1-df8f05be55bb",
              @"source": @"Kontext"}
         };
    XCTAssertEqualObjects(KontextTrackFirebaseAnalyticsOverrider.loggedEvents[0], received_event);
    
    // Trigger a new app session
    [self backgroundApp];
    NSDateOverrider.timeOffset = 41;
    [self resumeApp];
    [self runBackgroundThreads];
    
    // Since we opened the app under 2 mintues after receiving a notification
    //   an influence_open should be sent to firebase.
    XCTAssertEqual(KontextTrackFirebaseAnalyticsOverrider.loggedEvents.count, 2);
    id influence_open_event = @{
       @"os_notification_influence_open": @{
          @"campaign": @"Template Name - 1117f966-d8cc-11e4-bed1-df8f05be55bb",
          @"medium": @"notification",
          @"notification_id": @"b2f7f966-d8cc-11e4-bed1-df8f05be55bb",
          @"source": @"Kontext"}
       };
    XCTAssertEqualObjects(KontextTrackFirebaseAnalyticsOverrider.loggedEvents[1], influence_open_event);
}

- (void)testKontextNotificationPayloadParsesTemplateFields {
    NSDictionary *aps = @{@"custom": @{@"ti": @"templateId", @"tn": @"Template name"}};
    KontextNotificationPayload *paylaod = [KontextNotificationPayload parseWithApns:aps];
    XCTAssertEqual(paylaod.templateID, @"templateId");
    XCTAssertEqual(paylaod.templateName, @"Template name");
    
    // Test os_data format
    aps = @{@"os_data": @{@"ti": @"templateId", @"tn": @"Template name"}};
    paylaod = [KontextNotificationPayload parseWithApns:aps];
    XCTAssertEqual(paylaod.templateID, @"templateId");
    XCTAssertEqual(paylaod.templateName, @"Template name");
}


// Wrapper SDKs may not have the app_id available on cold starts.
// Open event should still fire however so the event is not missed.
- (void)testNotificationOpenOn2ndColdStartWithoutAppId {
    [self initKontextAndThreadWait];
    
    [self clearStateForAppRestart];
    
    __block BOOL openedWasFire = false;
    [Kontext initWithLaunchOptions:nil appId:nil handleNotificationAction:^(KontextNotificationOpenedResult *result) {
        openedWasFire = true;
    }];
    [self runBackgroundThreads];
    
    id notifResponse = [self createBasiciKontextNotificationResponse];
    UNUserNotificationCenter *notifCenter = [UNUserNotificationCenter currentNotificationCenter];
    id notifCenterDelegate = notifCenter.delegate;
    // UNUserNotificationCenterDelegate method iOS 10 calls directly when a notification is opened.
    [notifCenterDelegate userNotificationCenter:notifCenter didReceiveNotificationResponse:notifResponse withCompletionHandler:^() {}];
    
    XCTAssertTrue(openedWasFire);
}

// Testing iOS 10 - old pre-2.4.0 button fromat - with original aps payload format
- (void)testNotificationOpenFromButtonPress {
    
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        __block BOOL openedWasFire = false;
        
        [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba" handleNotificationAction:^(KontextNotificationOpenedResult *result) {
            XCTAssertEqualObjects(result.notification.payload.additionalData[@"actionSelected"], @"id1");
            XCTAssertEqual(result.action.type, KontextNotificationActionTypeActionTaken);
            XCTAssertEqualObjects(result.action.actionID, @"id1");
            openedWasFire = true;
        }];
        [self runBackgroundThreads];
        UIApplicationOverrider.currentUIApplicationState = UIApplicationStateInactive;
        
        id userInfo = @{@"aps": @{@"content_available": @1},
                        @"m": @"alert body only",
                        @"o": @[@{@"i": @"id1", @"n": @"text1"}],
                        @"custom": @{
                                @"i": @"b2f7f966-d8cc-11e4-bed1-df8f05be55bb"
                                }
                        };
        
        id notifResponse = [self createBasiciKontextNotificationResponseWithPayload:userInfo];
        [notifResponse setValue:@"id1" forKeyPath:@"actionIdentifier"];
        
        UNUserNotificationCenter *notifCenter = [UNUserNotificationCenter currentNotificationCenter];
        id notifCenterDelegate = notifCenter.delegate;
        
        // UNUserNotificationCenterDelegate method iOS 10 calls directly when a notification is opened.
        [notifCenterDelegate userNotificationCenter:notifCenter didReceiveNotificationResponse:notifResponse withCompletionHandler:^() {}];
        
        // Make sure open tracking network call was made.
        XCTAssertEqual(openedWasFire, true);
        XCTAssertEqualObjects(KontextClientOverrider.lastUrl, @"https://api.kontext.in/api/v1/notifications/b2f7f966-d8cc-11e4-bed1-df8f05be55bb");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"app_id"], @"b2f7f966-d8cc-11e4-bed1-df8f05be55ba");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"opened"], @1);
        
        // Make sure if the device recieved a duplicate we don't fire the open network call again.
        KontextClientOverrider.lastUrl = nil;
        KontextClientOverrider.lastHTTPRequest = nil;
        [notifCenterDelegate userNotificationCenter:notifCenter didReceiveNotificationResponse:notifResponse withCompletionHandler:^() {}];
        
        XCTAssertNil(KontextClientOverrider.lastUrl);
        XCTAssertNil(KontextClientOverrider.lastHTTPRequest);
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 2);
    }
}


// Testing iOS 10 - 2.4.0+ button fromat - with os_data aps payload format
- (void)testNotificationOpenFromButtonPressWithNewformat {
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        __block BOOL openedWasFire = false;
        
        [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba" handleNotificationAction:^(KontextNotificationOpenedResult *result) {
            XCTAssertEqualObjects(result.notification.payload.additionalData[@"actionSelected"], @"id1");
            XCTAssertEqual(result.action.type, KontextNotificationActionTypeActionTaken);
            XCTAssertEqualObjects(result.action.actionID, @"id1");
            openedWasFire = true;
        }];
        [self runBackgroundThreads];
        UIApplicationOverrider.currentUIApplicationState = UIApplicationStateInactive;
        
        id userInfo = @{@"aps": @{
                                @"mutable-content": @1,
                                @"alert": @"Message Body"
                                },
                        @"os_data": @{
                                @"i": @"b2f7f966-d8cc-11e4-bed1-df8f05be55bb",
                                @"buttons": @[@{@"i": @"id1", @"n": @"text1"}],
                                }};
        
        id notifResponse = [self createBasiciKontextNotificationResponseWithPayload:userInfo];
        [notifResponse setValue:@"id1" forKeyPath:@"actionIdentifier"];
        
        UNUserNotificationCenter *notifCenter = [UNUserNotificationCenter currentNotificationCenter];
        id notifCenterDelegate = notifCenter.delegate;
        
        // UNUserNotificationCenterDelegate method iOS 10 calls directly when a notification is opened.
        [notifCenterDelegate userNotificationCenter:notifCenter didReceiveNotificationResponse:notifResponse withCompletionHandler:^() {}];
        
        // Make sure open tracking network call was made.
        XCTAssertEqual(openedWasFire, true);
        XCTAssertEqualObjects(KontextClientOverrider.lastUrl, @"https://api.kontext.in/api/v1/notifications/b2f7f966-d8cc-11e4-bed1-df8f05be55bb");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"app_id"], @"b2f7f966-d8cc-11e4-bed1-df8f05be55ba");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"opened"], @1);
        
        // Make sure if the device recieved a duplicate we don't fire the open network call again.
        KontextClientOverrider.lastUrl = nil;
        KontextClientOverrider.lastHTTPRequest = nil;
        [notifCenterDelegate userNotificationCenter:notifCenter didReceiveNotificationResponse:notifResponse withCompletionHandler:^() {}];
        
        XCTAssertNil(KontextClientOverrider.lastUrl);
        XCTAssertNil(KontextClientOverrider.lastHTTPRequest);
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 2);
    }
}

// Testing iOS 10 - 2.4.0+ button fromat - with os_data aps payload format
- (void)notificationAlertButtonsDisplayWithFormat:(NSDictionary *)userInfo {
    __block BOOL openedWasFire = false;
    id receiveBlock = ^(KontextNotificationOpenedResult *result) {
        XCTAssertEqual(result.action.type, KontextNotificationActionTypeActionTaken);
        XCTAssertEqualObjects(result.action.actionID, @"id1");
        id actionButons = @[@{@"id": @"id1", @"text": @"text1"}];
        XCTAssertEqualObjects(result.notification.payload.actionButtons, actionButons);
        XCTAssertEqualObjects(result.notification.payload.additionalData[@"actionSelected"], @"id1");
        
        openedWasFire = true;
    };
    
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba" handleNotificationAction:receiveBlock];
    
    [self resumeApp];
    [self runBackgroundThreads];
    
    id notifResponse = [self createBasiciKontextNotificationResponseWithPayload:userInfo];
    [notifResponse setValue:@"id1" forKeyPath:@"actionIdentifier"];
    
    UNUserNotificationCenter *notifCenter = [UNUserNotificationCenter currentNotificationCenter];
    id notifCenterDelegate = notifCenter.delegate;
    [notifCenterDelegate userNotificationCenter:notifCenter
                        willPresentNotification:[notifResponse notification]
                          withCompletionHandler:^(UNNotificationPresentationOptions options) {}];
    
    XCTAssertEqual(UIAlertViewOverrider.uiAlertButtonArrayCount, 1);
    [UIAlertViewOverrider.lastUIAlertViewDelegate alertView:nil clickedButtonAtIndex:1];
    XCTAssertEqual(openedWasFire, true);
}

- (void)testOldFormatNotificationAlertButtonsDisplay {
    id oldFormat = @{@"aps" : @{
                             @"mutable-content" : @1,
                             @"alert" : @{
                                     @"title" : @"Test Title"
                                     }
                             },
                     @"buttons" : @[@{@"i": @"id1", @"n": @"text1"}],
                     @"custom" : @{
                             @"i" : @"b2f7f966-d8cc-11e4-bed1-df8f05be55bf"
                             }
                     };
    
    [self notificationAlertButtonsDisplayWithFormat:oldFormat];
}

- (void)testNewFormatNotificationAlertButtonsDisplay {
    id newFormat = @{@"aps": @{
                             @"mutable-content": @1,
                             @"alert": @{@"body": @"Message Body", @"title": @"title"}
                             },
                     @"os_data": @{
                             @"i": @"b2f7f966-d8cc-11e4-bed1-df8f05be55bf",
                             @"buttons": @[@{@"i": @"id1", @"n": @"text1"}],
                             }};
    
    [self notificationAlertButtonsDisplayWithFormat:newFormat];
}

// Testing iOS 10 - with original aps payload format
- (void)testOpeningWithAdditionalData {
    __block BOOL openedWasFire = false;
    
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba" handleNotificationAction:^(KontextNotificationOpenedResult *result) {
        XCTAssertEqualObjects(result.notification.payload.additionalData[@"foo"], @"bar");
        XCTAssertEqual(result.action.type, KontextNotificationActionTypeOpened);
        XCTAssertNil(result.action.actionID);
        openedWasFire = true;
    }];
    
    [self runBackgroundThreads];
    
    id userInfo = @{@"custom": @{
                      @"i": @"b2f7f966-d8cc-11e4-bed1-df8f05be55bb",
                      @"a": @{ @"foo": @"bar" }
                  }};
    
    id notifResponse = [self createBasiciKontextNotificationResponseWithPayload:userInfo];
    UNUserNotificationCenter *notifCenter = [UNUserNotificationCenter currentNotificationCenter];
    id notifCenterDelegate = notifCenter.delegate;
    
    // UNUserNotificationCenterDelegate method iOS 10 calls directly when a notification is opend.
    [notifCenterDelegate userNotificationCenter:notifCenter didReceiveNotificationResponse:notifResponse withCompletionHandler:^() {}];
    XCTAssertEqual(openedWasFire, true);
    
    // Part 2 - New paylaod test
    // Current mocking isn't able to setup this test correctly.
    // In an app AppDelete selectors fire instead of UNUserNotificationCenter
    // SDK could also used some refactoring as this should't have an effect.
    /*
    openedWasFire = false;
    userInfo = @{@"alert": @"body",
                 @"os_data": @{
                         @"i": @"b2f7f966-d8cc-11e4-bed1-df8f05be55bc"
                         },
                 @"foo": @"bar"};
    notifResponse = [self createBasiciKontextNotificationResponseWithPayload:userInfo];
    [notifCenterDelegate userNotificationCenter:notifCenter didReceiveNotificationResponse:notifResponse withCompletionHandler:^() {}];
    XCTAssertEqual(openedWasFire, true);
    */
}

// Testing iOS 10 - pre-2.4.0 button fromat - with os_data aps payload format
- (void)receivedCallbackWithButtonsWithUserInfo:(NSDictionary *)userInfo {
    __block BOOL recievedWasFire = false;
    
    [Kontext initWithLaunchOptions:nil
                               appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
          handleNotificationReceived:^(KontextNotification *notification) {
              recievedWasFire = true;
              let actionButons = @[ @{@"id": @"id1", @"text": @"text1"} ];
              XCTAssertEqualObjects(notification.payload.actionButtons, actionButons);
          }
            handleNotificationAction:nil
                            settings:nil];
    [self runBackgroundThreads];
    
    let notifResponse = [self createBasiciKontextNotificationResponseWithPayload:userInfo];
    UNUserNotificationCenter *notifCenter = [UNUserNotificationCenter currentNotificationCenter];
    let notifCenterDelegate = notifCenter.delegate;
    
    //iOS 10 calls UNUserNotificationCenterDelegate method directly when a notification is received while the app is in focus.
    [notifCenterDelegate userNotificationCenter:notifCenter
                        willPresentNotification:[notifResponse notification]
                          withCompletionHandler:^(UNNotificationPresentationOptions options) {}];
    
    XCTAssertEqual(recievedWasFire, true);
}

- (void)testReceivedCallbackWithButtonsWithNewFormat {
    let newFormat = @{@"aps": @{@"content_available": @1},
                      @"os_data": @{
                              @"i": @"b2f7f966-d8cc-11e4-bed1-df8f05be55bb",
                              @"buttons": @{
                                      @"m": @"alert body only",
                                      @"o": @[@{@"i": @"id1", @"n": @"text1"}]
                                      }
                              }
                      };
    
    id oldFormat = @{@"aps" : @{
                             @"mutable-content" : @1,
                             @"alert" : @{
                                     @"title" : @"Test Title"
                                     }
                             },
                     @"buttons" : @[@{@"i": @"id1", @"n": @"text1"}],
                     @"custom" : @{
                             @"i" : @"b2f7f966-d8cc-11e4-bed1-df8f05be55bf"
                             }
                     };
    
    [self receivedCallbackWithButtonsWithUserInfo:newFormat];
    [self receivedCallbackWithButtonsWithUserInfo:oldFormat];
}

-(void)fireDidReceiveRemoteNotification:(NSDictionary*)userInfo {
    let appDelegate = [UIApplication sharedApplication].delegate;
    [appDelegate application:[UIApplication sharedApplication]
didReceiveRemoteNotification:userInfo
      fetchCompletionHandler:^(UIBackgroundFetchResult result) { }];
}

-(void)assertLocalNotification:(NSDictionary*)userInfo {
    let localNotif = UIApplicationOverrider.lastUILocalNotification;
    XCTAssertEqualObjects(localNotif.alertBody, @"alert body only");
    XCTAssertEqualObjects(localNotif.category, @"__dynamic__");
    XCTAssertEqualObjects(localNotif.userInfo, userInfo);
    
    let categories = [UIApplication sharedApplication].currentUserNotificationSettings.categories;
    
    XCTAssertEqual(categories.count, 1);
    
    let category = categories.allObjects[0];
    XCTAssertEqualObjects(category.identifier, @"__dynamic__");
    
    let actions = [category actionsForContext:UIUserNotificationActionContextDefault];
    XCTAssertEqualObjects(actions[0].identifier, @"id1");
    XCTAssertEqualObjects(actions[0].title, @"text1");
}

// Testing iOS 8 - with os_data aps payload format
- (void)testGeneratingLocalNotificationWithButtonsiOS8_osdata_format {
    KontextHelperOverrider.mockIOSVersion = 8;
    [self initKontextAndThreadWait];
    [self backgroundApp];
    
    let userInfo = @{@"aps": @{@"content_available": @1},
                    @"os_data": @{
                            @"buttons": @{
                                    @"m": @"alert body only",
                                    @"o": @[@{@"i": @"id1", @"n": @"text1"}]
                                    }
                            },
                            @"i": @"b2f7f966-d8cc-11e4-bed1-df8f05be55bb"
                    };
    
    [self fireDidReceiveRemoteNotification:userInfo];
    [self assertLocalNotification:userInfo];
}

- (void)testGeneratingLocalNotificationWithButtonsiOS8 {
    KontextHelperOverrider.mockIOSVersion = 8;
    [self initKontextAndThreadWait];
    [self backgroundApp];
    
    let userInfo = @{@"aps": @{@"content_available": @1},
                    @"m": @"alert body only",
                    @"o": @[@{@"i": @"id1", @"n": @"text1"}],
                    @"custom": @{
                            @"i": @"b2f7f966-d8cc-11e4-bed1-df8f05be55bb"
                            }
                    };
    
    [self fireDidReceiveRemoteNotification:userInfo];
    [self assertLocalNotification:userInfo];
}

- (void)testSendEvents {
    
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        [self initKontextAndThreadWait];
        
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 1);
        
        // Simple test with a sendEvent and sendEvents call.
        [Kontext sendEvent:@"key" value:@"value"];
        [Kontext sendEvents:@{@"key1": @"value1", @"key2": @"value2"}];
        
        // Make sure all 3 sets of tags where send in 1 network call.
        [NSObjectOverrider runPendingSelectors];
        [self runBackgroundThreads];
        [NSObjectOverrider runPendingSelectors];
        
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"tags"][@"key"], @"value");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"tags"][@"key1"], @"value1");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"tags"][@"key2"], @"value2");
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 2);
        
        // More advanced test with callbacks.
        __block BOOL didRunSuccess1, didRunSuccess2, didRunSuccess3;
        
        [Kontext sendEvent:@"key10" value:@"value10" onSuccess:^(NSDictionary *result) {
            didRunSuccess1 = true;
        } onFailure:^(NSError *error) {}];
        [Kontext sendEvents:@{@"key11": @"value11", @"key12": @"value12"} onSuccess:^(NSDictionary *result) {
            didRunSuccess2 = true;
        } onFailure:^(NSError *error) {}];
        
        [Kontext sendEvent:@"key13" value:@"value13" onSuccess:^(NSDictionary *result) {
            didRunSuccess3 = true;
        } onFailure:^(NSError *error) {}];
        
        [self runBackgroundThreads];
        [NSObjectOverrider runPendingSelectors];
        [self runBackgroundThreads];
        
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"tags"][@"key10"], @"value10");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"tags"][@"key11"], @"value11");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"tags"][@"key12"], @"value12");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"tags"][@"key13"], @"value13");
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 3);
        
        XCTAssertEqual(didRunSuccess1, true);
        XCTAssertEqual(didRunSuccess2, true);
        XCTAssertEqual(didRunSuccess3, true);
    }
}

- (void)testDeleteTags {
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        [self initKontextAndThreadWait];
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 1);
        
        NSLog(@"Calling sendEvent and deleteTag");
        // send 2 tags and delete 1 before they get sent off.
        [Kontext sendEvent:@"key" value:@"value"];
        [Kontext sendEvent:@"key2" value:@"value2"];
        [Kontext deleteTag:@"key"];
        NSLog(@"Finished calling sendEvent and deleteTag");
        
        // Make sure only 1 network call is made and only key2 gets sent.
        [NSObjectOverrider runPendingSelectors];
        [self runBackgroundThreads];
        [NSObjectOverrider runPendingSelectors];
        
        XCTAssertNil(KontextClientOverrider.lastHTTPRequest[@"tags"][@"key"]);
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"tags"][@"key2"], @"value2");
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 2);
        
        [Kontext sendEvents:@{@"someKey": @NO}];
        [Kontext deleteTag:@"someKey"];
    }
}

- (void)testGetTags {
    [self initKontextAndThreadWait];
    XCTAssertEqual(KontextClientOverrider.networkRequestCount, 1);
    
    __block BOOL fireGetTags = false;
    
    [Kontext getTags:^(NSDictionary *result) {
        NSLog(@"getTags success HERE");
        fireGetTags = true;
    } onFailure:^(NSError *error) {
        NSLog(@"getTags onFailure HERE");
    }];
    
    [self runBackgroundThreads];
    
    XCTAssertTrue(fireGetTags);
}

- (void)testGetTagsBeforePlayerId {
    [self initKontextAndThreadWait];
    
    XCTAssertEqual(KontextClientOverrider.networkRequestCount, 1);
    
    __block BOOL fireGetTags = false;
    
    [Kontext getTags:^(NSDictionary *result) {
        NSLog(@"getTags success HERE");
        fireGetTags = true;
    } onFailure:^(NSError *error) {
        NSLog(@"getTags onFailure HERE");
    }];
    
    [self runBackgroundThreads];
    
    XCTAssertTrue(fireGetTags);

}

- (void)testGetTagsWithNestedDelete {
    [self initKontext];
    
    __block BOOL fireDeleteTags = false;
    
    [Kontext getTags:^(NSDictionary *result) {
        NSLog(@"getTags success HERE");
        [Kontext deleteTag:@"tag" onSuccess:^(NSDictionary *result) {
            fireDeleteTags = true;
            NSLog(@"deleteTag onSuccess HERE");
        } onFailure:^(NSError *error) {
            NSLog(@"deleteTag onFailure HERE");
        }];
    } onFailure:^(NSError *error) {
        NSLog(@"getTags onFailure HERE");
    }];
    
    
    [self runBackgroundThreads];
    
    [self runBackgroundThreads];
    [NSObjectOverrider runPendingSelectors];
    
    // create, ge tags, then sendEvents call.
    XCTAssertEqual(KontextClientOverrider.networkRequestCount, 3);
    XCTAssertTrue(fireDeleteTags);
}

- (void)testSendEventsBeforeRegisterComplete {
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        [self setCurrentNotificationPermissionAsUnanswered];
        
        [self initKontextAndThreadWait];
        
        NSObjectOverrider.selectorNamesForInstantOnlyForFirstRun = [@[@"sendEventsToServer"] mutableCopy];
        
        [Kontext sendEvent:@"key" value:@"value"];
        [self runBackgroundThreads];
        
        // Do not try to send tag update yet as there isn't a player_id yet.
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 0);
        
        [self answerNotifiationPrompt:false];
        [self runBackgroundThreads];
        
        // A single POST player create call should be made with tags included.
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 1);
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"tags"][@"key"], @"value");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"notification_types"], @0);
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"identifier"], @"0000000000000000000000000000000000000000000000000000000000000000");
    }
}

- (void)testPostNotification {
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        [self initKontextAndThreadWait];
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 1);
        
        
        // Normal post should auto add add_id.
        [Kontext postNotification:@{@"contents": @{@"en": @"message body"}}];
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 2);
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"contents"][@"en"], @"message body");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"app_id"], @"b2f7f966-d8cc-11e4-bed1-df8f05be55ba");
        
        // Should allow overriding the app_id
        [Kontext postNotification:@{@"contents": @{@"en": @"message body"}, @"app_id": @"override_app_UUID"}];
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 3);
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"contents"][@"en"], @"message body");
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"app_id"], @"override_app_UUID");
    }
}


- (void)testFirstInitWithNotificationsAlreadyDeclined {
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        [self backgroundModesDisabledInXcode];
        UNUserNotificationCenterOverrider.notifTypesOverride = 0;
        UNUserNotificationCenterOverrider.authorizationStatus = [NSNumber numberWithInteger:UNAuthorizationStatusDenied];
        
        [self initKontextAndThreadWait];
        
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"notification_types"], @0);
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 1);
    }
}

- (void)testPermissionChangedInSettingsOutsideOfApp {
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        [self backgroundModesDisabledInXcode];
        UNUserNotificationCenterOverrider.notifTypesOverride = 0;
        UNUserNotificationCenterOverrider.authorizationStatus = [NSNumber numberWithInteger:UNAuthorizationStatusDenied];
        
        [self initKontextAndThreadWait];
        
        KontextPermissionStateTestObserver* observer = [KontextPermissionStateTestObserver new];
        
        [Kontext addPermissionObserver:observer];
        
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"notification_types"], @0);
        XCTAssertNil(KontextClientOverrider.lastHTTPRequest[@"identifier"]);
        
        [self backgroundApp];
        [self setCurrentNotificationPermission:true];
        [self resumeApp];
        [self runBackgroundThreads];
        
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"notification_types"], @15);
        XCTAssertEqualObjects(KontextClientOverrider.lastHTTPRequest[@"identifier"], @"0000000000000000000000000000000000000000000000000000000000000000");
        XCTAssertEqual(KontextClientOverrider.networkRequestCount, 2);
        
        XCTAssertEqual(observer->last.from.accepted, false);
        XCTAssertEqual(observer->last.to.accepted, true);
    }
}

- (void) testOnSessionWhenResuming {
    [self initKontextAndThreadWait];
    
    // Don't make an on_session call if only out of the app for 20 secounds
    [self backgroundApp];
    NSDateOverrider.timeOffset = 10;
    [self resumeApp];
    [self runBackgroundThreads];
    XCTAssertEqual(KontextClientOverrider.networkRequestCount, 1);
    
    // Anything over 30 secounds should count as a session.
    [self backgroundApp];
    NSDateOverrider.timeOffset = 41;
    [self resumeApp];
    [self runBackgroundThreads];
    
    XCTAssertEqualObjects(KontextClientOverrider.lastUrl, @"https://api.kontext.in/api/v1/players/1234/on_session");
    XCTAssertEqual(KontextClientOverrider.networkRequestCount, 2);
}

// Tests that a slient content-available 1 notification doesn't trigger an on_session or count it has opened.
- (void)testContentAvailableDoesNotTriggerOpen  {
    UIApplicationOverrider.currentUIApplicationState = UIApplicationStateBackground;
    __block BOOL receivedWasFire = false;
    [Kontext initWithLaunchOptions:nil appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba"
          handleNotificationReceived:^(KontextNotification *result) {
            receivedWasFire = true;
          }
                 handleNotificationAction:nil
                            settings:nil];
    [self runBackgroundThreads];
    
    id userInfo = @{@"aps": @{@"content_available": @1},
                    @"custom": @{
                            @"i": @"b2f7f966-d8cc-11e4-1111-df8f05be55bb"
                            }
                    };
    
    [self fireDidReceiveRemoteNotification:userInfo];
    [self runBackgroundThreads];
    
    XCTAssertEqual(receivedWasFire, true);
    XCTAssertEqual(KontextClientOverrider.networkRequestCount, 0);
}

-(UNNotificationCategory*)unNotificagionCategoryWithId:(NSString*)identifier {
    return [UNNotificationCategory
            categoryWithIdentifier:identifier
            actions:@[]
            intentIdentifiers:@[]
            options:UNNotificationCategoryOptionCustomDismissAction];
}

// iOS 10 - Notification Service Extension test
- (void) didReceiveNotificationExtensionRequestDontOverrideCateogoryWithUserInfo:(NSDictionary *)userInfo {
    id notifResponse = [self createBasiciKontextNotificationResponseWithPayload:userInfo];
    
    [[notifResponse notification].request.content setValue:@"some_category" forKey:@"categoryIdentifier"];
    
    UNMutableNotificationContent* content = [Kontext didReceiveNotificationExtensionRequest:[notifResponse notification].request withMutableNotificationContent:nil];
    
    // Make sure we didn't override an existing category
    XCTAssertEqualObjects(content.categoryIdentifier, @"some_category");
    // Make sure attachments were added.
    XCTAssertEqualObjects(content.attachments[0].identifier, @"id");
    XCTAssertEqualObjects(content.attachments[0].URL.scheme, @"file");
}

- (void)testDidReceiveNotificationExtensionRequestDontOverrideCategory
{
    id newFormat = @{@"aps": @{
                             @"mutable-content": @1,
                             @"alert": @"Message Body"
                             },
                     @"os_data": @{
                             @"i": @"b2f7f966-d8cc-11e4-bed1-df8f05be55bb",
                             @"buttons": @[@{@"i": @"id1", @"n": @"text1"}],
                             @"att": @{ @"id": @"http://domain.com/file.jpg" }
                             }};
    
    id oldFormat = @{@"aps" : @{
                             @"mutable-content" : @1,
                             @"alert" : @{
                                     @"title" : @"Test Title"
                                     }
                             },
                     
                     @"att": @{ @"id": @"http://domain.com/file.jpg" },
                     @"buttons" : @[@{@"i": @"id1", @"n": @"text1"}],
                     @"custom" : @{
                             @"i" : @"b2f7f966-d8cc-11e4-bed1-df8f05be55bf"
                             }
                     };
    
    
    [self didReceiveNotificationExtensionRequestDontOverrideCateogoryWithUserInfo:oldFormat];
    [self didReceiveNotificationExtensionRequestDontOverrideCateogoryWithUserInfo:newFormat];
}

// iOS 10 - Notification Service Extension test
- (void) testDidReceiveNotificationExtensionRequestDontOverrideCateogory {    
    id userInfo = @{@"aps": @{
                            @"mutable-content": @1,
                            @"alert": @"Message Body"
                            },
                    @"os_data": @{
                            @"i": @"b2f7f966-d8cc-11e4-bed1-df8f05be55bb",
                            @"buttons": @[@{@"i": @"id1", @"n": @"text1"}],
                            @"att": @{ @"id": @"http://domain.com/file.jpg" }
                            }};
    
    id notifResponse = [self createBasiciKontextNotificationResponseWithPayload:userInfo];
    
    [[notifResponse notification].request.content setValue:@"some_category" forKey:@"categoryIdentifier"];
    
    UNMutableNotificationContent* content = [Kontext didReceiveNotificationExtensionRequest:[notifResponse notification].request withMutableNotificationContent:nil];
    
    // Make sure we didn't override an existing category
    XCTAssertEqualObjects(content.categoryIdentifier, @"some_category");
    // Make sure attachments were added.
    XCTAssertEqualObjects(content.attachments[0].identifier, @"id");
    XCTAssertEqualObjects(content.attachments[0].URL.scheme, @"file");
}

// iOS 10 - Notification Service Extension test - local file
- (void) testDidReceiveNotificationExtensionRequestLocalFile {
    id userInfo = @{@"aps": @{
                            @"mutable-content": @1,
                            @"alert": @"Message Body"
                            },
                    @"os_data": @{
                            @"i": @"b2f7f966-d8cc-11e4-bed1-df8f05be55bb",
                            @"att": @{ @"id": @"file.jpg" }
                            }};
    
    id notifResponse = [self createBasiciKontextNotificationResponseWithPayload:userInfo];
    
    UNMutableNotificationContent* content = [Kontext didReceiveNotificationExtensionRequest:[notifResponse notification].request withMutableNotificationContent:nil];

    // Make sure attachments were added.
    XCTAssertEqualObjects(content.attachments[0].identifier, @"id");
    XCTAssertEqualObjects(content.attachments[0].URL.scheme, @"file");
}

// iOS 10 - Notification Service Extension test
- (void) testServiceExtensionTimeWillExpireRequest {
    id userInfo = @{@"aps": @{
                        @"mutable-content": @1,
                        @"alert": @"Message Body"
                        },
                    @"os_data": @{
                        @"i": @"b2f7f966-d8cc-11e4-bed1-df8f05be55bb",
                        @"buttons": @[@{@"i": @"id1", @"n": @"text1"}],
                        @"att": @{ @"id": @"http://domain.com/file.jpg" }
                    }};
    
    id notifResponse = [self createBasiciKontextNotificationResponseWithPayload:userInfo];
    
    UNMutableNotificationContent* content = [Kontext serviceExtensionTimeWillExpireRequest:[notifResponse notification].request withMutableNotificationContent:nil];
    
    // Make sure butons were added.
    XCTAssertEqualObjects(content.categoryIdentifier, @"__dynamic__");
    // Make sure attachments were NOT added.
    //   We should not try to download attachemts as iOS is about to kill the extension and this will take to much time.
    XCTAssertNil(content.attachments);
}

-(void)testBuildKontextRequest {
    let request = [KontextRequestSendEventsToServer withUserId:@"12345" appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55bb" tags:@{@"tag1" : @"test1", @"tag2" : @"test2"} networkType:[KontextHelper getNetType]];
    
    XCTAssert([request.parameters[@"app_id"] isEqualToString:@"b2f7f966-d8cc-11e4-bed1-df8f05be55bb"]);
    XCTAssert([request.parameters[@"tags"][@"tag1"] isEqualToString:@"test1"]);
    XCTAssert([request.path isEqualToString:@"players/12345"]);
    
    let urlRequest = request.request;
    
    XCTAssert([urlRequest.URL.absoluteString isEqualToString:@"https://api.kontext.in/api/v1/players/12345"]);
    XCTAssert([urlRequest.HTTPMethod isEqualToString:@"PUT"]);
    XCTAssert([urlRequest.allHTTPHeaderFields[@"Content-Type"] isEqualToString:@"application/json"]);
}

-(void)testInvalidJSONTags {
    @synchronized(KontextClientOverrider.lastHTTPRequest) {
        [self initKontextAndThreadWait];
        
        //this test will also print invalid JSON warnings to console
        
        let invalidJson = @{@{@"invalid1" : @"invalid2"} : @"test"}; //Keys are required to be strings, this would crash the app if not handled appropriately
        
        let request = [KontextRequestSendEventsToServer withUserId:@"12345" appId:@"b2f7f966-d8cc-11e4-bed1-df8f05be55bb" tags:invalidJson networkType:[KontextHelper getNetType]];
        
        let urlRequest = request.request;
        
        XCTAssertNil(urlRequest.HTTPBody);
        
        //test Kontext sendEvents method
        [Kontext sendEvents:invalidJson];
        
        [NSObjectOverrider runPendingSelectors];
        [self runBackgroundThreads];
        [NSObjectOverrider runPendingSelectors];
        
        //the request should fail and the HTTP request should not contain the invalid tags
        XCTAssertNil(KontextClientOverrider.lastHTTPRequest[@"tags"]);
    }
}

@end
