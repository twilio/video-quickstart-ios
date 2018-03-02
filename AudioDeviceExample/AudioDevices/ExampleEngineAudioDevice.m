//
//  ExampleEngineAudioDevice.m
//  AudioDeviceExample
//
//  Copyright © 2018 Twilio, Inc. All rights reserved.
//

#import "ExampleEngineAudioDevice.h"

// We want to get as close to 10 msec buffers as possible because this is what the media engine prefers.
static double const kPreferredIOBufferDuration = 0.01;
// We will use stereo playback where available. Some audio routes may be restricted to mono only.
static size_t const kPreferredNumberOfChannels = 1;
// An audio sample is a signed 16-bit integer.
static size_t const kAudioSampleSize = 2;
static uint32_t const kPreferredSampleRate = 48000;


typedef struct ExampleEngineAudioContext {
    TVIAudioDeviceContext deviceContext;
    size_t expectedFramesPerBuffer;
    size_t maxFramesPerBuffer;
    __unsafe_unretained AVAudioEngineManualRenderingBlock renderBlock;
    AudioBufferList *renderBufferList;
    AudioBufferList *captureBufferList;
    AudioUnit audioUnit;
} ExampleEngineAudioContext;

// The RemoteIO audio unit uses bus 0 for ouptut, and bus 1 for input.
static int kOutputBus = 0;
static int kInputBus = 1;

// This is the maximum slice size for RemoteIO (as observed in the field). We will double check at initialization time.
static size_t kMaximumFramesPerBuffer = 1156;

@interface ExampleEngineAudioDevice()

@property (nonatomic, assign, getter=isInterrupted) BOOL interrupted;
@property (nonatomic, assign) AudioUnit audioUnit;

@property (nonatomic, strong, nullable) TVIAudioFormat *renderingFormat;
@property (nonatomic, strong, nullable) TVIAudioFormat *capturingFormat;

@property (atomic, assign) ExampleEngineAudioContext *renderingContext;
@property (nonatomic, assign) ExampleEngineAudioContext *captureContext;

@property (atomic, assign, getter=isRendering) BOOL rendering;

// AVAudioEngine
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioFormat *format;
@property (nonatomic, assign) AudioBufferList audioBufferList;

@end

@implementation ExampleEngineAudioDevice

#pragma mark - Init & Dealloc

- (id)init {
    self = [super init];
    if (self) {

        self.capturingFormat = [[TVIAudioFormat alloc] initWithChannels:kPreferredNumberOfChannels
                                                             sampleRate:kPreferredSampleRate
                                                        framesPerBuffer:kMaximumFramesPerBuffer];

        self.renderingFormat = [[TVIAudioFormat alloc] initWithChannels:kPreferredNumberOfChannels
                                                             sampleRate:kPreferredSampleRate
                                                        framesPerBuffer:kMaximumFramesPerBuffer];
    }
    return self;
}

- (void)dealloc {
    [self unregisterAVAudioSessionObservers];
}

