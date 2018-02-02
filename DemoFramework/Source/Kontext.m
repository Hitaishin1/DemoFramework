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

#import "Kontext.h"
#import "KontextInternal.h"
#import "KontextTracker.h"
#import "KontextTrackIAP.h"
#import "KontextLocation.h"
#import "KontextReachability.h"
#import "KontextJailbreakDetection.h"
#import "KontextMobileProvision.h"
#import "KontextAlertViewDelegate.h"
#import "KontextHelper.h"
#import "UNUserNotificationCenter+Kontext.h"
#import "KontextSelectorHelpers.h"
#import "UIApplicationDelegate+Kontext.h"
#import "NSString+Kontext.h"
#import "KontextTrackFirebaseAnalytics.h"
#import "KontextNotificationServiceExtensionHandler.h"
#import "KontextNotificationPayload+Internal.h"
#import "KontextNotificationSettings.h"
#import "KontextNotificationSettingsIOS10.h"
#import "KontextNotificationSettingsIOS8.h"
#import "KontextNotificationSettingsIOS7.h"
#import "KontextObservable.h"

#import <stdlib.h>
#import <stdio.h>
#import <sys/types.h>
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

#import "Requests.h"
#import "KontextClient.h"

#import <UserNotifications/UserNotifications.h>
#import <SystemConfiguration/CaptiveNetwork.h>

#define NOTIFICATION_TYPE_NONE 0
#define NOTIFICATION_TYPE_BADGE 1
#define NOTIFICATION_TYPE_SOUND 2
#define NOTIFICATION_TYPE_ALERT 4
#define NOTIFICATION_TYPE_ALL 7

#define ERROR_PUSH_CAPABLILITY_DISABLED    -13
#define ERROR_PUSH_DELEGATE_NEVER_FIRED    -14
#define ERROR_PUSH_SIMULATOR_NOT_SUPPORTED -15
#define ERROR_PUSH_UNKNOWN_APNS_ERROR      -16
#define ERROR_PUSH_OTHER_3000_ERROR        -17
#define ERROR_PUSH_NEVER_PROMPTED          -18
#define ERROR_PUSH_PROMPT_NEVER_ANSWERED   -19

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static KON_TEXT_LOG_LEVEL _nsLogLevel = KON_TEXT_LL_WARN;
static KON_TEXT_LOG_LEVEL _visualLogLevel = KON_TEXT_LL_NONE;

NSString* const kKontextSettingsKeyAutoPrompt = @"kKontextSettingsKeyAutoPrompt";

/* Enable the default in-app alerts*/
NSString* const kKontextSettingsKeyInAppAlerts = @"kKontextSettingsKeyInAppAlerts";

/* Enable the default in-app launch urls*/
NSString* const kKontextSettingsKeyInAppLaunchURL = @"kKontextSettingsKeyInAppLaunchURL";

/* Set InFocusDisplayOption value must be an KontextNotificationDisplayType enum*/
NSString* const kKontextSettingsKeyInFocusDisplayOption = @"kKontextSettingsKeyInFocusDisplayOption";

/* Omit no app_id error logging, for use with wrapper SDKs. */
NSString* const kKontextSettingsKeyInOmitNoAppIdLogging = @"kKontextSettingsKeyInOmitNoAppIdLogging";


@implementation KontextPermissionSubscriptionState
- (NSString*)description {
    static NSString* format = @"<KontextPermissionSubscriptionState:\npermissionStatus: %@,\nsubscriptionStatus: %@\n>";
    return [NSString stringWithFormat:format, _permissionStatus, _subscriptionStatus];
}
- (NSDictionary*)toDictionary {
    return @{@"permissionStatus": [_permissionStatus toDictionary],
             @"subscriptionStatus": [_subscriptionStatus toDictionary]};
}
@end

@interface KontextPendingCallbacks : NSObject
 @property KontextResultSuccessBlock successBlock;
 @property KontextFailureBlock failureBlock;
@end

@implementation KontextPendingCallbacks
@end

@implementation Kontext

NSString* const KONTEXT_VERSION = @"010000";
static NSString* mSDKType = @"native";
static BOOL coldStartFromTapOnNotification = NO;

static NSMutableArray* pendingSendEventCallbacks;
static KontextResultSuccessBlock pendingGetTagsSuccessBlock;
static KontextFailureBlock pendingGetTagsFailureBlock;

// Has attempted to register for push notifications with Apple since app was installed.
static BOOL registeredWithApple = NO;

// UIApplication-registerForRemoteNotifications has been called but a success or failure has not triggered yet.
static BOOL waitingForApnsResponse = false;

// Under Capabilities is "Background Modes" > "Remote notifications" enabled.
static BOOL backgroundModesEnabled = false;

static KontextTrackIAP* trackIAPPurchase;
static NSString* app_id;
//static NSString* auth_token;
NSString* emailToSet;
NSMutableDictionary* tagsToSend;
KontextResultSuccessBlock tokenUpdateSuccessBlock;
KontextFailureBlock tokenUpdateFailureBlock;

int mLastNotificationTypes = -1;
static int mSubscriptionStatus = -1;

KontextIdsAvailableBlock idsAvailableBlockWhenReady;
BOOL disableBadgeClearing = NO;
BOOL mShareLocation = YES;

static KontextNotificationDisplayType _inFocusDisplayType = KontextNotificationDisplayTypeInAppAlert;
+ (void)setInFocusDisplayType:(KontextNotificationDisplayType)value {
    NSInteger op = value;
    if (![KontextHelper isIOSVersionGreaterOrEqual:10] && KontextNotificationDisplayTypeNotification == op)
        op = KontextNotificationDisplayTypeInAppAlert;
    
    _inFocusDisplayType = op;
}
+ (KontextNotificationDisplayType)inFocusDisplayType {
    return _inFocusDisplayType;
}

// iOS version implemation
static NSObject<KontextNotificationSettings>* _osNotificationSettings;
+ (NSObject<KontextNotificationSettings>*)osNotificationSettings {
    if (!_osNotificationSettings) {
        if ([KontextHelper isIOSVersionGreaterOrEqual:10])
            _osNotificationSettings = [KontextNotificationSettingsIOS10 new];
        else if ([KontextHelper isIOSVersionGreaterOrEqual:8])
            _osNotificationSettings = [KontextNotificationSettingsIOS8 new];
        else
            _osNotificationSettings = [KontextNotificationSettingsIOS7 new];
    }
    return _osNotificationSettings;
}


// static property def for currentPermissionState
static KontextPermissionState* _currentPermissionState;
+ (KontextPermissionState*)currentPermissionState {
    if (!_currentPermissionState) {
        _currentPermissionState = [KontextPermissionState alloc];
        _currentPermissionState = [_currentPermissionState initAsTo];
        [self lastPermissionState]; // Trigger creation
        [_currentPermissionState.observable addObserver:[KontextPermissionChangedInternalObserver alloc]];
    }
    return _currentPermissionState;
}

// static property def for previous KontextSubscriptionState
static KontextPermissionState* _lastPermissionState;
+ (KontextPermissionState*)lastPermissionState {
    if (!_lastPermissionState)
        _lastPermissionState = [[KontextPermissionState alloc] initAsFrom];
    return _lastPermissionState;
}
+ (void)setLastPermissionState:(KontextPermissionState *)lastPermissionState {
    _lastPermissionState = lastPermissionState;
}


// static property def for current KontextSubscriptionState
static KontextSubscriptionState* _currentSubscriptionState;
+ (KontextSubscriptionState*)currentSubscriptionState {
    if (!_currentSubscriptionState) {
        _currentSubscriptionState = [KontextSubscriptionState alloc];
        _currentSubscriptionState = [_currentSubscriptionState initAsToWithPermision:self.currentPermissionState.accepted];
        mLastNotificationTypes = _currentPermissionState.notificationTypes;
        [self.currentPermissionState.observable addObserver:_currentSubscriptionState];
        [_currentSubscriptionState.observable addObserver:[KontextSubscriptionChangedInternalObserver alloc]];
    }
    return _currentSubscriptionState;
}

static KontextSubscriptionState* _lastSubscriptionState;
+ (KontextSubscriptionState*)lastSubscriptionState {
    if (!_lastSubscriptionState) {
        _lastSubscriptionState = [KontextSubscriptionState alloc];
        _lastSubscriptionState = [_lastSubscriptionState initAsFrom];
    }
    return _lastSubscriptionState;
}
+ (void)setLastSubscriptionState:(KontextSubscriptionState*)lastSubscriptionState {
    _lastSubscriptionState = lastSubscriptionState;
}


