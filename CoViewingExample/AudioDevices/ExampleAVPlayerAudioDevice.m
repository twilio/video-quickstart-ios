//
//  ExampleAVPlayerAudioDevice.m
//  CoViewingExample
//
//  Copyright © 2018 Twilio, Inc. All rights reserved.
//

#import "ExampleAVPlayerAudioDevice.h"

#import "TPCircularBuffer+AudioBufferList.h"

// We want to get as close to 20 msec buffers as possible, to match the behavior of TVIDefaultAudioDevice.
static double const kPreferredIOBufferDuration = 0.02;
// We will use stereo playback where available. Some audio routes may be restricted to mono only.
static size_t const kPreferredNumberOfChannels = 2;
// An audio sample is a signed 16-bit integer.
static size_t const kAudioSampleSize = 2;
static uint32_t const kPreferredSampleRate = 48000;

typedef struct ExampleAVPlayerAudioTapContext {
    TPCircularBuffer *capturingBuffer;
    dispatch_semaphore_t capturingInitSemaphore;

    TPCircularBuffer *renderingBuffer;
    dispatch_semaphore_t renderingInitSemaphore;
} ExampleAVPlayerAudioTapContext;

typedef struct ExampleAVPlayerRendererContext {
    // Used to pull audio from the media engine.
    TVIAudioDeviceContext deviceContext;
    size_t expectedFramesPerBuffer;
    size_t maxFramesPerBuffer;

    // The buffer of AVPlayer content that we will consume.
    TPCircularBuffer *playoutBuffer;
} ExampleAVPlayerRendererContext;

typedef struct ExampleAVPlayerCapturerContext {
    // Used to deliver recorded audio to the media engine.
    TVIAudioDeviceContext deviceContext;
    size_t expectedFramesPerBuffer;
    size_t maxFramesPerBuffer;

    // Core Audio's VoiceProcessingIO audio unit.
    AudioUnit audioUnit;
    AudioConverterRef audioConverter;

    // Buffer used to render audio samples into.
    int16_t *audioBuffer;

    // The buffer of AVPlayer content that we will consume.
    TPCircularBuffer *recordingBuffer;
} ExampleAVPlayerCapturerContext;

// The IO audio units use bus 0 for ouptut, and bus 1 for input.
static int kOutputBus = 0;
static int kInputBus = 1;
// This is the maximum slice size for RemoteIO (as observed in the field). We will double check at initialization time.
static size_t kMaximumFramesPerBuffer = 1156;

@interface ExampleAVPlayerAudioDevice()

@property (nonatomic, assign, getter=isInterrupted) BOOL interrupted;
@property (nonatomic, assign) AudioUnit playbackMixer;
@property (nonatomic, assign) AudioUnit voiceProcessingIO;

@property (nonatomic, assign, nullable) MTAudioProcessingTapRef audioTap;
@property (nonatomic, assign, nullable) ExampleAVPlayerAudioTapContext *audioTapContext;
@property (nonatomic, strong, nullable) dispatch_semaphore_t audioTapCapturingSemaphore;
@property (nonatomic, assign, nullable) TPCircularBuffer *audioTapCapturingBuffer;
@property (nonatomic, strong, nullable) dispatch_semaphore_t audioTapRenderingSemaphore;
@property (nonatomic, assign, nullable) TPCircularBuffer *audioTapRenderingBuffer;

@property (nonatomic, assign) AudioConverterRef captureConverter;
@property (nonatomic, assign) int16_t *captureBuffer;
@property (nonatomic, strong, nullable) TVIAudioFormat *capturingFormat;
@property (nonatomic, assign, nullable) ExampleAVPlayerCapturerContext *capturingContext;
@property (atomic, assign, nullable) ExampleAVPlayerRendererContext *renderingContext;
@property (nonatomic, strong, nullable) TVIAudioFormat *renderingFormat;

@end

#pragma mark - MTAudioProcessingTap

// TODO: Bad robot.
static AudioStreamBasicDescription *audioFormat = NULL;
static AudioConverterRef captureFormatConverter = NULL;
static AudioConverterRef formatConverter = NULL;

void init(MTAudioProcessingTapRef tap, void *clientInfo, void **tapStorageOut) {
    NSLog(@"Init audio tap.");

    // Provide access to our device in the Callbacks.
    *tapStorageOut = clientInfo;
}

void finalize(MTAudioProcessingTapRef tap) {
    NSLog(@"Finalize audio tap.");

    ExampleAVPlayerAudioTapContext *context = (ExampleAVPlayerAudioTapContext *)MTAudioProcessingTapGetStorage(tap);
    TPCircularBuffer *capturingBuffer = context->capturingBuffer;
    TPCircularBuffer *renderingBuffer = context->renderingBuffer;
    dispatch_semaphore_signal(context->capturingInitSemaphore);
    dispatch_semaphore_signal(context->renderingInitSemaphore);
    TPCircularBufferCleanup(capturingBuffer);
    TPCircularBufferCleanup(renderingBuffer);
}

void prepare(MTAudioProcessingTapRef tap,
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
    bufferSize *= 12;

    // TODO: If we are re-allocating then check the size?
    TPCircularBufferInit(capturingBuffer, bufferSize);
    TPCircularBufferInit(renderingBuffer, bufferSize);
    dispatch_semaphore_signal(context->capturingInitSemaphore);
    dispatch_semaphore_signal(context->renderingInitSemaphore);

    audioFormat = malloc(sizeof(AudioStreamBasicDescription));
    memcpy(audioFormat, processingFormat, sizeof(AudioStreamBasicDescription));

    TVIAudioFormat *playbackFormat = [[TVIAudioFormat alloc] initWithChannels:processingFormat->mChannelsPerFrame
                                                                   sampleRate:processingFormat->mSampleRate
                                                              framesPerBuffer:maxFrames];
    AudioStreamBasicDescription preferredPlaybackDescription = [playbackFormat streamDescription];
    BOOL requiresFormatConversion = preferredPlaybackDescription.mFormatFlags != processingFormat->mFormatFlags;

    if (requiresFormatConversion) {
        OSStatus status = AudioConverterNew(processingFormat, &preferredPlaybackDescription, &formatConverter);
        if (status != 0) {
            NSLog(@"Failed to create AudioConverter: %d", (int)status);
            return;
        }
    }

    TVIAudioFormat *recordingFormat = [[TVIAudioFormat alloc] initWithChannels:1
                                                                    sampleRate:processingFormat->mSampleRate
                                                               framesPerBuffer:maxFrames];
    AudioStreamBasicDescription preferredRecordingDescription = [recordingFormat streamDescription];

    if (requiresFormatConversion) {
        OSStatus status = AudioConverterNew(processingFormat, &preferredRecordingDescription, &captureFormatConverter);
        if (status != 0) {
            NSLog(@"Failed to create AudioConverter: %d", (int)status);
            return;
        }
    }
}

