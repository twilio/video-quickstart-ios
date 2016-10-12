//
//  ViewController.m
//  ObjCVideoQuickstart
//
//  Copyright © 2016 Twilio, Inc. All rights reserved.
//

#import "ViewController.h"
#import "Utils.h"

#import <TwilioVideo/TwilioVideo.h>

@interface ViewController () <UITextFieldDelegate, TVIParticipantDelegate, TVIRoomDelegate>

// Configure access token manually for testing in `ViewDidLoad`, if desired! Create one manually in the console.
@property (nonatomic, strong) NSString *accessToken;
@property (nonatomic, strong) NSString *tokenUrl;

#pragma mark Video SDK components

@property (nonatomic, strong) TVIVideoClient *client;
@property (nonatomic, strong) TVIRoom *room;
@property (nonatomic, strong) TVILocalMedia *localMedia;
@property (nonatomic, strong) TVICameraCapturer *camera;
@property (nonatomic, strong) TVILocalVideoTrack *localVideoTrack;
@property (nonatomic, strong) TVILocalAudioTrack *localAudioTrack;
@property (nonatomic, strong) TVIParticipant *participant;

#pragma mark UI Element Outlets and handles

@property (nonatomic, weak) IBOutlet UIView *remoteView;
@property (nonatomic, weak) IBOutlet UIView *previewView;
@property (nonatomic, weak) IBOutlet UIView *connectButton;
@property (nonatomic, weak) IBOutlet UIButton *disconnectButton;
@property (nonatomic, weak) IBOutlet UILabel *messageLabel;
@property (nonatomic, weak) IBOutlet UITextField *roomTextField;
@property (nonatomic, weak) IBOutlet UIButton *micButton;
@property (nonatomic, weak) IBOutlet UILabel *roomLabel;
@property (nonatomic, weak) IBOutlet UILabel *roomLine;

@end

@implementation ViewController

#pragma mark - UIViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSLog(@"version = %@",[TVIVideoClient version]);
    // Configure access token manually for testing, if desired! Create one manually in the console
    self.accessToken = @"TWILIO_ACCESS_TOKEN";
    
    // Using the PHP server to provide access tokens? Make sure the tokenURL is pointing to the correct location -
    // the default is http://localhost:8000/token.php
    self.tokenUrl = @"http://localhost:8000/token.php";
    
    // LocalMedia represents the collection of tracks that we are sending to other Participants from our VideoClient.
    self.localMedia = [[TVILocalMedia alloc] init];
    
    if ([PlatformUtils isSimulator]) {
        [self.previewView removeFromSuperview];
    } else {
        // Preview our local camera track in the local video preview view.
        [self startPreview];
    }
    
    // Disconnect and mic button will be displayed when client is connected to a room.
    self.disconnectButton.hidden = YES;
    self.micButton.hidden = YES;
    
    self.roomTextField.delegate = self;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    [self.view addGestureRecognizer:tap];
}

#pragma mark - Public

- (IBAction)connectButtonPressed:(id)sender {
    [self showRoomUI:YES];
    [self dismissKeyboard];
    
    if ([self.accessToken isEqualToString:@"TWILIO_ACCESS_TOKEN"]) {
        [self logMessage:[NSString stringWithFormat:@"Fetching an access token"]];
        [TokenUtils retrieveAccessTokenFromURL:self.tokenUrl completion:^(NSString *token, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!err) {
                    self.accessToken = token;
                    [self doConnect];
                } else {
                    [self logMessage:[NSString stringWithFormat:@"Error retrieving the access token"]];
                    [self showRoomUI:NO];
                }
            });
        }];
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
    
    self.camera = [[TVICameraCapturer alloc] init];
    self.localVideoTrack = [self.localMedia addVideoTrack:YES capturer:self.camera];
    if (!self.localVideoTrack) {
        [self logMessage:@"Failed to add video track"];
    } else {
        // Attach view to video track for local preview
        [self.localVideoTrack attach:self.previewView];
        
        [self logMessage:@"Video track added to localMedia"];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(flipCamera)];
        [self.previewView addGestureRecognizer:tap];
    }
}

- (void)flipCamera {
    if (self.camera.source == TVIVideoCaptureSourceFrontCamera) {
        [self.camera selectSource:TVIVideoCaptureSourceBackCameraWide];
    } else {
        [self.camera selectSource:TVIVideoCaptureSourceBackCameraWide];
    }
}

- (void)prepareLocalMedia {
    
    // We will offer local audio and video when we connect to room.
    
    // Adding local audio track to localMedia
    if (!self.localAudioTrack) {
        self.localAudioTrack = [self.localMedia addAudioTrack:YES];
    }
    
    // Adding local video track to localMedia and starting local preview if it is not already started.
    if (self.localMedia.videoTracks.count == 0) {
        [self startPreview];
    }
}

