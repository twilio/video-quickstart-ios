//
//  ExampleAudioRecorder.m
//  AudioSinkExample
//
//  Copyright © 2017 Twilio, Inc. All rights reserved.
//

#import "ExampleAudioRecorder.h"

#import <AVFoundation/AVFoundation.h>

@interface ExampleAudioRecorder()

@property (nonatomic, strong) AVAssetWriter *audioRecorder;
@property (nonatomic, strong) AVAssetWriterInput *audioRecorderInput;
@property (nonatomic, assign) CMTime recorderTimestamp;
@property (nonatomic, assign) int numberOfChannels;

@property (nonatomic, weak) TVIAudioTrack *audioTrack;

@end

@implementation ExampleAudioRecorder

- (instancetype)initWithAudioTrack:(TVIAudioTrack *)audioTrack identifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        _recorderTimestamp = kCMTimeInvalid;

        [self startRecordingAudioTrack:audioTrack withIdentifier:identifier];
    }
    return self;
}

- (void)startRecordingAudioTrack:(TVIAudioTrack *)audioTrack withIdentifier:(NSString *)identifier {
    NSParameterAssert(audioTrack);
    NSParameterAssert(identifier);

    // Setup Recorder
    NSError *error = nil;
    _audioRecorder = [[AVAssetWriter alloc] initWithURL:[[self class] recordingURLWithIdentifier:identifier]
                                               fileType:AVFileTypeWAVE
                                                  error:&error];

    if (error) {
        NSLog(@"Error setting up audio recorder: %@", error);
        return;
    }

    // The iOS audio device captures in mono.
    // In WebRTC 67 the channel count on the receiver side equals the sender side.
    _numberOfChannels = 1;

    // Assume that TVIAudioTrack will produce interleaved LPCM @ 16-bit / 48khz.
    // If the sample rate differs AVAssetWriterInput will upsample to 48 khz.
    NSDictionary<NSString *, id> *outputSettings = @{AVFormatIDKey : @(kAudioFormatLinearPCM),
                                                     AVSampleRateKey : @(48000),
                                                     AVNumberOfChannelsKey : @(self.numberOfChannels),
                                                     AVLinearPCMBitDepthKey : @(16),
                                                     AVLinearPCMIsFloatKey : @(NO),
                                                     AVLinearPCMIsBigEndianKey : @(NO),
                                                     AVLinearPCMIsNonInterleaved : @(NO)};

    _audioRecorderInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:outputSettings];
    _audioRecorderInput.expectsMediaDataInRealTime = YES;

    if ([_audioRecorder canAddInput:_audioRecorderInput]) {
        [_audioRecorder addInput:_audioRecorderInput];
        BOOL success = [_audioRecorder startWriting];

        if (success) {
            NSLog(@"Started recording audio track to: %@", _audioRecorder.outputURL);
            [audioTrack addSink:self];
            _audioTrack = audioTrack;
            _identifier = identifier;
        } else {
            NSLog(@"Couldn't start the AVAssetWriter: %@ error: %@", _audioRecorder, _audioRecorder.error);
        }
    }

    // This example does not support backgrounding. This is a good point to consider kicking off a background
    // task, and handling failures.
}

- (void)stopRecording {
    if (self.audioTrack) {
        [self.audioTrack removeSink:self];
        self.audioTrack = nil;
    }

    [self.audioRecorderInput markAsFinished];

    // Teardown the recorder
    [self.audioRecorder finishWritingWithCompletionHandler:^{
        if (self.audioRecorder.status == AVAssetWriterStatusFailed) {
            NSLog(@"AVAssetWriter failed with error: %@", self.audioRecorder.error);
        } else if (self.audioRecorder.status == AVAssetWriterStatusCompleted) {
            NSLog(@"AVAssetWriter finished writing to: %@", self.audioRecorder.outputURL);
        }
        self.audioRecorder = nil;
        self.audioRecorderInput = nil;
        self.recorderTimestamp = kCMTimeInvalid;
    }];
}

+ (NSURL *)recordingURLWithIdentifier:(NSString *)identifier {
    NSURL *documentsDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];

    // Choose a filename which will be unique if the `identifier` is reused (Append RFC3339 formatted date).
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    dateFormatter.dateFormat = @"HHmmss";
    dateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];

    NSString *dateComponent = [dateFormatter stringFromDate:[NSDate date]];
    NSString *filename = [NSString stringWithFormat:@"%@-%@.wav", identifier, dateComponent];

    return [documentsDirectory URLByAppendingPathComponent:filename];
}

#pragma mark - TVIAudioSink

- (void)renderSample:(CMSampleBufferRef)audioSample {
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(audioSample);

    // Detect and discard the initial invalid samples...
    // Waits for the track to start producing the expected number of channels, and for the timestamp to be reset.
    if (CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)->mChannelsPerFrame != _numberOfChannels) {
        return;
    }

    CMTime presentationTimestamp = CMSampleBufferGetPresentationTimeStamp(audioSample);

    if (CMTIME_IS_INVALID(self.recorderTimestamp)) {
        NSLog(@"Received first valid sample. Starting recording session.");
        [self.audioRecorder startSessionAtSourceTime:presentationTimestamp];
        self.recorderTimestamp = presentationTimestamp;
    }

    BOOL success = [self.audioRecorderInput appendSampleBuffer:audioSample];
    if (!success) {
        NSLog(@"Failed to append sample to writer: %@, error: %@", self.audioRecorder, self.audioRecorder.error);
    }
}

@end
