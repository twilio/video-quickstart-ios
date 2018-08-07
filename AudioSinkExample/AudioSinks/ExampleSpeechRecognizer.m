//
//  ExampleSpeechRecognizer.m
//  AudioSinkExample
//
//  Copyright © 2017 Twilio, Inc. All rights reserved.
//

#import "ExampleSpeechRecognizer.h"

#import <AudioToolbox/AudioToolbox.h>

static UInt32 kChannelCountMono = 1;

@interface ExampleSpeechRecognizer()

@property (nonatomic, strong) SFSpeechRecognizer *speechRecognizer;
@property (nonatomic, strong) SFSpeechAudioBufferRecognitionRequest *speechRequest;
@property (nonatomic, strong) SFSpeechRecognitionTask *speechTask;
@property (nonatomic, assign) AudioConverterRef speechConverter;

@property (nonatomic, copy) NSString *speechResult;
@property (nonatomic, weak) TVIAudioTrack *audioTrack;

@end

@implementation ExampleSpeechRecognizer

- (instancetype)initWithAudioTrack:(TVIAudioTrack *)audioTrack
                        identifier:(NSString *)identifier
                     resultHandler:(void (^)(SFSpeechRecognitionResult * result, NSError * error))resultHandler {
    self = [super init];

    if (self != nil) {
        _speechRecognizer = [[SFSpeechRecognizer alloc] init];
        _speechRecognizer.defaultTaskHint = SFSpeechRecognitionTaskHintDictation;

        _speechRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
        _speechRequest.shouldReportPartialResults = YES;

        __weak typeof(self) weakSelf = self;
        _speechTask = [_speechRecognizer recognitionTaskWithRequest:_speechRequest resultHandler:^(SFSpeechRecognitionResult * _Nullable result, NSError * _Nullable error) {
            __strong typeof(self) strongSelf = weakSelf;
            if (result) {
                strongSelf.speechResult = result.bestTranscription.formattedString;
            } else {
                NSLog(@"Speech recognition error: %@", error);
            }

            resultHandler(result, error);
        }];

        _audioTrack = audioTrack;
        [_audioTrack addSink:self];
        _identifier = identifier;
    }

    return self;
}

- (void)dealloc {
    [self.speechTask cancel];
}

- (void)stopRecognizing {
    [self.audioTrack removeSink:self];

    [self.speechTask finish];
    self.speechRequest = nil;
    self.speechRecognizer = nil;

    if (self.speechConverter != NULL) {
        AudioConverterDispose(self.speechConverter);
        self.speechConverter = NULL;
    }
}

#pragma mark - TVIAudioSink

- (void)renderSample:(CMSampleBufferRef)audioSample {
    CMAudioFormatDescriptionRef coreMediaFormat = (CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(audioSample);
    const AudioStreamBasicDescription *basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(coreMediaFormat);
    AVAudioFrameCount frameCount = (AVAudioFrameCount)CMSampleBufferGetNumSamples(audioSample);

    // SFSpeechAudioBufferRecognitionRequest does not handle stereo PCM inputs correctly, so always deliver mono.
    AVAudioFormat *avAudioFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16
                                                                    sampleRate:basicDescription->mSampleRate
                                                                      channels:kChannelCountMono
                                                                   interleaved:YES];

    // Allocate an AudioConverter to perform mono downmixing for us.
    if (self.speechConverter == NULL && basicDescription->mChannelsPerFrame != kChannelCountMono) {
        OSStatus status = AudioConverterNew(basicDescription, avAudioFormat.streamDescription, &_speechConverter);
        if (status != 0) {
            NSLog(@"Failed to create AudioConverter: %d", (int)status);
            return;
        }
    }

    // Perform downmixing if needed, otherwise deliver the original CMSampleBuffer.
    if (basicDescription->mChannelsPerFrame == kChannelCountMono) {
        [self.speechRequest appendAudioSampleBuffer:audioSample];
    } else {
        AVAudioPCMBuffer *pcmBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:avAudioFormat frameCapacity:frameCount];

        // Fill the AVAudioPCMBuffer with downmixed mono audio.
        CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(audioSample);
        size_t inputBytes = 0;
        char *inputSamples = NULL;
        OSStatus status = CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &inputBytes, &inputSamples);

        if (status != kCMBlockBufferNoErr) {
            NSLog(@"Failed to get data pointer: %d", (int)status);
            return;
        }

        // Allocate some memory for us...
        pcmBuffer.frameLength = pcmBuffer.frameCapacity;
        AudioBufferList *bufferList = pcmBuffer.mutableAudioBufferList;
        AudioBuffer buffer = bufferList->mBuffers[0];
        void *outputSamples = buffer.mData;
        UInt32 outputBytes = buffer.mDataByteSize;

        status = AudioConverterConvertBuffer(_speechConverter, (UInt32)inputBytes, (const void *)inputSamples, &outputBytes, outputSamples);

        if (status == 0) {
            [self.speechRequest appendAudioPCMBuffer:pcmBuffer];
        } else {
            NSLog(@"Failed to convert audio: %d", (int)status);
        }
    }
}

@end
