//
//  ExampleAudioEngineDevice.m
//  AudioDeviceExample
//
//  Copyright © 2018 Twilio, Inc. All rights reserved.
//

#import "ExampleAudioEngineDevice.h"

// We want to get as close to 10 msec buffers as possible because this is what the media engine prefers.
static double const kPreferredIOBufferDuration = 0.01;
// We will use stereo playback where available. Some audio routes may be restricted to mono only.
static size_t const kPreferredNumberOfChannels = 1;
// An audio sample is a signed 16-bit integer.
static size_t const kAudioSampleSize = 2;
static uint32_t const kPreferredSampleRate = 48000;

typedef struct RendererAudioContext {
    TVIAudioDeviceContext deviceContext;
    size_t maxFramesPerBuffer;
    AudioBufferList *bufferList;
    void *renderBlock; // AVAudioEngineManualRenderingBlock
} RendererAudioContext;

typedef struct CapturerAudioContext {
    TVIAudioDeviceContext deviceContext;
    AudioBufferList *bufferList;
    AudioUnit audioUnit;
} CapturerAudioContext;

// The RemoteIO audio unit uses bus 0 for ouptut, and bus 1 for input.
static int kOutputBus = 0;
static int kInputBus = 1;

// This is the maximum slice size for RemoteIO (as observed in the field). We will double check at initialization time.
static size_t kMaximumFramesPerBuffer = 1156;

@interface ExampleAudioEngineDevice()

@property (nonatomic, assign, getter=isInterrupted) BOOL interrupted;
@property (nonatomic, assign) AudioUnit audioUnit;
@property (nonatomic, assign) AudioBufferList captureBufferList;
@property (nonatomic, assign, getter=isCapturerInitialized) BOOL capturerInitialized;
@property (nonatomic, assign, getter=isRendererInitialized) BOOL rendererInitialized;

@property (nonatomic, strong, nullable) TVIAudioFormat *renderingFormat;
@property (nonatomic, strong, nullable) TVIAudioFormat *capturingFormat;
@property (atomic, assign) RendererAudioContext *renderingContext;
@property (nonatomic, assign) CapturerAudioContext *capturingContext;

@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioPlayerNode *player;
@property (nonatomic, strong) AVAudioUnitReverb *reverb;

@end

@implementation ExampleAudioEngineDevice

#pragma mark - Init & Dealloc

- (id)init {
    if (@available(iOS 11.0, *)) {
        self = [super init];

        if (self) {
            self.renderingContext = malloc(sizeof(RendererAudioContext));
            memset(self.renderingContext, 0, sizeof(RendererAudioContext));
            [self setupAudioEngine];
            self.renderingContext->renderBlock = (__bridge void *)(_engine.manualRenderingBlock);

            self.capturingContext = malloc(sizeof(CapturerAudioContext));
            memset(self.capturingContext, 0, sizeof(CapturerAudioContext));
            self.capturingContext->bufferList = &_captureBufferList;
        }

        return self;
    } else {
        self = nil;
        NSException *exception = [NSException exceptionWithName:@"ExampleAudioEngineDeviceNotSupported"
                                                         reason:@"ExampleAudioEngineDevice requires iOS 11.0 or greater." userInfo:nil];
        [exception raise];
        return self;
    }
}

- (void)dealloc {
    [self unregisterAVAudioSessionObservers];

    [self teardownAudioEngine];

    free(self.renderingContext);
    self.renderingContext = NULL;
}

