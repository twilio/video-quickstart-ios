//
//  ExampleAVPlayerProcessingTap.m
//  CoViewingExample
//
//  Copyright © 2018 Twilio Inc. All rights reserved.
//

#import "ExampleAVPlayerProcessingTap.h"

#import "ExampleAVPlayerAudioDevice.h"
#import "TPCircularBuffer+AudioBufferList.h"

static size_t const kPreferredNumberOfChannels = 2;
static uint32_t const kPreferredSampleRate = 48000;

typedef struct ExampleAVPlayerAudioConverterContext {
    AudioBufferList *cacheBuffers;
    UInt32 cachePackets;
    AudioBufferList *sourceBuffers;
    // Keep track if we are iterating through the source to provide data to a converter.
    UInt32 sourcePackets;
    UInt32 sourcePacketIndex;
} ExampleAVPlayerAudioConverterContext;

AudioBufferList *AudioBufferListCreate(const AudioStreamBasicDescription *audioFormat, int frameCount) {
    int numberOfBuffers = audioFormat->mFormatFlags & kAudioFormatFlagIsNonInterleaved ? audioFormat->mChannelsPerFrame : 1;
    AudioBufferList *audio = malloc(sizeof(AudioBufferList) + (numberOfBuffers - 1) * sizeof(AudioBuffer));
    if (!audio) {
        return NULL;
    }
    audio->mNumberBuffers = numberOfBuffers;

    int channelsPerBuffer = audioFormat->mFormatFlags & kAudioFormatFlagIsNonInterleaved ? 1 : audioFormat->mChannelsPerFrame;
    int bytesPerBuffer = audioFormat->mBytesPerFrame * frameCount;
    for (int i = 0; i < numberOfBuffers; i++) {
        if (bytesPerBuffer > 0) {
            audio->mBuffers[i].mData = calloc(bytesPerBuffer, 1);
            if (!audio->mBuffers[i].mData) {
                for (int j = 0; j < i; j++ ) {
                    free(audio->mBuffers[j].mData);
                }
                free(audio);
                return NULL;
            }
        } else {
            audio->mBuffers[i].mData = NULL;
        }
        audio->mBuffers[i].mDataByteSize = bytesPerBuffer;
        audio->mBuffers[i].mNumberChannels = channelsPerBuffer;
    }
    return audio;
}

void AudioBufferListFree(AudioBufferList *bufferList ) {
    for (int i=0; i<bufferList->mNumberBuffers; i++) {
        if (bufferList->mBuffers[i].mData != NULL) {
            free(bufferList->mBuffers[i].mData);
        }
    }
    free(bufferList);
}

