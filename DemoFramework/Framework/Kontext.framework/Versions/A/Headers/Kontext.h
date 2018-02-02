/**
 * Modified MIT License
 *
 * Copyright 2017 Kontext
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

/***
 
 ### Setting up the SDK ###
 Follow the documentation from https://documentation.onesignal.com/docs/ios-sdk-setupto setup Kontext in your app.
 
 ### API Reference ###
 Follow the documentation from https://documentation.onesignal.com/docs/ios-sdk-api for a detailed explanation of the API.
 
 ### Troubleshoot ###
 Follow the documentation from https://documentation.onesignal.com/docs/troubleshooting-ios to fix common problems.
 
 For help on how to upgrade your code from 1.* SDK to 2.*: https://documentation.onesignal.com/docs/upgrading-to-ios-sdk-20
 
 ### More ###
 iOS Push Cert: https://documentation.onesignal.com/docs/generating-an-ios-push-certificate
 
***/

#import <Foundation/Foundation.h>

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 100000
#define XC8_AVAILABLE 1
#import <UserNotifications/UserNotifications.h>
#endif

/* The action type associated to an KontextNotificationAction object */
typedef NS_ENUM(NSUInteger, KontextNotificationActionType)  {
    KontextNotificationActionTypeOpened,
    KontextNotificationActionTypeActionTaken
};

/* The way a notification was displayed to the user */
typedef NS_ENUM(NSUInteger, KontextNotificationDisplayType) {
    /*Notification is silent, or app is in focus but InAppAlertNotifications are disabled*/
    KontextNotificationDisplayTypeNone,
    
    /*Default UIAlertView display*/
    KontextNotificationDisplayTypeInAppAlert,
    
    /*iOS native notification display*/
    KontextNotificationDisplayTypeNotification
};


@interface KontextNotificationAction : NSObject

/* The type of the notification action */
@property(readonly)KontextNotificationActionType type;

/* The ID associated with the button tapped. NULL when the actionType is NotificationTapped or InAppAlertClosed */
@property(readonly)NSString* actionID;

@end


// #### Notification Payload Received Object

@interface KontextNotificationPayload : NSObject

/* Unique Message Identifier */
@property(readonly)NSString* notificationID;

/* Unique Template Identifier */
@property(readonly)NSString* templateID;

/* Name of Template */
@property(readonly)NSString* templateName;

/* True when the key content-available is set to 1 in the aps payload.
   content-available is used to wake your app when the payload is received.
   See Apple's documenation for more details.
  https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623013-application
*/
@property(readonly)BOOL contentAvailable;

/* True when the key mutable-content is set to 1 in the aps payload.
 mutable-content is used to wake your Notification Service Extension to modify a notification.
 See Apple's documenation for more details.
 https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension
 */
@property(readonly)BOOL mutableContent;

/*
 Notification category key previously registered to display with.
 This overrides Kontext's actionButtons.
 See Apple's documenation for more details.
 https://developer.apple.com/library/content/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SupportingNotificationsinYourApp.html#//apple_ref/doc/uid/TP40008194-CH4-SW26
*/
@property(readonly)NSString* category;

/* The badge assigned to the application icon */
@property(readonly)NSUInteger badge;

/* The sound parameter passed to the notification
 By default set to UILocalNotificationDefaultSoundName */
@property(readonly)NSString* sound;

/* Main push content */
@property(readonly)NSString* title;
@property(readonly)NSString* subtitle;
@property(readonly)NSString* body;

/* Web address to launch within the app via a UIWebView */
@property(readonly)NSString* launchURL;

/* Additional key value properties set within the payload */
@property(readonly)NSDictionary* additionalData;

/* iOS 10+ : Attachments sent as part of the rich notification */
@property(readonly)NSDictionary* attachments;

/* Action buttons passed */
@property(readonly)NSArray *actionButtons;

/* Holds the original payload received
 Keep the raw value for users that would like to root the push */
@property(readonly)NSDictionary *rawPayload;

@end

// ## Kontext KontextNotification
@interface KontextNotification : NSObject

/* Notification Payload */
@property(readonly)KontextNotificationPayload* payload;

/* Display method of the notification */
@property(readonly)KontextNotificationDisplayType displayType;

/* Set to true when the user was able to see the notification and reacted to it
 Set to false when app is in focus and in-app alerts are disabled, or the remote notification is silent. */
@property(readonly, getter=wasShown)BOOL shown;

/* Set to true if the app was in focus when the notification  */
@property(readonly, getter=wasAppInFocus)BOOL isAppInFocus;

/* Set to true when the received notification is silent
 Silent means there is no alert, sound, or badge payload in the aps dictionary
 requires remote-notification within UIBackgroundModes array of the Info.plist */
@property(readonly, getter=isSilentNotification)BOOL silentNotification;

/* iOS 10+: Indicates whether or not the received notification has mutableContent : 1 assigned to its payload
 Used for UNNotificationServiceExtension to launch extension.
*/
#if XC8_AVAILABLE
@property(readonly, getter=hasMutableContent)BOOL mutableContent;
#endif

