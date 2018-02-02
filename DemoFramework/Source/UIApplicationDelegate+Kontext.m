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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "UIApplicationDelegate+Kontext.h"
#import "Kontext.h"
#import "KontextTracker.h"
#import "KontextLocation.h"
#import "KontextSelectorHelpers.h"
#import "KontextHelper.h"

@interface Kontext (UN_extra)
+ (void) didRegisterForRemoteNotifications:(UIApplication*)app deviceToken:(NSData*)inDeviceToken;
+ (void) handleDidFailRegisterForRemoteNotification:(NSError*)error;
+ (void) updateNotificationTypes:(int)notificationTypes;
+ (NSString*) app_id;
+ (void) notificationOpened:(NSDictionary*)messageDict isActive:(BOOL)isActive;
+ (BOOL) remoteSilentNotification:(UIApplication*)application UserInfo:(NSDictionary*)userInfo completionHandler:(void (^)(UIBackgroundFetchResult))completionHandler;
+ (void) processLocalActionBasedNotification:(UILocalNotification*) notification identifier:(NSString*)identifier;
+ (void) kontext_Log:(KON_TEXT_LOG_LEVEL)logLevel message:(NSString*) message;
@end



// This class hooks into the UIApplicationDelegate selectors to receive iOS 9 and older events.
//   - UNUserNotificationCenter is used for iOS 10
//   - Orignal implementations are called so other plugins and the developers AppDelegate is still called.

@implementation KontextAppDelegate

+ (void) kontextLoadedTagSelector {}

static Class delegateClass = nil;

// Store an array of all UIAppDelegate subclasses to iterate over in cases where UIAppDelegate swizzled methods are not overriden in main AppDelegate
// But rather in one of the subclasses
static NSArray* delegateSubclasses = nil;

+(Class)delegateClass {
    return delegateClass;
}

- (void) setKontextDelegate:(id<UIApplicationDelegate>)delegate {
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:[NSString stringWithFormat:@"KONTEXT setKontextDelegate CALLED: %@", delegate]];
    
    if (delegateClass) {
        [self setKontextDelegate:delegate];
        return;
    }
    
    Class newClass = [KontextAppDelegate class];
    
    delegateClass = getClassWithProtocolInHierarchy([delegate class], @protocol(UIApplicationDelegate));
    delegateSubclasses = ClassGetSubclasses(delegateClass);
    
    // Need to keep this one for iOS 10 for content-available notifiations when the app is not in focus
    //   iOS 10 doesn't fire a selector on UNUserNotificationCenter in this cases most likely becuase
    //   UNNotificationServiceExtension (mutable-content) and UNNotificationContentExtension (with category) replaced it.
    injectToProperClass(@selector(kontextRemoteSilentNotification:UserInfo:fetchCompletionHandler:),
                        @selector(application:didReceiveRemoteNotification:fetchCompletionHandler:), delegateSubclasses, newClass, delegateClass);
    
    [KontextAppDelegate sizzlePreiOS10MethodsPhase1];

    injectToProperClass(@selector(kontextDidFailRegisterForRemoteNotification:error:),
                        @selector(application:didFailToRegisterForRemoteNotificationsWithError:), delegateSubclasses, newClass, delegateClass);
    
    if (NSClassFromString(@"CoronaAppDelegate")) {
        [self setKontextDelegate:delegate];
        return;
    }
    
    injectToProperClass(@selector(kontextDidRegisterForRemoteNotifications:deviceToken:),
                        @selector(application:didRegisterForRemoteNotificationsWithDeviceToken:), delegateSubclasses, newClass, delegateClass);
    
    [KontextAppDelegate sizzlePreiOS10MethodsPhase2];
    
    injectToProperClass(@selector(kontextApplicationWillResignActive:),
                        @selector(applicationWillResignActive:), delegateSubclasses, newClass, delegateClass);
    
    // Required for background location
    injectToProperClass(@selector(kontextApplicationDidEnterBackground:),
                        @selector(applicationDidEnterBackground:), delegateSubclasses, newClass, delegateClass);
    
    injectToProperClass(@selector(kontextApplicationDidBecomeActive:),
                        @selector(applicationDidBecomeActive:), delegateSubclasses, newClass, delegateClass);
    
    // Used to track how long the app has been closed
    injectToProperClass(@selector(kontextApplicationWillTerminate:),
                        @selector(applicationWillTerminate:), delegateSubclasses, newClass, delegateClass);
    
    [self setKontextDelegate:delegate];
}

