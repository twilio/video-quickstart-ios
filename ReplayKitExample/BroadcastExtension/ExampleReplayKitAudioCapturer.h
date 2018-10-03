//
//  ExampleCoreAudioDevice.h
//  AudioDeviceExample
//
//  Copyright © 2018 Twilio, Inc. All rights reserved.
//

#import <TwilioVideo/TwilioVideo.h>

@class SampleHandler;

OSStatus ExampleCoreAudioDeviceRecordCallback(CMSampleBufferRef audioSample);

typedef struct ExampleAudioContext {
    TVIAudioDeviceContext deviceContext;
    size_t expectedFramesPerBuffer;
    size_t maxFramesPerBuffer;
} ExampleAudioContext;

/*
 *  ExampleReplayKitAudioDevice consumes audio samples recorded by ReplayKit. Due to limitations of extensions, this
 *  device can't playback remote audio.
 */
@interface ExampleReplayKitAudioCapturer : NSObject <TVIAudioDevice>

- (instancetype)initWithAudioCapturer:(SampleHandler *)sampleHandler;

@end
