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

#import "KontextClient.h"
#import "UIApplicationDelegate+Kontext.h"

@interface KontextClient ()
@property (strong, nonatomic) NSURLSession *sharedSession;
@end

@implementation KontextClient

+ (KontextClient *)sharedClient {
    static KontextClient *sharedClient = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sharedClient = [KontextClient new];
    });
    return sharedClient;
}

-(instancetype)init {
    if (self = [super init]) {
        _sharedSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    }
    
    return self;
}

- (void)executeRequest:(KontextRequest *)request onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock {
    if (![self validRequest:request]) {
        [self handleMissingAppIdError:failureBlock withRequest:request];
        return;
    }
    
    let task = [self.sharedSession dataTaskWithRequest:request.request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        [KontextClient handleJSONNSURLResponse:response data:data error:error onSuccess:successBlock onFailure:failureBlock];
    }];
    
    [task resume];
}
/// New Funcation for Auth
- (void)executeRequestForAuth:(KontextRequest *)request onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock {
    if (![self validRequest:request]) {
        [self handleMissingAppIdError:failureBlock withRequest:request];
        return;
    }
    
    let task = [self.sharedSession dataTaskWithRequest:request.requestAuth completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        [KontextClient handleJSONNSURLResponse:response data:data error:error onSuccess:successBlock onFailure:failureBlock];
    }];
    
    [task resume];
}

- (void)executeSynchronousRequest:(KontextRequest *)request onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock {
    if (![self validRequest:request]) {
        [self handleMissingAppIdError:failureBlock withRequest:request];
        return;
    }
    
    __block NSURLResponse *httpResponse;
    __block NSError *httpError;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    let dataTask = [self.sharedSession dataTaskWithRequest:request.request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        httpResponse = response;
        httpError = error;
        
        dispatch_semaphore_signal(semaphore);
    }];
    
    [dataTask resume];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    [KontextClient handleJSONNSURLResponse:httpResponse data:nil error:httpError onSuccess:successBlock onFailure:failureBlock];
}

- (void)handleMissingAppIdError:(KontextFailureBlock)failureBlock withRequest:(KontextRequest *)request {
    let errorDescription = [NSString stringWithFormat:@"HTTP Request (%@) must contain app_id parameter", NSStringFromClass([request class])];
    
    [Kontext kontext_Log:KON_TEXT_LL_ERROR message:errorDescription];
    
    failureBlock([NSError errorWithDomain:@"KontextError" code:-1 userInfo:@{@"error" : errorDescription}]);
}

- (BOOL)validRequest:(KontextRequest *)request {
    if (request.missingAppId) {
        return false;
    }
    
    [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:[NSString stringWithFormat:@"HTTP Request (%@) with URL: %@, with parameters: %@", NSStringFromClass([request class]), request.request.URL.absoluteString, request.parameters]];
    
    return true;
}


+ (void)handleJSONNSURLResponse:(NSURLResponse*) response data:(NSData*) data error:(NSError*) error onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock {
    
    NSHTTPURLResponse* HTTPResponse = (NSHTTPURLResponse*)response;
    NSInteger statusCode = [HTTPResponse statusCode];
    NSError* jsonError = nil;
    NSMutableDictionary* innerJson;
    
    if (data != nil && [data length] > 0) {
        innerJson = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
        [Kontext kontext_Log:KON_TEXT_LL_VERBOSE message:[NSString stringWithFormat:@"network response: %@", innerJson]];
        if (jsonError) {
            if (failureBlock != nil)
                failureBlock([NSError errorWithDomain:@"Kontext Error" code:statusCode userInfo:@{@"returned" : jsonError}]);
            return;
        }
    }
    
    if (error == nil && statusCode == 200) {
        if (successBlock != nil) {
            if (innerJson != nil)
                successBlock(innerJson);
            else
                successBlock(nil);
        }
    } else if (failureBlock != nil) {
        if (innerJson != nil && error == nil)
            failureBlock([NSError errorWithDomain:@"KontextError" code:statusCode userInfo:@{@"returned" : innerJson}]);
        else if (error != nil)
            failureBlock([NSError errorWithDomain:@"KontextError" code:statusCode userInfo:@{@"error" : error}]);
        else
            failureBlock([NSError errorWithDomain:@"KontextError" code:statusCode userInfo:nil]);
    }
}

@end