// static property def to add developer's KontextPermissionStateChanges observers to.
static ObserablePermissionStateChangesType* _permissionStateChangesObserver;
+ (ObserablePermissionStateChangesType*)permissionStateChangesObserver {
    if (!_permissionStateChangesObserver)
        _permissionStateChangesObserver = [[KontextObservable alloc] initWithChangeSelector:@selector(onKontextPermissionChanged:)];
    return _permissionStateChangesObserver;
}

static ObserableSubscriptionStateChangesType* _subscriptionStateChangesObserver;
+ (ObserableSubscriptionStateChangesType*)subscriptionStateChangesObserver {
    if (!_subscriptionStateChangesObserver)
        _subscriptionStateChangesObserver = [[KontextObservable alloc] initWithChangeSelector:@selector(onKontextSubscriptionChanged:)];
    return _subscriptionStateChangesObserver;
}

+ (void)setMSubscriptionStatus:(NSNumber*)status {
    mSubscriptionStatus = [status intValue];
}
    
+ (NSString*)app_id {
    return app_id;
}

+ (NSString*)sdk_version_raw {
	return KONTEXT_VERSION;
}

+ (NSString*)sdk_semantic_version {

	// examples:
	// KONTEXT_VERSION = @"020402" returns 2.4.2
	// KONTEXT_VERSION = @"001000" returns 0.10.0
	// so that's 6 digits, where the first two are the major version
	// the second two are the minor version and that last two, the patch.
	// c.f. http://semver.org/

	return [KONTEXT_VERSION one_getSemanticVersion];
}

+ (NSString*)mUserId {
    return self.currentSubscriptionState.userId;
}

+ (void)setMSDKType:(NSString*)type {
    mSDKType = type;
}

+ (void) setWaitingForApnsResponse:(BOOL)value {
    waitingForApnsResponse = value;
}

+ (void)clearStatics {
    app_id = nil;
    _osNotificationSettings = nil;
    waitingForApnsResponse = false;
    mLastNotificationTypes = -1;
    
    _lastPermissionState = nil;
    _currentPermissionState = nil;
    
    _lastSubscriptionState = nil;
    _currentSubscriptionState = nil;
    
    _permissionStateChangesObserver = nil;
    _subscriptionStateChangesObserver = nil;
}

// Set to false as soon as it's read.
+ (BOOL)coldStartFromTapOnNotification {
    BOOL val = coldStartFromTapOnNotification;
    coldStartFromTapOnNotification = NO;
    return val;
}
    
+ (id)initWithLaunchOptions:(NSDictionary*)launchOptions appId:(NSString*)appId appSecret:(NSString*)appSecret {
    return [self initWithLaunchOptions: launchOptions appId: appId appSecret:appSecret handleNotificationReceived: NULL handleNotificationAction : NULL settings: @{kKontextSettingsKeyAutoPrompt : @YES, kKontextSettingsKeyInAppAlerts : @YES, kKontextSettingsKeyInAppLaunchURL : @YES}];
}

+ (id)initWithLaunchOptions:(NSDictionary*)launchOptions appId:(NSString*)appId appSecret:(NSString*)appSecret handleNotificationAction:(KontextHandleNotificationActionBlock)actionCallback {
    return [self initWithLaunchOptions: launchOptions appId: appId appSecret:appSecret handleNotificationReceived: NULL handleNotificationAction : actionCallback settings: @{kKontextSettingsKeyAutoPrompt : @YES, kKontextSettingsKeyInAppAlerts : @YES, kKontextSettingsKeyInAppLaunchURL : @YES}];
}

+ (id)initWithLaunchOptions:(NSDictionary*)launchOptions appId:(NSString*)appId appSecret:(NSString*)appSecret handleNotificationAction:(KontextHandleNotificationActionBlock)actionCallback settings:(NSDictionary*)settings {
    return [self initWithLaunchOptions: launchOptions appId: appId appSecret:appSecret handleNotificationReceived: NULL handleNotificationAction : actionCallback settings: settings];
}

// NOTE: Wrapper SDKs such as Unity3D will call this method with appId set to nil so open events are not lost.
//         Ensure a 2nd call can be made later with the appId from the developer's code.
+ (id)initWithLaunchOptions:(NSDictionary*)launchOptions appId:(NSString*)appId appSecret:(NSString*)appSecret handleNotificationReceived:(KontextHandleNotificationReceivedBlock)receivedCallback handleNotificationAction:(KontextHandleNotificationActionBlock)actionCallback settings:(NSDictionary*)settings {
    
    let userDefaults = [NSUserDefaults standardUserDefaults];
    
    let success = [self initAppId:appId
                 withUserDefaults:userDefaults
                     withSettings:settings];
    
    if (!success)
        return self;
    //// Check the Auth Token
    [self initAuthTokenWithAppId:appId withAppSecret:appSecret withUserDefaults:userDefaults];
    
    if (mShareLocation)
       [KontextLocation getLocation:false];
    
    if (self) {
        [KontextHelper notificationBlocks: receivedCallback : actionCallback];
        
        if ([KontextHelper isIOSVersionGreaterOrEqual:8])
            registeredWithApple = self.currentPermissionState.accepted;
        else
            registeredWithApple = self.currentSubscriptionState.pushToken || [userDefaults boolForKey:@"GT_REGISTERED_WITH_APPLE"];
        
        // Check if disabled in-app launch url if passed a NO
        if (settings[kKontextSettingsKeyInAppLaunchURL] && [settings[kKontextSettingsKeyInAppLaunchURL] isKindOfClass:[NSNumber class]])
            [self enableInAppLaunchURL:settings[kKontextSettingsKeyInAppLaunchURL]];
        else
            [self enableInAppLaunchURL:@YES];
        
        var autoPrompt = YES;
        if (settings[kKontextSettingsKeyAutoPrompt] && [settings[kKontextSettingsKeyAutoPrompt] isKindOfClass:[NSNumber class]])
            autoPrompt = [settings[kKontextSettingsKeyAutoPrompt] boolValue];
        
        // Register with Apple's APNS server if we registed once before or if auto-prompt hasn't been disabled.
        if (autoPrompt || registeredWithApple)
            [self registerForPushNotifications];
        else
            [self registerForAPNsToken];
        
        
        /* Check if in-app setting passed assigned
            LOGIC: Default - InAppAlerts enabled / InFocusDisplayOption InAppAlert.
            Priority for kKontextSettingsKeyInFocusDisplayOption.
        */
        NSNumber *IAASetting = settings[kKontextSettingsKeyInAppAlerts];
        let inAppAlertsPassed = IAASetting && (IAASetting.integerValue == 0 || IAASetting.integerValue == 1);
        
        NSNumber *IFDSetting = settings[kKontextSettingsKeyInFocusDisplayOption];
        let inFocusDisplayPassed = IFDSetting && IFDSetting.integerValue > -1 && IFDSetting.integerValue < 3;
        
        if (inAppAlertsPassed || inFocusDisplayPassed) {
            if (!inFocusDisplayPassed)
                self.inFocusDisplayType = (KontextNotificationDisplayType)IAASetting.integerValue;
            else
                self.inFocusDisplayType = (KontextNotificationDisplayType)IFDSetting.integerValue;
        }

        if (self.currentSubscriptionState.userId)
            [self registerUser];
        else {
            [self.osNotificationSettings getNotificationPermissionState:^(KontextPermissionState *state) {
                if (state.answeredPrompt)
                    [self registerUser];
                else
                    [self performSelector:@selector(registerUser) withObject:nil afterDelay:30.0f];
            }];
        }
    }
 
    /*
     * No need to call the handleNotificationOpened:userInfo as it will be called from one of the following selectors
     *  - application:didReceiveRemoteNotification:fetchCompletionHandler
     *  - userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler (iOS10)
     */
    
    // Cold start from tap on a remote notification
    //  NOTE: launchOptions may be nil if tapping on a notification's action button.
    NSDictionary* userInfo = [launchOptions objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (userInfo)
        coldStartFromTapOnNotification = YES;

    [self clearBadgeCount:false];
    
    if (!trackIAPPurchase && [KontextTrackIAP canTrack])
        trackIAPPurchase = [[KontextTrackIAP alloc] init];
    
    if (NSClassFromString(@"UNUserNotificationCenter"))
       [KontextHelper clearCachedMedia];
    
    if ([KontextTrackFirebaseAnalytics needsRemoteParams]) {
        [KontextTrackFirebaseAnalytics init];
        [self downloadIOSParams];
    }
    
    return self;
}
+(bool)initAppId:(NSString*)appId withUserDefaults:(NSUserDefaults*)userDefaults withSettings:(NSDictionary*)settings {
    if (appId)
        app_id = appId;
    else {
        // Read from .plist if not passed in with this method call.
        app_id = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"Kontext_APPID"];
        if (app_id == nil)
            app_id = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"GameThrive_APPID"];
    }
    
    if (!app_id) {
        if (![settings[kKontextSettingsKeyInOmitNoAppIdLogging] boolValue])
            kontext_Log(KON_TEXT_LL_FATAL, @"Kontext AppId never set!");
        app_id  = [userDefaults stringForKey:@"GT_APP_ID"];
    }
    else if (![app_id isEqualToString:[userDefaults stringForKey:@"GT_APP_ID"]]) {
        // Handle changes to the app id. This might happen on a developer's device when testing
        // Will also run the first time Kontext is initialized
        [userDefaults setObject:app_id forKey:@"GT_APP_ID"];
        [userDefaults setObject:nil forKey:@"GT_PLAYER_ID"];
        [userDefaults synchronize];
    }
    
    if (!app_id || ![[NSUUID alloc] initWithUUIDString:app_id]) {
        kontext_Log(KON_TEXT_LL_FATAL, @"Kontext AppId format is invalid.\nExample: 'b2f7f966-d8cc-11e4-bed1-df8f05be55ba'\n");
        return false;
    }
    
    if ([@"b2f7f966-d8cc-11e4-bed1-df8f05be55ba" isEqualToString:appId] || [@"5eb5a37e-b458-11e3-ac11-000c2940e62c" isEqualToString:appId])
        kontext_Log(KON_TEXT_LL_WARN, @"Kontext Example AppID detected, please update to your app's id found on Kontext.com");
    
    return true;
}

