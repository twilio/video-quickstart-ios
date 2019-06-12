//
//  Utils.m
//  ObjCVideoQuickstart
//
//  Copyright © 2016-2017 Twilio, Inc. All rights reserved.
//

#import "Utils.h"

@implementation PlatformUtils

+ (BOOL)isSimulator {
#if TARGET_IPHONE_SIMULATOR
    return YES;
#endif
    return NO;
}

@end

@implementation TokenUtils

+ (void)retrieveAccessTokenFromURL:(NSString *)tokenURLStr
                        completion:(void (^)(NSString* token, NSError *err)) completionHandler {
    NSURL *tokenURL = [NSURL URLWithString:tokenURLStr];
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];
    NSURLSessionDataTask *task = [session dataTaskWithURL:tokenURL
                                        completionHandler: ^(NSData * _Nullable data,
                                                             NSURLResponse * _Nullable response,
                                                             NSError * _Nullable error) {
                                            NSString *accessToken = nil;
                                            if (!error && data) {
                                                accessToken = [[NSString alloc] initWithData:data
                                                                                    encoding:NSUTF8StringEncoding];
                                            }
                                            completionHandler(accessToken, error);
                                        }];
    [task resume];
}

@end
