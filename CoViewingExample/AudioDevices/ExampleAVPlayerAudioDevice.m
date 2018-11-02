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
    TVIAudioDeviceContext deviceContext;
    size_t expectedFramesPerBuffer;
    size_t maxFramesPerBuffer;

    // The buffer of AVPlayer content that we will consume.
    TPCircularBuffer *playoutBuffer;
} ExampleAVPlayerRendererContext;

typedef struct ExampleAVPlayerCapturerContext {
    TVIAudioDeviceContext deviceContext;
    size_t expectedFramesPerBuffer;
    size_t maxFramesPerBuffer;

    // Core Audio's VoiceProcessingIO audio unit.
    AudioUnit audioUnit;

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
@property (nonatomic, assign) AudioUnit audioUnit;

@property (nonatomic, assign, nullable) ExampleAVPlayerAudioTapContext *audioTapContext;
@property (nonatomic, assign, nullable) TPCircularBuffer *audioTapCapturingBuffer;
@property (nonatomic, assign, nullable) TPCircularBuffer *audioTapRenderingBuffer;

@property (nonatomic, assign) int16_t *captureBuffer;
@property (nonatomic, strong, nullable) TVIAudioFormat *capturingFormat;
@property (nonatomic, assign, nullable) ExampleAVPlayerCapturerContext *capturingContext;
@property (atomic, assign, nullable) ExampleAVPlayerRendererContext *renderingContext;
@property (nonatomic, strong, nullable) TVIAudioFormat *renderingFormat;

@end

#pragma mark - MTAudioProcessingTap

// TODO: Bad robot.
static AudioStreamBasicDescription *audioFormat = NULL;
static AudioConverterRef formatConverter = NULL;

void init(MTAudioProcessingTapRef tap, void *clientInfo, void **tapStorageOut) {
    // Provide access to our device in the Callbacks.
    *tapStorageOut = clientInfo;
}

void finalize(MTAudioProcessingTapRef tap) {
    ExampleAVPlayerAudioTapContext *context = (ExampleAVPlayerAudioTapContext *)MTAudioProcessingTapGetStorage(tap);
    TPCircularBuffer *buffer = context->renderingBuffer;
    TPCircularBufferCleanup(buffer);
}

void prepare(MTAudioProcessingTapRef tap,
             CMItemCount maxFrames,
             const AudioStreamBasicDescription *processingFormat) {
    NSLog(@"Preparing with frames: %d, channels: %d, bits/channel: %d, sample rate: %0.1f",
          (int)maxFrames, processingFormat->mChannelsPerFrame, processingFormat->mBitsPerChannel, processingFormat->mSampleRate);
    assert(processingFormat->mFormatID == kAudioFormatLinearPCM);

    // Defer init of the ring buffer memory until we understand the processing format.
    ExampleAVPlayerAudioTapContext *context = (ExampleAVPlayerAudioTapContext *)MTAudioProcessingTapGetStorage(tap);
    TPCircularBuffer *buffer = context->renderingBuffer;

    size_t bufferSize = processingFormat->mBytesPerFrame * maxFrames;
    // We need to add some overhead for the AudioBufferList data structures.
    bufferSize += 2048;
    // TODO: Size the buffer appropriately, as we may need to accumulate more than maxFrames due to bursty processing.
    bufferSize *= 12;

    // TODO: If we are re-allocating then check the size?
    TPCircularBufferInit(buffer, bufferSize);
    audioFormat = malloc(sizeof(AudioStreamBasicDescription));
    memcpy(audioFormat, processingFormat, sizeof(AudioStreamBasicDescription));

    TVIAudioFormat *preferredFormat = [[TVIAudioFormat alloc] initWithChannels:processingFormat->mChannelsPerFrame
                                                                    sampleRate:processingFormat->mSampleRate
                                                               framesPerBuffer:maxFrames];
    AudioStreamBasicDescription preferredDescription = [preferredFormat streamDescription];
    BOOL requiresFormatConversion = preferredDescription.mFormatFlags != processingFormat->mFormatFlags;

    if (requiresFormatConversion) {
        OSStatus status = AudioConverterNew(processingFormat, &preferredDescription, &formatConverter);
        if (status != 0) {
            NSLog(@"Failed to create AudioConverter: %d", (int)status);
            return;
        }
    }
}

void unprepare(MTAudioProcessingTapRef tap) {
    // Prevent any more frames from being consumed. Note that this might end audio playback early.
    ExampleAVPlayerAudioTapContext *context = (ExampleAVPlayerAudioTapContext *)MTAudioProcessingTapGetStorage(tap);
    TPCircularBuffer *buffer = context->renderingBuffer;

    TPCircularBufferClear(buffer);
    free(audioFormat);
    audioFormat = NULL;

    if (formatConverter != NULL) {
        AudioConverterDispose(formatConverter);
        formatConverter = NULL;
    }
}

void process(MTAudioProcessingTapRef tap,
             CMItemCount numberFrames,
             MTAudioProcessingTapFlags flags,
             AudioBufferList *bufferListInOut,
             CMItemCount *numberFramesOut,
             MTAudioProcessingTapFlags *flagsOut) {
    ExampleAVPlayerAudioTapContext *context = (ExampleAVPlayerAudioTapContext *)MTAudioProcessingTapGetStorage(tap);
    TPCircularBuffer *buffer = context->renderingBuffer;

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
    UInt32 bytesToCopy = framesToCopy * 4;
    AudioBufferList *producerBufferList = TPCircularBufferPrepareEmptyAudioBufferList(buffer, 1, bytesToCopy, NULL);
    if (producerBufferList == NULL) {
        // TODO:
        return;
    }

    status = AudioConverterConvertComplexBuffer(formatConverter, framesToCopy, bufferListInOut, producerBufferList);
    if (status != kCVReturnSuccess) {
        // TODO: Do we still produce the buffer list?
        return;
    }

    TPCircularBufferProduceAudioBufferList(buffer, NULL);

    // TODO: Silence the audio returned to AVPlayer just in case?
//    memset(NULL, 0, numberFramesOut * )
}

@implementation ExampleAVPlayerAudioDevice

@synthesize audioTapCapturingBuffer = _audioTapCapturingBuffer;

#pragma mark - Init & Dealloc

- (id)init {
    self = [super init];
    if (self) {
        _audioTapCapturingBuffer = malloc(sizeof(TPCircularBuffer));
        _audioTapRenderingBuffer = malloc(sizeof(TPCircularBuffer));
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
    NSAssert(_audioTapContext == NULL, @"We should not already have an audio tap context when creating a tap.");
    _audioTapContext = malloc(sizeof(ExampleAVPlayerAudioTapContext));
    _audioTapContext->capturingBuffer = _audioTapCapturingBuffer;
    _audioTapContext->renderingBuffer = _audioTapRenderingBuffer;

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
        if (_audioUnit) {
            [self stopAudioUnit];
            [self teardownAudioUnit];
        }

        self.renderingContext = malloc(sizeof(ExampleAVPlayerRendererContext));
        self.renderingContext->deviceContext = context;
        self.renderingContext->maxFramesPerBuffer = _renderingFormat.framesPerBuffer;

        // TODO: Do we need to synchronize with the tap being started at this point?
        self.renderingContext->playoutBuffer = _audioTapRenderingBuffer;
        [NSThread sleepForTimeInterval:0.2];

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
            self.capturingContext->audioUnit = _audioUnit;
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
        size_t byteSize = kMaximumFramesPerBuffer * kPreferredNumberOfChannels * 2;
        _captureBuffer = malloc(byteSize);
    }

    return YES;
}

- (BOOL)startCapturing:(nonnull TVIAudioDeviceContext)context {
    NSLog(@"%s %@", __PRETTY_FUNCTION__, self.capturingFormat);

    @synchronized(self) {
        NSAssert(self.capturingContext == NULL, @"We should not have a capturing context when starting.");

        // Restart the already setup graph.
        if (_audioUnit) {
            [self stopAudioUnit];
            [self teardownAudioUnit];
        }

        self.capturingContext = malloc(sizeof(ExampleAVPlayerCapturerContext));
        memset(self.capturingContext, 0, sizeof(ExampleAVPlayerCapturerContext));
        self.capturingContext->deviceContext = context;
        self.capturingContext->maxFramesPerBuffer = _capturingFormat.framesPerBuffer;
        self.capturingContext->audioBuffer = _captureBuffer;

        // TODO: Do we need to synchronize with the tap being started at this point?
        self.capturingContext->recordingBuffer = _audioTapCapturingBuffer;
        [NSThread sleepForTimeInterval:0.2];

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
            self.capturingContext->audioUnit = _audioUnit;
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

static OSStatus ExampleAVPlayerAudioDevicePlayoutCallback(void *refCon,
                                                          AudioUnitRenderActionFlags *actionFlags,
                                                          const AudioTimeStamp *timestamp,
                                                          UInt32 busNumber,
                                                          UInt32 numFrames,
                                                          AudioBufferList *bufferList) {
    assert(bufferList->mNumberBuffers == 1);
    assert(bufferList->mBuffers[0].mNumberChannels <= 2);
    assert(bufferList->mBuffers[0].mNumberChannels > 0);

    ExampleAVPlayerRendererContext *context = (ExampleAVPlayerRendererContext *)refCon;
    TPCircularBuffer *buffer = context->playoutBuffer;
    int8_t *audioBuffer = (int8_t *)bufferList->mBuffers[0].mData;
    UInt32 audioBufferSizeInBytes = bufferList->mBuffers[0].mDataByteSize;

    // Render silence if there are temporary mismatches between CoreAudio and our rendering format.
    if (numFrames > context->maxFramesPerBuffer) {
        NSLog(@"Can handle a max of %u frames but got %u.", (unsigned int)context->maxFramesPerBuffer, (unsigned int)numFrames);
        *actionFlags |= kAudioUnitRenderAction_OutputIsSilence;
        memset(audioBuffer, 0, audioBufferSizeInBytes);
        return noErr;
    }

    assert(numFrames <= context->maxFramesPerBuffer);
    assert(audioBufferSizeInBytes == (bufferList->mBuffers[0].mNumberChannels * kAudioSampleSize * numFrames));

    // TODO: Include this format in the context? What if the formats are somehow not matched?
    AudioStreamBasicDescription format;
    format.mBitsPerChannel = 16;
    format.mChannelsPerFrame = bufferList->mBuffers[0].mNumberChannels;
    format.mBytesPerFrame = format.mChannelsPerFrame * format.mBitsPerChannel / 8;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger;
    format.mSampleRate = 44100;

    UInt32 framesInOut = numFrames;
    TPCircularBufferDequeueBufferListFrames(buffer, &framesInOut, bufferList, NULL, &format);

    if (framesInOut != numFrames) {
        // Render silence for the remaining frames.
        UInt32 framesRemaining = numFrames - framesInOut;
        UInt32 bytesRemaining = framesRemaining * format.mBytesPerFrame;
        audioBuffer += bytesRemaining;

        memset(audioBuffer, 0, bytesRemaining);
    }

    // TODO: Pull decoded, mixed audio data from the media engine into the AudioUnit's AudioBufferList.
//    TVIAudioDeviceReadRenderData(context->deviceContext, audioBuffer, audioBufferSizeInBytes);
    return noErr;
}

static OSStatus ExampleAVPlayerAudioDeviceRecordingCallback(void *refCon,
                                                            AudioUnitRenderActionFlags *actionFlags,
                                                            const AudioTimeStamp *timestamp,
                                                            UInt32 busNumber,
                                                            UInt32 numFrames,
                                                            AudioBufferList *bufferList) {

    if (numFrames > kMaximumFramesPerBuffer) {
        NSLog(@"Expected %u frames but got %u.", (unsigned int)kMaximumFramesPerBuffer, (unsigned int)numFrames);
        return noErr;
    }

    ExampleAVPlayerCapturerContext *context = (ExampleAVPlayerCapturerContext *)refCon;

    if (context->deviceContext == NULL) {
        return noErr;
    }

    // Render into our recording buffer.

    AudioBufferList renderingBufferList;
    renderingBufferList.mNumberBuffers = 1;

    AudioBuffer *audioBuffer = &renderingBufferList.mBuffers[0];
    audioBuffer->mNumberChannels = kPreferredNumberOfChannels;
    audioBuffer->mDataByteSize = (UInt32)context->maxFramesPerBuffer * kPreferredNumberOfChannels * 2;
    audioBuffer->mData = context->audioBuffer;

    OSStatus status = AudioUnitRender(context->audioUnit,
                                      actionFlags,
                                      timestamp,
                                      busNumber,
                                      numFrames,
                                      &renderingBufferList);

    if (status != noErr) {
        NSLog(@"Render failed with code: %d", status);
        return status;
    }

    // Copy the recorded samples.
    int8_t *audioData = (int8_t *)audioBuffer->mData;
    UInt32 audioDataByteSize = audioBuffer->mDataByteSize;

    if (context->deviceContext && audioBuffer) {
        TVIAudioDeviceWriteCaptureData(context->deviceContext, audioData, audioDataByteSize);
    }

    return noErr;
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
}

- (BOOL)setupAudioUnitRendererContext:(ExampleAVPlayerRendererContext *)rendererContext
                      capturerContext:(ExampleAVPlayerCapturerContext *)capturerContext {
    AudioComponentDescription audioUnitDescription = [[self class] audioUnitDescription];
    AudioComponent audioComponent = AudioComponentFindNext(NULL, &audioUnitDescription);

    OSStatus status = AudioComponentInstanceNew(audioComponent, &_audioUnit);
    if (status != noErr) {
        NSLog(@"Could not find the AudioComponent instance!");
        return NO;
    }

    /*
     * Configure the VoiceProcessingIO audio unit. Our rendering format attempts to match what AVAudioSession requires to
     * prevent any additional format conversions after the media engine has mixed our playout audio.
     */
    UInt32 enableOutput = rendererContext ? 1 : 0;
    status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Output, kOutputBus,
                                  &enableOutput, sizeof(enableOutput));
    if (status != noErr) {
        NSLog(@"Could not enable/disable output bus!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    if (enableOutput) {
        AudioStreamBasicDescription renderingFormatDescription = self.renderingFormat.streamDescription;

        status = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input, kOutputBus,
                                      &renderingFormatDescription, sizeof(renderingFormatDescription));
        if (status != noErr) {
            NSLog(@"Could not set stream format on the output bus!");
            AudioComponentInstanceDispose(_audioUnit);
            _audioUnit = NULL;
            return NO;
        }

        // Setup the rendering callback.
        AURenderCallbackStruct renderCallback;
        renderCallback.inputProc = ExampleAVPlayerAudioDevicePlayoutCallback;
        renderCallback.inputProcRefCon = (void *)(rendererContext);
        status = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_SetRenderCallback,
                                      kAudioUnitScope_Output, kOutputBus, &renderCallback,
                                      sizeof(renderCallback));
        if (status != 0) {
            NSLog(@"Could not set rendering callback!");
            AudioComponentInstanceDispose(_audioUnit);
            _audioUnit = NULL;
            return NO;
        }
    }

    UInt32 enableInput = capturerContext ? 1 : 0;
    status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input, kInputBus, &enableInput,
                                  sizeof(enableInput));

    if (status != noErr) {
        NSLog(@"Could not enable/disable input bus!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    if (enableInput) {
        AudioStreamBasicDescription capturingFormatDescription = self.capturingFormat.streamDescription;

        status = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Output, kInputBus,
                                      &capturingFormatDescription, sizeof(capturingFormatDescription));
        if (status != noErr) {
            NSLog(@"Could not set stream format on the input bus!");
            AudioComponentInstanceDispose(_audioUnit);
            _audioUnit = NULL;
            return NO;
        }

        // Setup the capturing callback.
        AURenderCallbackStruct capturerCallback;
        capturerCallback.inputProc = ExampleAVPlayerAudioDeviceRecordingCallback;
        capturerCallback.inputProcRefCon = (void *)(capturerContext);
        status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_SetInputCallback,
                                      kAudioUnitScope_Input, kInputBus, &capturerCallback,
                                      sizeof(capturerCallback));
        if (status != noErr) {
            NSLog(@"Could not set capturing callback!");
            AudioComponentInstanceDispose(_audioUnit);
            _audioUnit = NULL;
            return NO;
        }
    }

    // Finally, initialize and start the IO audio unit.
    status = AudioUnitInitialize(_audioUnit);
    if (status != noErr) {
        NSLog(@"Could not initialize the audio unit!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    return YES;
}

- (BOOL)startAudioUnit {
    OSStatus status = AudioOutputUnitStart(_audioUnit);
    if (status != noErr) {
        NSLog(@"Could not start the audio unit. code: %d", status);
        return NO;
    }
    return YES;
}

- (BOOL)stopAudioUnit {
    OSStatus status = AudioOutputUnitStop(_audioUnit);
    if (status != noErr) {
        NSLog(@"Could not stop the audio unit. code: %d", status);
        return NO;
    }
    return YES;
}

- (void)teardownAudioUnit {
    if (_audioUnit) {
        AudioUnitUninitialize(_audioUnit);
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
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
    } else if (_audioUnit == NULL) {
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
            }
        }
    }
}

- (void)handleMediaServiceLost:(NSNotification *)notification {
    @synchronized(self) {
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
