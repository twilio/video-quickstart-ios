//
//  ExampleCoreAudioDevice.m
//  AudioDeviceExample
//
//  Copyright © 2018 Twilio, Inc. All rights reserved.
//

#import "ExampleCoreAudioDevice.h"

// We want to get as close to 10 msec buffers as possible because this is what the media engine prefers.
static double kPreferredIOBufferDuration = 0.01;
// We will use stereo playback where available. Some audio routes may be restricted to mono only.
static size_t const kPreferredNumberOfChannels = 2;

#if TARGET_IPHONE_SIMULATOR
static uint32_t kPreferredSampleRate = 48000;
#else
static uint32_t kPreferredSampleRate = 48000;
#endif

typedef struct ExampleCoreAudioContext {
    TVIAudioDeviceContext deviceContext;
    size_t expectedFramesPerBuffer;
    size_t maxFramesPerBuffer;
} ExampleCoreAudioContext;

// The RemoteIO audio unit uses bus 0 for ouptut, and bus 1 for input.
static int kOutputBus = 0;
static int kInputBus = 1;
// This is the maximum slice size for RemoteIO (as observed in the field). We will double check at initialization time.
static size_t kMaximumFramesPerBuffer = 1156;

@interface ExampleCoreAudioDevice()

@property (nonatomic, assign, getter=isInterrupted) BOOL interrupted;
@property (nonatomic, assign) AudioUnit audioUnit;

@property (nonatomic, strong, nullable) TVIAudioFormat *renderingFormat;
@property (atomic, assign) ExampleCoreAudioContext *renderingContext;

@end

@implementation ExampleCoreAudioDevice

#pragma mark - Init & Dealloc

- (id)init {
    self = [super init];
    if (self) {
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

    NSLog(@"This device uses a maximum slice size of %d frames.", framesPerSlice);
    kMaximumFramesPerBuffer = (size_t)framesPerSlice;
    AudioComponentInstanceDispose(audioUnit);
}

#pragma mark - TVIAudioDeviceRenderer

- (nullable TVIAudioFormat *)renderFormat {
    if (!_renderingFormat) {
        // Setup the AVAudioSession early. You could also defer to `startRendering:` and `stopRendering:`.
        [self setupAVAudioSession];

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

        self.renderingContext = malloc(sizeof(ExampleCoreAudioContext));
        self.renderingContext->deviceContext = context;
        self.renderingContext->maxFramesPerBuffer = _renderingFormat.framesPerBuffer;

        const NSTimeInterval sessionBufferDuration = [AVAudioSession sharedInstance].IOBufferDuration;
        const double sessionSampleRate = [AVAudioSession sharedInstance].sampleRate;
        const size_t sessionFramesPerBuffer = (size_t)(sessionSampleRate * sessionBufferDuration + .5);
        self.renderingContext->expectedFramesPerBuffer = sessionFramesPerBuffer;

        NSAssert(self.audioUnit == NULL, @"The audio unit should not be created yet.");
        if (![self setupAudioUnit:self.renderingContext]) {
            free(self.renderingContext);
            self.renderingContext = NULL;
            return NO;
        }
    }
    return [self startAudioUnit];
}

- (BOOL)stopRendering {
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
    /*
     * We don't support capturing and return a nil format to indicate this. The other TVIAudioDeviceCapturer methods
     * are simply stubs.
     */
    return nil;
}

- (BOOL)initializeCapturer {
    return NO;
}

- (BOOL)startCapturing:(nonnull TVIAudioDeviceContext)context {
    return NO;
}

- (BOOL)stopCapturing {
    return NO;
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

    ExampleCoreAudioContext *context = (ExampleCoreAudioContext *)refCon;
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
    assert(audioBufferSizeInBytes == (bufferList->mBuffers[0].mNumberChannels * 2 * numFrames));
    TVIAudioDeviceReadRenderData(context->deviceContext, audioBuffer, audioBufferSizeInBytes);
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

    return [[TVIAudioFormat alloc] initWithChannels:(size_t)rendererChannels
                                         sampleRate:sessionSampleRate
                                    framesPerBuffer:sessionFramesPerBuffer];
}

+ (AudioComponentDescription)audioUnitDescription {
    AudioComponentDescription audioUnitDescription;
    audioUnitDescription.componentType = kAudioUnitType_Output;
    audioUnitDescription.componentSubType = kAudioUnitSubType_RemoteIO;
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

    if (![session setCategory:AVAudioSessionCategoryPlayback error:&error]) {
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

- (BOOL)setupAudioUnit:(ExampleCoreAudioContext *)context {
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
        NSLog(@"Could not enable output bus!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    status = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input, kOutputBus,
                                  &streamDescription, sizeof(streamDescription));
    if (status != 0) {
        NSLog(@"Could not enable output bus!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    // Disable input, we don't want it.
    UInt32 enableInput = 0;
    status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input, kInputBus, &enableInput,
                                  sizeof(enableInput));

    if (status != 0) {
        NSLog(@"Could not disable input bus!");
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

- (void)registerAVAudioSessionObservers {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center addObserver:self selector:@selector(handleAudioInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
    // On iOS 9.x, when an interruption ends and your application is not foregrounded you might not get a notification.
    // TODO: Test this on iOS 9.x to see if its needed.
//    [center addObserver:self selector:@selector(handleApplicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];

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
                if (self.interrupted) {
                    self.interrupted = NO;
                    [self startAudioUnit];
                }
            });
        }
    }
}

- (void)handleRouteChange:(NSNotification *)notification {
    // Check if the sample rate, channels or buffer duration changed. and trigger a format change if it did.
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
    if (self.interrupted) {
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
        TVIAudioDeviceFormatChanged(self.renderingContext->deviceContext);
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
