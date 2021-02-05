//
//  ExampleAVAudioEngineDevice.m
//  AudioDeviceExample
//
//  Copyright © 2018-2019 Twilio, Inc. All rights reserved.
//

#import "ExampleAVAudioEngineDevice.h"

// We want to get as close to 10 msec buffers as possible because this is what the media engine prefers.
static double const kPreferredIOBufferDuration = 0.01;

// We will use mono playback and recording where available.
static size_t const kPreferredNumberOfChannels = 1;

// An audio sample is a signed 16-bit integer.
static size_t const kAudioSampleSize = 2;
static uint32_t const kPreferredSampleRate = 48000;

/*
 * Calls to AudioUnitInitialize() can fail if called back-to-back after a format change or adding and removing tracks.
 * A fall-back solution is to allow multiple sequential calls with a small delay between each. This factor sets the max
 * number of allowed initialization attempts.
 */
static const int kMaxNumberOfAudioUnitInitializeAttempts = 5;

// Audio renderer contexts used in core audio's playout callback to retrieve the sdk's audio device context.
typedef struct AudioRendererContext {
    // Audio device context received in AudioDevice's `startRendering:context` callback.
    TVIAudioDeviceContext deviceContext;

    // Maximum frames per buffer.
    size_t maxFramesPerBuffer;

    // Buffer passed to AVAudioEngine's manualRenderingBlock to receive the mixed audio data.
    AudioBufferList *bufferList;

    /*
     * Points to AVAudioEngine's manualRenderingBlock. This block is called from within the VoiceProcessingIO playout
     * callback in order to receive mixed audio data from AVAudioEngine in real time.
     */
    void *renderBlock;
} AudioRendererContext;

// Audio renderer contexts used in core audio's record callback to retrieve the sdk's audio device context.
typedef struct AudioCapturerContext {
    // Audio device context received in AudioDevice's `startCapturing:context` callback.
    TVIAudioDeviceContext deviceContext;

    // Preallocated buffer list. Please note the buffer itself will be provided by Core Audio's VoiceProcessingIO audio unit.
    AudioBufferList *bufferList;

    // Preallocated mixed (AudioUnit mic + AVAudioPlayerNode file) audio buffer list.
    AudioBufferList *mixedAudioBufferList;

    // Core Audio's VoiceProcessingIO audio unit.
    AudioUnit audioUnit;

    /*
     * Points to AVAudioEngine's manualRenderingBlock. This block is called from within the VoiceProcessingIO playout
     * callback in order to receive mixed audio data from AVAudioEngine in real time.
     */
    void *renderBlock;
} AudioCapturerContext;

// The VoiceProcessingIO audio unit uses bus 0 for ouptut, and bus 1 for input.
static int kOutputBus = 0;
static int kInputBus = 1;

// This is the maximum slice size for VoiceProcessingIO (as observed in the field). We will double check at initialization time.
static size_t kMaximumFramesPerBuffer = 3072;

@interface ExampleAVAudioEngineDevice()

@property (nonatomic, assign, getter=isInterrupted) BOOL interrupted;
@property (nonatomic, assign) AudioUnit audioUnit;
@property (nonatomic, assign) AudioBufferList captureBufferList;

@property (nonatomic, strong, nullable) TVIAudioFormat *renderingFormat;
@property (nonatomic, strong, nullable) TVIAudioFormat *capturingFormat;
@property (atomic, assign) AudioRendererContext *renderingContext;
@property (nonatomic, assign) AudioCapturerContext *capturingContext;

// AudioEngine properties
@property (nonatomic, strong) AVAudioEngine *playoutEngine;
@property (nonatomic, strong) AVAudioPlayerNode *playoutFilePlayer;
@property (nonatomic, strong) AVAudioUnitReverb *playoutReverb;
@property (nonatomic, strong) AVAudioEngine *recordEngine;
@property (nonatomic, strong) AVAudioPlayerNode *recordFilePlayer;
@property (nonatomic, strong) AVAudioUnitReverb *recordReverb;

@property (nonatomic, strong) AVAudioPCMBuffer *musicBuffer;

@property (atomic, assign) BOOL continuousMusic;

@end

@implementation ExampleAVAudioEngineDevice

#pragma mark - Init & Dealloc

