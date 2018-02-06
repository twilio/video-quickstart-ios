//
//  ExampleCoreAudioDevice.h
//  AudioDeviceExample
//
//  Copyright © 2018 Twilio, Inc. All rights reserved.
//

#import <TwilioVideo/TwilioVideo.h>

/*
 *  ExampleCoreAudioDevice uses a RemoteIO audio unit to playback stereo audio at up to 48 kHz.
 *  In contrast to `TVIDefaultAudioDevice`, this class does not record audio and is intended for high quality playback.
 *  Since full duplex audio is not needed this device does not use the built in echo cancellation provided by
 *  CoreAudio's VoiceProcessingIO audio unit.
 */
@interface ExampleCoreAudioDevice : NSObject <TVIAudioDevice>

- (nullable TVIAudioFormat *)renderFormat;

- (BOOL)initializeRenderer;

- (BOOL)startRendering:(nonnull TVIAudioDeviceContext)context;

- (BOOL)stopRendering;

- (nullable TVIAudioFormat *)captureFormat;

- (BOOL)initializeCapturer;

- (BOOL)startCapturing:(nonnull TVIAudioDeviceContext)context;

- (BOOL)stopCapturing;

@end