void unprepare(MTAudioProcessingTapRef tap) {
    NSLog(@"Unpreparing audio tap.");

    // Prevent any more frames from being consumed. Note that this might end audio playback early.
    ExampleAVPlayerAudioTapContext *context = (ExampleAVPlayerAudioTapContext *)MTAudioProcessingTapGetStorage(tap);
    TPCircularBuffer *capturingBuffer = context->capturingBuffer;
    TPCircularBuffer *renderingBuffer = context->renderingBuffer;

    TPCircularBufferClear(capturingBuffer);
    TPCircularBufferClear(renderingBuffer);
    free(audioFormat);
    audioFormat = NULL;

    if (formatConverter != NULL) {
        AudioConverterDispose(formatConverter);
        formatConverter = NULL;
    }

    if (captureFormatConverter != NULL) {
        AudioConverterDispose(captureFormatConverter);
        captureFormatConverter = NULL;
    }
}

void process(MTAudioProcessingTapRef tap,
             CMItemCount numberFrames,
             MTAudioProcessingTapFlags flags,
             AudioBufferList *bufferListInOut,
             CMItemCount *numberFramesOut,
             MTAudioProcessingTapFlags *flagsOut) {
    ExampleAVPlayerAudioTapContext *context = (ExampleAVPlayerAudioTapContext *)MTAudioProcessingTapGetStorage(tap);
    TPCircularBuffer *capturingBuffer = context->capturingBuffer;
    TPCircularBuffer *renderingBuffer = context->renderingBuffer;
    CMTimeRange sourceRange;
    OSStatus status = MTAudioProcessingTapGetSourceAudio(tap,
                                                         numberFrames,
                                                         bufferListInOut,
                                                         flagsOut,
                                                         &sourceRange,
                                                         numberFramesOut);

    if (status != kCVReturnSuccess) {
        // TODO
        return;
    }

    UInt32 framesToCopy = (UInt32)*numberFramesOut;

    // TODO: Assumptions about our producer's format.
    // Produce renderer buffers.
    UInt32 bytesToCopy = framesToCopy * 4;
    AudioBufferList *rendererProducerBufferList = TPCircularBufferPrepareEmptyAudioBufferList(renderingBuffer, 1, bytesToCopy, NULL);
    if (rendererProducerBufferList != NULL) {
        status = AudioConverterConvertComplexBuffer(formatConverter,
                                                    framesToCopy, bufferListInOut, rendererProducerBufferList);
        if (status != kCVReturnSuccess) {
            // TODO: Do we still produce the buffer list?
            return;
        }

        TPCircularBufferProduceAudioBufferList(renderingBuffer, NULL);
    }

    // Produce capturer buffers.
    bytesToCopy = framesToCopy * 2;
    AudioBufferList *capturerProducerBufferList = TPCircularBufferPrepareEmptyAudioBufferList(capturingBuffer, 1, bytesToCopy, NULL);
    if (capturerProducerBufferList != NULL) {
        status = AudioConverterConvertComplexBuffer(captureFormatConverter,
                                                    framesToCopy, bufferListInOut, capturerProducerBufferList);
        if (status != kCVReturnSuccess) {
            // TODO: Do we still produce the buffer list?
            return;
        }

        TPCircularBufferProduceAudioBufferList(capturingBuffer, NULL);
    }

    // Flush converter buffers on discontinuity.
    if (*flagsOut & kMTAudioProcessingTapFlag_EndOfStream) {
        AudioConverterReset(formatConverter);
        AudioConverterReset(captureFormatConverter);
    }
}

@implementation ExampleAVPlayerAudioDevice

@synthesize audioTapCapturingBuffer = _audioTapCapturingBuffer;

#pragma mark - Init & Dealloc

- (id)init {
    self = [super init];
    if (self) {
        _audioTapCapturingBuffer = calloc(1, sizeof(TPCircularBuffer));
        _audioTapRenderingBuffer = calloc(1, sizeof(TPCircularBuffer));
        _audioTapCapturingSemaphore = dispatch_semaphore_create(0);
        _audioTapRenderingSemaphore = dispatch_semaphore_create(0);
    }
    return self;
}

- (void)dealloc {
    [self unregisterAVAudioSessionObservers];

    free(_audioTapCapturingBuffer);
    free(_audioTapRenderingBuffer);
    free(_audioTapContext);
}

+ (NSString *)description {
    return @"ExampleAVPlayerAudioDevice";
}

/*
 * Determine at runtime the maximum slice size used by our audio unit. Setting the stream format and sample rate doesn't
 * appear to impact the maximum size so we prefer to read this value once at initialization time.
 */
+ (void)initialize {
    AudioComponentDescription audioUnitDescription = [self audioUnitDescription];
    AudioComponent audioComponent = AudioComponentFindNext(NULL, &audioUnitDescription);
    AudioUnit audioUnit;
    OSStatus status = AudioComponentInstanceNew(audioComponent, &audioUnit);
    if (status != 0) {
        NSLog(@"Could not find RemoteIO AudioComponent instance!");
        return;
    }

    UInt32 framesPerSlice = 0;
    UInt32 propertySize = sizeof(framesPerSlice);
    status = AudioUnitGetProperty(audioUnit, kAudioUnitProperty_MaximumFramesPerSlice,
                                  kAudioUnitScope_Global, kOutputBus,
                                  &framesPerSlice, &propertySize);
    if (status != 0) {
        NSLog(@"Could not read RemoteIO AudioComponent instance!");
        AudioComponentInstanceDispose(audioUnit);
        return;
    }

    NSLog(@"This device uses a maximum slice size of %d frames.", (unsigned int)framesPerSlice);
    kMaximumFramesPerBuffer = (size_t)framesPerSlice;
    AudioComponentInstanceDispose(audioUnit);
}