- (id)init {
    self = [super init];

    if (self) {
        /*
         * Initialize rendering and capturing context. The deviceContext will be be filled in when startRendering or
         * startCapturing gets called.
         */

        // Initialize the rendering context
        self.renderingContext = malloc(sizeof(AudioRendererContext));
        memset(self.renderingContext, 0, sizeof(AudioRendererContext));

        // Setup the AVAudioEngine along with the rendering context
        if (![self setupPlayoutAudioEngine]) {
            NSLog(@"Failed to setup AVAudioEngine");
        }

        // Initialize the capturing context
        self.capturingContext = malloc(sizeof(AudioCapturerContext));
        memset(self.capturingContext, 0, sizeof(AudioCapturerContext));
        self.capturingContext->bufferList = &_captureBufferList;
        
        // Setup the AVAudioEngine along with the rendering context
        if (![self setupRecordAudioEngine]) {
            NSLog(@"Failed to setup AVAudioEngine");
        }
        
        [self setupAVAudioSession];
    }

    return self;
}

- (void)dealloc {
    [self unregisterAVAudioSessionObservers];

    [self teardownAudioEngine];

    free(self.renderingContext);
    self.renderingContext = NULL;

    AudioBufferList *mixedAudioBufferList = self.capturingContext->mixedAudioBufferList;
    if (mixedAudioBufferList) {
        for (size_t i = 0; i < mixedAudioBufferList->mNumberBuffers; i++) {
            free(mixedAudioBufferList->mBuffers[i].mData);
        }
        free(mixedAudioBufferList);
    }
    free(self.capturingContext);
    self.capturingContext = NULL;
}

+ (NSString *)description {
    return @"AVAudioEngine Audio Mixing";
}

/*
 * Determine at runtime the maximum slice size used by VoiceProcessingIO. Setting the stream format and sample rate
 * doesn't appear to impact the maximum size so we prefer to read this value once at initialization time.
 */
