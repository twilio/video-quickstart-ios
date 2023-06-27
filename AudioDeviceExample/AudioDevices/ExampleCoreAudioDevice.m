//
//  ExampleCoreAudioDevice.m
//  AudioDeviceExample
//
//  Copyright © 2018-2019 Twilio, Inc. All rights reserved.
//

#import "ExampleCoreAudioDevice.h"

// We want to get as close to 10 msec buffers as possible because this is what the media engine prefers.
static double const kPreferredIOBufferDurationSec = 0.01;
// We will use stereo playback where available. Some audio routes may be restricted to mono only.
static size_t const kPreferredNumberOfChannels = 2;
// An audio sample is a signed 16-bit integer.
static size_t const kAudioSampleSize = 2;
static uint32_t const kPreferredSampleRate = 48000;

/*
 * Calls to AudioUnitInitialize() can fail if called back-to-back after a format change or adding and removing tracks.
 * A fall-back solution is to allow multiple sequential calls with a small delay between each. This factor sets the max
 * number of allowed initialization attempts.
 */
static const int kMaxNumberOfAudioUnitInitializeAttempts = 5;
/*
 * Calls to AudioOutputUnitStart() can fail if called during CallKit performSetHeldAction (as a workaround for Apple's own bugs when the remote caller ends a call that interrupted our own)
 * Repeated attempts to call this function will allow time for the call to actually be unheld by CallKit thereby allowing us to start our AudioUnit
 */
static const int kMaxNumberOfAudioUnitStartAttempts = 5;

/*
 * Calls to setupAVAudioSession can fail if called during CallKit performSetHeldAction (as a workaround for Apple's own bugs when the remote caller ends a call that interrupted our own)
 * Repeated attempts to call this function will allow time for the call to actually be unheld by CallKit thereby allowing us to activate the AVAudioSession
 */
static const int kMaxNumberOfSetupAVAudioSessionAttempts = 5;

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
        [self setupAVAudioSession];
        [self registerAVAudioSessionObservers];
    }
    return self;
}

- (void)dealloc {
    [self unregisterAVAudioSessionObservers];

    free(self.renderingContext);
    self.renderingContext = NULL;
}

+ (NSString *)description {
    return @"ExampleCoreAudioDevice (stereo playback)";
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

    if (framesPerSlice < kMaximumFramesPerBuffer) {
        framesPerSlice = (UInt32) kMaximumFramesPerBuffer;
        status = AudioUnitSetProperty(audioUnit, kAudioUnitProperty_MaximumFramesPerSlice,
                                      kAudioUnitScope_Global, kOutputBus,
                                      &framesPerSlice, sizeof(framesPerSlice));
    } else {
        kMaximumFramesPerBuffer = (size_t)framesPerSlice;
    }

    NSLog(@"This device uses a maximum slice size of %d frames.", (unsigned int)framesPerSlice);
    AudioComponentInstanceDispose(audioUnit);
}

#pragma mark - TVIAudioDeviceRenderer

- (nullable TVIAudioFormat *)renderFormat {
    if (!_renderingFormat) {
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
        memset(self.renderingContext, 0, sizeof(ExampleCoreAudioContext));
        self.renderingContext->deviceContext = context;
        self.renderingContext->maxFramesPerBuffer = _renderingFormat.framesPerBuffer;

        const NSTimeInterval sessionBufferDuration = [AVAudioSession sharedInstance].IOBufferDuration;
        const double sessionSampleRate = [AVAudioSession sharedInstance].sampleRate;
        const size_t sessionFramesPerBuffer = (size_t)(sessionSampleRate * sessionBufferDuration + .5);
        self.renderingContext->expectedFramesPerBuffer = sessionFramesPerBuffer;

        NSAssert(self.audioUnit == NULL, @"The audio unit should not be created yet.");
        if (![self setupAndStartAudioUnit]) {
            free(self.renderingContext);
            self.renderingContext = NULL;
            return NO;
        }
    }

    BOOL success = [self startAudioUnit];
    return success;
}