/* Convert object into an NSString that can be convertible into a custom Dictionary / JSON Object */
- (NSString*)stringify;

@end


@interface KontextNotificationOpenedResult : NSObject

@property(readonly)KontextNotification* notification;
@property(readonly)KontextNotificationAction *action;

/* Convert object into an NSString that can be convertible into a custom Dictionary / JSON Object */
- (NSString*)stringify;

@end;


typedef NS_ENUM(NSInteger, KontextNotificationPermission) {
    // The user has not yet made a choice regarding whether your app can show notifications.
    KontextNotificationPermissionNotDetermined = 0,
    
    // The application is not authorized to post user notifications.
    KontextNotificationPermissionDenied,
    
    // The application is authorized to post user notifications.
    KontextNotificationPermissionAuthorized
};



// Permission Classes
@interface KontextPermissionState : NSObject

@property (readonly, nonatomic) BOOL hasPrompted;
@property (readonly, nonatomic) KontextNotificationPermission status;
- (NSDictionary*)toDictionary;

@end

@interface KontextPermissionStateChanges : NSObject

@property (readonly) KontextPermissionState* to;
@property (readonly) KontextPermissionState* from;
- (NSDictionary*)toDictionary;

@end

@protocol KontextPermissionObserver <NSObject>
- (void)onKontextPermissionChanged:(KontextPermissionStateChanges*)stateChanges;
@end


// Subscription Classes
@interface KontextSubscriptionState : NSObject

@property (readonly, nonatomic) BOOL subscribed; // (yes only if userId, pushToken, and setSubscription exists / are true)
@property (readonly, nonatomic) BOOL userSubscriptionSetting; // returns setSubscription state.
@property (readonly, nonatomic) NSString* userId;    // AKA Kontext PlayerId
@property (readonly, nonatomic) NSString* pushToken; // AKA Apple Device Token
- (NSDictionary*)toDictionary;

@end

@interface KontextSubscriptionStateChanges : NSObject

@property (readonly) KontextSubscriptionState* to;
@property (readonly) KontextSubscriptionState* from;

- (NSDictionary*)toDictionary;

@end

@protocol KontextSubscriptionObserver <NSObject>
- (void)onKontextSubscriptionChanged:(KontextSubscriptionStateChanges*)stateChanges;
@end



// Permission+Subscription Classes
@interface KontextPermissionSubscriptionState : NSObject

@property (readonly) KontextPermissionState* permissionStatus;
@property (readonly) KontextSubscriptionState* subscriptionStatus;
- (NSDictionary*)toDictionary;

@end



typedef void (^KontextResultSuccessBlock)(NSDictionary* result);
typedef void (^KontextFailureBlock)(NSError* error);

/*Block for notifying availability of the User's ID and push token*/
typedef void (^KontextIdsAvailableBlock)(NSString* userId, NSString* pushToken);

/*Block for handling the reception of a remote notification */
typedef void (^KontextHandleNotificationReceivedBlock)(KontextNotification* notification);

/*Block for handling a user reaction to a notification*/
typedef void (^KontextHandleNotificationActionBlock)(KontextNotificationOpenedResult * result);

/*Dictionary of keys to pass alongside the init settings*/
    
/*Let Kontext directly prompt for push notifications on init*/
extern NSString * const kKontextSettingsKeyAutoPrompt;
    
/*Enable the default in-app alerts*/
extern NSString * const kKontextSettingsKeyInAppAlerts;

/*Enable In-App display of Launch URLs*/
extern NSString * const kKontextSettingsKeyInAppLaunchURL;

/* iOS10 +
 Set notification's in-focus display option.
 Value must be an KontextNotificationDisplayType enum
*/
extern NSString * const kKontextSettingsKeyInFocusDisplayOption;



// ======= Kontext Class Interface =========
@interface Kontext : NSObject

extern NSString* const KONTEXT_VERSION;

typedef NS_ENUM(NSUInteger, KON_TEXT_LOG_LEVEL) {
    KON_TEXT_LL_NONE, KON_TEXT_LL_FATAL, KON_TEXT_LL_ERROR, KON_TEXT_LL_WARN, KON_TEXT_LL_INFO, KON_TEXT_LL_DEBUG, KON_TEXT_LL_VERBOSE
};


/**
 Initialize Kontext.
 Sends push token to Kontext so you can later send notifications.
*/

// - Initialization
//+ (id)initWithLaunchOptions:(NSDictionary*)launchOptions appId:(NSString*)appId;
//+ (id)initWithLaunchOptions:(NSDictionary*)launchOptions appId:(NSString*)appId handleNotificationAction:(KontextHandleNotificationActionBlock)actionCallback;
//+ (id)initWithLaunchOptions:(NSDictionary*)launchOptions appId:(NSString*)appId handleNotificationAction:(KontextHandleNotificationActionBlock)actionCallback settings:(NSDictionary*)settings;
//+ (id)initWithLaunchOptions:(NSDictionary*)launchOptions appId:(NSString*)appId handleNotificationReceived:(KontextHandleNotificationReceivedBlock)receivedCallback handleNotificationAction:(KontextHandleNotificationActionBlock)actionCallback settings:(NSDictionary*)settings;

