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
#import "KontextRequest.h"
#import "KontextLocation.h"

#ifndef KontextRequests_h
#define KontextRequests_h

NS_ASSUME_NONNULL_BEGIN

#pragma mark : Get the AuthToken
@interface KontextRequestGetAuthToken : KontextRequest
+ (instancetype)withAppId:(NSString *)appId appSecret:(NSString *)appSecret;
@end

@interface KontextRequestGetTags : KontextRequest
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId;
@end

@interface KontextRequestGetIosParams : KontextRequest
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId;
@end

@interface KontextRequestSendEventsToServer : KontextRequest
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId tags:(NSDictionary *)tags networkType:(NSNumber *)netType;
@end

@interface KontextRequestPostNotification : KontextRequest
+ (instancetype)withAppId:(NSString *)appId withJson:(NSMutableDictionary *)json;
@end

@interface KontextRequestUpdateDeviceToken : KontextRequest
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId deviceToken:(NSString *)identifier notificationTypes:(NSNumber *)notificationTypes;
@end

@interface KontextRequestUpdateNotificationTypes : KontextRequest
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId notificationTypes:(NSNumber *)notificationTypes;
@end

@interface KontextRequestSendPurchases : KontextRequest
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId withPurchases:(NSArray *)purchases;
@end

@interface KontextRequestSubmitNotificationOpened : KontextRequest
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId wasOpened:(BOOL)opened messageId:(NSString *)messageId;
@end

@interface KontextRequestSyncHashedEmail : KontextRequest
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId email:(NSString *)email networkType:(NSNumber *)netType;
@end

@interface KontextRequestSendLocation : KontextRequest
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId location:(kontext_last_location *)coordinate networkType:(NSNumber *)netType backgroundState:(BOOL)backgroundState;
@end

@interface KontextRequestOnFocus : KontextRequest
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId badgeCount:(NSNumber *)badgeCount;
+ (instancetype)withUserId:(NSString *)userId appId:(NSString *)appId state:(NSString *)state type:(NSNumber *)type activeTime:(NSNumber *)activeTime netType:(NSNumber *)netType;
@end

NS_ASSUME_NONNULL_END

@interface KontextRequestRegisterUser : KontextRequest
+ (instancetype _Nonnull)withData:(NSDictionary * _Nonnull)registrationData userId:(NSString * _Nullable)userId;
@end

@interface KontextRequestSyncUserState : KontextRequest
+ (instancetype _Nullable )withUserId:(NSString *_Nullable)userId appId:(NSString *_Nullable)appId userInfo:(NSDictionary *_Nonnull)userInfo;
@end

#endif /* Requests_h */

