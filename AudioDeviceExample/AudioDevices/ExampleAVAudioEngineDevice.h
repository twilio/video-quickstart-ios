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

/**
 *  @brief Enable audio device
 *
 *  @discussion By default, the SDK initializes this property to YES. Setting it to NO entirely disables the audio device. When the device is disabled, both audio capture and playback halt. This toggle should be used in CallKit delegate (CXProviderDelegate) methods (ex: didReset, didActivate, didDeactivate) to negotiate call holding and other events taking place from the iOS dialer
 */

@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

@end