+ (NSString *)description {
    return @"AVAudioEngine Audio Mixing";
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

#pragma mark - AudioEngine

- (void)setupAudioEngine {
    NSAssert(_engine == nil, @"AVAudioEngine is already configured");

    _engine = [AVAudioEngine new];
    [_engine stop];

    NSError *error = nil;
    const AudioStreamBasicDescription asbd = [[self renderFormat] streamDescription];
    
    AVAudioFormat *format = [[AVAudioFormat alloc] initWithStreamDescription:&asbd];
    if (@available(iOS 11.0, *)) {
        BOOL success = [_engine enableManualRenderingMode:AVAudioEngineManualRenderingModeRealtime
                                                   format:format
                                        maximumFrameCount:(uint32_t)kMaximumFramesPerBuffer
                                                    error:&error];
        if (!success) {
            NSLog(@"Failed to setup manual rendering mode, error = %@", error);
            return;
        }

        [_engine connect:_engine.inputNode to:_engine.mainMixerNode format:format];

        _renderingContext->renderBlock = (__bridge void *)(_engine.manualRenderingBlock);

        RendererAudioContext *context = _renderingContext;
        success = [_engine.inputNode setManualRenderingInputPCMFormat:format
                                                           inputBlock: ^const AudioBufferList * _Nullable(AVAudioFrameCount inNumberOfFrames) {

                                                               AudioBufferList *bufferList = context->bufferList;
                                                               int8_t *audioBuffer = (int8_t *)bufferList->mBuffers[0].mData;
                                                               UInt32 audioBufferSizeInBytes = bufferList->mBuffers[0].mDataByteSize;

                                                               if (context->deviceContext) {
                                                                   /*
                                                                    * Pull decoded the all remote Participant's mixed audio data from the media
                                                                    * engine into the AudioUnit's AudioBufferList.
                                                                    */
                                                                   TVIAudioDeviceReadRenderData(context->deviceContext, audioBuffer, audioBufferSizeInBytes);

                                                               } else {

                                                                   /*
                                                                    * Return silence when we do not have the plaout device context. This is the
                                                                    * case when the remote participant has not published an audio track yet.
                                                                    * Since the audio graph and audio engine has been setup, we can still play
                                                                    * the music file using the AVAudioEngine.
                                                                    */
                                                                   memset(audioBuffer, 0, audioBufferSizeInBytes);
                                                               }

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
}

- (void)teardownAudioEngine {
    [_engine stop];
    _engine = nil;
}

- (void)playMusic {
    if (!_engine) {
        NSLog(@"Cannot play music. AudioEngine has not been created yet.");
        return;
    }

    if (_player.isPlaying) {
        [_player stop];
    }

    NSString *fileName = [NSString stringWithFormat:@"%@/%@", [[NSBundle mainBundle] bundlePath], @"mixLoop.caf"];
    NSURL *url = [NSURL fileURLWithPath:fileName];
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:nil];

    _player = [[AVAudioPlayerNode alloc] init];
    _reverb = [[AVAudioUnitReverb alloc] init];

    [_reverb loadFactoryPreset:AVAudioUnitReverbPresetMediumHall];
    _reverb.wetDryMix = 50;

    [_engine attachNode:_player];
    [_engine attachNode:_reverb];

    [_engine connect:_player to:_reverb format:file.processingFormat];
    [_engine connect:_reverb to:_engine.mainMixerNode format:file.processingFormat];

    [_player scheduleFile:file atTime:nil completionHandler:^{}];
    [_player play];
}

- (void)teardownPlayer {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.player) {
            if (_player.isPlaying) {
                [_player stop];
            }
            [self.engine detachNode:self.player];
            [self.engine detachNode:_reverb];
            self.player = nil;
        }
    });
}

#pragma mark - TVIAudioDeviceRenderer

- (nullable TVIAudioFormat *)renderFormat {
    if (!_renderingFormat) {

        if (!self.isCapturerInitialized) {
            [self setupAVAudioSession];
            _rendererInitialized = YES;
        }

        /*
         * Assume that the AVAudioSession has already been configured and started and that the values
         * for sampleRate and IOBufferDuration are final.
         */
        _renderingFormat = [[self class] activeFormat];
        self.renderingContext->maxFramesPerBuffer = _renderingFormat.framesPerBuffer;
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

        /*
         * In this example, the app always publishes an audio track. So we will start the audio unit from the capturer
         * call backs. We will restart the audio unit if remote participant adds an audio track after the audio graph is
         * established.
         */
        BOOL restartAudioUnit = (self.capturingContext->deviceContext != nil);

        if (restartAudioUnit) {
            [self stopAudioUnit];
            [self teardownAudioUnit];

            self.renderingContext->deviceContext = context;

            if (![self setupAudioUnitWithRenderContext:self.renderingContext
                                      capturingContext:self.capturingContext]) {
                return NO;
            }
            return [self startAudioUnit];
        } else {
            self.renderingContext->deviceContext = context;
        }

        return YES;
    }
}

