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

#pragma mark Video SDK components

@property (nonatomic, strong) TVIVideoClient *client;
@property (nonatomic, strong) TVIRoom *room;
@property (nonatomic, strong) TVILocalMedia *localMedia;
@property (nonatomic, strong) TVICameraCapturer *camera;
@property (nonatomic, strong) TVILocalVideoTrack *localVideoTrack;
@property (nonatomic, strong) TVILocalAudioTrack *localAudioTrack;
@property (nonatomic, strong) TVIParticipant *participant;

#pragma mark UI Element Outlets and handles

@property (weak, nonatomic) IBOutlet UIView *remoteView;
@property (weak, nonatomic) IBOutlet UIView *previewView;
@property (weak, nonatomic) IBOutlet UIView *connectButton;
@property (weak, nonatomic) IBOutlet UIButton *disconnectButton;
@property (weak, nonatomic) IBOutlet UILabel *messageLabel;
@property (weak, nonatomic) IBOutlet UITextField *roomTextField;
@property (weak, nonatomic) IBOutlet UIButton *micButton;
@property (weak, nonatomic) IBOutlet UILabel *roomLabel;
@property (weak, nonatomic) IBOutlet UILabel *roomLine;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Configure access token manually for testing, if desired! Create one manually in the console
    self.accessToken = @"eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCIsICJjdHkiOiAidHdpbGlvLWZwYTt2PTEifQ.eyJpc3MiOiAiU0s2NzRiMTg4NjlmMTFmYWNjNjY1YTY1ZmQ0ZGRmMmY0ZiIsICJncmFudHMiOiB7InJ0YyI6IHsiY29uZmlndXJhdGlvbl9wcm9maWxlX3NpZCI6ICJWUzNmNzVlMGYxNGU3YzhiMjA5MzhmYzUwOTJlODJmMjNhIn0sICJpZGVudGl0eSI6ICJwdGFuayJ9LCAianRpIjogIlNLNjc0YjE4ODY5ZjExZmFjYzY2NWE2NWZkNGRkZjJmNGYtMTQ3NDkzNDQ1OSIsICJzdWIiOiAiQUM5NmNjYzkwNDc1M2IzMzY0ZjI0MjExZThkOTc0NmE5MyIsICJleHAiOiAxNDc0OTQxNjU5fQ.CuudtoC-SNNB5XjCbiC_O91I2mygN9dvpHnXBgH32xA";
    
    // Using the PHP server to provide access tokens? Make sure the tokenURL is pointing to the correct location -
    // the default is http://localhost:8000/token.php
    NSString *tokenUrl = @"http://localhost:8000/token.php";
    
    if ([self.accessToken isEqualToString:@"TWILIO_ACCESS_TOKEN"]) {
        [TokenUtils retrieveAccessTokenFromURL:tokenUrl completion:^(NSString *token, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!err) {
                    self.accessToken = token;
                } else {
                    [self logMessage:[NSString stringWithFormat:@"Error retrieving the access token"]];
                }
            });
        }];
    }
    
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

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyBoard)];
    [self.view addGestureRecognizer:tap];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

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
    [self.camera flipCamera];
}

- (void)prepareLocalMedia {
    
    // We will offer local audio and video when we connect to room.
    
    // Adding local audio track to localMedia
    self.localAudioTrack = [self.localMedia addAudioTrack:YES];
    
    // Adding local video track to localMedia and starting local preview if it is not already started.
    if (self.localMedia.videoTracks.count == 0) {
        [self startPreview];
    }
}

- (IBAction)connectButtonPressed:(id)sender {
    if([self.accessToken isEqualToString:@"TWILIO_ACCESS_TOKEN"]) {
        [self logMessage:@"Please provide a valid token to connect to a room."];
        return;
    }
    
    // Creating a video client with the use of the access token.
    if (!self.client) {
        self.client = [TVIVideoClient clientWithToken:self.accessToken];
        if (!self.client) {
            [self logMessage:@"Failed to create video client"];
            return;
        }
    }
    
    // Preparing local media to offer in when we connect to room.
    [self prepareLocalMedia];
    
    TVIConnectOptions *connectOptions = [TVIConnectOptions optionsWithBlock:^(TVIConnectOptionsBuilder * _Nonnull builder) {
        
        // We will set the prepared local media in connect options.
        builder.localMedia = self.localMedia;
        
        // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty
        // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
        builder.name = self.roomTextField.text;
    }];
    
    // Attempting to connect to room with connect options.
    self.room = [self.client connectWithOptions:connectOptions delegate:self];
    
    [self logMessage:[NSString stringWithFormat:@"Attempting to connect to room %@", self.roomTextField.text]];
    
    [self toggleView];
    [self dismissKeyBoard];
}

- (IBAction)disconnectButtonPressed:(id)sender {
    [self.room disconnect];
}

- (IBAction)micButtonPressed:(id)sender {
    // We will toggle the mic to mute/unmute and change the title according to the user action. 
    
    if ([self.localMedia.audioTracks count] > 0) {
        self.localMedia.audioTracks[0].enabled = !self.localMedia.audioTracks[0].isEnabled;
        
        //toggle the button title
        if (self.localMedia.audioTracks[0].isEnabled) {
            [self.micButton setTitle:@"Mute" forState:UIControlStateNormal];
        } else {
            [self.micButton setTitle:@"Unmute" forState:UIControlStateNormal];

        }
    }
}

// Reset the client ui status
- (void)toggleView {
    [self.micButton setTitle:@"Mute" forState:UIControlStateNormal];
    
    self.roomTextField.hidden = !self.roomTextField.isHidden;
    self.connectButton.hidden = !self.connectButton.isHidden;
    self.disconnectButton.hidden = !self.disconnectButton.isHidden;
    self.roomLine.hidden = !self.roomLine.isHidden;
    self.roomLabel.hidden = !self.roomLabel.isHidden;
    self.micButton.hidden = !self.micButton.isHidden;
    [UIApplication sharedApplication].idleTimerDisabled = ![UIApplication sharedApplication].isIdleTimerDisabled;
}

- (void)dismissKeyBoard {
    if (self.roomTextField.isFirstResponder) {
        [self.roomTextField resignFirstResponder];
    }
}

- (BOOL)testFieldShouldReturn:(UITextField *)textField {
    [self connectButtonPressed:textField];
    return YES;
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

#pragma mark - TVIRoomDelegate

- (void)didConnectToRoom:(TVIRoom *)room {
    // At the moment, this example only supports rendering one Participant at a time.
    
    [self logMessage:[NSString stringWithFormat:@"Connected to room %@", room.name]];
    
    if (room.participants.count > 0) {
        self.participant = room.participants[0];
        self.participant.delegate = self;
    }
}

- (void)room:(TVIRoom *)room didDisconnectWithError:(nullable NSError *)error {
    [self logMessage:[NSString stringWithFormat:@"Disconncted from room %@, error = %@", room.name, error]];
    
    [self cleanupRemoteParticipant];
    self.room = nil;
    
    [self toggleView];
}

- (void)room:(TVIRoom *)room didFailToConnectWithError:(nonnull NSError *)error{
    [self logMessage:[NSString stringWithFormat:@"Failed to connect to room, error = %@", error]];
    
    self.room = nil;
    
    [self toggleView];
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