#pragma mark - Public

- (MTAudioProcessingTapRef)createProcessingTap {
    if (_audioTap) {
        return _audioTap;
    }

    if (!_audioTapContext) {
        _audioTapContext = malloc(sizeof(ExampleAVPlayerAudioTapContext));
        _audioTapContext->capturingBuffer = _audioTapCapturingBuffer;
        _audioTapContext->capturingInitSemaphore = _audioTapCapturingSemaphore;
        _audioTapContext->renderingBuffer = _audioTapRenderingBuffer;
        _audioTapContext->renderingInitSemaphore = _audioTapRenderingSemaphore;
    }

    MTAudioProcessingTapRef processingTap;
    MTAudioProcessingTapCallbacks callbacks;
    callbacks.version = kMTAudioProcessingTapCallbacksVersion_0;
    callbacks.init = init;
    callbacks.prepare = prepare;
    callbacks.process = process;
    callbacks.unprepare = unprepare;
    callbacks.finalize = finalize;
    callbacks.clientInfo = (void *)(_audioTapContext);

    OSStatus status = MTAudioProcessingTapCreate(kCFAllocatorDefault,
                                                 &callbacks,
                                                 kMTAudioProcessingTapCreationFlag_PostEffects,
                                                 &processingTap);
    if (status == kCVReturnSuccess) {
        _audioTap = processingTap;
        return processingTap;
    } else {
        free(_audioTapContext);
        _audioTapContext = NULL;
        return NULL;
    }
}

#pragma mark - TVIAudioDeviceRenderer

- (nullable TVIAudioFormat *)renderFormat {
    if (!_renderingFormat) {
        // Setup the AVAudioSession early. You could also defer to `startRendering:` and `stopRendering:`.
        [self setupAVAudioSession];

        _renderingFormat = [[self class] activeFormat];
    }

    return _renderingFormat;
}

- (BOOL)initializeRenderer {
    /*
     * In this example we don't need any fixed size buffers or other pre-allocated resources. We will simply write
     * directly to the AudioBufferList provided in the AudioUnit's rendering callback.
     */
    return YES;
}

- (BOOL)startRendering:(nonnull TVIAudioDeviceContext)context {
    NSLog(@"%s %@", __PRETTY_FUNCTION__, self.renderingFormat);

    @synchronized(self) {
        NSAssert(self.renderingContext == NULL, @"Should not have any rendering context.");

        // Restart the already setup graph.
        if (_voiceProcessingIO) {
            [self stopAudioUnit];
            [self teardownAudioUnit];
        }

        self.renderingContext = malloc(sizeof(ExampleAVPlayerRendererContext));
        self.renderingContext->deviceContext = context;
        self.renderingContext->maxFramesPerBuffer = _renderingFormat.framesPerBuffer;

        // Ensure that we wait for the audio tap buffer to become ready.
        if (_audioTapCapturingBuffer) {
            self.renderingContext->playoutBuffer = _audioTapRenderingBuffer;
            dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 100 * 1000 * 1000);
            dispatch_semaphore_wait(_audioTapRenderingSemaphore, timeout);
        } else {
            self.renderingContext->playoutBuffer = NULL;
        }

        const NSTimeInterval sessionBufferDuration = [AVAudioSession sharedInstance].IOBufferDuration;
        const double sessionSampleRate = [AVAudioSession sharedInstance].sampleRate;
        const size_t sessionFramesPerBuffer = (size_t)(sessionSampleRate * sessionBufferDuration + .5);
        self.renderingContext->expectedFramesPerBuffer = sessionFramesPerBuffer;

        if (![self setupAudioUnitRendererContext:self.renderingContext
                                 capturerContext:self.capturingContext]) {
            free(self.renderingContext);
            self.renderingContext = NULL;
            return NO;
        } else if (self.capturingContext) {
            self.capturingContext->audioUnit = _voiceProcessingIO;
            self.capturingContext->audioConverter = _captureConverter;
        }
    }

    BOOL success = [self startAudioUnit];
    if (success) {
        TVIAudioSessionActivated(context);
    }
    return success;
}

- (BOOL)stopRendering {
    NSLog(@"%s", __PRETTY_FUNCTION__);

    @synchronized(self) {
        NSAssert(self.renderingContext != NULL, @"We should have a rendering context when stopping.");

        if (!self.capturingContext) {
            [self stopAudioUnit];
            TVIAudioSessionDeactivated(self.renderingContext->deviceContext);
            [self teardownAudioUnit];

            free(self.renderingContext);
            self.renderingContext = NULL;
        }
    }

    return YES;
}

#pragma mark - TVIAudioDeviceCapturer

- (nullable TVIAudioFormat *)captureFormat {
    if (!_capturingFormat) {

        /*
         * Assume that the AVAudioSession has already been configured and started and that the values
         * for sampleRate and IOBufferDuration are final.
         */
        _capturingFormat = [[self class] activeFormat];
    }

    return _capturingFormat;
}

- (BOOL)initializeCapturer {
    if (_captureBuffer == NULL) {
        size_t byteSize = kMaximumFramesPerBuffer * 4 * 2;
        byteSize += 16;
        _captureBuffer = malloc(byteSize);
    }

    return YES;
}