- (BOOL)stopRendering {
    _rendererInitialized = NO;

    @synchronized(self) {
        // If the capturer is runnning, we will not stop the audio unit.
        if (!self.capturingContext->deviceContext) {
            [self teardownPlayer];
            [self stopAudioUnit];
            [self teardownAudioUnit];
        }

        self.renderingContext->deviceContext = NULL;
    }

    return YES;
}

#pragma mark - TVIAudioDeviceCapturer

- (nullable TVIAudioFormat *)captureFormat {
    if (!_capturingFormat) {

        if (!self.isRendererInitialized) {
            [self setupAVAudioSession];
            _capturerInitialized = YES;
        }

        /*
         * Assume that the AVAudioSession has already been configured and started and that the values
         * for sampleRate and IOBufferDuration are final.
         */
        _capturingFormat = [[self class] activeFormat];
    }

    return _capturingFormat;
}

- (BOOL)initializeCapturer {
    _captureBufferList.mNumberBuffers = 1;
    _captureBufferList.mBuffers[0].mNumberChannels = kPreferredNumberOfChannels;

    return YES;
}

- (BOOL)startCapturing:(nonnull TVIAudioDeviceContext)context {
    @synchronized (self) {

        // Restart the audio unit if the audio graph is alreay setup and if we publish an audio track.

        if (self.renderingContext->deviceContext) {
            if (_audioUnit) {
                /*
                 * You will never hit this code as the app alwyas publishes an audio track. In case if you decide to
                 * to change this behavior, i.e. connect to a Room without an audio track and publish it after the audio
                 * graph is established, stop the audio unit first.
                 */
                [self stopAudioUnit];
                [self teardownAudioUnit];
            }
        }

        self.capturingContext->deviceContext = context;

        if (![self setupAudioUnitWithRenderContext:self.renderingContext
                                  capturingContext:self.capturingContext]) {
            return NO;
        }

        return [self startAudioUnit];
    }
}

- (BOOL)stopCapturing {
    _capturerInitialized = NO;

    @synchronized(self) {
        // If the renderer is runnning, we will not stop the audio unit.
        if (!self.renderingContext->deviceContext) {
            [self teardownPlayer];
            [self stopAudioUnit];
            [self teardownAudioUnit];
        }

        self.capturingContext->deviceContext = NULL;
    }

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

    RendererAudioContext *context = (RendererAudioContext *)refCon;
    context->bufferList = bufferList;

    int8_t *audioBuffer = (int8_t *)bufferList->mBuffers[0].mData;
    UInt32 audioBufferSizeInBytes = bufferList->mBuffers[0].mDataByteSize;

    // Pull decoded, mixed audio data from the media engine into the AudioUnit's AudioBufferList.
    assert(numFrames <= context->maxFramesPerBuffer);
    assert(audioBufferSizeInBytes == (bufferList->mBuffers[0].mNumberChannels * kAudioSampleSize * numFrames));
    OSStatus outputStatus = noErr;

    if (@available(iOS 11.0, *)) {
        AVAudioEngineManualRenderingBlock renderBlock = (__bridge AVAudioEngineManualRenderingBlock)(context->renderBlock);
        const AVAudioEngineManualRenderingStatus status = renderBlock(numFrames, bufferList, &outputStatus);

        /*
         * Render silence if there are temporary mismatches between CoreAudio and our rendering format or AVAudioEngine
         * could not render the audio samples.
         */
        if (numFrames > context->maxFramesPerBuffer ||
            status != AVAudioEngineManualRenderingStatusSuccess) {
            if (numFrames > context->maxFramesPerBuffer) {
                NSLog(@"Can handle a max of %u frames but got %u.", (unsigned int)context->maxFramesPerBuffer, (unsigned int)numFrames);
            }
            *actionFlags |= kAudioUnitRenderAction_OutputIsSilence;
            memset(audioBuffer, 0, audioBufferSizeInBytes);
        }
    }

    return noErr;
}

