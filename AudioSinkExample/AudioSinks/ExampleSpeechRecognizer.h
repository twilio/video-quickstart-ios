//
//  ExampleSpeechRecognizer.h
//  RTCRoomsDemo
//
//  Created by Chris Eagleston on 6/23/17.
//  Copyright © 2017 Twilio, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <TwilioVideo/TwilioVideo.h>

@interface ExampleSpeechRecognizer : NSObject

- (instancetype)initWithAudioTrack:(TVIAudioTrack *)audioTrack identifier:(NSString *)identifier;

// Breaks the strong reference from TVIAudioTrack by removing its Sink.
- (void)stopRecognizing;

@property (nonatomic, copy, readonly) NSString *speechResult;
@property (nonatomic, copy, readonly) NSString *identifier;

@end
