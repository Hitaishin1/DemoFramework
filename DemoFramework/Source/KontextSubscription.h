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

#import "Kontext.h"

#import "KontextObservable.h"

#import "KontextPermission.h"

// Redefines are done so we can make properites writeable and backed internal variables accesiable to the SDK.
// Basicly the C# equivlent of a public gettter with an internal settter.


@protocol KontextSubscriptionStateObserver
-(void)onChanged:(KontextSubscriptionState*)state;
@end

typedef KontextObservable<NSObject<KontextSubscriptionStateObserver>*, KontextSubscriptionState*> ObserableSubscriptionStateType;

// Redefine KontextSubscriptionState
@interface KontextSubscriptionState () {
@protected BOOL _userSubscriptionSetting;
@protected NSString* _userId;
@protected NSString* _pushToken;
}

// @property (readonly, nonatomic) BOOL subscribed; // (yes only if userId, pushToken, and setSubscription exists / are true)
@property (readwrite, nonatomic) BOOL userSubscriptionSetting; // returns setSubscription state.
@property (readwrite, nonatomic) NSString* userId;    // AKA Kontext PlayerId
@property (readwrite, nonatomic) NSString* pushToken; // AKA Apple Device Token
@property (nonatomic) ObserableSubscriptionStateType* observable;

- (instancetype)initAsToWithPermision:(BOOL)permission;
- (instancetype)initAsFrom;

@end


// Redefine KontextSubscriptionState
@interface KontextSubscriptionState () <KontextPermissionStateObserver>

@property (nonatomic) BOOL accpeted;

- (void)setAccepted:(BOOL)inAccpeted;
- (void)persistAsFrom;
- (BOOL)compare:(KontextSubscriptionState*)from;
@end

// Redefine KontextSubscriptionStateChanges
@interface KontextSubscriptionStateChanges ()

@property (readwrite) KontextSubscriptionState* to;
@property (readwrite) KontextSubscriptionState* from;

@end


typedef KontextObservable<NSObject<KontextSubscriptionObserver>*, KontextSubscriptionStateChanges*> ObserableSubscriptionStateChangesType;


@interface KontextSubscriptionChangedInternalObserver : NSObject<KontextSubscriptionStateObserver>
+ (void)fireChangesObserver:(KontextSubscriptionState*)state;
@end

@interface Kontext (SubscriptionAdditions)

@property (class) KontextSubscriptionState* lastSubscriptionState;
@property (class) KontextSubscriptionState* currentSubscriptionState;

// Used to manage observers added by the app developer.
@property (class) ObserableSubscriptionStateChangesType* subscriptionStateChangesObserver;

@end