+ (void)initialize {
    AudioComponentDescription audioUnitDescription = [self audioUnitDescription];
    AudioComponent audioComponent = AudioComponentFindNext(NULL, &audioUnitDescription);
    AudioUnit audioUnit;
    OSStatus status = AudioComponentInstanceNew(audioComponent, &audioUnit);
    if (status != 0) {
        NSLog(@"Could not find VoiceProcessingIO AudioComponent instance!");
        return;
    }

    UInt32 framesPerSlice = 0;
    UInt32 propertySize = sizeof(framesPerSlice);
    status = AudioUnitGetProperty(audioUnit, kAudioUnitProperty_MaximumFramesPerSlice,
                                  kAudioUnitScope_Global, kOutputBus,
                                  &framesPerSlice, &propertySize);
    if (status != 0) {
        NSLog(@"Could not read VoiceProcessingIO AudioComponent instance!");
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

#pragma mark - Private (AVAudioEngine)

- (BOOL)setupAudioEngine {
    return [self setupPlayoutAudioEngine] && [self setupRecordAudioEngine];
}

- (BOOL)setupRecordAudioEngine {
    NSAssert(_recordEngine == nil, @"AVAudioEngine is already configured");

    /*
     * By default AVAudioEngine will render to/from the audio device, and automatically establish connections between
     * nodes, e.g. inputNode -> effectNode -> outputNode.
     */
    _recordEngine = [AVAudioEngine new];

    // AVAudioEngine operates on the same format as the Core Audio output bus.
    NSError *error = nil;
    const AudioStreamBasicDescription asbd = [[[self class] activeFormat] streamDescription];
    AVAudioFormat *format = [[AVAudioFormat alloc] initWithStreamDescription:&asbd];

    // Switch to manual rendering mode
    [_recordEngine stop];
    BOOL success = [_recordEngine enableManualRenderingMode:AVAudioEngineManualRenderingModeRealtime
                                                      format:format
                                           maximumFrameCount:(uint32_t)kMaximumFramesPerBuffer
                                                       error:&error];
    if (!success) {
        NSLog(@"Failed to setup manual rendering mode, error = %@", error);
        return NO;
    }

    /*
     * In manual rendering mode, AVAudioEngine won't receive audio from the microhpone. Instead, it will receive the
     * audio data from the Video SDK and mix it in MainMixerNode. Here we connect the input node to the main mixer node.
     * InputNode -> MainMixer -> OutputNode
     */
    [_recordEngine connect:_recordEngine.inputNode to:_recordEngine.mainMixerNode format:format];

    /*
     * Attach AVAudioPlayerNode node to play music from a file.
     * AVAudioPlayerNode -> ReverbNode -> MainMixer -> OutputNode (note: ReverbNode is optional)
     */
    [self attachMusicNodeToEngine:_recordEngine];

    // Set the block to provide input data to engine
    AVAudioInputNode *inputNode = _recordEngine.inputNode;
    AudioBufferList *captureBufferList = &_captureBufferList;
    success = [inputNode setManualRenderingInputPCMFormat:format
                                               inputBlock: ^const AudioBufferList * _Nullable(AVAudioFrameCount inNumberOfFrames) {
                                                   assert(inNumberOfFrames <= kMaximumFramesPerBuffer);
                                                   return captureBufferList;
                                               }];
    if (!success) {
        NSLog(@"Failed to set the manual rendering block");
        return NO;
    }

    // The manual rendering block (called in Core Audio's VoiceProcessingIO's playout callback at real time)
    self.capturingContext->renderBlock = (__bridge void *)(_recordEngine.manualRenderingBlock);

    success = [_recordEngine startAndReturnError:&error];
    if (!success) {
        NSLog(@"Failed to start AVAudioEngine, error = %@", error);
        return NO;
    }

    return YES;
}

- (BOOL)setupPlayoutAudioEngine {
    NSAssert(_playoutEngine == nil, @"AVAudioEngine is already configured");

    /*
     * By default AVAudioEngine will render to/from the audio device, and automatically establish connections between
     * nodes, e.g. inputNode -> effectNode -> outputNode.
     */
    _playoutEngine = [AVAudioEngine new];

    // AVAudioEngine operates on the same format as the Core Audio output bus.
    NSError *error = nil;
    const AudioStreamBasicDescription asbd = [[[self class] activeFormat] streamDescription];
    AVAudioFormat *format = [[AVAudioFormat alloc] initWithStreamDescription:&asbd];

    // Switch to manual rendering mode
    [_playoutEngine stop];
    BOOL success = [_playoutEngine enableManualRenderingMode:AVAudioEngineManualRenderingModeRealtime
                                                      format:format
                                           maximumFrameCount:(uint32_t)kMaximumFramesPerBuffer
                                                       error:&error];
    if (!success) {
        NSLog(@"Failed to setup manual rendering mode, error = %@", error);
        return NO;
    }

    /*
     * In manual rendering mode, AVAudioEngine won't receive audio from the microhpone. Instead, it will receive the
     * audio data from the Video SDK and mix it in MainMixerNode. Here we connect the input node to the main mixer node.
     * InputNode -> MainMixer -> OutputNode
     */
    [_playoutEngine connect:_playoutEngine.inputNode to:_playoutEngine.mainMixerNode format:format];

    /*
     * Attach AVAudioPlayerNode node to play music from a file.
     * AVAudioPlayerNode -> ReverbNode -> MainMixer -> OutputNode (note: ReverbNode is optional)
     */
    [self attachMusicNodeToEngine:_playoutEngine];

    // Set the block to provide input data to engine
    AudioRendererContext *context = _renderingContext;
    AVAudioInputNode *inputNode = _playoutEngine.inputNode;
    success = [inputNode setManualRenderingInputPCMFormat:format
                                               inputBlock: ^const AudioBufferList * _Nullable(AVAudioFrameCount inNumberOfFrames) {
                                                   assert(inNumberOfFrames <= kMaximumFramesPerBuffer);

                                                   AudioBufferList *bufferList = context->bufferList;
                                                   int8_t *audioBuffer = (int8_t *)bufferList->mBuffers[0].mData;
                                                   UInt32 audioBufferSizeInBytes = bufferList->mBuffers[0].mDataByteSize;

                                                   if (context->deviceContext) {
                                                       /*
                                                        * Pull decoded, mixed audio data from the media engine into the
                                                        * AudioUnit's AudioBufferList.
                                                        */
                                                       TVIAudioDeviceReadRenderData(context->deviceContext, audioBuffer, audioBufferSizeInBytes);

                                                   } else {

                                                       /*
                                                        * Return silence when we do not have the playout device context. This is the
                                                        * case when the remote participant has not published an audio track yet.
                                                        * Since the audio graph and audio engine has been setup, we can still play
                                                        * the music file using AVAudioEngine.
                                                        */
                                                       memset(audioBuffer, 0, audioBufferSizeInBytes);
                                                   }

                                                   return bufferList;
                                               }];
    if (!success) {
        NSLog(@"Failed to set the manual rendering block");
        return NO;
    }

    // The manual rendering block (called in Core Audio's VoiceProcessingIO's playout callback at real time)
    self.renderingContext->renderBlock = (__bridge void *)(_playoutEngine.manualRenderingBlock);

    success = [_playoutEngine startAndReturnError:&error];
    if (!success) {
        NSLog(@"Failed to start AVAudioEngine, error = %@", error);
        return NO;
    }

    return YES;
}

- (void)teardownRecordAudioEngine {
    [_recordEngine stop];
    _recordEngine = nil;
}

- (void)teardownPlayoutAudioEngine {
    [_playoutEngine stop];
    _playoutEngine = nil;
}

- (void)teardownAudioEngine {
    [self teardownFilePlayers];
    [self teardownPlayoutAudioEngine];
    [self teardownRecordAudioEngine];
}

- (AVAudioPCMBuffer *)musicBuffer {
    if (!_musicBuffer) {
        NSString *fileName = [NSString stringWithFormat:@"%@/%@", [[NSBundle mainBundle] bundlePath], @"mixLoop.caf"];
        NSURL *url = [NSURL fileURLWithPath:fileName];
        AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:nil];

        _musicBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:file.processingFormat
                                                     frameCapacity:(AVAudioFrameCount)file.length];
        NSError *error = nil;

        /*
         * The sample app plays a small in size file `mixLoop.caf`, but if you are playing a bigger file, to unblock the
         * calling (main) thread, you should execute `[file readIntoBuffer:buffer error:&error]` on a background thread,
         * and once the read is completed, schedule buffer playout from the calling (main) thread.
         */
        BOOL success = [file readIntoBuffer:_musicBuffer error:&error];
        if (!success) {
            NSLog(@"Failed to read audio file into buffer. error = %@", error);
            _musicBuffer = nil;
        }
    }
    return _musicBuffer;
}

