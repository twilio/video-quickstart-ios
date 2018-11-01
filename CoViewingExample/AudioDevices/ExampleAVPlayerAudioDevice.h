//
//  ExampleAVPlayerAudioDevice.h
//  AudioDeviceExample
//
//  Copyright © 2018 Twilio, Inc. All rights reserved.
//

#import <TwilioVideo/TwilioVideo.h>

/*
 * ExampleAVPlayerAudioDevice uses a VoiceProcessingIO audio unit to play audio from an MTAudioProcessingTap
 * attached to an AVPlayerItem. The AVPlayer audio is mixed with Room audio provided by Twilio.
 * The microphone input, and MTAudioProcessingTap output are mixed into a single recorded stream.
 */
@interface ExampleAVPlayerAudioDevice : NSObject <TVIAudioDevice>

@end
