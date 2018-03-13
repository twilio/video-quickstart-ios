//
//  ExampleAVAudioEngineDevice.h
//  AudioDeviceExample
//
//  Copyright © 2018 Twilio Inc. All rights reserved.
//

#import <TwilioVideo/TwilioVideo.h>

NS_CLASS_AVAILABLE(NA, 11_0)
@interface ExampleAVAudioEngineDevice : NSObject <TVIAudioDevice>

- (void)playMusic;

@end