- (BOOL)stopRendering {
    @synchronized(self) {
        NSAssert(self.renderingContext != NULL, @"Should have a rendering context.");
        [self stopAndTeardownAudioUnit];

        self.renderingContext->deviceContext = NULL;
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

    // Render silence if rendering was stopped, or never started in the first place
    if (context->deviceContext == NULL) {
        *actionFlags |= kAudioUnitRenderAction_OutputIsSilence;
        memset(audioBuffer, 0, audioBufferSizeInBytes);
        return noErr;
    }

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
    audioUnitDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    audioUnitDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    audioUnitDescription.componentFlags = 0;
    audioUnitDescription.componentFlagsMask = 0;
    return audioUnitDescription;
}

- (BOOL)setupAVAudioSession {
    BOOL result = YES;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;

    if (![session setPreferredSampleRate:kPreferredSampleRate error:&error]) {
        NSLog(@"Error setting sample rate: %@", error);
        result = NO;
    }

    NSInteger preferredOutputChannels = session.outputNumberOfChannels >= kPreferredNumberOfChannels ? kPreferredNumberOfChannels : session.outputNumberOfChannels;
    if (![session setPreferredOutputNumberOfChannels:preferredOutputChannels error:&error]) {
        NSLog(@"Error setting number of output channels: %@", error);
        result = NO;
    }

    /*
     * We want to be as close as possible to the 10 millisecond buffer size that the media engine needs. If there is
     * a mismatch then TwilioVideo will ensure that appropriately sized audio buffers are delivered.
     */
    if (![session setPreferredIOBufferDuration:kPreferredIOBufferDurationSec error:&error]) {
        NSLog(@"Error setting IOBuffer duration: %@", error);
        result = NO;
    }

    if (![session setCategory:AVAudioSessionCategoryPlayback error:&error]) {
        NSLog(@"Error setting session category: %@", error);
        result = NO;
    }

    if (![session setActive:YES error:&error]) {
        NSLog(@"Error activating AVAudioSession: %@", error);
        result = NO;
    }

    return result;
}

- (BOOL)setupAndStartAudioUnit {
    BOOL setupSuccessful = [self setupAudioUnit:self.renderingContext];
    if (!setupSuccessful) {
        NSLog(@"ExampleCoreAudioDevice failed to setup audio unit");
        return NO;
    }

    BOOL startSuccessful = [self startAudioUnit];
    if (!startSuccessful) {
        NSLog(@"ExampleCoreAudioDevice failed to start audio unit");
        [self stopAndTeardownAudioUnit];
        return NO;
    }
    return YES;
}

- (void)stopAndTeardownAudioUnit {
    @synchronized(self) {
        if (self.audioUnit) {
            [self stopAudioUnit];
            [self teardownAudioUnit];
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
        NSLog(@"Could not set stream format on output bus!");
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

    NSInteger failedInitializeAttempts = 0;
    while (status != noErr) {
        NSLog(@"Failed to initialize the RemoteIO unit. Error= %ld.", (long)status);
        ++failedInitializeAttempts;
        if (failedInitializeAttempts == kMaxNumberOfAudioUnitInitializeAttempts) {
            break;
        }
        NSLog(@"Pause 100ms and try audio unit initialization again.");
        [NSThread sleepForTimeInterval:0.1f];
        status = AudioUnitInitialize(_audioUnit);
    }

    // Finally, initialize and start the RemoteIO audio unit.
    if (status != 0) {
        NSLog(@"Could not initialize the audio unit!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    return YES;
}

- (BOOL)startAudioUnit {
    NSInteger startAttempts = 0;
    OSStatus status = -1;
    while (status != 0){
        if (startAttempts == kMaxNumberOfAudioUnitStartAttempts) {
            NSLog(@"Could not start the audio unit!");
            return NO;
        } else if (startAttempts > 0) {
            NSLog(@"Pause 100ms and try starting audio unit again.");
            [NSThread sleepForTimeInterval:0.1f];
        }

        status = AudioOutputUnitStart(_audioUnit);
        ++startAttempts;
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

- (TVIAudioDeviceContext)deviceContext {
    return self.renderingContext ? self.renderingContext->deviceContext : NULL;
}

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
        TVIAudioDeviceContext context = [self deviceContext];
        if (context) {
            TVIAudioDeviceExecuteWorkerBlock(context, ^{
                if (type == AVAudioSessionInterruptionTypeBegan) {
                    NSLog(@"Interruption began.");
                    self.interrupted = YES;
                    [self stopAndTeardownAudioUnit];
                } else {
                    NSLog(@"Interruption ended.");
                    self.interrupted = NO;
                    [self reinitialize];
                }
            });
        }
    }
}

- (void)handleApplicationDidBecomeActive:(NSNotification *)notification {
    @synchronized(self) {
        // If the worker block is executed, then context is guaranteed to be valid.
        TVIAudioDeviceContext context = [self deviceContext];
        if (context) {
            TVIAudioDeviceExecuteWorkerBlock(context, ^{
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
                // If the worker block is executed, then context is guaranteed to be valid.
                TVIAudioDeviceContext context = [self deviceContext];
                if (context) {
                    TVIAudioDeviceExecuteWorkerBlock(context, ^{
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

    if ([self didFormatChange]) {
        [self reinitialize];
    }
}

- (BOOL)didFormatChange {
    BOOL formatDidChange = NO;
    TVIAudioFormat *activeFormat = [[self class] activeRenderingFormat];

    // Determine if the format actually changed. We only care about sample rate and number of channels.
    if (![activeFormat isEqual:_renderingFormat]) {
        formatDidChange = YES;
        NSLog(@"The rendering format changed. Restarting with %@", activeFormat);
    }

    return formatDidChange;
}

-(void)reinitialize {
    // Signal a change by clearing our cached format, and allowing TVIAudioDevice to drive the process.
    _renderingFormat = nil;

    @synchronized(self) {
        TVIAudioDeviceContext context = [self deviceContext];
        if (context) {
            // Setup AVAudioSession preferences
            BOOL setupSession = [self setupAVAudioSession];
            NSInteger setupAttempts = 1;
            while (!setupSession) {
                if (setupAttempts == kMaxNumberOfSetupAVAudioSessionAttempts) {
                    NSLog(@"Failed to setup AVAudioSession after multiple attempts");
                    break;
                }

                NSLog(@"Pause for 100ms and try setting up AVAudioSession again");
                [NSThread sleepForTimeInterval:0.1f];
                setupSession = [self setupAVAudioSession];
                ++setupAttempts;
            }

            // Update FineAudioBuffer and stop+init+start AudioUnit
            TVIAudioDeviceReinitialize(context);
        }
    }
}

- (void)handleMediaServiceLost:(NSNotification *)notification {
    @synchronized(self) {
        // If the worker block is executed, then context is guaranteed to be valid.
        TVIAudioDeviceContext context = [self deviceContext];
        if (context) {
            TVIAudioDeviceExecuteWorkerBlock(context, ^{
                [self teardownAudioUnit];
            });
        }
    }
}

- (void)handleMediaServiceRestored:(NSNotification *)notification {
    @synchronized(self) {
        // If the worker block is executed, then context is guaranteed to be valid.
        TVIAudioDeviceContext context = [self deviceContext];
        if (context) {
            TVIAudioDeviceExecuteWorkerBlock(context, ^{
                [self startAudioUnit];
            });
        }
    }
}

- (void)unregisterAVAudioSessionObservers {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