- (void)scheduleMusicOnRecordEngine {
    [self.recordFilePlayer scheduleBuffer:self.musicBuffer
                                   atTime:nil
                                  options:AVAudioPlayerNodeBufferInterrupts
                        completionHandler:^{
        NSLog(@"Downstream file player finished buffer playing");
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Completed playing file via AVAudioEngine.
            // `nil` context indicates TwilioVideo SDK does not need core audio either.
            if (![self deviceContext]) {
                [self tearDownAudio];
            }
        });
    }];
    [self.recordFilePlayer play];

    /*
     * TODO: The upstream AVAudioPlayerNode and downstream AVAudioPlayerNode schedule playout of the buffer
     * "now". In order to ensure full synchronization, choose a time in the near future when scheduling playback.
     */
}

- (void)scheduleMusicOnPlayoutEngine {
    [self.playoutFilePlayer scheduleBuffer:self.musicBuffer
                                    atTime:nil
                                   options:AVAudioPlayerNodeBufferInterrupts
                         completionHandler:^{
        NSLog(@"Upstream file player finished buffer playing");
        dispatch_async(dispatch_get_main_queue(), ^{
            // Completed playing file via AVAudioEngine.
            // `nil` context indicates TwilioVideo SDK does not need core audio either.
            if (![self deviceContext]) {
                [self tearDownAudio];
            }
        });
    }];
    [self.playoutFilePlayer play];
    
    /*
     * TODO: The upstream AVAudioPlayerNode and downstream AVAudioPlayerNode schedule playout of the buffer
     * "now". In order to ensure full synchronization, choose a time in the near future when scheduling playback.
     */
}

- (void)playMusic:(BOOL)continuous {
    @synchronized(self) {
        if (continuous) {
            if (!self.renderingFormat) {
                self.renderingFormat = [self renderFormat];
            }
            if (!self.capturingFormat) {
                self.capturingFormat = [self captureFormat];
            }
            // If device context is null, we will setup the audio unit by invoking the
            // rendring and capturing.
            [self initializeCapturer];
            [self initializeRenderer];
            
            TVIAudioDeviceContext *context = NULL;
            [self startRendering:context];
            [self startCapturing:context];
        }
        self.continuousMusic = continuous;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self scheduleMusicOnPlayoutEngine];
        [self scheduleMusicOnRecordEngine];
    });
}