- (BOOL)startCapturing:(nonnull TVIAudioDeviceContext)context {
    NSLog(@"%s %@", __PRETTY_FUNCTION__, self.capturingFormat);

    @synchronized(self) {
        NSAssert(self.capturingContext == NULL, @"We should not have a capturing context when starting.");

        // Restart the already setup graph.
        if (_voiceProcessingIO) {
            [self stopAudioUnit];
            [self teardownAudioUnit];
        }

        self.capturingContext = malloc(sizeof(ExampleAVPlayerCapturerContext));
        memset(self.capturingContext, 0, sizeof(ExampleAVPlayerCapturerContext));
        self.capturingContext->deviceContext = context;
        self.capturingContext->maxFramesPerBuffer = _capturingFormat.framesPerBuffer;
        self.capturingContext->audioBuffer = _captureBuffer;

        // Ensure that we wait for the audio tap buffer to become ready.
        if (_audioTapCapturingBuffer) {
            self.capturingContext->recordingBuffer = _audioTapCapturingBuffer;
            dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 100 * 1000 * 1000);
            dispatch_semaphore_wait(_audioTapCapturingSemaphore, timeout);
        } else {
            self.capturingContext->recordingBuffer = NULL;
        }

        const NSTimeInterval sessionBufferDuration = [AVAudioSession sharedInstance].IOBufferDuration;
        const double sessionSampleRate = [AVAudioSession sharedInstance].sampleRate;
        const size_t sessionFramesPerBuffer = (size_t)(sessionSampleRate * sessionBufferDuration + .5);
        self.capturingContext->expectedFramesPerBuffer = sessionFramesPerBuffer;

        if (![self setupAudioUnitRendererContext:self.renderingContext
                                 capturerContext:self.capturingContext]) {
            free(self.capturingContext);
            self.capturingContext = NULL;
            return NO;
        } else {
            self.capturingContext->audioUnit = _voiceProcessingIO;
            self.capturingContext->audioConverter = _captureConverter;
        }
    }
    BOOL success = [self startAudioUnit];
    if (success) {
        TVIAudioSessionActivated(context);
    }
    return success;
}

- (BOOL)stopCapturing {
    NSLog(@"%s", __PRETTY_FUNCTION__);

    @synchronized (self) {
        NSAssert(self.capturingContext != NULL, @"We should have a capturing context when stopping.");

        if (!self.renderingContext) {
            [self stopAudioUnit];
            TVIAudioSessionDeactivated(self.capturingContext->deviceContext);
            [self teardownAudioUnit];

            free(self.capturingContext);
            self.capturingContext = NULL;

            free(self.captureBuffer);
            self.captureBuffer = NULL;
        }
    }
    return YES;
}

#pragma mark - Private (AudioUnit callbacks)

static void ExampleAVPlayerAudioDeviceDequeueFrames(TPCircularBuffer *buffer,
                                                    UInt32 numFrames,
                                                    AudioBufferList *bufferList) {
    int8_t *audioBuffer = (int8_t *)bufferList->mBuffers[0].mData;

    // TODO: Include this format in the context? What if the formats are somehow not matched?
    AudioStreamBasicDescription format;
    format.mBitsPerChannel = 16;
    format.mChannelsPerFrame = bufferList->mBuffers[0].mNumberChannels;
    format.mBytesPerFrame = format.mChannelsPerFrame * format.mBitsPerChannel / 8;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger;
    format.mSampleRate = 44100;

    UInt32 framesInOut = numFrames;
    if (buffer->buffer != NULL) {
        TPCircularBufferDequeueBufferListFrames(buffer, &framesInOut, bufferList, NULL, &format);
    } else {
        framesInOut = 0;
    }

    if (framesInOut != numFrames) {
        // Render silence for the remaining frames.
        UInt32 framesRemaining = numFrames - framesInOut;
        UInt32 bytesRemaining = framesRemaining * format.mBytesPerFrame;
        audioBuffer += format.mBytesPerFrame * framesInOut;

        memset(audioBuffer, 0, bytesRemaining);
    }
}

static OSStatus ExampleAVPlayerAudioDeviceAudioTapPlaybackCallback(void *refCon,
                                                                   AudioUnitRenderActionFlags *actionFlags,
                                                                   const AudioTimeStamp *timestamp,
                                                                   UInt32 busNumber,
                                                                   UInt32 numFrames,
                                                                   AudioBufferList *bufferList) {
    assert(bufferList->mNumberBuffers == 1);
    assert(bufferList->mBuffers[0].mNumberChannels <= 2);
    assert(bufferList->mBuffers[0].mNumberChannels > 0);

    ExampleAVPlayerRendererContext *context = (ExampleAVPlayerRendererContext *)refCon;
    UInt32 audioBufferSizeInBytes = bufferList->mBuffers[0].mDataByteSize;

    // Render silence if there are temporary mismatches between CoreAudio and our rendering format.
    if (numFrames > context->maxFramesPerBuffer) {
        NSLog(@"Can handle a max of %u frames but got %u.", (unsigned int)context->maxFramesPerBuffer, (unsigned int)numFrames);
        *actionFlags |= kAudioUnitRenderAction_OutputIsSilence;
        int8_t *audioBuffer = (int8_t *)bufferList->mBuffers[0].mData;
        memset(audioBuffer, 0, audioBufferSizeInBytes);
        return noErr;
    }

    TPCircularBuffer *buffer = context->playoutBuffer;
    ExampleAVPlayerAudioDeviceDequeueFrames(buffer, numFrames, bufferList);

    return noErr;
}

static OSStatus ExampleAVPlayerAudioDeviceAudioRendererPlaybackCallback(void *refCon,
                                                                        AudioUnitRenderActionFlags *actionFlags,
                                                                        const AudioTimeStamp *timestamp,
                                                                        UInt32 busNumber,
                                                                        UInt32 numFrames,
                                                                        AudioBufferList *bufferList) {
    assert(bufferList->mNumberBuffers == 1);
    assert(bufferList->mBuffers[0].mNumberChannels <= 2);
    assert(bufferList->mBuffers[0].mNumberChannels > 0);

    ExampleAVPlayerCapturerContext *context = (ExampleAVPlayerCapturerContext *)refCon;
    int8_t *audioBuffer = (int8_t *)bufferList->mBuffers[0].mData;
    UInt32 audioBufferSizeInBytes = bufferList->mBuffers[0].mDataByteSize;

    // Render silence if there are temporary mismatches between CoreAudio and our rendering format.
    if (numFrames > context->maxFramesPerBuffer) {
        NSLog(@"Can handle a max of %u frames but got %u.", (unsigned int)context->maxFramesPerBuffer, (unsigned int)numFrames);
        *actionFlags |= kAudioUnitRenderAction_OutputIsSilence;
        memset(audioBuffer, 0, audioBufferSizeInBytes);
        return noErr;
    }

    // Pull decoded, mixed audio data from the media engine into the AudioUnit's AudioBufferList.
    assert(numFrames <= context->maxFramesPerBuffer);
    assert(audioBufferSizeInBytes == (bufferList->mBuffers[0].mNumberChannels * kAudioSampleSize * numFrames));
    TVIAudioDeviceReadRenderData(context->deviceContext, audioBuffer, audioBufferSizeInBytes);

    return noErr;
}

