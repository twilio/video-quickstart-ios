//
//  ExampleReplayKitAudioCapturer.h
//  ReplayKitExample
//
//  Copyright © 2018-2019 Twilio, Inc. All rights reserved.
//

#import <ReplayKit/ReplayKit.h>
//#import <TwilioVideo/TVIAudioFormat.h>
//#import <TwilioVideo/TVIAudioDevice.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wduplicate-protocol"
#pragma clang diagnostic ignored "-Wall"
@import TwilioVideo;
//#import "TwilioVideo/TVIAudioDevice.h"
#pragma clang diagnostic pop

#import "ExampleReplayKitAudioCapturerDispatch.h"

//@class TVIAudioFormat;

OSStatus ExampleCoreAudioDeviceRecordCallback(CMSampleBufferRef audioSample);

typedef struct ExampleAudioContext {
    void *deviceContext;
    size_t expectedFramesPerBuffer;
    size_t maxFramesPerBuffer;
} ExampleAudioContext;

/*
 *  ExampleReplayKitAudioCapturer consumes audio samples recorded by ReplayKit. Due to limitations of extensions, this
 *  device can't playback remote audio.
 */
@interface ExampleReplayKitAudioCapturer : NSObject <TVIAudioDevice>

- (instancetype)init;

- (instancetype)initWithSampleType:(RPSampleBufferType)type NS_DESIGNATED_INITIALIZER;

@end
