//
//  ExampleSpeechRecognizer.h
//  AudioSinkExample
//
//  Copyright © 2017 Twilio, Inc. All rights reserved.
//

@import Foundation;
@import Speech;
@import TwilioVideo;

@interface ExampleSpeechRecognizer : NSObject <TVIAudioSink>

- (null_unspecified instancetype)initWithAudioTrack:(nonnull TVIAudioTrack *)audioTrack
                                         identifier:(nonnull NSString *)identifier
                                      resultHandler:(void (^ _Nonnull)(SFSpeechRecognitionResult * __nullable result, NSError * __nullable error))resultHandler;

// Breaks the strong reference from TVIAudioTrack by removing its Sink.
- (void)stopRecognizing;

@property (nonatomic, copy, readonly, nullable) NSString *speechResult;
@property (nonatomic, copy, readonly, nonnull) NSString *identifier;

@end
