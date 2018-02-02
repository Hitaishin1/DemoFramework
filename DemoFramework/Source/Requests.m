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
#import "Requests.h"
#import "KontextRequest.h"
#import "KontextHelper.h"
#import <stdlib.h>
#import <stdio.h>
#import <sys/types.h>
#import <sys/utsname.h>
#import <sys/sysctl.h>

// SUBCLASSES - These subclasses each represent an individual request
#pragma mark : Get the AuthToken
@implementation KontextRequestGetAuthToken
+ (instancetype)withAppId:(NSString *)appId appSecret:(NSString *)appSecret {
    let request = [KontextRequestGetAuthToken new];
    
    request.parameters = @{@"app_id" : appId, @"app_secret" : appSecret, @"grant_type": @"app_credentials"};
    request.method = POST;
    request.path = [NSString stringWithFormat:@"oauth/grant/"];
    
    return request;
}
@end

@implementation KontextRequestGetTags
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId {
    let request = [KontextRequestGetTags new];
    
    request.parameters = @{@"app_id" : appId};
    request.method = GET;
    request.path = [NSString stringWithFormat:@"players/%@", userId];
    
    return request;
}
@end

@implementation KontextRequestGetIosParams
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId {
    let request = [KontextRequestGetIosParams new];
    
    if (userId) {
        request.parameters = @{@"player_id" : userId};
    }
    
    request.method = GET;
    request.path = [NSString stringWithFormat:@"apps/%@/ios_params.js", appId];
    
    return request;
}

-(BOOL)missingAppId {
    return false; //this request doesn't have an app ID parameter
}
@end

@implementation KontextRequestSendEventsToServer
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId tags:(NSDictionary *)tags networkType:(NSNumber *)netType {
    let request = [KontextRequestSendEventsToServer new];
    
    request.parameters = @{@"app_id" : appId, @"tags" : tags, @"net_type" : netType};
    request.method = PUT;
    request.path = [NSString stringWithFormat:@"players/%@", userId];
    
    return request;
}
@end

@implementation KontextRequestPostNotification
+ (instancetype)withAppId:(NSString *)appId withJson:(NSMutableDictionary *)json {
    let request = [KontextRequestPostNotification new];
    if (!json[@"app_id"]) {
        json[@"app_id"] = appId;
    }
    
    request.parameters = json;
    request.method = POST;
    request.path = @"notifications";
    
    return request;
}
@end

@implementation KontextRequestUpdateDeviceToken
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId deviceToken:(NSString *)identifier notificationTypes:(NSNumber *)notificationTypes {
    let request = [KontextRequestUpdateDeviceToken new];
    
    request.parameters = @{
                           @"app_id" : appId,
                           @"identifier" : identifier,
                           @"notification_types" : notificationTypes
                           };
    
    request.method = PUT;
    request.path = [NSString stringWithFormat:@"players/%@", userId];
    
    return request;
}
@end


@implementation KontextRequestUpdateNotificationTypes
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId notificationTypes:(NSNumber *)notificationTypes {
    let request = [KontextRequestUpdateNotificationTypes new];
    
    request.parameters = @{@"app_id" : appId, @"notification_types" : notificationTypes};
    request.method = PUT;
    request.path = [NSString stringWithFormat:@"players/%@", userId];
    
    return request;
}
@end

@implementation KontextRequestSendPurchases
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId withPurchases:(NSArray *)purchases {
    let request = [KontextRequestSendPurchases new];
    
    request.parameters = @{@"app_id" : appId, @"purchases" : purchases};
    request.method = POST;
    request.path = [NSString stringWithFormat:@"players/%@/on_purchase", purchases];
    
    return request;
}
@end

@implementation KontextRequestSubmitNotificationOpened
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId wasOpened:(BOOL)opened messageId:(NSString *)messageId {
    let request = [KontextRequestSubmitNotificationOpened new];
    
    request.parameters = @{@"player_id" : userId, @"app_id" : appId, @"opened" : @(opened)};
    request.method = PUT;
    request.path = [NSString stringWithFormat:@"notifications/%@", messageId];
    
    return request;
}
@end

@implementation KontextRequestRegisterUser
+ (instancetype _Nonnull)withData:(NSDictionary * _Nonnull)registrationData userId:(NSString * _Nullable)userId {
    
    let request = [KontextRequestRegisterUser new];
    
    request.parameters = registrationData;
    request.method = POST;
    request.path = userId ? [NSString stringWithFormat:@"players/%@/on_session", userId] : @"players";
    
    return request;
}
@end

@implementation KontextRequestSyncHashedEmail
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId email:(NSString *)email networkType:(NSNumber *)netType {
    let request = [KontextRequestSyncHashedEmail new];
    
    let lowerCase = [email lowercaseString];
    let md5Hash = [KontextHelper hashUsingMD5:lowerCase];
    let sha1Hash = [KontextHelper hashUsingSha1:lowerCase];
    
    [Kontext kontext_Log:KON_TEXT_LL_DEBUG message:[NSString stringWithFormat:@"%@ - MD5: %@, SHA1:%@", lowerCase, md5Hash, sha1Hash]];
    
    request.parameters = @{@"app_id" : appId, @"em_m" : md5Hash, @"em_s" : sha1Hash, @"net_type" : netType};
    request.method = PUT;
    request.path = [NSString stringWithFormat:@"players/%@", userId];
    
    return request;
}
@end

@implementation KontextRequestSendLocation
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId location:(os_last_location *)coordinate networkType:(NSNumber *)netType backgroundState:(BOOL)backgroundState {
    let request = [KontextRequestSendLocation new];
    
    request.parameters = @{@"app_id" : appId, @"lat" : @(coordinate->cords.latitude), @"long" : @(coordinate->cords.longitude), @"loc_acc_vert" : @(coordinate->verticalAccuracy), @"loc_acc" : @(coordinate->horizontalAccuracy), @"net_type" : netType, @"loc_bg" : @(backgroundState)};
    request.method = PUT;
    request.path = [NSString stringWithFormat:@"players/%@", userId];
    
    return request;
}
@end

@implementation KontextRequestOnFocus
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId badgeCount:(NSNumber *)badgeCount {
    let request = [KontextRequestOnFocus new];
    
    request.parameters = @{@"app_id" : appId, @"badge_count" : badgeCount};
    request.method = PUT;
    request.path = [NSString stringWithFormat:@"players/%@", userId];
    
    return request;
}

+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId state:(NSString *)state type:(NSNumber *)type activeTime:(NSNumber *)activeTime netType:(NSNumber *)netType {
    let request = [KontextRequestOnFocus new];
    
    request.parameters = @{@"app_id" : appId, @"state" : state, @"type" : type, @"active_time" : activeTime, @"net_type" : netType};
    request.method = POST;
    request.path = [NSString stringWithFormat:@"players/%@/on_focus", userId];
    
    return request;
}
@end