/*
 * Determine at runtime the maximum slice size used by RemoteIO. Setting the stream format and sample rate doesn't
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

- (void)setupAudioEngine {
    // TODO: @ptank - do we need this check?
    if (_engine) {
        NSLog(@"AVAudioEngine is already configured");
        return;
    }
    _engine = [AVAudioEngine new];
    const AudioStreamBasicDescription asbd = [self.renderingFormat streamDescription];
    _format = [[AVAudioFormat alloc] initWithStreamDescription:&asbd];
    [_engine stop];
    NSError *error = nil;
    BOOL success = [_engine enableManualRenderingMode:AVAudioEngineManualRenderingModeRealtime
                                               format:_format
                                    maximumFrameCount:1156 // TODO: PTPT
                                                error:&error];
    if (!success) {
        NSLog(@"Failed to setup manual rendering mode, error = %@", error);
        return;
    }

    [_engine connect:_engine.inputNode to:_engine.mainMixerNode format:_format];
    [_engine connect:_engine.mainMixerNode to:_engine.outputNode format:_format];

    _renderingContext->renderBlock = _engine.manualRenderingBlock;

    ExampleEngineAudioContext *context = _renderingContext;

    success = [_engine.inputNode setManualRenderingInputPCMFormat:_format
                                                       inputBlock:^const AudioBufferList * _Nullable(AVAudioFrameCount inNumberOfFrames) {
                                                           AudioBufferList *bufferList = context->renderBufferList;
                                                           int8_t *audioBuffer = (int8_t *)bufferList->mBuffers[0].mData;
                                                           UInt32 audioBufferSizeInBytes = bufferList->mBuffers[0].mDataByteSize;
                                                           TVIAudioDeviceReadRenderData(context->deviceContext, audioBuffer, audioBufferSizeInBytes);
                                                           return bufferList;
                                                       }];
    if (!success) {
        NSLog(@"Failed to set the manual rendering block");
        return;
    }

    success = [_engine startAndReturnError:&error];
    if (!success) {
        NSLog(@"Failed to start AVAudioEngine, error = %@", error);
    }
}

- (void)teardownAudioEngine {
    [_engine stop];
    _engine = nil;
}

- (void)playMusic {
    if (!_engine) {
        NSLog(@"Engine has not been created");
        return;
    }
    AVAudioPlayerNode *player = [[AVAudioPlayerNode alloc] init];

    NSString *fileName = [NSString stringWithFormat:@"%@/%@", [[NSBundle mainBundle] bundlePath], @"mixLoop.caf"];
    NSURL *url = [NSURL fileURLWithPath:fileName];
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:nil];

    [_engine attachNode:player];
    [self.engine connect:player to:_engine.mainMixerNode format:file.processingFormat];

    [player scheduleFile:file atTime:nil completionHandler:^{}];
    [player play];
}

#pragma mark - TVIAudioDeviceRenderer

- (nullable TVIAudioFormat *)renderFormat {

    if (!_renderingFormat) {
        /*
         * Assume that the AVAudioSession has already been configured and started and that the values
         * for sampleRate and IOBufferDuration are final.
         */
        _renderingFormat = [[self class] activeRenderingFormat];
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
    @synchronized(self) {
        NSAssert(self.renderingContext == NULL, @"Should not have any rendering context.");

        // TODO: can we have only one context for render and capture?
        self.renderingContext = malloc(sizeof(ExampleEngineAudioContext));
        memset(self.renderingContext, 0, sizeof(ExampleEngineAudioContext));
        self.renderingContext->deviceContext = context;
        self.renderingContext->maxFramesPerBuffer = _renderingFormat.framesPerBuffer;
        self.renderingContext->renderBlock = _engine.manualRenderingBlock;
        self.renderingContext->captureBufferList = &_audioBufferList;

        const NSTimeInterval sessionBufferDuration = [AVAudioSession sharedInstance].IOBufferDuration;
        const double sessionSampleRate = [AVAudioSession sharedInstance].sampleRate;
        const size_t sessionFramesPerBuffer = (size_t)(sessionSampleRate * sessionBufferDuration + .5);
        self.renderingContext->expectedFramesPerBuffer = sessionFramesPerBuffer;

        [self setupAudioEngine];

        NSAssert(self.audioUnit == NULL, @"The audio unit should not be created yet.");
        if (![self setupAudioUnit:self.renderingContext]) {
            free(self.renderingContext);
            self.renderingContext = NULL;
            return NO;
        }
        self.renderingContext->audioUnit = _audioUnit;
    }
    return [self startAudioUnit];
}

- (BOOL)stopRendering {
    [self teardownAudioEngine];
    [self stopAudioUnit];

    @synchronized(self) {
        [self teardownAudioUnit];

        NSAssert(self.renderingContext != NULL, @"Should have a rendering context.");
        free(self.renderingContext);
        self.renderingContext = NULL;
    }

    return YES;
}

#pragma mark - TVIAudioDeviceCapturer

- (nullable TVIAudioFormat *)captureFormat {
    return self.capturingFormat;
}

- (BOOL)initializeCapturer {
    return YES;
}

- (BOOL)startCapturing:(nonnull TVIAudioDeviceContext)context {

    self.captureContext = malloc(sizeof(ExampleEngineAudioContext));
    memset(self.captureContext, 0, sizeof(ExampleEngineAudioContext));
    self.captureContext->deviceContext = context;
    self.captureContext->maxFramesPerBuffer = _capturingFormat.framesPerBuffer;
    self.captureContext->audioUnit = _audioUnit;

    OSStatus status = noErr;
    // Setup the capturing callback.
    AURenderCallbackStruct captureCallback;
    captureCallback.inputProc = ExampleCoreAudioDeviceCaptureCallback;
    captureCallback.inputProcRefCon = (void *)(self.captureContext);
    status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_SetInputCallback,
                                  kAudioUnitScope_Input, kInputBus, &captureCallback,
                                  sizeof(captureCallback));
    if (status != 0) {
        NSLog(@"Could not set capture callback!");
        return NO;
    }
    return YES;
}

- (BOOL)stopCapturing {
    return YES;
}

#pragma mark - Private (AudioUnit callbacks)

