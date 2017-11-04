//
//  ExampleAudioRecorder.h
//  RTCRoomsDemo
//
//  Created by Chris Eagleston on 6/23/17.
//  Copyright © 2017 Twilio, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ExampleAudioRecorder : NSObject

- (null_unspecified instancetype)initWithAudioTrack:(nonnull TVIAudioTrack *)audioTrack identifier:(nonnull NSString *)identifier;

// Breaks the strong reference from TVIAudioTrack by removing its Sink.
- (void)stopRecording;

@property (nonatomic, copy, readonly, nonnull) NSString *identifier;

@end