- (void)tearDownAudio {
    @synchronized(self) {
        [self teardownAudioUnit];
        [self teardownAudioEngine];
        self.continuousMusic = NO;
    }
}

- (void)attachMusicNodeToEngine:(AVAudioEngine *)engine {
    if (!engine) {
        NSLog(@"Cannot play music. AudioEngine has not been created yet.");
        return;
    }

    AVAudioPlayerNode *player = nil;
    AVAudioUnitReverb *reverb = nil;

    BOOL isPlayoutEngine = [self.playoutEngine isEqual:engine];

    /*
     * Attach an AVAudioPlayerNode as an input to the main mixer.
     * AVAudioPlayerNode -> AVAudioUnitReverb -> MainMixerNode -> Core Audio
     */

    NSString *fileName = [NSString stringWithFormat:@"%@/%@", [[NSBundle mainBundle] bundlePath], @"mixLoop.caf"];
    NSURL *url = [NSURL fileURLWithPath:fileName];
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:nil];

    player = [[AVAudioPlayerNode alloc] init];
    reverb = [[AVAudioUnitReverb alloc] init];

    [reverb loadFactoryPreset:AVAudioUnitReverbPresetMediumHall];
    reverb.wetDryMix = 50;

    [engine attachNode:player];
    [engine attachNode:reverb];
    [engine connect:player to:reverb format:file.processingFormat];
    [engine connect:reverb to:engine.mainMixerNode format:file.processingFormat];

    if (isPlayoutEngine) {
        self.playoutReverb = reverb;
        self.playoutFilePlayer = player;
    } else {
        self.recordReverb = reverb;
        self.recordFilePlayer = player;
    }
}

- (void)teardownRecordFilePlayer {
    if (self.recordFilePlayer) {
        if (self.recordFilePlayer.isPlaying) {
            [self.recordFilePlayer stop];
        }
        [self.recordEngine detachNode:self.recordFilePlayer];
        [self.recordEngine detachNode:self.recordReverb];
        self.recordReverb = nil;
    }
}

- (void)teardownPlayoutFilePlayer {
    if (self.playoutFilePlayer) {
        if (self.playoutFilePlayer.isPlaying) {
            [self.playoutFilePlayer stop];
        }
        [self.playoutEngine detachNode:self.playoutFilePlayer];
        [self.playoutEngine detachNode:self.playoutReverb];
        self.playoutReverb = nil;
    }
}

- (void)teardownFilePlayers {
    [self teardownRecordFilePlayer];
    [self teardownPlayoutFilePlayer];
}

#pragma mark - TVIAudioDeviceRenderer

- (nullable TVIAudioFormat *)renderFormat {
    if (!_renderingFormat) {

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
         * call backs. We will restart the audio unit if a remote participant adds an audio track after the audio graph is
         * established. Also we will re-establish the audio graph in case the format changes.
         */
        if (_audioUnit) {
            [self stopAudioUnit];
            [self teardownAudioUnit];
        }
        
        // If music is being played then we have already setup the engine
        if (!self.continuousMusic) {
            // We will make sure AVAudioEngine and AVAudioPlayerNode is accessed on the main queue.
            dispatch_async(dispatch_get_main_queue(), ^{
                AVAudioFormat *manualRenderingFormat  = self.playoutEngine.manualRenderingFormat;
                TVIAudioFormat *engineFormat = [[TVIAudioFormat alloc] initWithChannels:manualRenderingFormat.channelCount
                                                                             sampleRate:manualRenderingFormat.sampleRate
                                                                        framesPerBuffer:kMaximumFramesPerBuffer];
                if ([engineFormat isEqual:[[self class] activeFormat]]) {
                    if (self.playoutEngine.isRunning) {
                        [self.playoutEngine stop];
                    }
                    
                    NSError *error = nil;
                    if (![self.playoutEngine startAndReturnError:&error]) {
                        NSLog(@"Failed to start AVAudioEngine, error = %@", error);
                    }
                } else {
                    [self teardownPlayoutFilePlayer];
                    [self teardownPlayoutAudioEngine];
                    [self setupPlayoutAudioEngine];
                }
            });
        }

        self.renderingContext->deviceContext = context;

        if (![self setupAudioUnitWithRenderContext:self.renderingContext
                                    captureContext:self.capturingContext]) {
            return NO;
        }
        BOOL success = [self startAudioUnit];
        return success;
    }
}

