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

#import "KontextPermission.h"

#import "KontextInternal.h"

@implementation KontextPermissionState

- (ObserablePermissionStateType*)observable {
    if (!_observable)
        _observable = [KontextObservable new];
    return _observable;
}

- (instancetype)initAsTo {
    [Kontext.osNotificationSettings getNotificationPermissionState];
    
    return self;
}

- (instancetype)initAsFrom {
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    
    _hasPrompted = [userDefaults boolForKey:@"OS_HAS_PROMPTED_FOR_NOTIFICATIONS_LAST"];
    _answeredPrompt = [userDefaults boolForKey:@"OS_NOTIFICATION_PROMPT_ANSWERED_LAST"];
    _accepted  = [userDefaults boolForKey:@"KONTEXT_ACCEPTED_NOTIFICATION_LAST"];
    
    return self;
}

- (void)persistAsFrom {
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    
    [userDefaults setBool:_hasPrompted forKey:@"OS_HAS_PROMPTED_FOR_NOTIFICATIONS_LAST"];
    [userDefaults setBool:_answeredPrompt forKey:@"OS_NOTIFICATION_PROMPT_ANSWERED_LAST"];
    [userDefaults setBool:_accepted forKey:@"KONTEXT_ACCEPTED_NOTIFICATION_LAST"];
    
    [userDefaults synchronize];
}


- (instancetype)copyWithZone:(NSZone*)zone {
    KontextPermissionState* copy = [[self class] new];
    
    if (copy) {
        copy->_hasPrompted = _hasPrompted;
        copy->_answeredPrompt = _answeredPrompt;
        copy->_accepted = _accepted;
    }
    
    return copy;
}

- (void)setHasPrompted:(BOOL)inHasPrompted {
    if (_hasPrompted != inHasPrompted) {
        NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
        [userDefaults setBool:true forKey:@"OS_HAS_PROMPTED_FOR_NOTIFICATIONS"];
        [userDefaults synchronize];
    }
    
    BOOL last = self.hasPrompted;
    _hasPrompted = inHasPrompted;
    if (last != self.hasPrompted)
        [self.observable notifyChange:self];
}

- (BOOL)hasPrompted {
    // If we know they answered turned notificaitons on then were prompted at some point.
    if (self.answeredPrompt) // self. triggers getter
        return true;
    return _hasPrompted;
}

- (void)setAnsweredPrompt:(BOOL)inansweredPrompt {
    BOOL last = self.answeredPrompt;
    _answeredPrompt = inansweredPrompt;
    if (last != self.answeredPrompt)
        [self.observable notifyChange:self];
}

- (BOOL)answeredPrompt {
    // If we got an accepted permission then they answered the prompt.
    if (_accepted)
        return true;
    return _answeredPrompt;
}

- (void)setAccepted:(BOOL)accepted {
    BOOL changed = _accepted != accepted;
    _accepted = accepted;
    if (changed)
        [self.observable notifyChange:self];
}

- (KontextNotificationPermission)status {
    if (_accepted)
        return KontextNotificationPermissionAuthorized;
    
    if (self.answeredPrompt)
        return KontextNotificationPermissionDenied;
    return KontextNotificationPermissionNotDetermined;
}

- (NSString*)statusAsString {
    switch(self.status) {
        case KontextNotificationPermissionNotDetermined:
            return @"NotDetermined";
        case KontextNotificationPermissionAuthorized:
            return @"Authorized";
        case KontextNotificationPermissionDenied:
            return @"Denied";
    }
    return @"NotDetermined";
}

- (BOOL)compare:(KontextPermissionState*)from {
    return self.accepted != from.accepted ||
           self.answeredPrompt != from.answeredPrompt ||
           self.hasPrompted != from.hasPrompted;
}

- (NSString*)description {
    static NSString* format = @"<KontextPermissionState: hasPrompted: %d, status: %@>";
    return [NSString stringWithFormat:format, self.hasPrompted, self.statusAsString];
}

- (NSDictionary*)toDictionary {
    return @{@"hasPrompted": @(self.hasPrompted),
             @"status": @(self.status)};
}

@end


@implementation KontextPermissionChangedInternalObserver

- (void)onChanged:(KontextPermissionState*)state {
    [KontextPermissionChangedInternalObserver fireChangesObserver:state];
}

+ (void)fireChangesObserver:(KontextPermissionState*)state  {
    KontextPermissionStateChanges* stateChanges = [KontextPermissionStateChanges alloc];
    stateChanges.from = Kontext.lastPermissionState;
    stateChanges.to = [state copy];
    
    BOOL hasReceiver = [Kontext.permissionStateChangesObserver notifyChange:stateChanges];
    if (hasReceiver) {
        Kontext.lastPermissionState = [state copy];
        [Kontext.lastPermissionState persistAsFrom];
    }
}

@end

@implementation KontextPermissionStateChanges
- (NSString*)description {
    static NSString* format = @"<KontextSubscriptionStateChanges:\nfrom: %@,\nto:   %@\n>";
    return [NSString stringWithFormat:format, _from, _to];
}

- (NSDictionary*)toDictionary {
    return @{@"from": [_from toDictionary], @"to": [_to toDictionary]};
}

@end
