//
//  ExampleAVPlayerProcessingTap.h
//  CoViewingExample
//
//  Copyright © 2018 Twilio Inc. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <TPCircularBuffer/TPCircularBuffer.h>

@class ExampleAVPlayerAudioDevice;

typedef struct ExampleAVPlayerAudioTapContext {
    __weak ExampleAVPlayerAudioDevice *audioDevice;
    BOOL audioTapPrepared;

    TPCircularBuffer *capturingBuffer;
    AudioConverterRef captureFormatConverter;
    BOOL capturingSampleRateConversion;
    BOOL captureFormatConvertIsPrimed;

    TPCircularBuffer *renderingBuffer;
    AudioConverterRef renderFormatConverter;
    AudioStreamBasicDescription renderingFormat;

    // Cached source audio, in case we need to perform a sample rate conversion and can't consume all the samples in one go.
    AudioBufferList *sourceCache;
    UInt32 sourceCacheFrames;
    AudioStreamBasicDescription sourceFormat;
} ExampleAVPlayerAudioTapContext;

void AVPlayerProcessingTapInit(MTAudioProcessingTapRef tap, void *clientInfo, void **tapStorageOut);

void AVPlayerProcessingTapFinalize(MTAudioProcessingTapRef tap);

void AVPlayerProcessingTapPrepare(MTAudioProcessingTapRef tap,
                                  CMItemCount maxFrames,
                                  const AudioStreamBasicDescription *processingFormat);

void AVPlayerProcessingTapUnprepare(MTAudioProcessingTapRef tap);

void AVPlayerProcessingTapProcess(MTAudioProcessingTapRef tap,
                                  CMItemCount numberFrames,
                                  MTAudioProcessingTapFlags flags,
                                  AudioBufferList *bufferListInOut,
                                  CMItemCount *numberFramesOut,
                                  MTAudioProcessingTapFlags *flagsOut);
