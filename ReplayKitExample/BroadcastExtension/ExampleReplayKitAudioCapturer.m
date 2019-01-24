//
//  ExampleReplayKitAudioCapturer.m
//  ReplayKitExample
//
//  Copyright © 2018 Twilio, Inc. All rights reserved.
//

#import "ExampleReplayKitAudioCapturer.h"

// Our guess at the maximum slice size used by ReplayKit app audio. We have observed up to 22596 in the field.
static size_t kMaximumFramesPerAppAudioBuffer = 45192;
// Our guess at the maximum slice size used by ReplayKit mic audio. We have observed up to 1024 in the field.
static size_t kMaximumFramesPerMicAudioBuffer = 2048;

static ExampleAudioContext *capturingContext;

@interface ExampleReplayKitAudioCapturer()

@property (nonatomic, strong, nullable) TVIAudioFormat *capturingFormat;

/**
 The maximum number of frames that we will capture at a time. This is determined based upon the RPSampleBufferType.
 */
@property (nonatomic, assign, readonly) size_t maxFramesPerBuffer;

@end

@implementation ExampleReplayKitAudioCapturer

#pragma mark - Init & Dealloc

- (instancetype)init {
    return [self initWithSampleType:RPSampleBufferTypeAudioMic];
}

- (instancetype)initWithSampleType:(RPSampleBufferType)type {
    NSAssert(type == RPSampleBufferTypeAudioMic || type == RPSampleBufferTypeAudioApp, @"We only support capturing audio samples.");

    self = [super init];
    if (self) {
        // Unfortunately, we need to spend more memory to capture application audio samples, which have some delay.
        _maxFramesPerBuffer = type == RPSampleBufferTypeAudioMic ? kMaximumFramesPerMicAudioBuffer : kMaximumFramesPerAppAudioBuffer;
    }
    return self;
}

+ (NSString *)description {
    return @"ExampleReplayKitAudioCapturer";
}

#pragma mark - TVIAudioDeviceRenderer

- (nullable TVIAudioFormat *)renderFormat {
    return nil;
}

- (BOOL)initializeRenderer {
    return NO;
}

- (BOOL)startRendering:(nonnull TVIAudioDeviceContext)context {
    return NO;
}

- (BOOL)stopRendering {
    return NO;
}

#pragma mark - TVIAudioDeviceCapturer

- (nullable TVIAudioFormat *)captureFormat {
    if (!_capturingFormat) {
        /*
         * Assume that the AVAudioSession has already been configured and started and that the values
         * for sampleRate and IOBufferDuration are final.
         */
        _capturingFormat = [[self class] activeCapturingFormat:_maxFramesPerBuffer];
    }

    NSLog (@"Capturing Format = %@", _capturingFormat);
    return _capturingFormat;
}

- (BOOL)initializeCapturer {
    return YES;
}

- (BOOL)startCapturing:(nonnull TVIAudioDeviceContext)context {
    @synchronized (self) {
        NSAssert(capturingContext == NULL, @"Should not have any capturing context.");
        capturingContext = malloc(sizeof(ExampleAudioContext));
        capturingContext->deviceContext = context;
        capturingContext->maxFramesPerBuffer = _capturingFormat.framesPerBuffer;

        const NSTimeInterval sessionBufferDuration = [AVAudioSession sharedInstance].IOBufferDuration;
        const double sessionSampleRate = [AVAudioSession sharedInstance].sampleRate;
        const size_t sessionFramesPerBuffer = (size_t)(sessionSampleRate * sessionBufferDuration + .5);
        capturingContext->expectedFramesPerBuffer = sessionFramesPerBuffer;

        capturingContext->deviceContext = context;
    }
    return YES;
}

- (BOOL)stopCapturing {
    @synchronized(self) {
        NSAssert(capturingContext != NULL, @"Should have a capturing context.");
        free(capturingContext);
        capturingContext = NULL;
    }

    return YES;
}

#pragma mark - Public

dispatch_queue_t ExampleCoreAudioDeviceGetCurrentQueue() {
    /*
     * The current dispatch queue is needed in order to synchronize with samples delivered by ReplayKit. Ideally, the
     * ReplayKit APIs would support this use case, but since they do not we use a deprecated API to discover the queue.
     * The dispatch queue is used for both resource teardown, and to schedule retransmissions (when enabled).
     */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"
    return dispatch_get_current_queue();
#pragma clang diagnostic pop
}

OSStatus ExampleCoreAudioDeviceRecordCallback(CMSampleBufferRef sampleBuffer) {
    if (!capturingContext || !capturingContext->deviceContext) {
        return noErr;
    }

    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (blockBuffer == nil) {
        NSLog(@"Empty buffer received");
        return noErr;
    }

    AudioBufferList bufferList;
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer,
                                                            NULL,
                                                            &bufferList,
                                                            sizeof(bufferList),
                                                            NULL,
                                                            NULL,
                                                            kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                                                            &blockBuffer);

    int8_t *audioBuffer = (int8_t *)bufferList.mBuffers[0].mData;
    UInt32 audioBufferSizeInBytes = bufferList.mBuffers[0].mDataByteSize;

    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);

    NSLog(@"%d audio frames.", audioBufferSizeInBytes / asbd->mBytesPerFrame);

    // Perform an endianess conversion, if needed. A TVIAudioDevice should deliver little endian samples.
    if (asbd->mFormatFlags & kAudioFormatFlagIsBigEndian) {
        for (int i=0; i<(audioBufferSizeInBytes-1); i += 2) {
            int8_t temp = audioBuffer[i];
            audioBuffer[i] = audioBuffer[i+1];
            audioBuffer[i+1] = temp;
        }
    }

    TVIAudioDeviceWriteCaptureData(capturingContext->deviceContext, (int8_t *)audioBuffer, audioBufferSizeInBytes);

    CFRelease(blockBuffer);

    return noErr;
}

#pragma mark - Private

+ (nullable TVIAudioFormat *)activeCapturingFormat:(const size_t)framesPerBuffer {
    // We are making some assumptions about the format received from ReplayKit. So far, only 1/44.1 kHz has been encountered.
    const double sessionSampleRate = 44100;
    size_t rendererChannels = 1;

    return [[TVIAudioFormat alloc] initWithChannels:rendererChannels
                                         sampleRate:sessionSampleRate
                                    framesPerBuffer:framesPerBuffer];
}

@end
