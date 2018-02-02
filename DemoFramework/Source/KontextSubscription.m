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

#import "KontextSubscription.h"


@implementation KontextSubscriptionState

- (ObserableSubscriptionStateType*)observable {
    if (!_observable)
        _observable = [KontextObservable new];
    return _observable;
}

- (instancetype)initAsToWithPermision:(BOOL)permission {
    _accpeted = permission;
    
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    _userId = [userDefaults stringForKey:@"GT_PLAYER_ID"];
    _pushToken = [userDefaults stringForKey:@"GT_DEVICE_TOKEN"];
    _userSubscriptionSetting = [userDefaults objectForKey:@"KONTEXT_SUBSCRIPTION"] == nil;
    
    return self;
}

- (BOOL)compare:(KontextSubscriptionState*)from {
    return ![self.userId ?: @"" isEqualToString:from.userId ?: @""] ||
           ![self.pushToken ?: @"" isEqualToString:from.pushToken ?: @""] ||
           self.userSubscriptionSetting != from.userSubscriptionSetting ||
           self.accpeted != from.accpeted;
}

- (instancetype)initAsFrom {
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    
    _userId = [userDefaults stringForKey:@"GT_PLAYER_ID_LAST"];
    _pushToken = [userDefaults stringForKey:@"GT_DEVICE_TOKEN_LAST"];
    _userSubscriptionSetting = [userDefaults objectForKey:@"KONTEXT_SUBSCRIPTION_LAST"] == nil;
    _accpeted = [userDefaults boolForKey:@"KONTEXT_PERMISSION_ACCEPTED_LAST"];
    
    return self;
}

- (void)persistAsFrom {
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    
    NSString* strUserSubscriptionSetting = nil;
    if (!_userSubscriptionSetting)
        strUserSubscriptionSetting = @"no";
    [userDefaults setObject:strUserSubscriptionSetting forKey:@"KONTEXT_SUBSCRIPTION_LAST"];
    
    [userDefaults setObject:_userId forKey:@"GT_PLAYER_ID_LAST"];
    [userDefaults setObject:_pushToken forKey:@"GT_DEVICE_TOKEN_LAST"];
    [userDefaults setBool:_accpeted forKey:@"KONTEXT_PERMISSION_ACCEPTED_LAST"];
    
    [userDefaults synchronize];
}

- (instancetype)copyWithZone:(NSZone*)zone {
    KontextSubscriptionState* copy = [[[self class] alloc] init];
    
    if (copy) {
        copy->_userId = [_userId copy];
        copy->_pushToken = [_pushToken copy];
        copy->_userSubscriptionSetting = _userSubscriptionSetting;
        copy->_accpeted = _accpeted;
    }
    
    return copy;
}


- (void)onChanged:(KontextPermissionState*)state {
    [self setAccepted:state.accepted];
}

- (void)setUserId:(NSString*)userId {
    BOOL changed = ![[NSString stringWithString:userId] isEqualToString:_userId];
    _userId = userId;
    if (self.observable && changed)
        [self.observable notifyChange:self];
}

- (void)setPushToken:(NSString*)pushToken {
    BOOL changed = ![[NSString stringWithString:pushToken] isEqualToString:_pushToken];
    _pushToken = pushToken;
    if (changed) {
        [[NSUserDefaults standardUserDefaults] setObject:_pushToken forKey:@"GT_DEVICE_TOKEN"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        if (self.observable)
            [self.observable notifyChange:self];
    }
}

- (void)setUserSubscriptionSetting:(BOOL)userSubscriptionSetting {
    BOOL changed = userSubscriptionSetting != _userSubscriptionSetting;
    _userSubscriptionSetting = userSubscriptionSetting;
    if (self.observable && changed)
        [self.observable notifyChange:self];
}

- (void)setAccepted:(BOOL)inAccpeted {
    BOOL lastSubscribed = self.subscribed;
    _accpeted = inAccpeted;
    if (lastSubscribed != self.subscribed)
        [self.observable notifyChange:self];
}

- (BOOL)subscribed {
    return _userId && _pushToken && _userSubscriptionSetting && _accpeted;
}

- (NSString*)description {
    static NSString* format = @"<KontextSubscriptionState: userId: %@, pushToken: %@, userSubscriptionSetting: %d, subscribed: %d>";
    return [NSString stringWithFormat:format, self.userId, self.pushToken, self.userSubscriptionSetting, self.subscribed];
}

- (NSDictionary*)toDictionary {
    return @{@"userId": _userId ?: [NSNull null],
             @"pushToken": _pushToken ?: [NSNull null],
             @"userSubscriptionSetting": @(_userSubscriptionSetting),
             @"subscribed": @(self.subscribed)};
}

@end


@implementation KontextSubscriptionChangedInternalObserver

- (void)onChanged:(KontextSubscriptionState*)state {
    [KontextSubscriptionChangedInternalObserver fireChangesObserver:state];
}

+ (void)fireChangesObserver:(KontextSubscriptionState*)state {
    KontextSubscriptionStateChanges* stateChanges = [KontextSubscriptionStateChanges alloc];
    stateChanges.from = Kontext.lastSubscriptionState;
    stateChanges.to = [state copy];
    
    BOOL hasReceiver = [Kontext.subscriptionStateChangesObserver notifyChange:stateChanges];
    if (hasReceiver) {
        Kontext.lastSubscriptionState = [state copy];
        [Kontext.lastSubscriptionState persistAsFrom];
    }
}

@end

@implementation KontextSubscriptionStateChanges
- (NSString*)description {
    static NSString* format = @"<KontextSubscriptionStateChanges:\nfrom: %@,\nto:   %@\n>";
    return [NSString stringWithFormat:format, _from, _to];
}

- (NSDictionary*)toDictionary {
    return @{@"from": [_from toDictionary],
             @"to": [_to toDictionary]};
}

@end
