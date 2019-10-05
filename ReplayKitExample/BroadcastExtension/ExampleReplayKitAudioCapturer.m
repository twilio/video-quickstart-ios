//
//  ExampleReplayKitAudioCapturer.m
//  ReplayKitExample
//
//  Copyright © 2018-2019 Twilio, Inc. All rights reserved.
//

#import "ExampleReplayKitAudioCapturer.h"

// Our guess at the maximum slice size used by ReplayKit app audio. We have observed up to 22596 in the field.
static size_t kMaximumFramesPerAppAudioBuffer = 45192;
// Our guess at the maximum slice size used by ReplayKit mic audio. We have observed up to 1024 in the field.
static size_t kMaximumFramesPerMicAudioBuffer = 2048;

@interface ExampleReplayKitAudioCapturer()

@property (nonatomic, strong, nullable) TVIAudioFormat *capturingFormat;

@property (nonatomic, assign, nullable) ExampleAudioContext *capturingContext;

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
        _capturingFormat = [[self class] defaultCapturingFormat:_maxFramesPerBuffer];
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
    return _capturingFormat;
}

- (BOOL)initializeCapturer {
    return YES;
}

- (BOOL)startCapturing:(nonnull TVIAudioDeviceContext)context {
    @synchronized (self) {
        NSAssert(_capturingContext == NULL, @"Should not have any capturing context.");
        _capturingContext = malloc(sizeof(ExampleAudioContext));
        _capturingContext->deviceContext = context;
        _capturingContext->maxFramesPerBuffer = _capturingFormat.framesPerBuffer;
        _capturingContext->deviceContext = context;
        // Represents the expected capture format. If the capturer's guess is incorrect then a restart will occur.
        _capturingContext->streamDescription = _capturingFormat.streamDescription;
    }
    return YES;
}

- (BOOL)stopCapturing {
    @synchronized(self) {
        NSAssert(_capturingContext != NULL, @"Should have a capturing context.");
        free(_capturingContext);
        _capturingContext = NULL;
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

OSStatus ExampleCoreAudioDeviceCapturerCallback(ExampleReplayKitAudioCapturer *capturer,
                                                CMSampleBufferRef sampleBuffer) {
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);
    ExampleAudioContext *context = capturer->_capturingContext;

    if (!context || !context->deviceContext) {
        return noErr;
    }

    // Update the capture format at runtime in case the input changes, or does not match the capturer's initial guess.
    TVIAudioFormat *format = capturer->_capturingFormat;
    if (asbd->mChannelsPerFrame != context->streamDescription.mChannelsPerFrame ||
        asbd->mSampleRate != context->streamDescription.mSampleRate) {
        capturer->_capturingFormat = [[TVIAudioFormat alloc] initWithChannels:asbd->mChannelsPerFrame
                                                                   sampleRate:asbd->mSampleRate
                                                              framesPerBuffer:format.framesPerBuffer];
        context->streamDescription = *asbd;
        TVIAudioDeviceFormatChanged(context->deviceContext);
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

    // Perform an endianess conversion, if needed. A TVIAudioDevice should deliver little endian samples.
    if (asbd->mFormatFlags & kAudioFormatFlagIsBigEndian) {
        for (int i = 0; i < (audioBufferSizeInBytes - 1); i += 2) {
            int8_t temp = audioBuffer[i];
            audioBuffer[i] = audioBuffer[i+1];
            audioBuffer[i+1] = temp;
        }
    }

    TVIAudioDeviceWriteCaptureData(context->deviceContext, (int8_t *)audioBuffer, audioBufferSizeInBytes);

    CFRelease(blockBuffer);

    return noErr;
}

#pragma mark - Private

+ (nullable TVIAudioFormat *)defaultCapturingFormat:(const size_t)framesPerBuffer {
    // It is possible that 44.1 kHz / 1 channel or 44.1 kHz / 2 channel will be enountered at runtime depending on
    // the RPSampleBufferType and iOS version.
    const double sessionSampleRate = 44100;
    size_t rendererChannels = 1;

    return [[TVIAudioFormat alloc] initWithChannels:rendererChannels
                                         sampleRate:sessionSampleRate
                                    framesPerBuffer:framesPerBuffer];
}

@end