#pragma mark : New Function for Auth Token
+(void)initAuthTokenWithAppId:(NSString*)appId withAppSecret:(NSString*)appSecret withUserDefaults:(NSUserDefaults*)userDefaults
{
    NSString* auth_token = [userDefaults stringForKey:@"GT_AUTH_TOKEN"];

    if ([auth_token isEqualToString:@""] || (!auth_token))
    {
        [KontextClient.sharedClient executeRequestForAuth:[KontextRequestGetAuthToken withAppId:appId appSecret:appSecret] onSuccess:^(NSDictionary *result) {
            [userDefaults setObject:[result objectForKey:@"token"] forKey:@"GT_AUTH_TOKEN"];
             NSLog(@"KONTEXT - Token generatedl: %@", [result objectForKey:@"token"]);
        } onFailure:nil];
    }
}

+(void)downloadIOSParams {
    [KontextClient.sharedClient executeRequest:[KontextRequestGetIosParams withUserId:self.currentSubscriptionState.userId appId:self.app_id] onSuccess:^(NSDictionary *result) {
        [KontextTrackFirebaseAnalytics updateFromDownloadParams:result];
    } onFailure:nil];
}

+ (void)setLogLevel:(KON_TEXT_LOG_LEVEL)nsLogLevel visualLevel:(KON_TEXT_LOG_LEVEL)visualLogLevel {
    NSLog(@"KONTEXT - Setting log level: %d", (int)nsLogLevel);
    _nsLogLevel = nsLogLevel; _visualLogLevel = visualLogLevel;
}

+ (void) kontext_Log:(KON_TEXT_LOG_LEVEL)logLevel message:(NSString*) message {
    kontext_Log(logLevel, message);
}

void kontext_Log(KON_TEXT_LOG_LEVEL logLevel, NSString* message) {
    NSString* levelString;
    switch (logLevel) {
        case KON_TEXT_LL_FATAL:
            levelString = @"FATAL: ";
            break;
        case KON_TEXT_LL_ERROR:
            levelString = @"ERROR: ";
            break;
        case KON_TEXT_LL_WARN:
            levelString = @"WARNING: ";
            break;
        case KON_TEXT_LL_INFO:
            levelString = @"INFO: ";
            break;
        case KON_TEXT_LL_DEBUG:
            levelString = @"DEBUG: ";
            break;
        case KON_TEXT_LL_VERBOSE:
            levelString = @"VERBOSE: ";
            break;
            
        default:
            break;
    }

    if (logLevel <= _nsLogLevel)
        NSLog(@"%@", [levelString stringByAppendingString:message]);
    
    if (logLevel <= _visualLogLevel) {
        [KontextHelper runOnMainThread:^{
            let alertView = [[UIAlertView alloc] initWithTitle:levelString
                                                       message:message
                                                      delegate:nil
                                             cancelButtonTitle:NSLocalizedString(@"Close", nil)
                                             otherButtonTitles:nil, nil];
            [alertView show];
        }];
    }
}


// iOS 8+, only tries to register for an APNs token
+ (BOOL)registerForAPNsToken {
    if (![KontextHelper isIOSVersionGreaterOrEqual:8])
        return false;
    
    if (waitingForApnsResponse)
        return true;
    
    id backgroundModes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UIBackgroundModes"];
    backgroundModesEnabled = (backgroundModes && [backgroundModes containsObject:@"remote-notification"]);
    
    // Only try to register for a pushToken if:
    //  - The user accepted notifications
    //  - "Background Modes" > "Remote Notifications" are enabled in Xcode
    if (![self.osNotificationSettings getNotificationPermissionState].accepted && !backgroundModesEnabled)
        return false;
    
    // Don't attempt to register again if there was a non-recoverable error.
    if (mSubscriptionStatus < -9)
        return false;
    
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:@"Firing registerForRemoteNotifications"];
    
    waitingForApnsResponse = true;
    [[UIApplication sharedApplication] registerForRemoteNotifications];
    
    return true;
}

+ (void)promptForPushNotificationsWithUserResponse:(void(^)(BOOL accepted))completionHandler {
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:[NSString stringWithFormat:@"registerForPushNotifications Called:waitingForApnsResponse: %d", waitingForApnsResponse]];
    
    self.currentPermissionState.hasPrompted = true;
    
    [self.osNotificationSettings promptForNotifications:completionHandler];
}

// This registers for a push token and prompts the user for notifiations permisions
//    Will trigger didRegisterForRemoteNotificationsWithDeviceToken on the AppDelegate when APNs responses.
+ (void)registerForPushNotifications {
    [self promptForPushNotificationsWithUserResponse:nil];
}


+ (KontextPermissionSubscriptionState*)getPermissionSubscriptionState {
    KontextPermissionSubscriptionState* status = [KontextPermissionSubscriptionState alloc];
    
    status.subscriptionStatus = self.currentSubscriptionState;
    status.permissionStatus = self.currentPermissionState;
    
    return status;
}


// onKontextPermissionChanged should only fire if something changed.
+ (void)addPermissionObserver:(NSObject<KontextPermissionObserver>*)observer {
    [self.permissionStateChangesObserver addObserver:observer];
    
    if ([self.currentPermissionState compare:self.lastPermissionState])
        [KontextPermissionChangedInternalObserver fireChangesObserver:self.currentPermissionState];
}
+ (void)removePermissionObserver:(NSObject<KontextPermissionObserver>*)observer {
    [self.permissionStateChangesObserver removeObserver:observer];
}


// onKontextSubscriptionChanged should only fire if something changed.
+ (void)addSubscriptionObserver:(NSObject<KontextSubscriptionObserver>*)observer {
    [self.subscriptionStateChangesObserver addObserver:observer];
    
    if ([self.currentSubscriptionState compare:self.lastSubscriptionState])
        [KontextSubscriptionChangedInternalObserver fireChangesObserver:self.currentSubscriptionState];
}
+ (void)removeSubscriptionObserver:(NSObject<KontextSubscriptionObserver>*)observer {
    [self.subscriptionStateChangesObserver removeObserver:observer];
}



// Block not assigned if userID nil and there is a device token
+ (void)IdsAvailable:(KontextIdsAvailableBlock)idsAvailableBlock {
    idsAvailableBlockWhenReady = idsAvailableBlock;
    [self fireIdsAvailableCallback];
}