static OSStatus ExampleCoreAudioDevicePlayoutCallback(void *refCon,
                                                      AudioUnitRenderActionFlags *actionFlags,
                                                      const AudioTimeStamp *timestamp,
                                                      UInt32 busNumber,
                                                      UInt32 numFrames,
                                                      AudioBufferList *bufferList) {
    assert(bufferList->mNumberBuffers == 1);
    assert(bufferList->mBuffers[0].mNumberChannels <= 2);
    assert(bufferList->mBuffers[0].mNumberChannels > 0);

    ExampleEngineAudioContext *context = (ExampleEngineAudioContext *)refCon;
    int8_t *audioBuffer = (int8_t *)bufferList->mBuffers[0].mData;
    UInt32 audioBufferSizeInBytes = bufferList->mBuffers[0].mDataByteSize;
    context->renderBufferList = bufferList;

    OSStatus outputStatus = noErr;
    const AVAudioEngineManualRenderingStatus status = context->renderBlock(numFrames, bufferList, &outputStatus);
    switch (status) {
        case AVAudioEngineManualRenderingStatusSuccess:
            //NSLog(@"AVAudioEngineManualRenderingStatusSuccess");
            break;
        case AVAudioEngineManualRenderingStatusInsufficientDataFromInputNode:
            NSLog(@"AVAudioEngineManualRenderingStatusInsufficientDataFromInputNode");
            *actionFlags |= kAudioUnitRenderAction_OutputIsSilence;
            memset(audioBuffer, 0, audioBufferSizeInBytes);
            break;
        default:
            break;
    }

    assert(numFrames <= context->maxFramesPerBuffer);
    assert(audioBufferSizeInBytes == (bufferList->mBuffers[0].mNumberChannels * kAudioSampleSize * numFrames));
    return noErr;
}

static OSStatus ExampleCoreAudioDeviceCaptureCallback(void *refCon,
                                                      AudioUnitRenderActionFlags *actionFlags,
                                                      const AudioTimeStamp *timestamp,
                                                      UInt32 busNumber,
                                                      UInt32 numFrames,
                                                      AudioBufferList *bufferList) {



    if (!bufferList) {
        if (bufferList) {
            free(bufferList->mBuffers[0].mData);
            free(bufferList);
        }

        bufferList = (AudioBufferList*)malloc(sizeof(AudioBufferList) + sizeof(AudioBuffer));
        bufferList->mNumberBuffers = 1;
        bufferList->mBuffers[0].mNumberChannels = kPreferredNumberOfChannels;

        bufferList->mBuffers[0].mDataByteSize = numFrames * sizeof(UInt16) * kPreferredNumberOfChannels;
        bufferList->mBuffers[0].mData = malloc(numFrames * sizeof(UInt16) * kPreferredNumberOfChannels);
    }


    ExampleEngineAudioContext *context = (ExampleEngineAudioContext *)refCon;
    assert(context);

    OSStatus status;
    status = AudioUnitRender(context->audioUnit,
                             actionFlags,
                             timestamp,
                             1,
                             numFrames,
                             bufferList);



    assert(bufferList->mNumberBuffers == 1);
    assert(bufferList->mBuffers[0].mNumberChannels <= 2);
    assert(bufferList->mBuffers[0].mNumberChannels > 0);

    int8_t *audioBuffer = (int8_t *)bufferList->mBuffers[0].mData;
    UInt32 audioBufferSizeInBytes = bufferList->mBuffers[0].mDataByteSize;

    if (numFrames > kMaximumFramesPerBuffer) {
        NSLog(@"Expected %u frames but got %u.", (unsigned int)kMaximumFramesPerBuffer, (unsigned int)numFrames);
        *actionFlags |= kAudioUnitRenderAction_OutputIsSilence;
        memset(audioBuffer, 0, audioBufferSizeInBytes);
        return noErr;
    }

    TVIAudioDeviceWriteCaptureData(context->deviceContext, audioBuffer, audioBufferSizeInBytes);
    return noErr;
}

#pragma mark - Private (AVAudioSession and CoreAudio)