+ (void)sizzlePreiOS10MethodsPhase1 {
    if ([KontextHelper isIOSVersionGreaterOrEqual:10])
        return;
    
    injectToProperClass(@selector(kontextLocalNotificationOpened:handleActionWithIdentifier:forLocalNotification:completionHandler:),
                        @selector(application:handleActionWithIdentifier:forLocalNotification:completionHandler:), delegateSubclasses, [KontextAppDelegate class], delegateClass);
    
    // iOS 10 requestAuthorizationWithOptions has it's own callback
    //   We also check the permssion status from applicationDidBecomeActive: each time.
    //   Keeping for fallback in case of a race condidion where the focus event fires to soon.
    injectToProperClass(@selector(kontextDidRegisterUserNotifications:settings:),
                        @selector(application:didRegisterUserNotificationSettings:), delegateSubclasses, [KontextAppDelegate class], delegateClass);
}

+ (void)sizzlePreiOS10MethodsPhase2 {
    if ([KontextHelper isIOSVersionGreaterOrEqual:10])
        return;
    
    injectToProperClass(@selector(kontextReceivedRemoteNotification:userInfo:),
                        @selector(application:didReceiveRemoteNotification:), delegateSubclasses, [KontextAppDelegate class], delegateClass);
    
    injectToProperClass(@selector(kontextLocalNotificationOpened:notification:),
                        @selector(application:didReceiveLocalNotification:), delegateSubclasses, [KontextAppDelegate class], delegateClass);
}


- (void)kontextDidRegisterForRemoteNotifications:(UIApplication*)app deviceToken:(NSData*)inDeviceToken {
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:@"kontextDidRegisterForRemoteNotifications:deviceToken:"];
    
    [Kontext didRegisterForRemoteNotifications:app deviceToken:inDeviceToken];
    
    if ([self respondsToSelector:@selector(kontextDidRegisterForRemoteNotifications:deviceToken:)])
        [self kontextDidRegisterForRemoteNotifications:app deviceToken:inDeviceToken];
}

- (void)kontextDidFailRegisterForRemoteNotification:(UIApplication*)app error:(NSError*)err {
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:@"kontextDidFailRegisterForRemoteNotification:error:"];
    
    if ([Kontext app_id])
        [Kontext handleDidFailRegisterForRemoteNotification:err];
    
    if ([self respondsToSelector:@selector(kontextDidFailRegisterForRemoteNotification:error:)])
        [self kontextDidFailRegisterForRemoteNotification:app error:err];
}

// iOS 8 & 9 Only
- (void)kontextDidRegisterUserNotifications:(UIApplication*)application settings:(UIUserNotificationSettings*)notificationSettings {
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:@"kontextDidRegisterUserNotifications:settings:"];
    
    if ([Kontext app_id])
        [Kontext updateNotificationTypes:notificationSettings.types];
    
    if ([self respondsToSelector:@selector(kontextDidRegisterUserNotifications:settings:)])
        [self kontextDidRegisterUserNotifications:application settings:notificationSettings];
}


// Fallback method - Normally this would not fire as kontextRemoteSilentNotification below will fire instead. Was needed for iOS 6 support in the past.
- (void)kontextReceivedRemoteNotification:(UIApplication*)application userInfo:(NSDictionary*)userInfo {
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:@"kontextReceivedRemoteNotification:userInfo:"];
    
    if ([Kontext app_id])
        [Kontext notificationOpened:userInfo isActive:[application applicationState] == UIApplicationStateActive];
    
    if ([self respondsToSelector:@selector(kontextReceivedRemoteNotification:userInfo:)])
        [self kontextReceivedRemoteNotification:application userInfo:userInfo];
}