+ (void) fireIdsAvailableCallback {
    if (!idsAvailableBlockWhenReady)
        return;
    if (!self.currentSubscriptionState.userId)
        return;
    
    // Ensure we are on the main thread incase app developer updates UI from the callback.
    [KontextHelper dispatch_async_on_main_queue: ^{
        id pushToken = [self getUsableDeviceToken];
        if (!idsAvailableBlockWhenReady)
            return;
        idsAvailableBlockWhenReady(self.currentSubscriptionState.userId, pushToken);
        if (pushToken)
           idsAvailableBlockWhenReady = nil;
    }];
}

#pragma mark : Send Screen Name
+ (void)sendScreen:(NSString*)screenName {
    NSMutableDictionary* obj = [NSMutableDictionary new];
    [obj setValue:@"screen_viewed" forKey:@"event_type"];
    [obj setValue:screenName forKey:@"event_payload"];
    [self sendEvents:obj];
}

#pragma mark : Get the User Attribute
+ (void)setUserAttributes:(NSDictionary*)keyValues {
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:keyValues
                                                       options:NSJSONWritingPrettyPrinted // Pass 0 if you don't care about the readability of the generated string
                                                         error:&error];
    NSString *jsonString;
    if (! jsonData) {
        NSLog(@"Got an error: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    
    let userDefaults = [NSUserDefaults standardUserDefaults];
    NSString *userAttributes = [userDefaults objectForKey:@"PREF_USER_ATTRIBUTE"];
    if (!userAttributes || ![userAttributes isEqualToString:jsonString]) {
        [self setUserAttributesInternal:jsonString];
    }
}

+ (void)setUserAttributesInternal:(NSString*)userAttributes {
    let userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setValue:userAttributes forKey:@"PREF_USER_ATTRIBUTE"];
    [userDefaults setValue:@"true" forKey:@"PREF_USER_ATTRIBUTE_STATE"];
    [userDefaults synchronize];
}
#pragma mark : Get Wifi Results

+ (void)getWifiResults:(NSString*)userAttributes {
    
    NSArray *interfaceNames = CFBridgingRelease(CNCopySupportedInterfaces());
    NSLog(@"%s: Supported interfaces: %@", __func__, interfaceNames);
    
    NSDictionary *SSIDInfo;
    for (NSString *interfaceName in interfaceNames) {
        SSIDInfo = CFBridgingRelease(
                                     CNCopyCurrentNetworkInfo((__bridge CFStringRef)interfaceName));
        NSLog(@"%s: %@ => %@", __func__, interfaceName, SSIDInfo);
        
        BOOL isNotEmpty = (SSIDInfo.count > 0);
        if (isNotEmpty) {
            break;
        }
    }
    NSMutableDictionary *payloadObject = [[NSMutableDictionary alloc] init];
    [payloadObject setObject:SSIDInfo forKey:@"connected_state"];
    
    NSMutableDictionary *event = [[NSMutableDictionary alloc] init];
    [event setObject:@"wifi" forKey:@"event_type"];
    [event setObject:payloadObject forKey:@"event_payload"];

    [self sendEvents:event];
}
    
+ (void)sendEventsWithJsonString:(NSString*)jsonString {
    NSError* jsonError;
    
    NSData* data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary* keyValuePairs = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
    if (jsonError == nil) {
        [self sendEvents:keyValuePairs];
    } else {
        kontext_Log(KON_TEXT_LL_WARN,[NSString stringWithFormat: @"sendEvents JSON Parse Error: %@", jsonError]);
        kontext_Log(KON_TEXT_LL_WARN,[NSString stringWithFormat: @"sendEvents JSON Parse Error, JSON: %@", jsonString]);
    }
}

+ (void)sendEvents:(NSDictionary*)keyValuePair {
    [self sendEvents:keyValuePair onSuccess:nil onFailure:nil];
}

+ (void)sendEvents:(NSDictionary*)keyValuePair onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock {
   
    if (![NSJSONSerialization isValidJSONObject:keyValuePair]) {
        kontext_Log(KON_TEXT_LL_WARN, [NSString stringWithFormat:@"sendEvents JSON Invalid: The following key/value pairs you attempted to send as tags are not valid JSON: %@", keyValuePair]);
        return;
    }
    
    for (NSString *key in [keyValuePair allKeys]) {
        if ([keyValuePair[key] isKindOfClass:[NSDictionary class]]) {
            kontext_Log(KON_TEXT_LL_WARN, @"sendEvents Tags JSON must not contain nested objects");
            return;
        }
    }
    
    if (tagsToSend == nil)
        tagsToSend = [keyValuePair mutableCopy];
    else
        [tagsToSend addEntriesFromDictionary:keyValuePair];
    
    if (successBlock || failureBlock) {
        if (!pendingSendEventCallbacks)
            pendingSendEventCallbacks = [[NSMutableArray alloc] init];
        KontextPendingCallbacks* pendingCallbacks = [KontextPendingCallbacks alloc];
        pendingCallbacks.successBlock = successBlock;
        pendingCallbacks.failureBlock = failureBlock;
        [pendingSendEventCallbacks addObject:pendingCallbacks];
    }
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sendEventsToServer) object:nil];
    
    // Can't send tags yet as their isn't a player_id.
    //   tagsToSend will be sent with the POST create player call later in this case.
    if (self.currentSubscriptionState.userId)
       [KontextHelper performSelector:@selector(sendEventsToServer) onMainThreadOnObject:self withObject:nil afterDelay:5];
}

// Called only with a delay to batch network calls.
+ (void) sendEventsToServer {
    if (!tagsToSend)
        return;
    
    NSDictionary* nowSendingTags = tagsToSend;
    tagsToSend = nil;
    
    NSArray* nowProcessingCallbacks = pendingSendEventCallbacks;
    pendingSendEventCallbacks = nil;
    
    [KontextClient.sharedClient executeRequest:[KontextRequestSendEventsToServer withUserId:self.currentSubscriptionState.userId appId:self.app_id tags:nowSendingTags networkType:[KontextHelper getNetType]] onSuccess:^(NSDictionary *result) {
        if (nowProcessingCallbacks)
            for (KontextPendingCallbacks *callbackSet in nowProcessingCallbacks)
                if (callbackSet.successBlock)
                    callbackSet.successBlock(result);
    } onFailure:^(NSError *error) {
        if (nowProcessingCallbacks)
            for (KontextPendingCallbacks *callbackSet in nowProcessingCallbacks)
                if (callbackSet.failureBlock)
                    callbackSet.failureBlock(error);
    }];
}

+ (void)sendEvent:(NSString*)key value:(NSString*)value {
    [self sendEvent:key value:value onSuccess:nil onFailure:nil];
}

+ (void)sendEvent:(NSString*)key value:(NSString*)value onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock {
    [self sendEvents:[NSDictionary dictionaryWithObjectsAndKeys: value, key, nil] onSuccess:successBlock onFailure:failureBlock];
}
#pragma mark : Comment the Code
/* Comment the Code
+ (void)getTags:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock {
    if (!self.currentSubscriptionState.userId) {
        pendingGetTagsSuccessBlock = successBlock;
        pendingGetTagsFailureBlock = failureBlock;
        return;
    }
    
    [KontextClient.sharedClient executeRequest:[KontextRequestGetTags withUserId:self.currentSubscriptionState.userId appId:self.app_id] onSuccess:^(NSDictionary *result) {
        successBlock([result objectForKey:@"tags"]);
    } onFailure:failureBlock];
    
}

+ (void)getTags:(KontextResultSuccessBlock)successBlock {
    [self getTags:successBlock onFailure:nil];
}


+ (void)deleteTag:(NSString*)key onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock {
    [self deleteTags:@[key] onSuccess:successBlock onFailure:failureBlock];
}

+ (void)deleteTag:(NSString*)key {
    [self deleteTags:@[key] onSuccess:nil onFailure:nil];
}

+ (void)deleteTags:(NSArray*)keys {
    [self deleteTags:keys onSuccess:nil onFailure:nil];
}

+ (void)deleteTagsWithJsonString:(NSString*)jsonString {
    NSError* jsonError;
    
    NSData* data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSArray* keys = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&jsonError];
    if (jsonError == nil)
        [self deleteTags:keys];
    else {
        kontext_Log(KON_TEXT_LL_WARN,[NSString stringWithFormat: @"deleteTags JSON Parse Error: %@", jsonError]);
        kontext_Log(KON_TEXT_LL_WARN,[NSString stringWithFormat: @"deleteTags JSON Parse Error, JSON: %@", jsonString]);
    }
}

+ (void)deleteTags:(NSArray*)keys onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock {
    NSMutableDictionary* tags = [[NSMutableDictionary alloc] init];
    
    for(NSString* key in keys) {
        if (tagsToSend && tagsToSend[key]) {
            if (![tagsToSend[key] isEqual:@""])
                [tagsToSend removeObjectForKey:key];
        }
        else
            tags[key] = @"";
    }
    
    [self sendEvents:tags onSuccess:successBlock onFailure:failureBlock];
}
*/