OSStatus AVPlayerAudioTapConverterInputDataProc(AudioConverterRef inAudioConverter,
                                                UInt32 *ioNumberDataPackets,
                                                AudioBufferList *ioData,
                                                AudioStreamPacketDescription * _Nullable *outDataPacketDescription,
                                                void *inUserData) {
    UInt32 bytesPerChannel = 4;

    // Give the converter what they asked for. They might not consume all of our source in one callback.
    UInt32 minimumPackets = *ioNumberDataPackets;
    ExampleAVPlayerAudioConverterContext *context = inUserData;

    assert(context->sourcePackets + context->cachePackets >= *ioNumberDataPackets);
//    printf("Convert at least %d input packets. We have %d source packets, %d cached packets.\n", *ioNumberDataPackets, context->sourcePackets, context->cachePackets);
    AudioBufferList *sourceBufferList = (AudioBufferList *)context->sourceBuffers;
    AudioBufferList *cacheBufferList = (AudioBufferList *)context->cacheBuffers;
    assert(sourceBufferList->mNumberBuffers == ioData->mNumberBuffers);

    for (UInt32 i = 0; i < sourceBufferList->mNumberBuffers; i++) {
        if (context->cachePackets > 0) {
            AudioBuffer *cacheBuffer = &cacheBufferList->mBuffers[i];
            AudioBuffer *outputBuffer = &ioData->mBuffers[i];
            UInt32 cachedBytes = context->cachePackets * bytesPerChannel;
            UInt32 cachedFrames = context->cachePackets;
            outputBuffer->mNumberChannels = cacheBuffer->mNumberChannels;
            outputBuffer->mDataByteSize = cachedBytes;
            outputBuffer->mData = cacheBuffer->mData;
            *ioNumberDataPackets = cachedFrames;
        } else {
            UInt32 sourceFrames = minimumPackets;
            UInt32 sourceBytes = sourceFrames * bytesPerChannel;

            AudioBuffer *sourceBuffer = &sourceBufferList->mBuffers[i];
            AudioBuffer *outputBuffer = &ioData->mBuffers[i];
            outputBuffer->mNumberChannels = sourceBuffer->mNumberChannels;
            outputBuffer->mDataByteSize = sourceBytes;
            outputBuffer->mData = sourceBuffer->mData + (context->sourcePacketIndex * bytesPerChannel * sourceBuffer->mNumberChannels);
        }
    }

    if (context->cachePackets > 0) {
        context->cachePackets = 0;
    } else {
        context->sourcePacketIndex += *ioNumberDataPackets;
    }

//    if (context->sourcePackets - minimumPackets > 0) {
//        // Copy the remainder of the source which was not used into the front of our cache.
//
//        UInt32 packetsToCopy = context->sourcePackets - minimumPackets;
//        for (UInt32 i = 0; i < sourceBufferList->mNumberBuffers; i++) {
//            AudioBuffer *cacheBuffer = &cacheBufferList->mBuffers[i];
//            AudioBuffer *sourceBuffer = &sourceBufferList->mBuffers[i];
//            assert(cacheBuffer->mDataByteSize >= sourceBuffer->mDataByteSize);
//            UInt32 bytesToCopy = packetsToCopy * bytesPerChannel;
//            void *sourceData = sourceBuffer->mData + (minimumPackets * bytesPerChannel);
//            memcpy(cacheBuffer->mData, sourceData, bytesToCopy);
//        }
//        context->cachePackets = packetsToCopy;
//    }

    return noErr;
}

