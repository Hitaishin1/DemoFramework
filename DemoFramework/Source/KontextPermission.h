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

// Redefines are done so we can make properites writeable and backed internal variables accesiable to the SDK.
// Basicly the C# equivlent of a public gettter with an internal/protected settter.

@protocol KontextPermissionStateObserver<NSObject>
- (void)onChanged:(KontextPermissionState*)state;
@end

typedef KontextObservable<NSObject<KontextPermissionStateObserver>*, KontextPermissionState*> ObserablePermissionStateType;


// Redefine KontextPermissionState
@interface KontextPermissionState () {
@protected BOOL _hasPrompted;
@protected BOOL _answeredPrompt;
}
@property (readwrite, nonatomic) BOOL hasPrompted;
@property (readwrite, nonatomic) BOOL answeredPrompt;
@property (readwrite, nonatomic) BOOL accepted;
@property int notificationTypes;

@property (nonatomic) ObserablePermissionStateType* observable;

- (void) persistAsFrom;

- (instancetype)initAsTo;
- (instancetype)initAsFrom;

- (BOOL)compare:(KontextPermissionState*)from;

@end

// Redefine KontextPermissionStateChanges
@interface KontextPermissionStateChanges ()

@property (readwrite) KontextPermissionState* to;
@property (readwrite) KontextPermissionState* from;

@end

typedef KontextObservable<NSObject<KontextPermissionObserver>*, KontextPermissionStateChanges*> ObserablePermissionStateChangesType;


@interface KontextPermissionChangedInternalObserver : NSObject<KontextPermissionStateObserver>
+ (void)fireChangesObserver:(KontextPermissionState*)state;
@end

@interface Kontext (PermissionAdditions)

@property (class) KontextPermissionState* lastPermissionState;
@property (class) KontextPermissionState* currentPermissionState;

// Used to manage observers added by the app developer.
@property (class) ObserablePermissionStateChangesType* permissionStateChangesObserver;

@end
