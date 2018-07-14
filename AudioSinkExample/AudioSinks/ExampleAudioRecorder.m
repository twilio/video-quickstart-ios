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
@property (nonatomic, assign) UInt32 numberOfChannels;
@property (nonatomic, assign) Float64 sampleRate;

@property (nonatomic, weak) TVIAudioTrack *audioTrack;

@end

@implementation ExampleAudioRecorder

- (instancetype)initWithAudioTrack:(TVIAudioTrack *)audioTrack identifier:(NSString *)identifier {
    NSParameterAssert(audioTrack);
    NSParameterAssert(identifier);

    self = [super init];
    if (self) {
        _recorderTimestamp = kCMTimeInvalid;
        _audioTrack = audioTrack;
        _identifier = identifier;

        // We will defer recording until the first audio sample is available.
        [_audioTrack addSink:self];
    }
    return self;
}

- (void)startRecordingWithTimestamp:(CMTime)timestamp basicDescription:(const AudioStreamBasicDescription *)basicDescription {
    // Setup Recorder
    NSError *error = nil;
    _audioRecorder = [[AVAssetWriter alloc] initWithURL:[[self class] recordingURLWithIdentifier:_identifier]
                                               fileType:AVFileTypeWAVE
                                                  error:&error];

    if (error) {
        NSLog(@"Error setting up audio recorder: %@", error);
        return;
    }

    _numberOfChannels = basicDescription->mChannelsPerFrame;
    _sampleRate = basicDescription->mSampleRate;

    NSLog(@"Recorder input is %d %@, %f Hz.",
          _numberOfChannels, _numberOfChannels == 1 ? @"channel" : @"channels", _sampleRate);

    // Assume that TVIAudioTrack will produce interleaved stereo LPCM @ 16-bit / 48khz
    NSDictionary<NSString *, id> *outputSettings = @{AVFormatIDKey : @(kAudioFormatLinearPCM),
                                                     AVSampleRateKey : @(_sampleRate),
                                                     AVNumberOfChannelsKey : @(_numberOfChannels),
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
            [self.audioRecorder startSessionAtSourceTime:timestamp];
            self.recorderTimestamp = timestamp;
        } else {
            NSLog(@"Couldn't start the AVAssetWriter: %@ error: %@", _audioRecorder, _audioRecorder.error);
        }
    } else {
        _audioRecorder = nil;
        _audioRecorderInput = nil;
    }

    // This example does not support backgrounding. Now is a good point to consider kicking off a background
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

- (BOOL)detectSilence:(CMSampleBufferRef)audioSample {
    // Get the audio samples. We count a corrupted buffer as silence.
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(audioSample);
    size_t inputBytes = 0;
    char *inputSamples = NULL;
    OSStatus status = CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &inputBytes, &inputSamples);

    if (status != kCMBlockBufferNoErr) {
        NSLog(@"Failed to get data pointer: %d", status);
        return YES;
    }

    // Check for silence. This technique is not efficient, it might be better to sum the values of the vector instead.
    BOOL silence = YES;
    for (int i = 0; i < inputBytes; i+=2) {
        int16_t *sample = (int16_t *)(inputSamples + i);
        if (*sample != 0) {
            silence = NO;
            break;
        }
    }

    return silence;
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
    const AudioStreamBasicDescription *basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);
    CMTime presentationTimestamp = CMSampleBufferGetPresentationTimeStamp(audioSample);

    // We defer recording until the first sample in order to determine the appropriate channel layout and sample rate.
    if (CMTIME_IS_INVALID(self.recorderTimestamp)) {
        // Detect and discard initial 16 kHz silence, before the first real samples are received from a remote source.
        if (basicDescription->mSampleRate == 16000. && [self detectSilence:audioSample]) {
            return;
        } else {
            [self startRecordingWithTimestamp:presentationTimestamp basicDescription:basicDescription];
        }
    } else {
        // Sanity check on our assumptions.
        NSAssert(basicDescription->mChannelsPerFrame == _numberOfChannels,
                 @"Channel mismatch. was: %d now: %d", _numberOfChannels, basicDescription->mChannelsPerFrame);
        NSAssert(basicDescription->mSampleRate == _sampleRate,
                 @"Sample rate mismatch. was: %f now: %f", _sampleRate, basicDescription->mSampleRate);
    }

    BOOL success = [self.audioRecorderInput appendSampleBuffer:audioSample];
    if (!success) {
        NSLog(@"Failed to append sample to writer: %@, error: %@", self.audioRecorder, self.audioRecorder.error);
    }
}

@end
