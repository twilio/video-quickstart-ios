//
//  ViewController.m
//  ObjCVideoQuickstart
//
//  Copyright © 2016-2017 Twilio, Inc. All rights reserved.
//

#import "ViewController.h"
#import "Utils.h"
#import "MapViewController.h"

#import <CoreLocation/CoreLocation.h>
#import <TwilioVideo/TwilioVideo.h>

@interface ViewController () <UITextFieldDelegate, TVIRemoteParticipantDelegate, TVIRoomDelegate, TVIRemoteDataTrackDelegate, TVIVideoViewDelegate, TVICameraCapturerDelegate, CLLocationManagerDelegate>

// Configure access token manually for testing in `ViewDidLoad`, if desired! Create one manually in the console.
@property (nonatomic, strong) NSString *accessToken;
@property (nonatomic, strong) NSString *tokenUrl;

#pragma mark Video SDK components

@property (nonatomic, strong) TVICameraCapturer *camera;
@property (nonatomic, strong) TVILocalVideoTrack *localVideoTrack;
@property (nonatomic, strong) TVILocalAudioTrack *localAudioTrack;
@property (nonatomic, strong) TVILocalDataTrack *localDataTrack;
@property (nonatomic, strong) TVIRemoteParticipant *remoteParticipant;
@property (nonatomic, weak) TVIVideoView *remoteView;
@property (nonatomic, strong) TVIRoom *room;

@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CLLocation *currentLocation;

#pragma mark UI Element Outlets and handles

// `TVIVideoView` created from a storyboard
@property (weak, nonatomic) IBOutlet TVIVideoView *previewView;

@property (nonatomic, weak) IBOutlet UIView *connectButton;
@property (nonatomic, weak) IBOutlet UIButton *disconnectButton;
@property (nonatomic, weak) IBOutlet UILabel *messageLabel;
@property (nonatomic, weak) IBOutlet UITextField *roomTextField;
@property (nonatomic, weak) IBOutlet UIButton *micButton;
@property (nonatomic, weak) IBOutlet UILabel *roomLabel;
@property (nonatomic, weak) IBOutlet UILabel *roomLine;
@property (nonatomic, weak) IBOutlet UIButton *shareLocationButton;
@property (nonatomic, weak) IBOutlet UIActivityIndicatorView *shareLocationActivityIndicator;

@end

@implementation ViewController

#pragma mark - UIViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"QuickStart";
    self.messageLabel.adjustsFontSizeToFitWidth = YES;
    self.messageLabel.minimumScaleFactor = 0.75;

    [self logMessage:[NSString stringWithFormat:@"TwilioVideo v%@", [TwilioVideo version]]];

    // Configure access token manually for testing, if desired! Create one manually in the console
    self.accessToken = @"TWILIO_ACCESS_TOKEN";
    
    // Using the PHP server to provide access tokens? Make sure the tokenURL is pointing to the correct location -
    // the default is http://localhost:8000/token.php
    self.tokenUrl = @"http://localhost:8000/token.php";
    
    // Preview our local camera track in the local video preview view.
    [self startPreview];

    // Disconnect, share location and mic button will be displayed when the Client is connected to a Room.
    self.disconnectButton.hidden = YES;
    self.micButton.hidden = YES;
    self.shareLocationButton.hidden = YES;
    
    self.roomTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.roomTextField.delegate = self;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    [self.view addGestureRecognizer:tap];

    self.locationManager = [CLLocationManager new];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self showRoomUI:(self.room != nil)];
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

