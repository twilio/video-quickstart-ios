//
//  Utils.m
//  AVPlayerExample
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
                                            NSError *err = error;
                                            NSString *accessToken;
                                            NSString *identity;
                                            if (!err) {
                                                if (data != nil) {
                                                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                                                         options:0
                                                                                                           error:&err];
                                                    if (!err) {
                                                        accessToken = json[@"token"];
                                                        identity = json[@"identity"];
                                                        NSLog(@"Logged in as %@",identity);
                                                    }
                                                }
                                            }
                                            completionHandler(accessToken, err);
                                        }];
    [task resume];
}

@end
