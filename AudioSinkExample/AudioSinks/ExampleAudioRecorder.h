//
//  ExampleAudioRecorder.h
//  AudioSinkExample
//
//  Copyright © 2017 Twilio, Inc. All rights reserved.
//

@import Foundation;

#import <TwilioVideo/TwilioVideo.h>

@interface ExampleAudioRecorder : NSObject <TVIAudioSink>

- (null_unspecified instancetype)initWithAudioTrack:(nonnull TVIAudioTrack *)audioTrack
                                         identifier:(nonnull NSString *)identifier;

// Breaks the strong reference from TVIAudioTrack by removing its Sink.
- (void)stopRecording;

@property (nonatomic, copy, readonly, nonnull) NSString *identifier;

@end