- (IBAction)shareLocation:(id)sender {
    [self logMessage:@"Fetching current location..."];

    self.shareLocationButton.enabled = NO;
    [self.shareLocationButton setTitleColor:UIColor.grayColor forState:UIControlStateNormal];
    [self.shareLocationActivityIndicator startAnimating];

    [self.locationManager requestWhenInUseAuthorization];
    self.locationManager.delegate = self;

    if ([self.locationManager respondsToSelector:@selector(requestLocation)]) {
        [self.locationManager requestLocation];
    } else {
        [self.locationManager startUpdatingLocation];
    }
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
    // TVICameraCapturer is not supported with the Simulator.
    if ([PlatformUtils isSimulator]) {
        [self.previewView removeFromSuperview];
        return;
    }
    
    self.camera = [[TVICameraCapturer alloc] initWithSource:TVICameraCaptureSourceFrontCamera delegate:self];
    self.localVideoTrack = [TVILocalVideoTrack trackWithCapturer:self.camera
                                                         enabled:YES
                                                     constraints:nil
                                                            name:@"Camera"];
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

- (void)prepareLocalMedia {
    
    // We will share local audio and video when we connect to room.
    
    // Create an audio track.
    if (!self.localAudioTrack) {
        self.localAudioTrack = [TVILocalAudioTrack trackWithOptions:nil
                                                            enabled:YES
                                                               name:@"Microphone"];

        if (!self.localAudioTrack) {
            [self logMessage:@"Failed to add audio track"];
        }
    }

    // Create a video track which captures from the camera.
    if (!self.localVideoTrack) {
        [self startPreview];
    }

    // Create a data track which will be used to share location information
    if (!self.localDataTrack) {
        self.localDataTrack = [TVILocalDataTrack trackWithOptions:nil name:@"Location"];
    }
}

- (void)doConnect {
    if ([self.accessToken isEqualToString:@"TWILIO_ACCESS_TOKEN"]) {
        [self logMessage:@"Please provide a valid token to connect to a room"];
        return;
    }
    
    // Prepare local media which we will share with Room Participants.
    [self prepareLocalMedia];
    
    TVIConnectOptions *connectOptions = [TVIConnectOptions optionsWithToken:self.accessToken
                                                                      block:^(TVIConnectOptionsBuilder * _Nonnull builder) {

        // Use the local media that we prepared earlier.
        builder.audioTracks = self.localAudioTrack ? @[ self.localAudioTrack ] : @[ ];
        builder.videoTracks = self.localVideoTrack ? @[ self.localVideoTrack ] : @[ ];
        builder.dataTracks = self.localDataTrack ? @[ self.localDataTrack ] : @[ ];

        // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty
        // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
        builder.roomName = self.roomTextField.text;
    }];
    
    // Connect to the Room using the options we provided.
    self.room = [TwilioVideo connectWithOptions:connectOptions delegate:self];
    
    [self logMessage:[NSString stringWithFormat:@"Attempting to connect to room %@", self.roomTextField.text]];
}

- (void)setupRemoteView {
    // Creating `TVIVideoView` programmatically
    TVIVideoView *remoteView = [[TVIVideoView alloc] init];
    
    // `TVIVideoView` supports UIViewContentModeScaleToFill, UIViewContentModeScaleAspectFill and UIViewContentModeScaleAspectFit
    // UIViewContentModeScaleAspectFit is the default mode when you create `TVIVideoView` programmatically.
    self.remoteView.contentMode = UIViewContentModeScaleAspectFit;
    
    [self.view insertSubview:remoteView atIndex:0];
    self.remoteView = remoteView;
    
    NSLayoutConstraint *centerX = [NSLayoutConstraint constraintWithItem:self.remoteView
                                                               attribute:NSLayoutAttributeCenterX
                                                               relatedBy:NSLayoutRelationEqual
                                                                  toItem:self.view
                                                               attribute:NSLayoutAttributeCenterX
                                                              multiplier:1
                                                                constant:0];
    [self.view addConstraint:centerX];
    NSLayoutConstraint *centerY = [NSLayoutConstraint constraintWithItem:self.remoteView
                                                               attribute:NSLayoutAttributeCenterY
                                                               relatedBy:NSLayoutRelationEqual
                                                                  toItem:self.view
                                                               attribute:NSLayoutAttributeCenterY
                                                              multiplier:1
                                                                constant:0];
    [self.view addConstraint:centerY];
    NSLayoutConstraint *width = [NSLayoutConstraint constraintWithItem:self.remoteView
                                                             attribute:NSLayoutAttributeWidth
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:self.view
                                                             attribute:NSLayoutAttributeWidth
                                                            multiplier:1
                                                              constant:0];
    [self.view addConstraint:width];
    NSLayoutConstraint *height = [NSLayoutConstraint constraintWithItem:self.remoteView
                                                              attribute:NSLayoutAttributeHeight
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:self.view
                                                              attribute:NSLayoutAttributeHeight
                                                             multiplier:1
                                                               constant:0];
    [self.view addConstraint:height];
}

// Reset the client ui status
- (void)showRoomUI:(BOOL)inRoom {
    self.roomTextField.hidden = inRoom;
    self.connectButton.hidden = inRoom;
    self.roomLine.hidden = inRoom;
    self.roomLabel.hidden = inRoom;
    self.micButton.hidden = !inRoom;
    self.disconnectButton.hidden = !inRoom;
    self.shareLocationButton.hidden = !inRoom;
    [self.navigationController setNavigationBarHidden:inRoom animated:YES];
    [UIApplication sharedApplication].idleTimerDisabled = inRoom;
}

- (void)dismissKeyboard {
    if (self.roomTextField.isFirstResponder) {
        [self.roomTextField resignFirstResponder];
    }
}

- (void)cleanupRemoteParticipant {
    if (self.remoteParticipant) {
        if ([self.remoteParticipant.videoTracks count] > 0) {
            TVIRemoteVideoTrack *videoTrack = self.remoteParticipant.remoteVideoTracks[0].remoteTrack;
            [videoTrack removeRenderer:self.remoteView];
            [self.remoteView removeFromSuperview];
        }
        self.remoteParticipant = nil;
    }
}

- (void)logMessage:(NSString *)msg {
    NSLog(@"%@", msg);
    self.messageLabel.text = msg;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"mapSegue"]) {
        [self.navigationController setNavigationBarHidden:NO animated:NO];

        UIBarButtonItem *backItem = [UIBarButtonItem new];
        backItem.title = @"Back";
        self.navigationItem.backBarButtonItem = backItem;

        MapViewController *mapViewController = (MapViewController *)segue.destinationViewController;
        mapViewController.identity = self.remoteParticipant.identity;
        mapViewController.location = self.currentLocation;
    }
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
    
    if (room.remoteParticipants.count > 0) {
        self.remoteParticipant = room.remoteParticipants[0];
        self.remoteParticipant.delegate = self;
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

- (void)room:(TVIRoom *)room participantDidConnect:(TVIRemoteParticipant *)participant {
    if (!self.remoteParticipant) {
        self.remoteParticipant = participant;
        self.remoteParticipant.delegate = self;
    }
    [self logMessage:[NSString stringWithFormat:@"Participant %@ connected with %lu audio and %lu video tracks",
                      participant.identity,
                      (unsigned long)[participant.audioTracks count],
                      (unsigned long)[participant.videoTracks count]]];
}

- (void)room:(TVIRoom *)room participantDidDisconnect:(TVIRemoteParticipant *)participant {
    if (self.remoteParticipant == participant) {
        [self cleanupRemoteParticipant];
    }
    [self logMessage:[NSString stringWithFormat:@"Room %@ participant %@ disconnected", room.name, participant.identity]];
}

#pragma mark - TVIRemoteParticipantDelegate

- (void)remoteParticipant:(TVIRemoteParticipant *)participant
      publishedVideoTrack:(TVIRemoteVideoTrackPublication *)publication {
    
    // Remote Participant has offered to share the video Track.

    [self logMessage:[NSString stringWithFormat:@"Participant %@ published %@ video track .",
                      participant.identity, publication.trackName]];
}

- (void)remoteParticipant:(TVIRemoteParticipant *)participant
    unpublishedVideoTrack:(TVIRemoteVideoTrackPublication *)publication {
    
    // Remote Participant has stopped sharing the video Track.
    
    [self logMessage:[NSString stringWithFormat:@"Participant %@ unpublished %@ video track.",
                      participant.identity, publication.trackName]];
}

- (void)remoteParticipant:(TVIRemoteParticipant *)participant
      publishedAudioTrack:(TVIRemoteAudioTrackPublication *)publication {
    
    // Remote Participant has offered to share the audio Track.
    
    [self logMessage:[NSString stringWithFormat:@"Participant %@ published %@ audio track.",
                      participant.identity, publication.trackName]];
}

- (void)remoteParticipant:(TVIRemoteParticipant *)participant
    unpublishedAudioTrack:(TVIRemoteAudioTrackPublication *)publication {
    
    // Remote Participant has stopped sharing the audio Track.
    
    [self logMessage:[NSString stringWithFormat:@"Participant %@ unpublished %@ audio track.",
                      participant.identity, publication.trackName]];
}

- (void)remoteParticipant:(TVIRemoteParticipant *)participant
       publishedDataTrack:(nonnull TVIRemoteDataTrackPublication *)publication {

    // Remote Participant has offered to share the data Track.

    [self logMessage:[NSString stringWithFormat:@"Participant %@ published %@ data track.",
                      participant.identity, publication.trackName]];
}

- (void)remoteParticipant:(TVIRemoteParticipant *)participant
     unpublishedDataTrack:(TVIRemoteDataTrackPublication *)publication {

    // Remote Participant has stopped sharing the data Track.

    [self logMessage:[NSString stringWithFormat:@"Participant %@ unpublished %@ data track.",
                      participant.identity, publication.trackName]];
}

- (void)subscribedToVideoTrack:(TVIRemoteVideoTrack *)videoTrack
                   publication:(TVIRemoteVideoTrackPublication *)publication
                forParticipant:(TVIRemoteParticipant *)participant {
    
    // We are subscribed to the remote Participant's audio Track. We will start receiving the
    // remote Participant's video frames now.
    
    [self logMessage:[NSString stringWithFormat:@"Subscribed to %@ video track for Participant %@",
                      publication.trackName, participant.identity]];
    
    if (self.remoteParticipant == participant) {
        [self setupRemoteView];
        [videoTrack addRenderer:self.remoteView];
    }
}

- (void)unsubscribedFromVideoTrack:(TVIRemoteVideoTrack *)videoTrack
                       publication:(TVIRemoteVideoTrackPublication *)publication
                    forParticipant:(TVIRemoteParticipant *)participant {
    
    // We are unsubscribed from the remote Participant's video Track. We will no longer receive the
    // remote Participant's video.
    
    [self logMessage:[NSString stringWithFormat:@"Unsubscribed from %@ video track for Participant %@",
                      publication.trackName, participant.identity]];
    
    if (self.remoteParticipant == participant) {
        [videoTrack removeRenderer:self.remoteView];
        [self.remoteView removeFromSuperview];
    }
}

- (void)subscribedToAudioTrack:(TVIRemoteAudioTrack *)audioTrack
                   publication:(TVIRemoteAudioTrackPublication *)publication
                forParticipant:(TVIRemoteParticipant *)participant {
    
    // We are subscribed to the remote Participant's audio Track. We will start receiving the
    // remote Participant's audio now.
    
    [self logMessage:[NSString stringWithFormat:@"Subscribed to %@ audio track for Participant %@",
                      publication.trackName, participant.identity]];
}

- (void)unsubscribedFromAudioTrack:(TVIRemoteAudioTrack *)audioTrack
                       publication:(TVIRemoteAudioTrackPublication *)publication
                    forParticipant:(TVIRemoteParticipant *)participant {
    
    // We are unsubscribed from the remote Participant's audio Track. We will no longer receive the
    // remote Participant's audio.
    
    [self logMessage:[NSString stringWithFormat:@"Unsubscribed from %@ audio track for Participant %@",
                      publication.trackName, participant.identity]];
}

- (void)subscribedToDataTrack:(TVIRemoteDataTrack *)dataTrack
                  publication:(TVIRemoteDataTrackPublication *)publication
               forParticipant:(TVIRemoteParticipant *)participant {

    // We are subscribed to the remote Participant's data Track. We will start receiving the
    // remote Participant's data messages now.

    [self logMessage:[NSString stringWithFormat:@"Subscribed to %@ data track for Participant %@",
                      publication.trackName, participant.identity]];

    dataTrack.delegate = self;
}

- (void)unsubscribedFromDataTrack:(TVIRemoteDataTrack *)dataTrack
                      publication:(TVIRemoteDataTrackPublication *)publication
                   forParticipant:(TVIRemoteParticipant *)participant {

    // We are unsubscribed from the remote Participant's data Track. We will no longer receive the
    // remote Participant's data messages.

    [self logMessage:[NSString stringWithFormat:@"Unsubscribed from %@ data track for Participant %@",
                      publication.trackName, participant.identity]];
}

- (void)remoteParticipant:(TVIRemoteParticipant *)participant
        enabledVideoTrack:(TVIRemoteVideoTrackPublication *)publication {
    [self logMessage:[NSString stringWithFormat:@"Participant %@ enabled %@ video track.",
                      participant.identity, publication.trackName]];
}

- (void)remoteParticipant:(TVIRemoteParticipant *)participant
       disabledVideoTrack:(TVIRemoteVideoTrackPublication *)publication {
    [self logMessage:[NSString stringWithFormat:@"Participant %@ disabled %@ video track.",
                      participant.identity, publication.trackName]];
}

- (void)remoteParticipant:(TVIRemoteParticipant *)participant
        enabledAudioTrack:(TVIRemoteAudioTrackPublication *)publication {
    [self logMessage:[NSString stringWithFormat:@"Participant %@ enabled %@ audio track.",
                      participant.identity, publication.trackName]];
}

- (void)remoteParticipant:(TVIRemoteParticipant *)participant
       disabledAudioTrack:(TVIRemoteAudioTrackPublication *)publication {
    [self logMessage:[NSString stringWithFormat:@"Participant %@ disabled %@ audio track.",
                      participant.identity, publication.trackName]];
}

#pragma mark - TVIRemoteDataTrackDelegate

- (void)remoteDataTrack:(TVIRemoteDataTrack *)remoteDataTrack didReceiveData:(NSData *)message {
    CLLocation *location = [NSKeyedUnarchiver unarchiveObjectWithData:message];

    if (location != nil) {
        self.currentLocation = location;

        NSString *alertMessage = [NSString stringWithFormat:@"%@ has shared their location. Would you like to display it?", self.remoteParticipant.identity];
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Show Location"
                                                                                 message:alertMessage
                                                                          preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *yesAction = [UIAlertAction actionWithTitle:@"Yes"
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * _Nonnull action) {
                                                              [self performSegueWithIdentifier:@"mapSegue" sender:self];
                                                          }];

        UIAlertAction *noAction = [UIAlertAction actionWithTitle:@"No"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];

        [alertController addAction:yesAction];
        [alertController addAction:noAction];
        [self presentViewController:alertController animated:YES completion:nil];
    } else {
        [self logMessage:@"Received invalid data track payload"];
    }
}

#pragma mark - TVIVideoViewDelegate

- (void)videoView:(TVIVideoView *)view videoDimensionsDidChange:(CMVideoDimensions)dimensions {
    NSLog(@"Dimensions changed to: %d x %d", dimensions.width, dimensions.height);
    [self.view setNeedsLayout];
}

#pragma mark - TVICameraCapturerDelegate

- (void)cameraCapturer:(TVICameraCapturer *)capturer didStartWithSource:(TVICameraCaptureSource)source {
    self.previewView.mirror = (source == TVICameraCaptureSourceFrontCamera);
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    self.shareLocationButton.enabled = YES;
    [self.shareLocationButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.shareLocationActivityIndicator stopAnimating];
    [self logMessage:@"Unable to fetch location"];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    self.shareLocationButton.enabled = YES;
    [self.shareLocationButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.shareLocationActivityIndicator stopAnimating];
    [manager stopUpdatingLocation];

    CLLocation *location = [locations firstObject];

    if (location != nil) {
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:location];
        [self.localDataTrack sendData:data];
    } else {
        [self logMessage:@"No location received"];
    }
}

@end
