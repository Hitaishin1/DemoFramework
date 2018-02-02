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


// Internal selectors to the Kontext SDK to be shared by other Classes.

#ifndef KontextInternal_h
#define KontextInternal_h

#import "Kontext.h"
#import "KontextObservable.h"
#import "KontextNotificationSettings.h"

#import "KontextPermission.h"
#import "KontextSubscription.h"


// Permission + Subscription - Redefine KontextPermissionSubscriptionState
@interface KontextPermissionSubscriptionState ()

@property (readwrite) KontextPermissionState* permissionStatus;
@property (readwrite) KontextSubscriptionState* subscriptionStatus;

@end


@interface Kontext (KontextInternal)
+ (void)updateNotificationTypes:(int)notificationTypes;
+ (BOOL)registerForAPNsToken;
+ (void)setWaitingForApnsResponse:(BOOL)value;

@property (class) NSObject<KontextNotificationSettings>* osNotificationSettings;

@property (class) KontextPermissionState* currentPermissionState;

@end


#endif /* KontextInternal_h */
