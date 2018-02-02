//
//  KontextClientOverrider.m
//  Kontext
//
//  Created by Brad Hesse on 12/19/17.
//  Copyright © 2017 Hiptic. All rights reserved.
//

//
//  KontextClientOverrider.m
//  UnitTests
//
//  Created by Brad Hesse on 12/18/17.
//  Copyright © 2017 Hiptic. All rights reserved.
//

#import "KontextClientOverrider.h"
#import "TestHelperFunctions.h"

#import "Kontext.h"
#import "KontextHelper.h"
#import "KontextClient.h"
#import "KontextRequest.h"
#import "KontextSelectorHelpers.h"

@implementation KontextClientOverrider

static dispatch_queue_t serialMockMainLooper;
static NSString* lastUrl;
static int networkRequestCount;
static NSDictionary* lastHTTPRequest;
static XCTestCase* currentTestInstance;

+ (void)load {
    serialMockMainLooper = dispatch_queue_create("com.kontext.unittest", DISPATCH_QUEUE_SERIAL);
    
    
    //with refactored networking code, need to replace the implementation of the execute request method so tests don't actually execite HTTP requests
    injectToProperClass(@selector(overrideExecuteRequest:onSuccess:onFailure:), @selector(executeRequest:onSuccess:onFailure:), @[], [KontextClientOverrider class], [KontextClient class]);
}

- (void)overrideExecuteRequest:(KontextRequest *)request onSuccess:(KontextResultSuccessBlock)successBlock onFailure:(KontextFailureBlock)failureBlock {
    NSMutableDictionary *parameters = [request.parameters mutableCopy];
    
    if (!parameters[@"app_id"] && ![request.request.URL.absoluteString containsString:@"/apps/"])
        _XCTPrimitiveFail(currentTestInstance, @"All request should include an app_id");
    
    networkRequestCount++;
    
    id url = [request.request URL];
    NSLog(@"url: %@", url);
    NSLog(@"parameters: %@", parameters);
    
    lastUrl = [url absoluteString];
    lastHTTPRequest = parameters;
    
    if (successBlock) {
        if ([request.request.URL.absoluteString hasPrefix:@"https://api.kontext.in/api/v1/apps/"])
            successBlock(@{@"fba": @true});
        else
            successBlock(@{@"id": @"1234"});
    }
}

+(void)reset:(XCTestCase*)testInstance {
    currentTestInstance = testInstance;
    
    networkRequestCount = 0;
    lastUrl = nil;
    lastHTTPRequest = nil;
}

+(void)setLastHTTPRequest:(NSDictionary*)value {
    lastHTTPRequest = value;
}
+(NSDictionary*)lastHTTPRequest {
    return lastHTTPRequest;
}

+(int)networkRequestCount {
    return networkRequestCount;
}

+(void)setLastUrl:(NSString*)value {
    lastUrl = value;
}

+(NSString*)lastUrl {
    return lastUrl;
}

@end

