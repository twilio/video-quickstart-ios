//
//  ViewController.m
//  AVPlayerExample
//
//  Copyright © 2016-2017 Twilio, Inc. All rights reserved.
//

#import "ViewController.h"

@import AVFoundation;
@import TwilioVideo;

#import "AVPlayerView.h"
#import "Utils.h"

typedef NS_ENUM(NSUInteger, ViewControllerState) {
    /**
     *  The initial lobby UI is shown.
     */
    ViewControllerStateLobby = 0,
    /**
     *  The AVPlayer UI is shown.
     */
    ViewControllerStateMediaPlayer,
    /**
     *  The in Room UI is shown.
     */
    ViewControllerStateRoom
};

NSString *const kVideoMovURL = @"https://s3-us-west-1.amazonaws.com/avplayervideo/What+Is+Cloud+Communications.mov";
NSString *const kStatusKey   = @"status";

@interface ViewController () <UITextFieldDelegate, TVIParticipantDelegate, TVIRoomDelegate, TVIVideoViewDelegate, TVICameraCapturerDelegate>

// Configure access token manually for testing in `viewDidLoad`, if desired! Create one manually in the console.
@property (nonatomic, strong) NSString *accessToken;
@property (nonatomic, strong) NSString *tokenUrl;

#pragma mark Video SDK components

@property (nonatomic, strong) TVIRoom *room;
@property (nonatomic, strong) TVICameraCapturer *camera;
@property (nonatomic, strong) TVILocalVideoTrack *localVideoTrack;
@property (nonatomic, strong) TVILocalAudioTrack *localAudioTrack;
@property (nonatomic, strong) TVIParticipant *participant;
@property (nonatomic, weak) TVIVideoView *remoteView;

#pragma mark AVPlayer

@property (nonatomic, strong) AVPlayer *videoPlayer;
@property (nonatomic, weak) AVPlayerView *videoPlayerView;

#pragma mark UI Element Outlets and handles

// `TVIVideoView` created from a storyboard
@property (nonatomic, weak) IBOutlet TVIVideoView *previewView;

@property (nonatomic, weak) IBOutlet UIView *connectButton;
@property (nonatomic, weak) IBOutlet UIButton *disconnectButton;
@property (nonatomic, weak) IBOutlet UILabel *messageLabel;
@property (nonatomic, weak) IBOutlet UITextField *roomTextField;
@property (nonatomic, weak) IBOutlet UIButton *micButton;
@property (nonatomic, weak) IBOutlet UILabel *roomLabel;
@property (nonatomic, weak) IBOutlet UILabel *roomLine;

@end

@implementation ViewController

- (void)dealloc {
    // We are done with AVAudioSession
    [self resetAudioSession];
}

#pragma mark - UIViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self logMessage:[NSString stringWithFormat:@"TwilioVideo v%@", [TwilioVideo version]]];

    // Configure access token for testing. Create one manually in the console
    // at https://www.twilio.com/console/video/runtime/testing-tools
    self.accessToken = @"TWILIO_ACCESS_TOKEN";

    // Using a token server to provide access tokens? Make sure the tokenURL is pointing to the correct location.
    self.tokenUrl = @"http://localhost:8000/token.php";

    // Start with the Lobby UI
    [self showInterfaceState:ViewControllerStateLobby];

    self.roomTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.roomTextField.delegate = self;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    [self.view addGestureRecognizer:tap];

    // Manually configure the AudioSession
    [self setupAudioSession];

    // Prepare local media which we will share with Room Participants.
    [self prepareMedia];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];

    self.videoPlayerView.frame = CGRectMake(0, 0, CGRectGetWidth(self.view.bounds), CGRectGetHeight(self.view.bounds));
    self.remoteView.frame = CGRectMake(0, 0, CGRectGetWidth(self.view.bounds), CGRectGetHeight(self.view.bounds));
}

#pragma mark - NSObject

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    NSLog(@"Player changed: %@ status: %@", object, change);
}

#pragma mark - Public

- (IBAction)connectButtonPressed:(id)sender {
    [self showInterfaceState:ViewControllerStateMediaPlayer];
    [self dismissKeyboard];

    if ([self.accessToken isEqualToString:@"TWILIO_ACCESS_TOKEN"]) {
        [self fetchTokenAndConnect];
    } else {
        [self doConnect];
    }
}