+ (void)postNotification:(NSDictionary*)jsonData {
    [self postNotification:jsonData onSuccess:nil onFailure:nil];
}

+ (void)postNotification:(NSDictionary*)jsonData onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock {
    [KontextClient.sharedClient executeRequest:[KontextRequestPostNotification withAppId:self.app_id withJson:[jsonData mutableCopy]] onSuccess:^(NSDictionary *result) {
        NSData* jsonData = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        NSString* jsonResultsString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        
        kontext_Log(KON_TEXT_LL_DEBUG, [NSString stringWithFormat: @"HTTP create notification success %@", jsonResultsString]);
        if (successBlock)
            successBlock(result);
    } onFailure:^(NSError *error) {
        kontext_Log(KON_TEXT_LL_ERROR, @"Create notification failed");
        kontext_Log(KON_TEXT_LL_INFO, [NSString stringWithFormat: @"%@", error]);
        if (failureBlock)
            failureBlock(error);
    }];
}

+ (void)postNotificationWithJsonString:(NSString*)jsonString onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock {
    NSError* jsonError;
    
    NSData* data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary* jsonData = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
    if (jsonError == nil && jsonData != nil)
        [self postNotification:jsonData onSuccess:successBlock onFailure:failureBlock];
    else {
        kontext_Log(KON_TEXT_LL_WARN, [NSString stringWithFormat: @"postNotification JSON Parse Error: %@", jsonError]);
        kontext_Log(KON_TEXT_LL_WARN, [NSString stringWithFormat: @"postNotification JSON Parse Error, JSON: %@", jsonString]);
    }
}

+ (NSString*)parseNSErrorAsJsonString:(NSError*)error {
    NSString* jsonResponse;
    
    if (error.userInfo && error.userInfo[@"returned"]) {
        @try {
            NSData* jsonData = [NSJSONSerialization dataWithJSONObject:error.userInfo[@"returned"] options:0 error:nil];
            jsonResponse = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        } @catch(NSException* e) {
            kontext_Log(KON_TEXT_LL_ERROR, [NSString stringWithFormat:@"%@", e]);
            kontext_Log(KON_TEXT_LL_ERROR, [NSString stringWithFormat:@"%@",  [NSThread callStackSymbols]]);
            jsonResponse = @"{\"error\": \"Unknown error parsing error response.\"}";
        }
    }
    else
        jsonResponse = @"{\"error\": \"HTTP no response error\"}";
    
    return jsonResponse;
}

