//
//  ExampleAVAudioEngineDevice.h
//  AudioDeviceExample
//
//  Copyright © 2018-2019 Twilio Inc. All rights reserved.
//

#import <TwilioVideo/TwilioVideo.h>

NS_CLASS_AVAILABLE(NA, 11_0)
@interface ExampleAVAudioEngineDevice : NSObject <TVIAudioDevice>

/**
 *  @brief This method is invoked when client wish to play music using the AVAudioEngine and CoreAudio
 *
 *  @param continuous Continue playing music after the disconnect.
 *
 *  @discussion Your app can play music before connecting a Room, while in a Room or after the disconnect.
 *  If you wish to play music irespective of you are connected to a Room or not (before [TwilioVideo connect:] or
 *  after [room disconnect]), or wish to continue playing music after disconnected from a Room, set the `continuous`
 *  argument to `YES`.
 *  If the `continuous` is set to `NO`, the audio device will not continue playing the music once you disconnect from the Room.
 */
- (void)playMusic:(BOOL)continuous;

@end