static OSStatus ExampleAVPlayerAudioDeviceRecordingInputCallback(void *refCon,
                                                                 AudioUnitRenderActionFlags *actionFlags,
                                                                 const AudioTimeStamp *timestamp,
                                                                 UInt32 busNumber,
                                                                 UInt32 numFrames,
                                                                 AudioBufferList *bufferList) {
    ExampleAVPlayerCapturerContext *context = (ExampleAVPlayerCapturerContext *)refCon;
    if (context->deviceContext == NULL) {
        return noErr;
    }

    if (numFrames > context->maxFramesPerBuffer) {
        NSLog(@"Expected %u frames but got %u.", (unsigned int)context->maxFramesPerBuffer, (unsigned int)numFrames);
        return noErr;
    }


    // Render input into the IO Unit's internal buffer.
    AudioBufferList microphoneBufferList;
    microphoneBufferList.mNumberBuffers = 1;

    AudioBuffer *microphoneAudioBuffer = &microphoneBufferList.mBuffers[0];
    microphoneAudioBuffer->mNumberChannels = 1;
    microphoneAudioBuffer->mDataByteSize = (UInt32)numFrames * 2;
    microphoneAudioBuffer->mData = NULL;

    OSStatus status = AudioUnitRender(context->audioUnit,
                                      actionFlags,
                                      timestamp,
                                      busNumber,
                                      numFrames,
                                      &microphoneBufferList);
    if (status != noErr) {
        return status;
    }

    // Dequeue the AVPlayer audio.
    AudioBufferList playerBufferList;
    playerBufferList.mNumberBuffers = 1;
    AudioBuffer *playerAudioBuffer = &playerBufferList.mBuffers[0];
    playerAudioBuffer->mNumberChannels = 1;
    playerAudioBuffer->mDataByteSize = (UInt32)numFrames * 2;
    playerAudioBuffer->mData = context->audioBuffer;

    ExampleAVPlayerAudioDeviceDequeueFrames(context->recordingBuffer, numFrames, &playerBufferList);

    // Convert the mono AVPlayer and Microphone sources into a stereo stream.
    AudioConverterRef converter = context->audioConverter;

    // Source buffers.
    AudioBufferList *playerMicrophoneBufferList = (AudioBufferList *)alloca(sizeof(AudioBufferList) + sizeof(AudioBuffer));
    playerMicrophoneBufferList->mNumberBuffers = 2;

    AudioBuffer *playerConvertBuffer = &playerMicrophoneBufferList->mBuffers[0];
    playerConvertBuffer->mNumberChannels = 1;
    playerConvertBuffer->mDataByteSize = (UInt32)numFrames * 2;
    playerConvertBuffer->mData = context->audioBuffer;

    AudioBuffer *microphoneConvertBuffer = &playerMicrophoneBufferList->mBuffers[1];
    microphoneConvertBuffer->mNumberChannels = microphoneAudioBuffer->mNumberChannels;
    microphoneConvertBuffer->mDataByteSize = microphoneAudioBuffer->mDataByteSize;
    microphoneConvertBuffer->mData = microphoneAudioBuffer->mData;

    // Destination buffer list.
    AudioBufferList convertedBufferList;
    convertedBufferList.mNumberBuffers = 1;
    AudioBuffer *convertedAudioBuffer = &convertedBufferList.mBuffers[0];
    convertedAudioBuffer->mNumberChannels = 2;
    convertedAudioBuffer->mDataByteSize = (UInt32)numFrames * 4;
    // Ensure 16-byte alignment.
    UInt32 byteOffset = (UInt32)numFrames * 2;
    byteOffset += 16 - (byteOffset % 16);
    convertedAudioBuffer->mData = context->audioBuffer + byteOffset;
    assert((byteOffset % 16) == 0);

    status = AudioConverterConvertComplexBuffer(converter, numFrames, playerMicrophoneBufferList, &convertedBufferList);
    if (status != noErr) {
        NSLog(@"Convert failed, status: %d", status);
    }
    int8_t *convertedAudioData = (int8_t *)convertedAudioBuffer->mData;

    // Deliver the samples (via copying) to WebRTC.
    if (context->deviceContext && convertedAudioData) {
        TVIAudioDeviceWriteCaptureData(context->deviceContext, convertedAudioData, convertedAudioBuffer->mDataByteSize);
    }

    return status;
}

#pragma mark - Private (AVAudioSession and CoreAudio)

+ (nullable TVIAudioFormat *)activeFormat {
    /*
     * Use the pre-determined maximum frame size. AudioUnit callbacks are variable, and in most sitations will be close
     * to the `AVAudioSession.preferredIOBufferDuration` that we've requested.
     */
    const size_t sessionFramesPerBuffer = kMaximumFramesPerBuffer;
//    const double sessionSampleRate = [AVAudioSession sharedInstance].sampleRate;
    const double sessionSampleRate = 44100.;
    const NSInteger sessionOutputChannels = [AVAudioSession sharedInstance].outputNumberOfChannels;
    size_t rendererChannels = sessionOutputChannels >= TVIAudioChannelsStereo ? TVIAudioChannelsStereo : TVIAudioChannelsMono;

    return [[TVIAudioFormat alloc] initWithChannels:rendererChannels
                                         sampleRate:sessionSampleRate
                                    framesPerBuffer:sessionFramesPerBuffer];
}

+ (AudioComponentDescription)audioUnitDescription {
    AudioComponentDescription audioUnitDescription;
    audioUnitDescription.componentType = kAudioUnitType_Output;
    audioUnitDescription.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    audioUnitDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    audioUnitDescription.componentFlags = 0;
    audioUnitDescription.componentFlagsMask = 0;
    return audioUnitDescription;
}

+ (AudioComponentDescription)mixerAudioCompontentDescription {
    AudioComponentDescription audioUnitDescription;
    audioUnitDescription.componentType = kAudioUnitType_Mixer;
    audioUnitDescription.componentSubType = kAudioUnitSubType_MultiChannelMixer;
    audioUnitDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    audioUnitDescription.componentFlags = 0;
    audioUnitDescription.componentFlagsMask = 0;
    return audioUnitDescription;
}