static inline void AVPlayerAudioTapProduceFilledFrames(TPCircularBuffer *buffer,
                                                       AudioConverterRef converter,
                                                       BOOL isConverterPrimed,
                                                       AudioBufferList *bufferListIn,
                                                       AudioBufferList *sourceCache,
                                                       UInt32 *cachedSourceFrames,
                                                       UInt32 framesIn,
                                                       UInt32 channelsOut) {
    // Start with input buffer size as our argument.
    // TODO: Does non-interleaving count towards the size (*2)?
    // Give us a little more priming than we need (~8 frames).
    UInt32 primeFrames = 8;
    UInt32 sourceFrames = framesIn;
    if (!isConverterPrimed) {
        framesIn -= primeFrames;
    } else if (*cachedSourceFrames > 0) {
        framesIn += *cachedSourceFrames;
    }
    UInt32 desiredIoBufferSize = framesIn * 4 * bufferListIn->mNumberBuffers;
//    printf("Input is %d bytes (%d total frames, %d cached frames).\n", desiredIoBufferSize, framesIn, *cachedSourceFrames);
    UInt32 propertySizeIo = sizeof(desiredIoBufferSize);
    OSStatus status = AudioConverterGetProperty(converter,
                                                kAudioConverterPropertyCalculateOutputBufferSize,
                                                &propertySizeIo, &desiredIoBufferSize);

    UInt32 bytesPerFrameOut = channelsOut * sizeof(SInt16);
    UInt32 framesOut = (desiredIoBufferSize) / bytesPerFrameOut;
//    UInt32 framesOut = (desiredIoBufferSize + (bytesPerFrameOut - 1)) / bytesPerFrameOut;
//    framesOut += framesOut % 2;
    UInt32 bytesOut = framesOut * bytesPerFrameOut;
//    printf("Converter wants an output of %d bytes (%d frames, %d bytes per frames).\n",
//           desiredIoBufferSize, framesOut, bytesPerFrameOut);

    AudioBufferList *producerBufferList = TPCircularBufferPrepareEmptyAudioBufferList(buffer, 1, bytesOut, NULL);
    if (producerBufferList == NULL) {
        return;
    }
    producerBufferList->mBuffers[0].mNumberChannels = channelsOut;

    UInt32 ioPacketSize = framesOut;
//    printf("Ready to fill output buffer of frames: %d, bytes: %d with input buffer of frames: %d, bytes: %d.\n",
//           framesOut, bytesOut, framesIn, framesIn * 4 * bufferListIn->mNumberBuffers);
    ExampleAVPlayerAudioConverterContext context;
    context.sourceBuffers = bufferListIn;
    context.cacheBuffers = sourceCache;
    context.sourcePackets = sourceFrames;
    context.sourcePacketIndex = 0;
    context.cachePackets = *cachedSourceFrames;
    status = AudioConverterFillComplexBuffer(converter,
                                             AVPlayerAudioTapConverterInputDataProc,
                                             &context,
                                             &ioPacketSize,
                                             producerBufferList,
                                             NULL);
    // Adjust for what the format converter actually produced, in case it was different than what we asked for.
    producerBufferList->mBuffers[0].mDataByteSize = ioPacketSize * bytesPerFrameOut;
//    printf("Output was: %d packets / %d bytes. Consumed input packets: %d. Cached input packets: %d.\n",
//           ioPacketSize, ioPacketSize * bytesPerFrameOut, context.sourcePackets, context.cachePackets);

    // TODO: Do we still produce the buffer list after a failure?
    if (status == kCVReturnSuccess) {
        *cachedSourceFrames = context.cachePackets;
        TPCircularBufferProduceAudioBufferList(buffer, NULL);
    } else {
        printf("Error converting buffers: %d\n", status);
    }
}

static inline void AVPlayerAudioTapProduceConvertedFrames(TPCircularBuffer *buffer,
                                                          AudioConverterRef converter,
                                                          AudioBufferList *bufferListIn,
                                                          UInt32 framesIn,
                                                          CMTimeRange *sourceRangeIn,
                                                          UInt32 channelsOut) {
    UInt32 bytesOut = framesIn * channelsOut * 2;
    AudioBufferList *producerBufferList = TPCircularBufferPrepareEmptyAudioBufferList(buffer, 1, bytesOut, NULL);
    if (producerBufferList == NULL) {
        return;
    }
    producerBufferList->mBuffers[0].mNumberChannels = channelsOut;

    OSStatus status = AudioConverterConvertComplexBuffer(converter,
                                                         framesIn,
                                                         bufferListIn,
                                                         producerBufferList);

    // TODO: Do we still produce the buffer list after a failure?
    if (status == kCVReturnSuccess) {
        AudioTimeStamp timestamp = {0};
        timestamp.mFlags = kAudioTimeStampSampleTimeValid;
        timestamp.mSampleTime = sourceRangeIn->start.value;
        TPCircularBufferProduceAudioBufferList(buffer, &timestamp);
    } else {
        printf("Error converting buffers: %d\n", status);
    }
}

#pragma mark - MTAudioProcessingTap

void AVPlayerProcessingTapInit(MTAudioProcessingTapRef tap, void *clientInfo, void **tapStorageOut) {
    NSLog(@"Init audio tap.");

    // Provide access to our device in the Callbacks.
    *tapStorageOut = clientInfo;
}