+ (void)enableInAppLaunchURL:(NSNumber*)enable {
    [[NSUserDefaults standardUserDefaults] setObject:enable forKey:@"KONTEXT_INAPP_LAUNCH_URL"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (void)setSubscription:(BOOL)enable {
    NSString* value = nil;
    if (!enable)
        value = @"no";

    [[NSUserDefaults standardUserDefaults] setObject:value forKey:@"KONTEXT_SUBSCRIPTION"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    self.currentSubscriptionState.userSubscriptionSetting = enable;
    
    if (app_id)
        [Kontext sendNotificationTypesUpdate];
}


+ (void)setLocationShared:(BOOL)enable {
   mShareLocation = enable;
}

+ (void) promptLocation {
    [KontextLocation getLocation:true];
}


+ (void) handleDidFailRegisterForRemoteNotification:(NSError*)err {
    waitingForApnsResponse = false;
    
    if (err.code == 3000) {
        if ([((NSString*)[err.userInfo objectForKey:NSLocalizedDescriptionKey]) rangeOfString:@"no valid 'aps-environment'"].location != NSNotFound) {
            // User did not enable push notification capability
            [Kontext setSubscriptionErrorStatus:ERROR_PUSH_CAPABLILITY_DISABLED];
            [Kontext kontext_Log:KON_TEXT_LL_ERROR message:@"ERROR! 'Push Notification' capability not turned on! Enable it in Xcode under 'Project Target' -> Capability."];
        }
        else {
            [Kontext setSubscriptionErrorStatus:ERROR_PUSH_OTHER_3000_ERROR];
            [Kontext kontext_Log:KON_TEXT_LL_ERROR message:[NSString stringWithFormat:@"ERROR! Unknown 3000 error returned from APNs when getting a push token: %@", err]];
        }
    }
    else if (err.code == 3010) {
        [Kontext setSubscriptionErrorStatus:ERROR_PUSH_SIMULATOR_NOT_SUPPORTED];
        [Kontext kontext_Log:KON_TEXT_LL_ERROR message:[NSString stringWithFormat:@"Error! iOS Simulator does not support push! Please test on a real iOS device. Error: %@", err]];
    }
    else {
        [Kontext setSubscriptionErrorStatus:ERROR_PUSH_UNKNOWN_APNS_ERROR];
        [Kontext kontext_Log:KON_TEXT_LL_ERROR message:[NSString stringWithFormat:@"Error registering for Apple push notifications! Error: %@", err]];
    }
    
    // iOS 7
    [self.osNotificationSettings onAPNsResponse:false];
}

+ (void)updateDeviceToken:(NSString*)deviceToken onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock {
    kontext_Log(KON_TEXT_LL_VERBOSE, @"updateDeviceToken:onSuccess:onFailure:");
    
    // iOS 7
    [self.osNotificationSettings onAPNsResponse:true];
    
    // Do not block next registration as there's a new token in hand
    nextRegistrationIsHighPriority = ![deviceToken isEqualToString:self.currentSubscriptionState.pushToken] || [self getNotificationTypes] != mLastNotificationTypes;
    
    if (!self.currentSubscriptionState.userId) {
        self.currentSubscriptionState.pushToken = deviceToken;
        tokenUpdateSuccessBlock = successBlock;
        tokenUpdateFailureBlock = failureBlock;
        
        // iOS 8+ - We get a token right away but give the user 30 sec to respond notification permission prompt.
        // The goal is to only have 1 server call.
        [self.osNotificationSettings getNotificationPermissionState:^(KontextPermissionState *status) {
            if (status.answeredPrompt)
                [Kontext registerUser];
            else
                [self registerUserAfterDelay];
        }];
        return;
    }
    
    if ([deviceToken isEqualToString:self.currentSubscriptionState.pushToken]) {
        if (successBlock)
            successBlock(nil);
        return;
    }
    
    self.currentSubscriptionState.pushToken = deviceToken;
    
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:@"Calling Kontext PUT updated pushToken!"];
    
    [KontextClient.sharedClient executeRequest:[KontextRequestUpdateDeviceToken withUserId:self.currentSubscriptionState.userId appId:self.app_id deviceToken:deviceToken notificationTypes:@([self getNotificationTypes])] onSuccess:successBlock onFailure:failureBlock];
    
    [self fireIdsAvailableCallback];
}

// Set to yes whenever a high priority registration fails ... need to make the next one a high priority to disregard the timer delay
bool nextRegistrationIsHighPriority = NO;

+ (BOOL)isHighPriorityCall {
    return !self.currentSubscriptionState.userId || nextRegistrationIsHighPriority;
}

static BOOL waitingForOneSReg = false;


+ (void)updateLastSessionDateTime {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    [[NSUserDefaults standardUserDefaults] setDouble:now forKey:@"GT_LAST_CLOSED_TIME"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+(BOOL)shouldRegisterNow {
    if (waitingForOneSReg)
        return false;
    
    // Figure out if should pass or not
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval lastTimeClosed = [[NSUserDefaults standardUserDefaults] doubleForKey:@"GT_LAST_CLOSED_TIME"];
    if (!lastTimeClosed) {
        [self updateLastSessionDateTime];
        return true;
    }
    
    if ([self isHighPriorityCall])
        return true;
    
    // Make sure last time we closed app was more than 30 secs ago
    const int minTimeThreshold = 30;
    NSTimeInterval delta = now - lastTimeClosed;
    return delta > minTimeThreshold;
}


+ (void)registerUserAfterDelay {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(registerUser) object:nil];
    [KontextHelper performSelector:@selector(registerUser) onMainThreadOnObject:self withObject:nil afterDelay:30.0f];
}

static dispatch_queue_t serialQueue;

+ (dispatch_queue_t) getRegisterQueue {
    return serialQueue;
}

+ (void)registerUser {
    if (waitingForApnsResponse) {
        [self registerUserAfterDelay];
        return;
    }
    
    if (!serialQueue)
        serialQueue = dispatch_queue_create("com.kontext.regiseruser", DISPATCH_QUEUE_SERIAL);
   
   dispatch_async(serialQueue, ^{
        [self registerUserInternal];
    });
}

+ (void)registerUserInternal {
    // Make sure we only call create or on_session once per open of the app.
    if (![self shouldRegisterNow])
        return;
    
    [KontextTrackFirebaseAnalytics trackInfluenceOpenEvent];
    
    waitingForOneSReg = true;
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(registerUser) object:nil];
    
    let infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString* build = infoDictionary[(NSString*)kCFBundleVersionKey];
    
    struct utsname systemInfo;
    uname(&systemInfo);
    let deviceModel = [NSString stringWithCString:systemInfo.machine
                                         encoding:NSUTF8StringEncoding];
    
    let dataDic = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                   app_id, @"app_id",
                   [[UIDevice currentDevice] systemVersion], @"device_os",
                   [NSNumber numberWithInt:(int)[[NSTimeZone localTimeZone] secondsFromGMT]], @"timezone",
                   [NSNumber numberWithInt:0], @"device_type",
                   [[[UIDevice currentDevice] identifierForVendor] UUIDString], @"ad_id",
                   KONTEXT_VERSION, @"sdk",
                   self.currentSubscriptionState.pushToken, @"identifier", // identifier MUST be at the end as it could be nil.
                   nil];
    
    if (deviceModel)
        dataDic[@"device_model"] = deviceModel;
    
    if (build)
        dataDic[@"game_version"] = build;
    
    if ([KontextJailbreakDetection isJailbroken])
        dataDic[@"rooted"] = @YES;
    
    dataDic[@"net_type"] = [KontextHelper getNetType];
    
    if (!self.currentSubscriptionState.userId) {
        dataDic[@"sdk_type"] = mSDKType;
        dataDic[@"ios_bundle"] = [[NSBundle mainBundle] bundleIdentifier];
    }
    
    let preferredLanguages = [NSLocale preferredLanguages];
    if (preferredLanguages && preferredLanguages.count > 0)
        dataDic[@"language"] = [preferredLanguages objectAtIndex:0];
    
    let notificationTypes = [self getNotificationTypes];
    mLastNotificationTypes = notificationTypes;
    dataDic[@"notification_types"] = [NSNumber numberWithInt:notificationTypes];
    
    let ASIdentifierManagerClass = NSClassFromString(@"ASIdentifierManager");
    if (ASIdentifierManagerClass) {
        id asIdManager = [ASIdentifierManagerClass valueForKey:@"sharedManager"];
        if ([[asIdManager valueForKey:@"advertisingTrackingEnabled"] isEqual:[NSNumber numberWithInt:1]])
            dataDic[@"as_id"] = [[asIdManager valueForKey:@"advertisingIdentifier"] UUIDString];
        else
            dataDic[@"as_id"] = @"OptedOut";
    }
    
    let releaseMode = [KontextMobileProvision releaseMode];
    if (releaseMode == UIApplicationReleaseDev || releaseMode == UIApplicationReleaseAdHoc || releaseMode == UIApplicationReleaseWildcard)
        dataDic[@"test_type"] = [NSNumber numberWithInt:releaseMode];
    
    if (tagsToSend) {
        dataDic[@"tags"] = tagsToSend;
        tagsToSend = nil;
    }
    
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:@"Calling Kontext create/on_session"];
    
    if (mShareLocation && [KontextLocation lastLocation]) {
        dataDic[@"lat"] = [NSNumber numberWithDouble:[KontextLocation lastLocation]->cords.latitude];
        dataDic[@"long"] = [NSNumber numberWithDouble:[KontextLocation lastLocation]->cords.longitude];
        dataDic[@"loc_acc_vert"] = [NSNumber numberWithDouble:[KontextLocation lastLocation]->verticalAccuracy];
        dataDic[@"loc_acc"] = [NSNumber numberWithDouble:[KontextLocation lastLocation]->horizontalAccuracy];
        [KontextLocation clearLastLocation];
    }
    
    [KontextClient.sharedClient executeRequest:[KontextRequestRegisterUser withData:dataDic userId:self.currentSubscriptionState.userId] onSuccess:^(NSDictionary *result) {
        waitingForOneSReg = false;
        
        // Success, no more high priority
        nextRegistrationIsHighPriority = NO;
        
        [self updateLastSessionDateTime];
        
        if (result[@"id"]) {
            self.currentSubscriptionState.userId = result[@"id"];
            [[NSUserDefaults standardUserDefaults] setObject:self.currentSubscriptionState.userId forKey:@"GT_PLAYER_ID"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            if (self.currentSubscriptionState.pushToken)
                [self updateDeviceToken:self.currentSubscriptionState.pushToken
                              onSuccess:tokenUpdateSuccessBlock
                              onFailure:tokenUpdateFailureBlock];
            
            if (tagsToSend)
                [self performSelector:@selector(sendEventsToServer) withObject:nil afterDelay:5];
            
            // try to send location
            [KontextLocation sendLocation];
            
            if (emailToSet) {
                [Kontext syncHashedEmail:emailToSet];
                emailToSet = nil;
            }
            
            [self fireIdsAvailableCallback];
            
            [self sendNotificationTypesUpdate];
            
            if (pendingGetTagsSuccessBlock) {
                // TODO: Comment the code
                //[Kontext getTags:pendingGetTagsSuccessBlock onFailure:pendingGetTagsFailureBlock];
                pendingGetTagsSuccessBlock = nil;
                pendingGetTagsFailureBlock = nil;
            }
            
        }
    } onFailure:^(NSError *error) {
        waitingForOneSReg = false;
        [Kontext kontext_Log:KON_TEXT_LL_ERROR message:[NSString stringWithFormat: @"Error registering with Kontext: %@", error]];
        
        //If the failed registration is priority, force the next one to be a high priority
        nextRegistrationIsHighPriority = YES;
    }];
}

+(NSString*)getUsableDeviceToken {
    if (mSubscriptionStatus < -1)
        return NULL;
    
    return self.currentPermissionState.accepted ? self.currentSubscriptionState.pushToken : NULL;
}

// Updates the server with the new user's notification setting or subscription status changes
+ (BOOL) sendNotificationTypesUpdate {
    // User changed notification settings for the app.
    if ([self getNotificationTypes] != -1 && self.currentSubscriptionState.userId && mLastNotificationTypes != [self getNotificationTypes]) {
        if (!self.currentSubscriptionState.pushToken) {
            if ([self registerForAPNsToken])
                return true;
        }
        
        mLastNotificationTypes = [self getNotificationTypes];
        
        [KontextClient.sharedClient executeRequest:[KontextRequestUpdateNotificationTypes withUserId:self.currentSubscriptionState.userId appId:self.app_id notificationTypes:@([self getNotificationTypes])] onSuccess:nil onFailure:nil];
        
        if ([self getUsableDeviceToken])
            [self fireIdsAvailableCallback];
        
        return true;
    }
    
    return false;
}

+ (void)sendPurchases:(NSArray*)purchases {
    if (!self.currentSubscriptionState.userId)
        return;
    
    [KontextClient.sharedClient executeRequest:[KontextRequestSendPurchases withUserId:self.currentSubscriptionState.userId appId:self.app_id withPurchases:purchases] onSuccess:nil onFailure:nil];
}


static NSString *_lastAppActiveMessageId;
+ (void)setLastAppActiveMessageId:(NSString*)value { _lastAppActiveMessageId = value; }

static NSString *_lastnonActiveMessageId;
+ (void)setLastnonActiveMessageId:(NSString*)value { _lastnonActiveMessageId = value; }

// Entry point for the following:
//  - 1. (iOS all) - Opening notifications
//  - 2. Notification received
//    - 2A. iOS 9  - Notification received while app is in focus.
//    - 2B. iOS 10 - Notification received/displayed while app is in focus.
+ (void)notificationOpened:(NSDictionary*)messageDict isActive:(BOOL)isActive {
    if (!app_id)
        return;
    
    kontext_Log(KON_TEXT_LL_VERBOSE, @"notificationOpened:isActive called!");
    
    NSDictionary* customDict = [messageDict objectForKey:@"os_data"];
    if (!customDict)
        customDict = [messageDict objectForKey:@"custom"];
    
    // Should be called first, other methods relay on this global state below.
    [KontextHelper lastMessageReceived:messageDict];
    
    if (isActive) {
        // Prevent duplicate calls
        let newId = [self checkForProcessedDups:customDict lastMessageId:_lastAppActiveMessageId];
        if ([@"dup" isEqualToString:newId])
            return;
        if (newId)
            _lastAppActiveMessageId = newId;
        
        let inAppAlert = (self.inFocusDisplayType == KontextNotificationDisplayTypeInAppAlert);
        
        // Make sure it is not a silent one do display, if inAppAlerts are enabled
        if (inAppAlert && ![KontextHelper isRemoteSilentNotification:messageDict]) {
            [KontextAlertView showInAppAlert:messageDict];
            return;
        }
        
        // App is active and a notification was received without inApp display. Display type is none or notification
        // Call Received Block
        [KontextHelper handleNotificationReceived:self.inFocusDisplayType];
        
        // Notify backend that user opened the notification
        NSString *messageId = [customDict objectForKey:@"i"];
        [Kontext submitNotificationOpened:messageId];
    }
    else {
        // Prevent duplicate calls
        let newId = [self checkForProcessedDups:customDict lastMessageId:_lastnonActiveMessageId];
        if ([@"dup" isEqualToString:newId])
            return;
        if (newId)
            _lastnonActiveMessageId = newId;
        
        //app was in background / not running and opened due to a tap on a notification or an action check what type
        NSString* actionSelected = NULL;
        KontextNotificationActionType type = KontextNotificationActionTypeOpened;
        if (messageDict[@"custom"][@"a"][@"actionSelected"]) {
            actionSelected = messageDict[@"custom"][@"a"][@"actionSelected"];
            type = KontextNotificationActionTypeActionTaken;
        }
        if (messageDict[@"actionSelected"]) {
            actionSelected = messageDict[@"actionSelected"];
            type = KontextNotificationActionTypeActionTaken;
        }
        
        // Call Action Block
        [KontextHelper handleNotificationAction:type actionID:actionSelected displayType:KontextNotificationDisplayTypeNotification];
        [Kontext handleNotificationOpened:messageDict isActive:isActive actionType:type displayType:KontextNotificationDisplayTypeNotification];
    }
}

+ (NSString*) checkForProcessedDups:(NSDictionary*)customDict lastMessageId:(NSString*)lastMessageId {
    if (customDict && customDict[@"i"]) {
        NSString* currentNotificationId = customDict[@"i"];
        if ([currentNotificationId isEqualToString:lastMessageId])
            return @"dup";
        return customDict[@"i"];
    }
    return nil;
}

+ (void)handleNotificationOpened:(NSDictionary*)messageDict
                        isActive:(BOOL)isActive
                      actionType:(KontextNotificationActionType)actionType
                     displayType:(KontextNotificationDisplayType)displayType {
    NSDictionary* customDict = [messageDict objectForKey:@"os_data"];
    if (customDict == nil)
        customDict = [messageDict objectForKey:@"custom"];
    
    // Notify backend that user opened the notification
    NSString* messageId = [customDict objectForKey:@"i"];
    [Kontext submitNotificationOpened:messageId];
    
    //Try to fetch the open url to launch
    [Kontext launchWebURL:[customDict objectForKey:@"u"]];
    
    [self clearBadgeCount:true];
    
    NSString* actionID = NULL;
    if (actionType == KontextNotificationActionTypeActionTaken) {
        actionID = messageDict[@"custom"][@"a"][@"actionSelected"];
        if(!actionID)
            actionID = messageDict[@"actionSelected"];
    }
    
    //Call Action Block
    [KontextHelper lastMessageReceived:messageDict];
    [KontextHelper handleNotificationAction:actionType actionID:actionID displayType:displayType];
}

+ (void)launchWebURL:(NSString*)openUrl {
    NSString* toOpenUrl = [KontextHelper trimURLSpacing:openUrl];
    
    if (toOpenUrl && [KontextHelper verifyURL:toOpenUrl]) {
        NSURL *url = [NSURL URLWithString:toOpenUrl];
        // Give the app resume animation time to finish when tapping on a notification from the notification center.
        // Isn't a requirement but improves visual flow.
        [KontextHelper performSelector:@selector(displayWebView:) withObject:url afterDelay:0.5];
    }
    
}

+ (void)submitNotificationOpened:(NSString*)messageId {
    //(DUPLICATE Fix): Make sure we do not upload a notification opened twice for the same messageId
    //Keep track of the Id for the last message sent
    NSString* lastMessageId = [[NSUserDefaults standardUserDefaults] objectForKey:@"GT_LAST_MESSAGE_OPENED_"];
    //Only submit request if messageId not nil and: (lastMessage is nil or not equal to current one)
    if(messageId && (!lastMessageId || ![lastMessageId isEqualToString:messageId])) {
        [KontextClient.sharedClient executeRequest:[KontextRequestSubmitNotificationOpened withUserId:self.currentSubscriptionState.userId appId:self.app_id wasOpened:YES messageId:messageId] onSuccess:nil onFailure:nil];
        [[NSUserDefaults standardUserDefaults] setObject:messageId forKey:@"GT_LAST_MESSAGE_OPENED_"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}
    
+ (BOOL) clearBadgeCount:(BOOL)fromNotifOpened {
    
    NSNumber *disableBadgeNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"Kontext_disable_badge_clearing"];
    
    if (disableBadgeNumber)
        disableBadgeClearing = [disableBadgeNumber boolValue];
    else
        disableBadgeClearing = NO;
    
    if (disableBadgeClearing ||
        ([KontextHelper isIOSVersionGreaterOrEqual:8] && [self.osNotificationSettings getNotificationPermissionState].notificationTypes & NOTIFICATION_TYPE_BADGE) == 0)
        return false;
    
    bool wasBadgeSet = [UIApplication sharedApplication].applicationIconBadgeNumber > 0;
    
    if ((!(NSFoundationVersionNumber > NSFoundationVersionNumber_iOS_7_1) && fromNotifOpened) || wasBadgeSet) {
        // Clear badges and notifications from this app.
        // Setting to 1 then 0 was needed to clear the notifications on iOS 6 & 7. (Otherwise you can click the notification multiple times.)
        // iOS 8+ auto dismisses the notification you tap on so only clear the badge (and notifications [side-effect]) if it was set.
        [[UIApplication sharedApplication] setApplicationIconBadgeNumber:1];
        [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
    }
    
    return wasBadgeSet;
}

+ (int) getNotificationTypes {
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message: [NSString stringWithFormat:@"getNotificationTypes:mSubscriptionStatus: %d", mSubscriptionStatus]];
    
    if (mSubscriptionStatus < -9)
        return mSubscriptionStatus;
    
    if (waitingForApnsResponse && !self.currentSubscriptionState.pushToken)
        return ERROR_PUSH_DELEGATE_NEVER_FIRED;
    
    KontextPermissionState* permissionStatus = [self.osNotificationSettings getNotificationPermissionState];
    
    if (!permissionStatus.hasPrompted)
        return ERROR_PUSH_NEVER_PROMPTED;
    if (!permissionStatus.answeredPrompt)
        return ERROR_PUSH_PROMPT_NEVER_ANSWERED;
    
    if (!self.currentSubscriptionState.userSubscriptionSetting)
        return -2;

    return permissionStatus.notificationTypes;
}

+ (void)setSubscriptionErrorStatus:(int)errorType {
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message: [NSString stringWithFormat:@"setSubscriptionErrorStatus: %d", errorType]];
    
    mSubscriptionStatus = errorType;
    if (self.currentSubscriptionState.userId)
        [self sendNotificationTypesUpdate];
    else
        [self registerUser];
}

// iOS 8.0+ only
//    User just responed to the iOS native notification permission prompt.
//    Also extra calls to registerUserNotificationSettings will fire this without prompting again.
+ (void)updateNotificationTypes:(int)notificationTypes {
    
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:[NSString stringWithFormat:@"updateNotificationTypes called: %d", notificationTypes]];
    
    if (![KontextHelper isIOSVersionGreaterOrEqual:10]) {
        NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
        [userDefaults setBool:true forKey:@"OS_NOTIFICATION_PROMPT_ANSWERED"];
        [userDefaults synchronize];
    }
    
    BOOL startedRegister = [self registerForAPNsToken];
    
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:[NSString stringWithFormat:@"startedRegister: %d", startedRegister]];
    
    [self.osNotificationSettings onNotificationPromptResponse:notificationTypes];
    
    if (mSubscriptionStatus == -2)
        return;
    
    if (!self.currentSubscriptionState.userId && !startedRegister)
        [Kontext registerUser];
    else if (self.currentSubscriptionState.pushToken)
        [self sendNotificationTypesUpdate];
    
    if ([self getUsableDeviceToken])
        [self fireIdsAvailableCallback];
}