// Fires when a notication is opened or recieved while the app is in focus.
//   - Also fires when the app is in the background and a notificaiton with content-available=1 is received.
// NOTE: completionHandler must only be called once!
//          iOS 10 - This crashes the app if it is called twice! Crash will happen when the app is resumed.
//          iOS 9  - Does not have this issue.
- (void) kontextRemoteSilentNotification:(UIApplication*)application UserInfo:(NSDictionary*)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult)) completionHandler {
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:@"kontextRemoteSilentNotification:UserInfo:fetchCompletionHandler:"];
    
    BOOL callExistingSelector = [self respondsToSelector:@selector(kontextRemoteSilentNotification:UserInfo:fetchCompletionHandler:)];
    BOOL startedBackgroundJob = false;
    
    if ([Kontext app_id]) {
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive && userInfo[@"aps"][@"alert"])
            [Kontext notificationOpened:userInfo isActive:YES];
        else
            startedBackgroundJob = [Kontext remoteSilentNotification:application UserInfo:userInfo completionHandler:callExistingSelector ? nil : completionHandler];
    }
    
    if (callExistingSelector) {
        [self kontextRemoteSilentNotification:application UserInfo:userInfo fetchCompletionHandler:completionHandler];
        return;
    }
    
    // Make sure not a cold start from tap on notification (OS doesn't call didReceiveRemoteNotification)
    if ([self respondsToSelector:@selector(kontextReceivedRemoteNotification:userInfo:)]
        && ![[Kontext valueForKey:@"coldStartFromTapOnNotification"] boolValue])
        [self kontextReceivedRemoteNotification:application userInfo:userInfo];
    
    if (!startedBackgroundJob)
        completionHandler(UIBackgroundFetchResultNewData);
}

- (void) kontextLocalNotificationOpened:(UIApplication*)application handleActionWithIdentifier:(NSString*)identifier forLocalNotification:(UILocalNotification*)notification completionHandler:(void(^)()) completionHandler {
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:@"kontextLocalNotificationOpened:handleActionWithIdentifier:forLocalNotification:completionHandler:"];
    
    if ([Kontext app_id])
        [Kontext processLocalActionBasedNotification:notification identifier:identifier];
    
    if ([self respondsToSelector:@selector(kontextLocalNotificationOpened:handleActionWithIdentifier:forLocalNotification:completionHandler:)])
        [self kontextLocalNotificationOpened:application handleActionWithIdentifier:identifier forLocalNotification:notification completionHandler:completionHandler];
    
    completionHandler();
}

- (void)kontextLocalNotificationOpened:(UIApplication*)application notification:(UILocalNotification*)notification {
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:@"kontextLocalNotificationOpened:notification:"];
    
    if ([Kontext app_id])
        [Kontext processLocalActionBasedNotification:notification identifier:@"__DEFAULT__"];
    
    if([self respondsToSelector:@selector(kontextLocalNotificationOpened:notification:)])
        [self kontextLocalNotificationOpened:application notification:notification];
}

- (void)kontextApplicationWillResignActive:(UIApplication*)application {
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:@"kontextApplicationWillResignActive"];
    
    if ([Kontext app_id])
        [KontextTracker onFocus:YES];
    
    if ([self respondsToSelector:@selector(kontextApplicationWillResignActive:)])
        [self kontextApplicationWillResignActive:application];
}

- (void) kontextApplicationDidEnterBackground:(UIApplication*)application {
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:@"kontextApplicationDidEnterBackground"];
    
    if ([Kontext app_id])
        [KontextLocation onfocus:NO];
    
    if ([self respondsToSelector:@selector(kontextApplicationDidEnterBackground:)])
        [self kontextApplicationDidEnterBackground:application];
}

- (void)kontextApplicationDidBecomeActive:(UIApplication*)application {
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:@"kontextApplicationDidBecomeActive"];
    
    if ([Kontext app_id]) {
        [KontextTracker onFocus:NO];
        [KontextLocation onfocus:YES];
    }
    
    if ([self respondsToSelector:@selector(kontextApplicationDidBecomeActive:)])
        [self kontextApplicationDidBecomeActive:application];
}

-(void)kontextApplicationWillTerminate:(UIApplication *)application {
    
    if ([Kontext app_id])
        [KontextTracker onFocus:YES];
    
    if ([self respondsToSelector:@selector(kontextApplicationWillTerminate:)])
        [self kontextApplicationWillTerminate:application];
}

@end
