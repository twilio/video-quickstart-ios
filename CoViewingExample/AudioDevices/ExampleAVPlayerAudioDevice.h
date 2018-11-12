//
//  ExampleAVPlayerAudioDevice.h
//  CoViewingExample
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

- (void)audioTapDidPrepare;

- (void)startAudioTapAtTime:(CMTime)startTime;

/*
 * Creates a processing tap bound to the device instance.
 *
 * @return An `MTAudioProcessingTap`, or NULL if there is an error. The caller assumes all ownership
 * of the tap, and should call CFRelease when they are finished with it.
 */
- (nullable MTAudioProcessingTapRef)createProcessingTap;

@end
