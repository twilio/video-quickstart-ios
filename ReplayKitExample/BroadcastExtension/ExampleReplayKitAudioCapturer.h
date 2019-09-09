//
//  ExampleReplayKitAudioCapturer.h
//  ReplayKitExample
//
//  Copyright © 2018-2019 Twilio, Inc. All rights reserved.
//

#import <ReplayKit/ReplayKit.h>
#import <TwilioVideo/TwilioVideo.h>

dispatch_queue_t _Nullable ExampleCoreAudioDeviceGetCurrentQueue(void);

typedef struct ExampleAudioContext {
    TVIAudioDeviceContext _Nullable deviceContext;
    size_t maxFramesPerBuffer;
    AudioStreamBasicDescription streamDescription;
} ExampleAudioContext;

/*
 *  ExampleReplayKitAudioCapturer consumes audio samples recorded by ReplayKit. Due to limitations of extensions, this
 *  device can't playback remote audio.
 */
@interface ExampleReplayKitAudioCapturer : NSObject <TVIAudioDevice>

- (nonnull instancetype)init;

- (nonnull instancetype)initWithSampleType:(RPSampleBufferType)type NS_DESIGNATED_INITIALIZER;

@end

/// Deliver audio samples to the capturer.
/// @param capturer The capturer to deliver the samples to.
/// @param sampleBuffer A CMSampleBuffer which contains an audio sample.
OSStatus ExampleCoreAudioDeviceCapturerCallback(ExampleReplayKitAudioCapturer * _Nonnull capturer,
                                              CMSampleBufferRef _Nonnull sampleBuffer);