+ (AudioComponentDescription)genericOutputAudioCompontentDescription {
    AudioComponentDescription audioUnitDescription;
    audioUnitDescription.componentType = kAudioUnitType_Output;
    audioUnitDescription.componentSubType = kAudioUnitSubType_GenericOutput;
    audioUnitDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    audioUnitDescription.componentFlags = 0;
    audioUnitDescription.componentFlagsMask = 0;
    return audioUnitDescription;
}

- (void)setupAVAudioSession {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;

    if (![session setPreferredSampleRate:kPreferredSampleRate error:&error]) {
        NSLog(@"Error setting sample rate: %@", error);
    }

    NSInteger preferredOutputChannels = session.outputNumberOfChannels >= kPreferredNumberOfChannels ? kPreferredNumberOfChannels : session.outputNumberOfChannels;
    if (![session setPreferredOutputNumberOfChannels:preferredOutputChannels error:&error]) {
        NSLog(@"Error setting number of output channels: %@", error);
    }

    /*
     * We want to be as close as possible to the buffer size that the media engine needs. If there is
     * a mismatch then TwilioVideo will ensure that appropriately sized audio buffers are delivered.
     */
    if (![session setPreferredIOBufferDuration:kPreferredIOBufferDuration error:&error]) {
        NSLog(@"Error setting IOBuffer duration: %@", error);
    }

    if (![session setCategory:AVAudioSessionCategoryPlayAndRecord error:&error]) {
        NSLog(@"Error setting session category: %@", error);
    }

    if (![session setMode:AVAudioSessionModeVideoChat error:&error]) {
        NSLog(@"Error setting session category: %@", error);
    }

    [self registerAVAudioSessionObservers];

    if (![session setActive:YES error:&error]) {
        NSLog(@"Error activating AVAudioSession: %@", error);
    }

    // TODO: Set preferred input channels to 1?
}

- (AudioStreamBasicDescription)microphoneInputStreamDescription {
    AudioStreamBasicDescription capturingFormatDescription = self.capturingFormat.streamDescription;
    capturingFormatDescription.mBytesPerFrame = 2;
    capturingFormatDescription.mBytesPerPacket = 2;
    capturingFormatDescription.mChannelsPerFrame = 1;
    return capturingFormatDescription;
}

- (AudioStreamBasicDescription)nonInterleavedStereoStreamDescription {
    AudioStreamBasicDescription capturingFormatDescription = self.capturingFormat.streamDescription;
    capturingFormatDescription.mBytesPerFrame = 2;
    capturingFormatDescription.mBytesPerPacket = 2;
    capturingFormatDescription.mChannelsPerFrame = 2;
    capturingFormatDescription.mFormatFlags |= kAudioFormatFlagIsNonInterleaved;
    return capturingFormatDescription;
}

- (OSStatus)setupAudioCapturer:(ExampleAVPlayerCapturerContext *)capturerContext {
    UInt32 enableInput = capturerContext ? 1 : 0;
    OSStatus status = AudioUnitSetProperty(_voiceProcessingIO, kAudioOutputUnitProperty_EnableIO,
                                           kAudioUnitScope_Input, kInputBus, &enableInput,
                                           sizeof(enableInput));

    if (status != noErr) {
        NSLog(@"Could not enable/disable input bus!");
        AudioComponentInstanceDispose(_voiceProcessingIO);
        _voiceProcessingIO = NULL;
        return status;
    } else if (!enableInput) {
        // Input is not required.
        return noErr;
    }

    // Request mono audio capture regardless of hardware.
    AudioStreamBasicDescription capturingFormatDescription = [self microphoneInputStreamDescription];

    // Our converter will interleave the mono microphone input and player audio in one stereo stream.
    if (_captureConverter == NULL) {
        AudioStreamBasicDescription sourceFormat = [self nonInterleavedStereoStreamDescription];
        AudioStreamBasicDescription destinationFormat = [self.capturingFormat streamDescription];
        OSStatus status = AudioConverterNew(&sourceFormat,
                                            &destinationFormat,
                                            &_captureConverter);
        if (status != noErr) {
            NSLog(@"Could not create capture converter! code: %d", status);
            return status;
        }
    }

    status = AudioUnitSetProperty(_voiceProcessingIO, kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output, kInputBus,
                                  &capturingFormatDescription, sizeof(capturingFormatDescription));
    if (status != noErr) {
        NSLog(@"Could not set stream format on the input bus!");
        AudioComponentInstanceDispose(_voiceProcessingIO);
        _voiceProcessingIO = NULL;
        return status;
    }

    // Setup the I/O input callback.
    AURenderCallbackStruct capturerCallback;
    capturerCallback.inputProc = ExampleAVPlayerAudioDeviceRecordingInputCallback;
    capturerCallback.inputProcRefCon = (void *)(capturerContext);
    status = AudioUnitSetProperty(_voiceProcessingIO, kAudioOutputUnitProperty_SetInputCallback,
                                  kAudioUnitScope_Global, kInputBus, &capturerCallback,
                                  sizeof(capturerCallback));
    if (status != noErr) {
        NSLog(@"Could not set capturing callback!");
        AudioComponentInstanceDispose(_voiceProcessingIO);
        _voiceProcessingIO = NULL;
        return status;
    }

    return status;
}