- (BOOL)stopRendering {
    @synchronized(self) {
        
        // Continue playing music even after disconnected from a Room.
        if (self.continuousMusic) {
            return YES;
        }
        
        // If the capturer is runnning, we will not stop the audio unit.
        if (!self.capturingContext->deviceContext) {
            [self stopAudioUnit];
            [self teardownAudioUnit];
        }
        self.renderingContext->deviceContext = NULL;
        
        // We will make sure AVAudioEngine and AVAudioPlayerNode is accessed on the main queue.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.playoutFilePlayer.isPlaying) {
                [self.playoutFilePlayer stop];
            }
            if (self.playoutEngine.isRunning) {
                [self.playoutEngine stop];
            }
        });
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
    _captureBufferList.mNumberBuffers = 1;
    _captureBufferList.mBuffers[0].mNumberChannels = kPreferredNumberOfChannels;

    AudioBufferList *mixedAudioBufferList = self.capturingContext->mixedAudioBufferList;
    if (mixedAudioBufferList == NULL) {
        mixedAudioBufferList = (AudioBufferList*)malloc(sizeof(AudioBufferList));
        mixedAudioBufferList->mNumberBuffers = 1;
        mixedAudioBufferList->mBuffers[0].mNumberChannels = kPreferredNumberOfChannels;
        mixedAudioBufferList->mBuffers[0].mDataByteSize = 0;
        mixedAudioBufferList->mBuffers[0].mData = malloc(kMaximumFramesPerBuffer * kPreferredNumberOfChannels * kAudioSampleSize);

        self.capturingContext->mixedAudioBufferList = mixedAudioBufferList;
    }

    return YES;
}

- (BOOL)startCapturing:(nonnull TVIAudioDeviceContext)context {
    @synchronized (self) {

        // Restart the audio unit if the audio graph is alreay setup and if we publish an audio track.
        if (_audioUnit) {
            [self stopAudioUnit];
            [self teardownAudioUnit];
        }
        
        // If music is being played then we have already setup the engine
        if (!self.continuousMusic) {
            // We will make sure AVAudioEngine and AVAudioPlayerNode is accessed on the main queue.
            dispatch_async(dispatch_get_main_queue(), ^{
                AVAudioFormat *manualRenderingFormat  = self.recordEngine.manualRenderingFormat;
                TVIAudioFormat *engineFormat = [[TVIAudioFormat alloc] initWithChannels:manualRenderingFormat.channelCount
                                                                             sampleRate:manualRenderingFormat.sampleRate
                                                                        framesPerBuffer:kMaximumFramesPerBuffer];
                if ([engineFormat isEqual:[[self class] activeFormat]]) {
                    if (self.recordEngine.isRunning) {
                        [self.recordEngine stop];
                    }
                    
                    NSError *error = nil;
                    if (![self.recordEngine startAndReturnError:&error]) {
                        NSLog(@"Failed to start AVAudioEngine, error = %@", error);
                    }
                } else {
                    [self teardownRecordFilePlayer];
                    [self teardownRecordAudioEngine];
                    [self setupRecordAudioEngine];
                }
            });
        }

        self.capturingContext->deviceContext = context;

        if (![self setupAudioUnitWithRenderContext:self.renderingContext
                                    captureContext:self.capturingContext]) {
            return NO;
        }

        BOOL success = [self startAudioUnit];
        return success;
    }
}

- (BOOL)stopCapturing {
    @synchronized(self) {

        // Continue playing music even after disconnected from a Room.
        if (self.continuousMusic) {
            return YES;
        }

        // If the renderer is runnning, we will not stop the audio unit.
        if (!self.renderingContext->deviceContext) {
            [self stopAudioUnit];
            [self teardownAudioUnit];
        }
        self.capturingContext->deviceContext = NULL;
        
        // We will make sure AVAudioEngine and AVAudioPlayerNode is accessed on the main queue.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.recordFilePlayer.isPlaying) {
                [self.recordFilePlayer stop];
            }
            if (self.recordEngine.isRunning) {
                [self.recordEngine stop];
            }
        });
    }

    return YES;
}