+ (void)didRegisterForRemoteNotifications:(UIApplication*)app deviceToken:(NSData*)inDeviceToken {
    let trimmedDeviceToken = [[inDeviceToken description] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
    let parsedDeviceToken = [[trimmedDeviceToken componentsSeparatedByString:@" "] componentsJoinedByString:@""];
    
    [Kontext kontext_Log:KON_TEXT_LL_INFO message: [NSString stringWithFormat:@"Device Registered with Apple: %@", parsedDeviceToken]];
    
    waitingForApnsResponse = false;
    
    if (!app_id)
        return;
    
    [Kontext updateDeviceToken:parsedDeviceToken onSuccess:^(NSDictionary* results) {
        [Kontext kontext_Log:KON_TEXT_LL_INFO message:[NSString stringWithFormat: @"Device Registered with Kontext: %@", self.currentSubscriptionState.userId]];
    } onFailure:^(NSError* error) {
        [Kontext kontext_Log:KON_TEXT_LL_ERROR message:[NSString stringWithFormat: @"Error in Kontext Registration: %@", error]];
    }];
}
    
+ (BOOL)remoteSilentNotification:(UIApplication*)application UserInfo:(NSDictionary*)userInfo completionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    var startedBackgroundJob = false;
    
    NSDictionary* richData = nil;
    
    // TODO: Look into why the userInfo payload would be different here for displaying vs opening....
    // Check for buttons or attachments pre-2.4.0 version
    if ((userInfo[@"os_data"][@"buttons"] && [userInfo[@"os_data"][@"buttons"] isKindOfClass:[NSDictionary class]]) || userInfo[@"at"] || userInfo[@"o"])
        richData = userInfo;
    
    // Generate local notification for action button and/or attachments.
    if (richData) {
        let osPayload = [KontextNotificationPayload parseWithApns:userInfo];
        
        if ([KontextHelper isIOSVersionGreaterOrEqual:10]) {
            startedBackgroundJob = true;
            [KontextHelper addNotificationRequest:osPayload completionHandler:completionHandler];
        }
        else {
            let notification = [KontextHelper prepareUILocalNotification:osPayload];
            [[UIApplication sharedApplication] scheduleLocalNotification:notification];
        }
    }
    // Method was called due to a tap on a notification - Fire open notification
    else if (application.applicationState != UIApplicationStateBackground) {
        [KontextHelper lastMessageReceived:userInfo];
        if (application.applicationState == UIApplicationStateActive)
            [KontextHelper handleNotificationReceived:KontextNotificationDisplayTypeNotification];
        [Kontext notificationOpened:userInfo isActive:NO];
        return startedBackgroundJob;
    }
    // content-available notification received in the background - Fire handleNotificationReceived block in app
    else {
        [KontextHelper lastMessageReceived:userInfo];
        if ([KontextHelper isRemoteSilentNotification:userInfo])
            [KontextHelper handleNotificationReceived:KontextNotificationDisplayTypeNone];
        else
            [KontextHelper handleNotificationReceived:KontextNotificationDisplayTypeNotification];
    }
    
    return startedBackgroundJob;
}