void AVPlayerProcessingTapFinalize(MTAudioProcessingTapRef tap) {
    NSLog(@"Finalize audio tap.");

    ExampleAVPlayerAudioTapContext *context = (ExampleAVPlayerAudioTapContext *)MTAudioProcessingTapGetStorage(tap);
    context->audioTapPrepared = NO;
    TPCircularBuffer *capturingBuffer = context->capturingBuffer;
    TPCircularBuffer *renderingBuffer = context->renderingBuffer;
    TPCircularBufferCleanup(capturingBuffer);
    TPCircularBufferCleanup(renderingBuffer);
}

void AVPlayerProcessingTapPrepare(MTAudioProcessingTapRef tap,
                                  CMItemCount maxFrames,
                                  const AudioStreamBasicDescription *processingFormat) {
    NSLog(@"Preparing with frames: %d, channels: %d, bits/channel: %d, sample rate: %0.1f",
          (int)maxFrames, processingFormat->mChannelsPerFrame, processingFormat->mBitsPerChannel, processingFormat->mSampleRate);
    assert(processingFormat->mFormatID == kAudioFormatLinearPCM);

    // Defer init of the ring buffer memory until we understand the processing format.
    ExampleAVPlayerAudioTapContext *context = (ExampleAVPlayerAudioTapContext *)MTAudioProcessingTapGetStorage(tap);
    TPCircularBuffer *capturingBuffer = context->capturingBuffer;
    TPCircularBuffer *renderingBuffer = context->renderingBuffer;

    size_t bufferSize = processingFormat->mBytesPerFrame * maxFrames;
    // We need to add some overhead for the AudioBufferList data structures.
    bufferSize += 2048;
    // TODO: Size the buffer appropriately, as we may need to accumulate more than maxFrames due to bursty processing.
    bufferSize *= 20;

    // TODO: If we are re-allocating then check the size?
    TPCircularBufferInit(capturingBuffer, bufferSize);
    TPCircularBufferInit(renderingBuffer, bufferSize);

    AudioBufferList *cacheBufferList = AudioBufferListCreate(processingFormat, (int)maxFrames);
    context->sourceCache = cacheBufferList;
    context->sourceCacheFrames = 0;
    context->sourceFormat = *processingFormat;

    TVIAudioFormat *playbackFormat = [[TVIAudioFormat alloc] initWithChannels:processingFormat->mChannelsPerFrame
                                                                   sampleRate:processingFormat->mSampleRate
                                                              framesPerBuffer:maxFrames];
    AudioStreamBasicDescription preferredPlaybackDescription = [playbackFormat streamDescription];
    BOOL requiresFormatConversion = preferredPlaybackDescription.mFormatFlags != processingFormat->mFormatFlags;

    context->renderingFormat = preferredPlaybackDescription;

    if (requiresFormatConversion) {
        OSStatus status = AudioConverterNew(processingFormat, &preferredPlaybackDescription, &context->renderFormatConverter);
        if (status != 0) {
            NSLog(@"Failed to create AudioConverter: %d", (int)status);
            return;
        }
    }

    TVIAudioFormat *recordingFormat = [[TVIAudioFormat alloc] initWithChannels:kPreferredNumberOfChannels
                                                                    sampleRate:(Float64)kPreferredSampleRate
                                                               framesPerBuffer:maxFrames];
    AudioStreamBasicDescription preferredRecordingDescription = [recordingFormat streamDescription];
    BOOL requiresSampleRateConversion = processingFormat->mSampleRate != preferredRecordingDescription.mSampleRate;
    context->capturingSampleRateConversion = requiresSampleRateConversion;

    if (requiresFormatConversion || requiresSampleRateConversion) {
        OSStatus status = AudioConverterNew(processingFormat, &preferredRecordingDescription, &context->captureFormatConverter);
        if (status != 0) {
            NSLog(@"Failed to create AudioConverter: %d", (int)status);
            return;
        }
        UInt32 primingMethod = kConverterPrimeMethod_Normal;
        status = AudioConverterSetProperty(context->captureFormatConverter, kAudioConverterPrimeMethod,
                                           sizeof(UInt32), &primingMethod);
    }

    context->audioTapPrepared = YES;
    [context->audioDevice audioTapDidPrepare];
}