#pragma mark - Private (AudioUnit callbacks)

static OSStatus ExampleAVAudioEngineDevicePlayoutCallback(void *refCon,
                                                          AudioUnitRenderActionFlags *actionFlags,
                                                          const AudioTimeStamp *timestamp,
                                                          UInt32 busNumber,
                                                          UInt32 numFrames,
                                                          AudioBufferList *bufferList) NS_AVAILABLE(NA, 11_0) {
    assert(bufferList->mNumberBuffers == 1);
    assert(bufferList->mBuffers[0].mNumberChannels <= 2);
    assert(bufferList->mBuffers[0].mNumberChannels > 0);

    AudioRendererContext *context = (AudioRendererContext *)refCon;
    context->bufferList = bufferList;

    int8_t *audioBuffer = (int8_t *)bufferList->mBuffers[0].mData;
    UInt32 audioBufferSizeInBytes = bufferList->mBuffers[0].mDataByteSize;

    // Pull decoded, mixed audio data from the media engine into the AudioUnit's AudioBufferList.
    assert(audioBufferSizeInBytes == (bufferList->mBuffers[0].mNumberChannels * kAudioSampleSize * numFrames));
    OSStatus outputStatus = noErr;

    // Get the mixed audio data from AVAudioEngine's output node by calling the `renderBlock`
    AVAudioEngineManualRenderingBlock renderBlock = (__bridge AVAudioEngineManualRenderingBlock)(context->renderBlock);
    const AVAudioEngineManualRenderingStatus status = renderBlock(numFrames, bufferList, &outputStatus);

    /*
     * Render silence if there are temporary mismatches between CoreAudio and our rendering format or AVAudioEngine
     * could not render the audio samples.
     */
    if (numFrames > context->maxFramesPerBuffer || status != AVAudioEngineManualRenderingStatusSuccess) {
        if (numFrames > context->maxFramesPerBuffer) {
            NSLog(@"Can handle a max of %u frames but got %u.", (unsigned int)context->maxFramesPerBuffer, (unsigned int)numFrames);
        }
        *actionFlags |= kAudioUnitRenderAction_OutputIsSilence;
        memset(audioBuffer, 0, audioBufferSizeInBytes);
    }

    return noErr;
}