- (IBAction)disconnectButtonPressed:(id)sender {
    [self.room disconnect];
}

- (IBAction)micButtonPressed:(id)sender {
    // We will toggle the mic to mute/unmute and change the title according to the user action.

    if (self.localAudioTrack) {
        self.localAudioTrack.enabled = !self.localAudioTrack.isEnabled;

        // Toggle the button title
        if (self.localAudioTrack.isEnabled) {
            [self.micButton setTitle:@"Mute" forState:UIControlStateNormal];
        } else {
            [self.micButton setTitle:@"Unmute" forState:UIControlStateNormal];
        }
    }
}

#pragma mark - Private

- (void)startPreview {
    if ([PlatformUtils isSimulator]) {
        return;
    }

    self.camera = [[TVICameraCapturer alloc] initWithSource:TVICameraCaptureSourceFrontCamera delegate:self];
    self.localVideoTrack = [TVILocalVideoTrack trackWithCapturer:self.camera];
    if (!self.localVideoTrack) {
        [self logMessage:@"Failed to add video track"];
    } else {
        // Add renderer to video track for local preview
        [self.localVideoTrack addRenderer:self.previewView];

        [self logMessage:@"Video track created"];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(flipCamera)];
        [self.previewView addGestureRecognizer:tap];
    }
}

- (void)flipCamera {
    if (self.camera.source == TVICameraCaptureSourceFrontCamera) {
        [self.camera selectSource:TVICameraCaptureSourceBackCameraWide];
    } else {
        [self.camera selectSource:TVICameraCaptureSourceFrontCamera];
    }
}

- (void)prepareMedia {
    // We will share audio and video when we connect to the Room.

    // Create an audio track.
    if (!self.localAudioTrack) {
        self.localAudioTrack = [TVILocalAudioTrack track];

        if (!self.localAudioTrack) {
            [self logMessage:@"Failed to add audio track"];
        }
    }

    // Create a video track which captures from the camera.
    [self startPreview];
}

- (void)setupAudioSession {
    // In this example we don't want TwilioVideo to dynamically configure and activate / deactivate the AVAudioSession.
    // Instead we will setup audio once, and deal with activation and de-activation manually.
    [[TVIAudioController sharedController] configureAudioSession:TVIAudioOutputVideoChatDefault];

    // This is similar to when CallKit is used, but instead we will activate AVAudioSession ourselves.
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if (error) {
        [self logMessage:[NSString stringWithFormat:@"Couldn't activate AVAudioSession. %@", error]];
    }

    [[TVIAudioController sharedController] startAudio];
}

- (void)resetAudioSession {
    [[TVIAudioController sharedController] stopAudio];

    NSError *error = nil;
    [[AVAudioSession sharedInstance] setActive:NO
                                   withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                         error:&error];
    if (error) {
        [self logMessage:[NSString stringWithFormat:@"Couldn't deactivate AVAudioSession. %@", error]];
    }
}

- (void)startVideoPlayer {
    if (self.videoPlayer != nil) {
        [self logMessage:@"Using an already prepared AVPlayer"];
        [self.videoPlayer play];
        return;
    }

    NSURL *contentUrl = [NSURL URLWithString:kVideoMovURL];
    AVPlayer *player = [AVPlayer playerWithURL:contentUrl];
    [player addObserver:self forKeyPath:kStatusKey options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:nil];
    [player play];

    self.videoPlayer = player;

    // Add Video UI on screen.
    AVPlayerView *playerView = [[AVPlayerView alloc] initWithPlayer:player];
    [self.view insertSubview:playerView atIndex:0];
    self.videoPlayerView = playerView;

    // We will rely on frame based layout to size and position `self.videoPlayerView`.
    [self.view setNeedsLayout];
}

- (void)stopVideoPlayer {
    [self.videoPlayer pause];
    [self.videoPlayer removeObserver:self forKeyPath:kStatusKey];
    self.videoPlayer = nil;

    // Remove Video UI from screen.
    [self.videoPlayerView removeFromSuperview];
    self.videoPlayerView = nil;
}

- (void)fetchTokenAndConnect {
    [self logMessage:[NSString stringWithFormat:@"Fetching an access token"]];

    [TokenUtils retrieveAccessTokenFromURL:self.tokenUrl completion:^(NSString *token, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!err) {
                self.accessToken = token;
                [self doConnect];
            } else {
                [self logMessage:[NSString stringWithFormat:@"Error retrieving the access token"]];
                [self showInterfaceState:ViewControllerStateLobby];
            }
        });
    }];
}