// iOS 8-9 - Entry point when Kontext action button notification is displayed or opened.
+ (void)processLocalActionBasedNotification:(UILocalNotification*) notification identifier:(NSString*)identifier {
    if (!notification.userInfo)
        return;

    let userInfo = [KontextHelper formatApsPayloadIntoStandard:notification.userInfo identifier:identifier];
    
    if (!userInfo)
        return;
    
    let isActive = [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive;
    [Kontext notificationOpened:userInfo isActive:isActive];
    
    // Notification Tapped or notification Action Tapped
    if (!isActive)
        [self handleNotificationOpened:userInfo
                              isActive:isActive
                            actionType:KontextNotificationActionTypeActionTaken
                           displayType:KontextNotificationDisplayTypeNotification];
}

+ (void)syncHashedEmail:(NSString *)email {
    if (!email)
        return;
    
    let trimmedEmail = [email stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    if (![KontextHelper isValidEmail:trimmedEmail])
        return;
    
    if (!self.currentSubscriptionState.userId) {
        emailToSet = email;
        return;
    }
    
    [KontextClient.sharedClient executeRequest:[KontextRequestSyncHashedEmail withUserId:self.currentSubscriptionState.userId appId:self.app_id email:trimmedEmail networkType:[KontextHelper getNetType]] onSuccess:nil onFailure:nil];
}

// Called from the app's Notification Service Extension
+ (UNMutableNotificationContent*)didReceiveNotificationExtensionRequest:(UNNotificationRequest*)request withMutableNotificationContent:(UNMutableNotificationContent*)replacementContent {
    
    return [KontextNotificationServiceExtensionHandler
            didReceiveNotificationExtensionRequest:request
            withMutableNotificationContent:replacementContent];
}


// Called from the app's Notification Service Extension
+ (UNMutableNotificationContent*)serviceExtensionTimeWillExpireRequest:(UNNotificationRequest*)request withMutableNotificationContent:(UNMutableNotificationContent*)replacementContent {
    return [KontextNotificationServiceExtensionHandler
            serviceExtensionTimeWillExpireRequest:request
            withMutableNotificationContent:replacementContent];
}
@end

// Swizzles UIApplication class to swizzling the following:
//   - UIApplication
//      - setDelegate:
//        - Used to swizzle all UIApplicationDelegate selectors on the passed in class.
//        - Almost always this is the AppDelegate class but since UIApplicationDelegate is an "interface" this could be any class.
//   - UNUserNotificationCenter
//     - setDelegate:
//        - For iOS 10 only, swizzle all UNUserNotificationCenterDelegate selectors on the passed in class.
//         -  This may or may not be set so we set our own now in registerAsUNNotificationCenterDelegate to an empty class.
//
//  Note1: Do NOT move this category to it's own file. This is required so when the app developer calls Kontext.initWithLaunchOptions this load+
//            will fire along with it. This is due to how iOS loads .m files into memory instead of classes.
//  Note2: Do NOT directly add swizzled selectors to this category as if this class is loaded into the runtime twice unexpected results will occur.
//            The kontextLoadedTagSelector: selector is used a flag to prevent double swizzling if this library is loaded twice.
@implementation UIApplication (Kontext)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)
+ (void)load {
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:@"UIApplication(Kontext) LOADED!"];
    
    // Prevent Xcode storyboard rendering process from crashing with custom IBDesignable Views
    // https://github.com/Kontext/Kontext-iOS-SDK/issues/160
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    if ([[processInfo processName] isEqualToString:@"IBDesignablesAgentCocoaTouch"])
        return;
    
    if (SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(@"7.0"))
        return;

    // Double loading of class detection.
    BOOL existing = injectSelector([KontextAppDelegate class], @selector(kontextLoadedTagSelector:), self, @selector(kontextLoadedTagSelector:));
    if (existing) {
        [Kontext kontext_Log:KON_TEXT_LL_WARN message:@"Already swizzled UIApplication.setDelegate. Make sure the Kontext library wasn't loaded into the runtime twice!"];
        return;
    }
    
    // Swizzle - UIApplication delegate
    injectToProperClass(@selector(setKontextDelegate:), @selector(setDelegate:), @[], [KontextAppDelegate class], [UIApplication class]);
    
    [self setupUNUserNotificationCenterDelegate];
}

+(void)setupUNUserNotificationCenterDelegate {
    // Swizzle - UNUserNotificationCenter delegate - iOS 10+
    if (!NSClassFromString(@"UNUserNotificationCenter"))
        return;

    [KontextUNUserNotificationCenter swizzleSelectors];

    // Set our own delegate if one hasn't been set already from something else.
    [KontextHelper registerAsUNNotificationCenterDelegate];
}

@end


#pragma clang diagnostic pop
#pragma clang diagnostic pop