- (BOOL)setupAudioUnitRendererContext:(ExampleAVPlayerRendererContext *)rendererContext
                      capturerContext:(ExampleAVPlayerCapturerContext *)capturerContext {
    AudioComponentDescription audioUnitDescription = [[self class] audioUnitDescription];
    AudioComponent audioComponent = AudioComponentFindNext(NULL, &audioUnitDescription);

    OSStatus status = AudioComponentInstanceNew(audioComponent, &_voiceProcessingIO);
    if (status != noErr) {
        NSLog(@"Could not find the AudioComponent instance!");
        return NO;
    }

    /*
     * Configure the VoiceProcessingIO audio unit. Our rendering format attempts to match what AVAudioSession requires to
     * prevent any additional format conversions after the media engine has mixed our playout audio.
     */
    UInt32 enableOutput = rendererContext ? 1 : 0;
    status = AudioUnitSetProperty(_voiceProcessingIO, kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Output, kOutputBus,
                                  &enableOutput, sizeof(enableOutput));
    if (status != noErr) {
        NSLog(@"Could not enable/disable output bus!");
        AudioComponentInstanceDispose(_voiceProcessingIO);
        _voiceProcessingIO = NULL;
        return NO;
    }

    if (enableOutput) {
        AudioStreamBasicDescription renderingFormatDescription = self.renderingFormat.streamDescription;

        // Setup playback mixer.
        AudioComponentDescription mixerComponentDescription = [[self class] mixerAudioCompontentDescription];
        AudioComponent mixerComponent = AudioComponentFindNext(NULL, &mixerComponentDescription);

        OSStatus status = AudioComponentInstanceNew(mixerComponent, &_playbackMixer);
        if (status != noErr) {
            NSLog(@"Could not find the mixer AudioComponent instance!");
            return NO;
        }

        // Configure the mixer's output format.
        status = AudioUnitSetProperty(_playbackMixer, kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Output, kOutputBus,
                                      &renderingFormatDescription, sizeof(renderingFormatDescription));
        if (status != noErr) {
            NSLog(@"Could not set stream format on the mixer output bus!");
            AudioComponentInstanceDispose(_voiceProcessingIO);
            _voiceProcessingIO = NULL;
            return NO;
        }

        status = AudioUnitSetProperty(_playbackMixer, kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input, 0,
                                      &renderingFormatDescription, sizeof(renderingFormatDescription));
        if (status != noErr) {
            NSLog(@"Could not set stream format on the mixer input bus 0!");
            AudioComponentInstanceDispose(_voiceProcessingIO);
            _voiceProcessingIO = NULL;
            return NO;
        }

        status = AudioUnitSetProperty(_playbackMixer, kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input, 1,
                                      &renderingFormatDescription, sizeof(renderingFormatDescription));
        if (status != noErr) {
            NSLog(@"Could not set stream format on the mixer input bus 1!");
            AudioComponentInstanceDispose(_voiceProcessingIO);
            _voiceProcessingIO = NULL;
            return NO;
        }

        // Connection: Mixer Output 0 -> VoiceProcessingIO Input Scope, Output Bus
        AudioUnitConnection mixerOutputConnection;
        mixerOutputConnection.sourceAudioUnit = _playbackMixer;
        mixerOutputConnection.sourceOutputNumber = kOutputBus;
        mixerOutputConnection.destInputNumber = kOutputBus;

        status = AudioUnitSetProperty(_voiceProcessingIO, kAudioUnitProperty_MakeConnection,
                                      kAudioUnitScope_Input, kOutputBus,
                                      &mixerOutputConnection, sizeof(mixerOutputConnection));
        if (status != noErr) {
            NSLog(@"Could not connect the mixer output to voice processing input!");
            AudioComponentInstanceDispose(_voiceProcessingIO);
            _voiceProcessingIO = NULL;
            return NO;
        }

        status = AudioUnitSetProperty(_voiceProcessingIO, kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input, kOutputBus,
                                      &renderingFormatDescription, sizeof(renderingFormatDescription));
        if (status != noErr) {
            NSLog(@"Could not set stream format on the output bus!");
            AudioComponentInstanceDispose(_voiceProcessingIO);
            _voiceProcessingIO = NULL;
            return NO;
        }

        // Setup the rendering callbacks.
        UInt32 elementCount = 2;
        status = AudioUnitSetProperty(_playbackMixer, kAudioUnitProperty_ElementCount,
                                      kAudioUnitScope_Input, 0, &elementCount,
                                      sizeof(elementCount));
        if (status != 0) {
            NSLog(@"Could not set input element count!");
            AudioComponentInstanceDispose(_voiceProcessingIO);
            _voiceProcessingIO = NULL;
            return NO;
        }

        AURenderCallbackStruct audioTapRenderCallback;
        audioTapRenderCallback.inputProc = ExampleAVPlayerAudioDeviceAudioTapPlaybackCallback;
        audioTapRenderCallback.inputProcRefCon = (void *)(rendererContext);
        status = AudioUnitSetProperty(_playbackMixer, kAudioUnitProperty_SetRenderCallback,
                                      kAudioUnitScope_Input, 0, &audioTapRenderCallback,
                                      sizeof(audioTapRenderCallback));
        if (status != 0) {
            NSLog(@"Could not set audio tap rendering callback!");
            AudioComponentInstanceDispose(_voiceProcessingIO);
            _voiceProcessingIO = NULL;
            return NO;
        }

        AURenderCallbackStruct audioRendererRenderCallback;
        audioRendererRenderCallback.inputProc = ExampleAVPlayerAudioDeviceAudioRendererPlaybackCallback;
        audioRendererRenderCallback.inputProcRefCon = (void *)(rendererContext);
        status = AudioUnitSetProperty(_playbackMixer, kAudioUnitProperty_SetRenderCallback,
                                      kAudioUnitScope_Input, 1, &audioRendererRenderCallback,
                                      sizeof(audioRendererRenderCallback));
        if (status != 0) {
            NSLog(@"Could not set audio renderer rendering callback!");
            AudioComponentInstanceDispose(_voiceProcessingIO);
            _voiceProcessingIO = NULL;
            return NO;
        }
    }

    [self setupAudioCapturer:self.capturingContext];

    // Finally, initialize the IO audio unit and mixer (if present).
    status = AudioUnitInitialize(_voiceProcessingIO);
    if (status != noErr) {
        NSLog(@"Could not initialize the audio unit!");
        AudioComponentInstanceDispose(_voiceProcessingIO);
        _voiceProcessingIO = NULL;
        return NO;
    }

    if (_playbackMixer) {
        status = AudioUnitInitialize(_playbackMixer);
        if (status != noErr) {
            NSLog(@"Could not initialize the playback mixer audio unit!");
            AudioComponentInstanceDispose(_playbackMixer);
            _playbackMixer = NULL;
            return NO;
        }
    }

    return YES;
}

- (BOOL)startAudioUnit {
    OSStatus status = AudioOutputUnitStart(_voiceProcessingIO);
    if (status != noErr) {
        NSLog(@"Could not start the audio unit. code: %d", status);
        return NO;
    }

    return YES;
}

- (BOOL)stopAudioUnit {
    OSStatus status = AudioOutputUnitStop(_voiceProcessingIO);
    if (status != noErr) {
        NSLog(@"Could not stop the audio unit. code: %d", status);
        return NO;
    }

    return YES;
}