+ (nullable TVIAudioFormat *)activeRenderingFormat {
    /*
     * Use the pre-determined maximum frame size. AudioUnit callbacks are variable, and in most sitations will be close
     * to the `AVAudioSession.preferredIOBufferDuration` that we've requested.
     */
    const size_t sessionFramesPerBuffer = kMaximumFramesPerBuffer;
    const double sessionSampleRate = [AVAudioSession sharedInstance].sampleRate;
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

    if (![session setPreferredOutputNumberOfChannels:kPreferredNumberOfChannels error:&error]) {
        NSLog(@"Error setting number of output channels: %@", error);
    }

    /*
     * We want to be as close as possible to the 10 millisecond buffer size that the media engine needs. If there is
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

    if (session.maximumInputNumberOfChannels > 0) {
        if (![session setPreferredInputNumberOfChannels:TVIAudioChannelsMono error:&error]) {
            NSLog(@"Error setting number of input channels: %@", error);
        }
    }
}

- (BOOL)setupAudioUnit:(ExampleEngineAudioContext *)context {
    // Find and instantiate the RemoteIO audio unit.
    AudioComponentDescription audioUnitDescription = [[self class] audioUnitDescription];
    AudioComponent audioComponent = AudioComponentFindNext(NULL, &audioUnitDescription);

    OSStatus status = AudioComponentInstanceNew(audioComponent, &_audioUnit);
    if (status != 0) {
        NSLog(@"Could not find RemoteIO AudioComponent instance!");
        return NO;
    }

    /*
     * Configure the RemoteIO audio unit. Our rendering format attempts to match what AVAudioSession requires to
     * prevent any additional format conversions after the media engine has mixed our playout audio.
     */
    AudioStreamBasicDescription streamDescription = self.renderingFormat.streamDescription;

    UInt32 enableOutput = 1;
    status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Output, kOutputBus,
                                  &enableOutput, sizeof(enableOutput));
    if (status != 0) {
        NSLog(@"Could not enable out bus!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    status = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output, kInputBus,
                                  &streamDescription, sizeof(streamDescription));
    if (status != 0) {
        NSLog(@"Could not enable output bus!");
        return NO;
    }



    status = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input, kOutputBus,
                                  &streamDescription, sizeof(streamDescription));
    if (status != 0) {
        NSLog(@"Could not enable output bus!");
        return NO;
    }

    // Enable the microphone input
    UInt32 enableInput = 1;
    status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input, kInputBus, &enableInput,
                                  sizeof(enableInput));

    if (status != 0) {
        NSLog(@"Could not enable input bus!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    // Setup the rendering callback.
    AURenderCallbackStruct renderCallback;
    renderCallback.inputProc = ExampleCoreAudioDevicePlayoutCallback;
    renderCallback.inputProcRefCon = (void *)(context);
    status = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Output, kOutputBus, &renderCallback,
                                  sizeof(renderCallback));
    if (status != 0) {
        NSLog(@"Could not set rendering callback!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    /*
     AURenderCallbackStruct captureCallback;
     captureCallback.inputProc = ExampleCoreAudioDeviceCaptureCallback;
     captureCallback.inputProcRefCon = (void *)(context);
     status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_SetInputCallback,
     kAudioUnitScope_Output, kInputBus, &captureCallback,
     sizeof(captureCallback));
     if (status != 0) {
     NSLog(@"Could not set capturing callback!");
     AudioComponentInstanceDispose(_audioUnit);
     _audioUnit = NULL;
     return NO;
     }*/


    // Finally, initialize and start the RemoteIO audio unit.
    status = AudioUnitInitialize(_audioUnit);
    if (status != 0) {
        NSLog(@"Could not initialize the audio unit!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    return YES;
}

- (BOOL)startAudioUnit {
    OSStatus status = AudioOutputUnitStart(_audioUnit);
    if (status != 0) {
        NSLog(@"Could not start the audio unit!");
        return NO;
    }
    return YES;
}

- (BOOL)stopAudioUnit {
    OSStatus status = AudioOutputUnitStop(_audioUnit);
    if (status != 0) {
        NSLog(@"Could not stop the audio unit!");
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
        if (self.renderingContext) {
            TVIAudioDeviceExecuteWorkerBlock(self.renderingContext->deviceContext, ^{
                if (type == AVAudioSessionInterruptionTypeBegan) {
                    NSLog(@"Interruption began.");
                    self.interrupted = YES;
                    [self stopAudioUnit];
                } else {
                    NSLog(@"Interruption ended.");
                    self.interrupted = NO;
                    [self startAudioUnit];
                }
            });
        }
    }
}

- (void)handleApplicationDidBecomeActive:(NSNotification *)notification {
    @synchronized(self) {
        if (self.renderingContext) {
            TVIAudioDeviceExecuteWorkerBlock(self.renderingContext->deviceContext, ^{
                if (self.isInterrupted) {
                    NSLog(@"Synthesizing an interruption ended event for iOS 9.x devices.");
                    self.interrupted = NO;
                    [self startAudioUnit];
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
    TVIAudioFormat *activeFormat = [[self class] activeRenderingFormat];

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
            });
        }
    }
}

- (void)handleMediaServiceRestored:(NSNotification *)notification {
    @synchronized(self) {
        if (self.renderingContext) {
            TVIAudioDeviceExecuteWorkerBlock(self.renderingContext->deviceContext, ^{
                [self startAudioUnit];
            });
        }
    }
}

- (void)unregisterAVAudioSessionObservers {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
