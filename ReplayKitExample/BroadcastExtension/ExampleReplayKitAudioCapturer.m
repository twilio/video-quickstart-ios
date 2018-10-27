//
//  ExampleReplayKitAudioCapturer.m
//  ReplayKitExample
//
//  Copyright © 2018 Twilio, Inc. All rights reserved.
//

#import "ExampleReplayKitAudioCapturer.h"

// Our guess at the maximum slice size used by ReplayKit. We have observed 1024 in the field.
static size_t kMaximumFramesPerBuffer = 2048;

static ExampleAudioContext *capturingContext;

@interface ExampleReplayKitAudioCapturer()

@property (nonatomic, strong, nullable) TVIAudioFormat *capturingFormat;

@end

@implementation ExampleReplayKitAudioCapturer

#pragma mark - Init & Dealloc

- (instancetype)init {
    self = [super init];
    if (self) {
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
        _capturingFormat = [[self class] activeCapturingFormat];
    }

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

    TVIAudioDeviceWriteCaptureData(capturingContext->deviceContext, (int8_t *)audioBuffer, audioBufferSizeInBytes);

    CFRelease(blockBuffer);
    return noErr;
}

#pragma mark - Private

+ (nullable TVIAudioFormat *)activeCapturingFormat {
    // We are making some assumptions about the format received from ReplayKit.
    const size_t sessionFramesPerBuffer = kMaximumFramesPerBuffer;
    const double sessionSampleRate = 44100;
    size_t rendererChannels = 1;

    return [[TVIAudioFormat alloc] initWithChannels:rendererChannels
                                         sampleRate:sessionSampleRate
                                    framesPerBuffer:sessionFramesPerBuffer];
}

@end