- (void)doConnect {
    if ([self.accessToken isEqualToString:@"TWILIO_ACCESS_TOKEN"]) {
        [self logMessage:@"Please provide a valid token to connect to a room"];
        return;
    }

    // Since we are configuring audio session explicitly, we will call setupAudioSession every time we attempt to connect.
    [self setupAudioSession];

    TVIConnectOptions *connectOptions = [TVIConnectOptions optionsWithToken:self.accessToken
                                                                      block:^(TVIConnectOptionsBuilder * _Nonnull builder) {

                                                                          // Use the local media that we prepared earlier.
                                                                          builder.audioTracks = self.localAudioTrack ? @[ self.localAudioTrack ] : @[ ];
                                                                          builder.videoTracks = self.localVideoTrack ? @[ self.localVideoTrack ] : @[ ];

                                                                          // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty
                                                                          // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
                                                                          builder.roomName = self.roomTextField.text;
                                                                      }];

    // Connect to the Room using the options we provided.
    self.room = [TwilioVideo connectWithOptions:connectOptions delegate:self];

    [self logMessage:[NSString stringWithFormat:@"Attempting to connect to room %@", self.roomTextField.text]];
}

- (void)setupRemoteView {
    // Creating a `TVIVideoView` programmatically.
    TVIVideoView *remoteView = [[TVIVideoView alloc] init];

    // `TVIVideoView` supports UIViewContentModeScaleToFill, UIViewContentModeScaleAspectFill and UIViewContentModeScaleAspectFit
    // UIViewContentModeScaleAspectFit is the default mode when you create `TVIVideoView` programmatically.
    self.remoteView.contentMode = UIViewContentModeScaleAspectFit;

    [self.view insertSubview:remoteView atIndex:0];
    self.remoteView = remoteView;

    // We will rely on frame based layout to size and position `self.remoteView`.
    [self.view setNeedsLayout];
}

// Reset the client ui status
- (void)showInterfaceState:(ViewControllerState)state {
    self.roomTextField.hidden = state != ViewControllerStateLobby;
    self.connectButton.hidden = state != ViewControllerStateLobby;
    self.roomLine.hidden = state != ViewControllerStateLobby;
    self.roomLabel.hidden = state != ViewControllerStateLobby;
    self.micButton.hidden = state != ViewControllerStateRoom;
    self.messageLabel.hidden = state == ViewControllerStateMediaPlayer;
    self.disconnectButton.hidden = state == ViewControllerStateLobby;
    [UIApplication sharedApplication].idleTimerDisabled = state != ViewControllerStateLobby;
}

- (void)dismissKeyboard {
    if (self.roomTextField.isFirstResponder) {
        [self.roomTextField resignFirstResponder];
    }
}

- (void)cleanupRemoteParticipant {
    if (self.participant) {
        if ([self.participant.videoTracks count] > 0) {
            [self.participant.videoTracks[0] removeRenderer:self.remoteView];
            [self.remoteView removeFromSuperview];
        }
        self.participant = nil;
    }
}

- (void)logMessage:(NSString *)msg {
    NSLog(@"%@", msg);
    self.messageLabel.text = msg;
}

#pragma mark - TVIRoomDelegate

- (void)didConnectToRoom:(TVIRoom *)room {
    // At the moment, this example only supports rendering one Participant at a time.

    [self logMessage:[NSString stringWithFormat:@"Connected to room %@ as %@", room.name, room.localParticipant.identity]];

    if (room.participants.count > 0) {
        self.participant = room.participants[0];
        self.participant.delegate = self;
        [self showInterfaceState:ViewControllerStateRoom];
    } else {
        // If there are no Participants, we will play the pre-roll content instead.
        [self startVideoPlayer];
        [self showInterfaceState:ViewControllerStateMediaPlayer];
    }
}

- (void)room:(TVIRoom *)room didDisconnectWithError:(nullable NSError *)error {
    [self logMessage:[NSString stringWithFormat:@"Disconncted from room %@, error = %@", room.name, error]];
    
    // If AVPlayer is playing, we will not deactivate the audio session
    if (!self.videoPlayer) {
        [self resetAudioSession];
    } else {
        [self stopVideoPlayer];
    }
    
    [self cleanupRemoteParticipant];
    self.room = nil;
    [self showInterfaceState:ViewControllerStateLobby];
}