static OSStatus ExampleAVAudioEngineDeviceRecordCallback(void *refCon,
                                                         AudioUnitRenderActionFlags *actionFlags,
                                                         const AudioTimeStamp *timestamp,
                                                         UInt32 busNumber,
                                                         UInt32 numFrames,
                                                         AudioBufferList *bufferList) NS_AVAILABLE(NA, 11_0) {

    if (numFrames > kMaximumFramesPerBuffer) {
        NSLog(@"Expected %u frames but got %u.", (unsigned int)kMaximumFramesPerBuffer, (unsigned int)numFrames);
        return noErr;
    }

    AudioCapturerContext *context = (AudioCapturerContext *)refCon;

    AudioBufferList *audioBufferList = context->bufferList;
    audioBufferList->mBuffers[0].mDataByteSize = numFrames * sizeof(UInt16) * kPreferredNumberOfChannels;
    // The buffer will be filled by VoiceProcessingIO AudioUnit
    audioBufferList->mBuffers[0].mData = NULL;

    OSStatus status = noErr;
    status = AudioUnitRender(context->audioUnit,
                             actionFlags,
                             timestamp,
                             1,
                             numFrames,
                             audioBufferList);

    AudioBufferList *mixedAudioBufferList = context->mixedAudioBufferList;
    assert(mixedAudioBufferList != NULL);
    assert(mixedAudioBufferList->mNumberBuffers == audioBufferList->mNumberBuffers);
    for(int i = 0; i < audioBufferList->mNumberBuffers; i++) {
        mixedAudioBufferList->mBuffers[i].mNumberChannels = audioBufferList->mBuffers[i].mNumberChannels;
        mixedAudioBufferList->mBuffers[i].mDataByteSize = audioBufferList->mBuffers[i].mDataByteSize;
    }

    OSStatus outputStatus = noErr;
    AVAudioEngineManualRenderingBlock renderBlock = (__bridge AVAudioEngineManualRenderingBlock)(context->renderBlock);
    const AVAudioEngineManualRenderingStatus ret = renderBlock(numFrames, mixedAudioBufferList, &outputStatus);

    if (ret != AVAudioEngineManualRenderingStatusSuccess) {
        NSLog(@"AVAudioEngine failed mix audio");
    }

    int8_t *audioBuffer = (int8_t *)mixedAudioBufferList->mBuffers[0].mData;
    UInt32 audioBufferSizeInBytes = mixedAudioBufferList->mBuffers[0].mDataByteSize;

    if (context->deviceContext && audioBuffer) {
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

    return [[TVIAudioFormat alloc] initWithChannels:TVIAudioChannelsMono
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

- (BOOL)setupAudioUnitWithRenderContext:(AudioRendererContext *)renderContext
                         captureContext:(AudioCapturerContext *)captureContext {

    // Find and instantiate the VoiceProcessingIO audio unit.
    AudioComponentDescription audioUnitDescription = [[self class] audioUnitDescription];
    AudioComponent audioComponent = AudioComponentFindNext(NULL, &audioUnitDescription);

    OSStatus status = AudioComponentInstanceNew(audioComponent, &_audioUnit);
    if (status != 0) {
        NSLog(@"Could not find VoiceProcessingIO AudioComponent instance!");
        return NO;
    }

    /*
     * Configure the VoiceProcessingIO audio unit. Our rendering format attempts to match what AVAudioSession requires
     * to prevent any additional format conversions after the media engine has mixed our playout audio.
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
        NSLog(@"Could not set stream format on input bus!");
        return NO;
    }

    status = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input, kOutputBus,
                                  &streamDescription, sizeof(streamDescription));
    if (status != 0) {
        NSLog(@"Could not set stream format on output bus!");
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
    renderCallback.inputProc = ExampleAVAudioEngineDevicePlayoutCallback;
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
    captureCallback.inputProc = ExampleAVAudioEngineDeviceRecordCallback;
    captureCallback.inputProcRefCon = (void *)(captureContext);
    status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_SetInputCallback,
                                  kAudioUnitScope_Input, kInputBus, &captureCallback,
                                  sizeof(captureCallback));
    if (status != 0) {
        NSLog(@"Could not set capturing callback!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    NSInteger failedInitializeAttempts = 0;
    while (status != noErr) {
        NSLog(@"Failed to initialize the Voice Processing I/O unit. Error= %ld.", (long)status);
        ++failedInitializeAttempts;
        if (failedInitializeAttempts == kMaxNumberOfAudioUnitInitializeAttempts) {
            break;
        }
        NSLog(@"Pause 100ms and try audio unit initialization again.");
        [NSThread sleepForTimeInterval:0.1f];
        status = AudioUnitInitialize(_audioUnit);
    }

    // Finally, initialize and start the VoiceProcessingIO audio unit.
    if (status != 0) {
        NSLog(@"Could not initialize the audio unit!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    captureContext->audioUnit = _audioUnit;

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

- (TVIAudioDeviceContext)deviceContext {
    if (self.renderingContext->deviceContext) {
        return self.renderingContext->deviceContext;
    } else if (self.capturingContext->deviceContext) {
        return self.capturingContext->deviceContext;
    }
    return NULL;
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

    // Determine if the format actually changed. We only care about sample rate and number of channels.
    TVIAudioFormat *activeFormat = [[self class] activeFormat];

    // Notify Video SDK about the format change
    if (![activeFormat isEqual:_renderingFormat] ||
        ![activeFormat isEqual:_capturingFormat]) {

        NSLog(@"Format changed, restarting with %@", activeFormat);

        // Signal a change by clearing our cached format, and allowing TVIAudioDevice to drive the process.
        _renderingFormat = nil;
        _capturingFormat = nil;

        @synchronized(self) {
            TVIAudioDeviceContext context = [self deviceContext];
            if (context) {
                TVIAudioDeviceFormatChanged(context);
            }
        }
    }
}

- (void)handleMediaServiceLost:(NSNotification *)notification {
    [self teardownAudioEngine];

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
    [self setupAudioEngine];

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