void AVPlayerProcessingTapUnprepare(MTAudioProcessingTapRef tap) {
    NSLog(@"Unpreparing audio tap.");

    // Prevent any more frames from being consumed. Note that this might end audio playback early.
    ExampleAVPlayerAudioTapContext *context = (ExampleAVPlayerAudioTapContext *)MTAudioProcessingTapGetStorage(tap);
    TPCircularBuffer *capturingBuffer = context->capturingBuffer;
    TPCircularBuffer *renderingBuffer = context->renderingBuffer;

    TPCircularBufferClear(capturingBuffer);
    TPCircularBufferClear(renderingBuffer);
    if (context->sourceCache) {
        AudioBufferListFree(context->sourceCache);
        context->sourceCache = NULL;
        context->sourceCacheFrames = 0;
    }

    if (context->renderFormatConverter != NULL) {
        AudioConverterDispose(context->renderFormatConverter);
        context->renderFormatConverter = NULL;
    }

    if (context->captureFormatConverter != NULL) {
        AudioConverterDispose(context->captureFormatConverter);
        context->captureFormatConverter = NULL;
        context->captureFormatConvertIsPrimed = NO;
    }
}

void AVPlayerProcessingTapProcess(MTAudioProcessingTapRef tap,
                                  CMItemCount numberFrames,
                                  MTAudioProcessingTapFlags flags,
                                  AudioBufferList *bufferListInOut,
                                  CMItemCount *numberFramesOut,
                                  MTAudioProcessingTapFlags *flagsOut) {
    ExampleAVPlayerAudioTapContext *context = (ExampleAVPlayerAudioTapContext *)MTAudioProcessingTapGetStorage(tap);
    CMTimeRange sourceRange;
    OSStatus status = MTAudioProcessingTapGetSourceAudio(tap,
                                                         numberFrames,
                                                         bufferListInOut,
                                                         flagsOut,
                                                         &sourceRange,
                                                         numberFramesOut);
    if (status != noErr) {
        // TODO: It might be useful to fill zeros here.
        return;
    } else if(CMTIMERANGE_IS_EMPTY(sourceRange) ||
              CMTIMERANGE_IS_INVALID(sourceRange)) {
        return;
    }

    UInt32 framesToCopy = (UInt32)*numberFramesOut;

    // Produce renderer buffers. These are interleaved, signed integer frames in the source's sample rate.
    TPCircularBuffer *renderingBuffer = context->renderingBuffer;
    AVPlayerAudioTapProduceConvertedFrames(renderingBuffer,
                                           context->renderFormatConverter,
                                           bufferListInOut,
                                           framesToCopy,
                                           &sourceRange,
                                           kPreferredNumberOfChannels);

    // Produce capturer buffers. We will perform a sample rate conversion if needed.
    TPCircularBuffer *capturingBuffer = context->capturingBuffer;
    if (context->capturingSampleRateConversion) {
        AVPlayerAudioTapProduceFilledFrames(capturingBuffer,
                                            context->captureFormatConverter,
                                            context->captureFormatConvertIsPrimed,
                                            bufferListInOut, context->sourceCache,
                                            &context->sourceCacheFrames,
                                            framesToCopy,
                                            kPreferredNumberOfChannels);
        context->captureFormatConvertIsPrimed = YES;
    } else {
        AVPlayerAudioTapProduceConvertedFrames(capturingBuffer,
                                               context->captureFormatConverter,
                                               bufferListInOut,
                                               framesToCopy,
                                               &sourceRange,
                                               kPreferredNumberOfChannels);
    }

    // Flush converters on a discontinuity. This is especially important for priming a sample rate converter.
    if (*flagsOut & kMTAudioProcessingTapFlag_EndOfStream) {
        AudioConverterReset(context->renderFormatConverter);
        AudioConverterReset(context->captureFormatConverter);
        context->captureFormatConvertIsPrimed = NO;
    }
}