- (void)doConnect {
    if ([self.accessToken isEqualToString:@"TWILIO_ACCESS_TOKEN"]) {
        [self logMessage:@"Please provide a valid token to connect to a room"];
        return;
    }
    
    // Create a Client with the access token that we fetched (or hardcoded).
    if (!self.client) {
        self.client = [TVIVideoClient clientWithToken:self.accessToken];
        if (!self.client) {
            [self logMessage:@"Failed to create video client"];
            return;
        }
    }
    
    // Prepare local media which we will share with Room Participants.
    [self prepareLocalMedia];
    
    TVIConnectOptions *connectOptions = [TVIConnectOptions optionsWithBlock:^(TVIConnectOptionsBuilder * _Nonnull builder) {
        
        // Use the local media that we prepared earlier.
        builder.localMedia = self.localMedia;
        
        // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty
        // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
        builder.name = self.roomTextField.text;
    }];
    
    // Connect to the Room using the options we provided.
    self.room = [self.client connectWithOptions:connectOptions delegate:self];
    
    [self logMessage:[NSString stringWithFormat:@"Attempting to connect to room %@", self.roomTextField.text]];
}

// Reset the client ui status
- (void)showRoomUI:(BOOL)inRoom {
    self.roomTextField.hidden = inRoom;
    self.connectButton.hidden = inRoom;
    self.roomLine.hidden = inRoom;
    self.roomLabel.hidden = inRoom;
    self.micButton.hidden = !inRoom;
    self.disconnectButton.hidden = !inRoom;
    [UIApplication sharedApplication].idleTimerDisabled = inRoom;
}

- (void)dismissKeyboard {
    if (self.roomTextField.isFirstResponder) {
        [self.roomTextField resignFirstResponder];
    }
}

- (void)cleanupRemoteParticipant {
    if (self.participant) {
        if ([self.participant.media.videoTracks count] > 0) {
            [self.participant.media.videoTracks[0] detach:self.remoteView];
        }
        self.participant = nil;
    }
}

- (void)logMessage:(NSString *)msg {
    self.messageLabel.text = msg;
}

#pragma mark - UITextFieldDelegate

- (BOOL)testFieldShouldReturn:(UITextField *)textField {
    [self connectButtonPressed:textField];
    return YES;
}

#pragma mark - TVIRoomDelegate

- (void)didConnectToRoom:(TVIRoom *)room {
    // At the moment, this example only supports rendering one Participant at a time.
    
    [self logMessage:[NSString stringWithFormat:@"Connected to room %@ as %@", room.name, room.localParticipant.identity]];
    
    if (room.participants.count > 0) {
        self.participant = room.participants[0];
        self.participant.delegate = self;
    }
}

- (void)room:(TVIRoom *)room didDisconnectWithError:(nullable NSError *)error {
    [self logMessage:[NSString stringWithFormat:@"Disconncted from room %@, error = %@", room.name, error]];
    
    [self cleanupRemoteParticipant];
    self.room = nil;
    
    [self showRoomUI:NO];
}

- (void)room:(TVIRoom *)room didFailToConnectWithError:(nonnull NSError *)error{
    [self logMessage:[NSString stringWithFormat:@"Failed to connect to room, error = %@", error]];
    
    self.room = nil;
    
    [self showRoomUI:NO];
}

- (void)room:(TVIRoom *)room participantDidConnect:(TVIParticipant *)participant {
    if (!self.participant) {
        self.participant = participant;
        self.participant.delegate = self;
    }
    [self logMessage:[NSString stringWithFormat:@"Room %@ participant %@ connected", room.name, participant.identity]];
}

- (void)room:(TVIRoom *)room participantDidDisconnect:(TVIParticipant *)participant {
    if (self.participant == participant) {
        [self cleanupRemoteParticipant];
    }
    [self logMessage:[NSString stringWithFormat:@"Room %@ participant %@ disconnected", room.name, participant.identity]];
}

#pragma mark - TVIParticipantDelegate

- (void)participant:(TVIParticipant *)participant addedVideoTrack:(TVIVideoTrack *)videoTrack {
    [self logMessage:[NSString stringWithFormat:@"Participant %@ added video track.", participant.identity]];
    
    if (self.participant == participant) {
        [videoTrack attach:self.remoteView];
    }
}

- (void)participant:(TVIParticipant *)participant removedVideoTrack:(TVIVideoTrack *)videoTrack {
    [self logMessage:[NSString stringWithFormat:@"Participant %@ removed video track.", participant.identity]];
    
    if (self.participant == participant) {
        [videoTrack detach:self.remoteView];
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

@end