// New Methods
+ (id)initWithLaunchOptions:(NSDictionary*)launchOptions appId:(NSString*)appId appSecret:(NSString*)appSecret;
+ (id)initWithLaunchOptions:(NSDictionary*)launchOptions appId:(NSString*)appId appSecret:(NSString*)appSecret handleNotificationAction:(KontextHandleNotificationActionBlock)actionCallback;
+ (id)initWithLaunchOptions:(NSDictionary*)launchOptions appId:(NSString*)appId appSecret:(NSString*)appSecret handleNotificationAction:(KontextHandleNotificationActionBlock)actionCallback settings:(NSDictionary*)settings;
+ (id)initWithLaunchOptions:(NSDictionary*)launchOptions appId:(NSString*)appId appSecret:(NSString*)appSecret handleNotificationReceived:(KontextHandleNotificationReceivedBlock)receivedCallback handleNotificationAction:(KontextHandleNotificationActionBlock)actionCallback settings:(NSDictionary*)settings;

@property (class) KontextNotificationDisplayType inFocusDisplayType;

+ (NSString*)app_id;
+ (NSString*)sdk_version_raw;
+ (NSString*)sdk_semantic_version;

// Only use if you set kKontextSettingsKeyAutoPrompt to false
+ (void)registerForPushNotifications __deprecated_msg("Please use promptForPushNotificationsWithUserResponse instead.");
+ (void)promptForPushNotificationsWithUserResponse:(void(^)(BOOL accepted))completionHandler;

// - Logging
+ (void)setLogLevel:(KON_TEXT_LOG_LEVEL)logLevel visualLevel:(KON_TEXT_LOG_LEVEL)visualLogLevel;
+ (void) kontext_Log:(KON_TEXT_LOG_LEVEL)logLevel message:(NSString*)message;

// Send Screen
+ (void)sendScreen:(NSString*)screenName;

// Set UserAttributes
+ (void)setUserAttributes:(NSDictionary*)keyValues;

// - Tagging
+ (void)sendEvent:(NSString*)key value:(NSString*)value onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock;
+ (void)sendEvent:(NSString*)key value:(NSString*)value;
+ (void)sendEvents:(NSDictionary*)keyValuePair onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock;
+ (void)sendEvents:(NSDictionary*)keyValuePair;
+ (void)sendEventsWithJsonString:(NSString*)jsonString;
#pragma mark : Comment the Code
/* Comment the Code
 // Remove getTags, deleteTag, deleteTags api calls from Kontext.m class
+ (void)getTags:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock;
+ (void)getTags:(KontextResultSuccessBlock)successBlock;
+ (void)deleteTag:(NSString*)key onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock;
+ (void)deleteTag:(NSString*)key;
+ (void)deleteTags:(NSArray*)keys onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock;
+ (void)deleteTags:(NSArray*)keys;
+ (void)deleteTagsWithJsonString:(NSString*)jsonString;
*/
// Optional method that sends us the user's email as an anonymized hash so that we can better target and personalize notifications sent to that user across their devices.
// Sends as MD5 and SHA1 of the provided email
+ (void)syncHashedEmail:(NSString*)email;

// - Subscription and Permissions
+ (void)IdsAvailable:(KontextIdsAvailableBlock)idsAvailableBlock __deprecated_msg("Please use getPermissionSubscriptionState or addSubscriptionObserver and addPermissionObserver instead.");

+ (KontextPermissionSubscriptionState*)getPermissionSubscriptionState;

+ (void)addPermissionObserver:(NSObject<KontextPermissionObserver>*)observer;
+ (void)removePermissionObserver:(NSObject<KontextPermissionObserver>*)observer;

+ (void)addSubscriptionObserver:(NSObject<KontextSubscriptionObserver>*)observer;
+ (void)removeSubscriptionObserver:(NSObject<KontextSubscriptionObserver>*)observer;

+ (void)setSubscription:(BOOL)enable;

// - Posting Notification
+ (void)postNotification:(NSDictionary*)jsonData;
+ (void)postNotification:(NSDictionary*)jsonData onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock;
+ (void)postNotificationWithJsonString:(NSString*)jsonData onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock;
+ (NSString*)parseNSErrorAsJsonString:(NSError*)error;

// - Request and track user's location
+ (void)promptLocation;
+ (void)setLocationShared:(BOOL)enable;


// Only used for wrapping SDKs, such as Unity, Cordova, Xamarin, etc.
+ (void)setMSDKType:(NSString*)type;


// iOS 10 only
// Process from Notification Service Extension.
// Used for iOS Media Attachemtns and Action Buttons.
+ (UNMutableNotificationContent*)didReceiveNotificationExtensionRequest:(UNNotificationRequest*)request withMutableNotificationContent:(UNMutableNotificationContent*)replacementContent;
+ (UNMutableNotificationContent*)serviceExtensionTimeWillExpireRequest:(UNNotificationRequest*)request withMutableNotificationContent:(UNMutableNotificationContent*)replacementContent;

@end