- (void)room:(TVIRoom *)room didFailToConnectWithError:(nonnull NSError *)error{
    [self logMessage:[NSString stringWithFormat:@"Failed to connect to room, error = %@", error]];

    self.room = nil;

    [self showInterfaceState:ViewControllerStateLobby];
}

- (void)room:(TVIRoom *)room participantDidConnect:(TVIParticipant *)participant {
    if (!self.participant) {
        self.participant = participant;
        self.participant.delegate = self;
    }

    if ([room.participants count] == 1) {
        [self stopVideoPlayer];
        [self showInterfaceState:ViewControllerStateRoom];
    }

    [self logMessage:[NSString stringWithFormat:@"Room %@ participant %@ connected", room.name, participant.identity]];
}

- (void)room:(TVIRoom *)room participantDidDisconnect:(TVIParticipant *)participant {
    if (self.participant == participant) {
        [self cleanupRemoteParticipant];
    }

    if ([room.participants count] == 0) {
        [self startVideoPlayer];
        [self showInterfaceState:ViewControllerStateMediaPlayer];
    }

    [self logMessage:[NSString stringWithFormat:@"Room %@ participant %@ disconnected", room.name, participant.identity]];
}

#pragma mark - TVIParticipantDelegate

- (void)participant:(TVIParticipant *)participant addedVideoTrack:(TVIVideoTrack *)videoTrack {
    [self logMessage:[NSString stringWithFormat:@"Participant %@ added video track.", participant.identity]];

    if (self.participant == participant) {
        [self setupRemoteView];
        [videoTrack addRenderer:self.remoteView];
    }
}

- (void)participant:(TVIParticipant *)participant removedVideoTrack:(TVIVideoTrack *)videoTrack {
    [self logMessage:[NSString stringWithFormat:@"Participant %@ removed video track.", participant.identity]];

    if (self.participant == participant) {
        [videoTrack removeRenderer:self.remoteView];
        [self.remoteView removeFromSuperview];
    }
}

- (void)participant:(TVIParticipant *)participant addedAudioTrack:(TVIAudioTrack *)audioTrack {
    [self logMessage:[NSString stringWithFormat:@"Participant %@ added audio track.", participant.identity]];
}

- (void)participant:(TVIParticipant *)participant removedAudioTrack:(TVIAudioTrack *)audioTrack {
    [self logMessage:[NSString stringWithFormat:@"Participant %@ removed audio track.", participant.identity]];
}

- (void)participant:(TVIParticipant *)participant enabledTrack:(TVITrack *)track {
    NSString *type = @"";
    if ([track isKindOfClass:[TVIAudioTrack class]]) {
        type = @"audio";
    } else {
        type = @"video";
    }
    [self logMessage:[NSString stringWithFormat:@"Participant %@ enabled %@ track.", participant.identity, type]];
}

- (void)participant:(TVIParticipant *)participant disabledTrack:(TVITrack *)track {
    NSString *type = @"";
    if ([track isKindOfClass:[TVIAudioTrack class]]) {
        type = @"audio";
    } else {
        type = @"video";
    }
    [self logMessage:[NSString stringWithFormat:@"Participant %@ disabled %@ track.", participant.identity, type]];
}

#pragma mark - TVIVideoViewDelegate

- (void)videoView:(TVIVideoView *)view videoDimensionsDidChange:(CMVideoDimensions)dimensions {
    NSLog(@"Dimensions changed to: %d x %d", dimensions.width, dimensions.height);
    [self.view setNeedsLayout];
}

#pragma mark - TVICameraCapturerDelegate

- (void)cameraCapturer:(TVICameraCapturer *)capturer didStartWithSource:(TVICameraCaptureSource)source {
    self.previewView.mirror = (source == TVICameraCaptureSourceFrontCamera);

    self.localVideoTrack.enabled = YES;
}

- (void)cameraCapturerWasInterrupted:(TVICameraCapturer *)capturer reason:(TVICameraCapturerInterruptionReason)reason {
    // We will disable `self.localVideoTrack` when the TVICameraCapturer is interrupted.
    // This prevents other Participants from seeing a frozen frame while the Client is backgrounded.
    self.localVideoTrack.enabled = NO;
}

@end