- (void)teardownAudioUnit {
    if (_voiceProcessingIO) {
        AudioUnitUninitialize(_voiceProcessingIO);
        AudioComponentInstanceDispose(_voiceProcessingIO);
        _voiceProcessingIO = NULL;
    }

    if (_playbackMixer) {
        AudioUnitUninitialize(_playbackMixer);
        AudioComponentInstanceDispose(_playbackMixer);
        _playbackMixer = NULL;
    }

    if (_captureConverter == NULL) {
        AudioConverterDispose(_captureConverter);
        _captureConverter = NULL;
    }
}

#pragma mark - NSNotification Observers

- (void)registerAVAudioSessionObservers {
    // An audio device that interacts with AVAudioSession should handle events like interruptions and route changes.
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center addObserver:self selector:@selector(handleAudioInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
    /*
     * Interruption handling is different on iOS 9.x. If your application becomes interrupted while it is in the
     * background then you will not get a corresponding notification when the interruption ends. We workaround this
     * by handling UIApplicationDidBecomeActiveNotification and treating it as an interruption end.
     */
    if (![[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){10, 0, 0}]) {
        [center addObserver:self selector:@selector(handleApplicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    }

    [center addObserver:self selector:@selector(handleRouteChange:) name:AVAudioSessionRouteChangeNotification object:nil];
    [center addObserver:self selector:@selector(handleMediaServiceLost:) name:AVAudioSessionMediaServicesWereLostNotification object:nil];
    [center addObserver:self selector:@selector(handleMediaServiceRestored:) name:AVAudioSessionMediaServicesWereResetNotification object:nil];
}

- (void)handleAudioInterruption:(NSNotification *)notification {
    AVAudioSessionInterruptionType type = [notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];

    @synchronized(self) {
        // If the worker block is executed, then context is guaranteed to be valid.
        TVIAudioDeviceContext context = self.renderingContext ? self.renderingContext->deviceContext : NULL;
        if (context) {
            TVIAudioDeviceExecuteWorkerBlock(context, ^{
                if (type == AVAudioSessionInterruptionTypeBegan) {
                    NSLog(@"Interruption began.");
                    self.interrupted = YES;
                    [self stopAudioUnit];
                    TVIAudioSessionDeactivated(context);
                } else {
                    NSLog(@"Interruption ended.");
                    self.interrupted = NO;
                    if ([self startAudioUnit]) {
                        TVIAudioSessionActivated(context);
                    }
                }
            });
        }
    }
}

- (void)handleApplicationDidBecomeActive:(NSNotification *)notification {
    @synchronized(self) {
        // If the worker block is executed, then context is guaranteed to be valid.
        TVIAudioDeviceContext context = self.renderingContext ? self.renderingContext->deviceContext : NULL;
        if (context) {
            TVIAudioDeviceExecuteWorkerBlock(context, ^{
                if (self.isInterrupted) {
                    NSLog(@"Synthesizing an interruption ended event for iOS 9.x devices.");
                    self.interrupted = NO;
                    if ([self startAudioUnit]) {
                        TVIAudioSessionActivated(context);
                    }
                }
            });
        }
    }
}

- (void)handleRouteChange:(NSNotification *)notification {
    // Check if the sample rate, or channels changed and trigger a format change if it did.
    AVAudioSessionRouteChangeReason reason = [notification.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];

    switch (reason) {
        case AVAudioSessionRouteChangeReasonUnknown:
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            // Each device change might cause the actual sample rate or channel configuration of the session to change.
        case AVAudioSessionRouteChangeReasonCategoryChange:
            // In iOS 9.2+ switching routes from a BT device in control center may cause a category change.
        case AVAudioSessionRouteChangeReasonOverride:
        case AVAudioSessionRouteChangeReasonWakeFromSleep:
        case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
        case AVAudioSessionRouteChangeReasonRouteConfigurationChange:
            // With CallKit, AVAudioSession may change the sample rate during a configuration change.
            // If a valid route change occurs we may want to update our audio graph to reflect the new output device.
            @synchronized(self) {
                // TODO: Contexts
                if (self.renderingContext) {
                    TVIAudioDeviceExecuteWorkerBlock(self.renderingContext->deviceContext, ^{
                        [self handleValidRouteChange];
                    });
                }
            }
            break;
    }
}

- (void)handleValidRouteChange {
    // Nothing to process while we are interrupted. We will interrogate the AVAudioSession once the interruption ends.
    if (self.isInterrupted) {
        return;
    } else if (_voiceProcessingIO == NULL) {
        return;
    }

    NSLog(@"A route change ocurred while the AudioUnit was started. Checking the active audio format.");

    // Determine if the format actually changed. We only care about sample rate and number of channels.
    TVIAudioFormat *activeFormat = [[self class] activeFormat];

    if (![activeFormat isEqual:_renderingFormat]) {
        NSLog(@"The rendering format changed. Restarting with %@", activeFormat);
        // Signal a change by clearing our cached format, and allowing TVIAudioDevice to drive the process.
        _renderingFormat = nil;

        @synchronized(self) {
            if (self.renderingContext) {
                TVIAudioDeviceFormatChanged(self.renderingContext->deviceContext);
            } else if (self.capturingContext) {
                TVIAudioDeviceFormatChanged(self.capturingContext->deviceContext);
            }
        }
    }
}

- (void)handleMediaServiceLost:(NSNotification *)notification {
    @synchronized(self) {
        // TODO: Contexts.
        if (self.renderingContext) {
            TVIAudioDeviceExecuteWorkerBlock(self.renderingContext->deviceContext, ^{
                [self stopAudioUnit];
                TVIAudioSessionDeactivated(self.renderingContext->deviceContext);
            });
        }
    }
}

- (void)handleMediaServiceRestored:(NSNotification *)notification {
    @synchronized(self) {
        // If the worker block is executed, then context is guaranteed to be valid.
        TVIAudioDeviceContext context = self.renderingContext ? self.renderingContext->deviceContext : NULL;
        if (context) {
            TVIAudioDeviceExecuteWorkerBlock(context, ^{
                if ([self startAudioUnit]) {
                    TVIAudioSessionActivated(context);
                }
            });
        }
    }
}

- (void)unregisterAVAudioSessionObservers {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