static OSStatus ExampleCoreAudioDeviceCaptureCallback(void *refCon,
                                                      AudioUnitRenderActionFlags *actionFlags,
                                                      const AudioTimeStamp *timestamp,
                                                      UInt32 busNumber,
                                                      UInt32 numFrames,
                                                      AudioBufferList *bufferList) {

    if (numFrames > kMaximumFramesPerBuffer) {
        NSLog(@"Expected %u frames but got %u.", (unsigned int)kMaximumFramesPerBuffer, (unsigned int)numFrames);
        return noErr;
    }

    CapturerAudioContext *context = (CapturerAudioContext *)refCon;

    if (context->deviceContext == NULL) {
        return noErr;
    }

    AudioBufferList *audioBufferList = context->bufferList;
    audioBufferList->mBuffers[0].mDataByteSize = numFrames * sizeof(UInt16) * kPreferredNumberOfChannels;
    audioBufferList->mBuffers[0].mData = NULL;

    OSStatus status = noErr;
    status = AudioUnitRender(context->audioUnit,
                             actionFlags,
                             timestamp,
                             1,
                             numFrames,
                             audioBufferList);

    int8_t *audioBuffer = (int8_t *)audioBufferList->mBuffers[0].mData;
    UInt32 audioBufferSizeInBytes = audioBufferList->mBuffers[0].mDataByteSize;

    if (context->deviceContext) {
        TVIAudioDeviceWriteCaptureData(context->deviceContext, audioBuffer, audioBufferSizeInBytes);
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

- (BOOL)setupAudioUnitWithRenderContext:(RendererAudioContext *)renderContext
                         capturingContext:(CapturerAudioContext *)capturingContext {
    assert(renderContext);
    assert(capturingContext);

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
    renderCallback.inputProcRefCon = (void *)(renderContext);
    status = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Output, kOutputBus, &renderCallback,
                                  sizeof(renderCallback));
    if (status != 0) {
        NSLog(@"Could not set rendering callback!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    // Setup the capturing callback.
    AURenderCallbackStruct captureCallback;
    captureCallback.inputProc = ExampleCoreAudioDeviceCaptureCallback;
    captureCallback.inputProcRefCon = (void *)(self.capturingContext);
    status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_SetInputCallback,
                                  kAudioUnitScope_Input, kInputBus, &captureCallback,
                                  sizeof(captureCallback));
    if (status != 0) {
        NSLog(@"Could not set rendering callback!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    // Finally, initialize and start the RemoteIO audio unit.
    status = AudioUnitInitialize(_audioUnit);
    if (status != 0) {
        NSLog(@"Could not initialize the audio unit!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    self.capturingContext->audioUnit = _audioUnit;

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
        if (self.renderingContext->deviceContext) {
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
        if (self.renderingContext->deviceContext) {
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
                if (self.renderingContext->deviceContext) {
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
            if (self.renderingContext->deviceContext) {
                TVIAudioDeviceFormatChanged(self.renderingContext->deviceContext);
            }
        }
    }
}

- (void)handleMediaServiceLost:(NSNotification *)notification {
    @synchronized(self) {
        if (self.renderingContext->deviceContext) {
            TVIAudioDeviceExecuteWorkerBlock(self.renderingContext->deviceContext, ^{
                [self stopAudioUnit];
            });
        }
    }
}

- (void)handleMediaServiceRestored:(NSNotification *)notification {
    @synchronized(self) {
        if (self.renderingContext->deviceContext) {
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
