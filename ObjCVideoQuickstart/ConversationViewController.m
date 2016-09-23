//
//  ConversationViewController.m
//  Twilio Video Conversations Quickstart - Objective C


#import "ConversationViewController.h"

#import <TwilioVideo/TwilioVideo.h>


@interface ConversationViewController ()<TVIParticipantDelegate, TVIRoomDelegate,
TVICameraCapturerDelegate, TVIVideoTrackDelegate>

#pragma mark Video SDK components
@property (nonatomic, strong) TVIVideoClient *videoClient;
@property (nonatomic, strong) TVIRoom *room;
@property (nonatomic, strong) TVICameraCapturer *cameraCapturer;
@property (nonatomic, strong) TVILocalVideoTrack *localVideoTrack;

#pragma mark UI Element Outlets and handles
@property (weak, nonatomic) IBOutlet UIView *localMediaView;
@property (weak, nonatomic) IBOutlet UIView *remoteMediaView;
@property (weak, nonatomic) IBOutlet UIButton *hangUpButton;
@property (weak, nonatomic) IBOutlet UILabel *statusLabel;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *joinRoomBarButtonItem;

@end

@implementation ConversationViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    NSString *accessToken = @"TWILIO_ACCESS_TOKEN";
    NSURL *tokenURL = [NSURL URLWithString:@"https://7d97b86f.ngrok.io/token"];
    
    /**
     * Providing your own access token? Replace TWILIO_ACCESS_TOKEN
     * above this with your token.
     */
    
    //[self initializeClientWithAccessToken:accessToken];
    
    /**
     * Using the PHP server to provide access tokens? Make sure the tokenURL is
     * pointing to the correct location - the default is
     * http://localhost:8000/token.php
     *
     * Uncomment out the following line of code:
     */
    [self retrieveAccessTokenFromURL:tokenURL];
    
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Quickstart Initialization methods

- (void) retrieveAccessTokenFromURL:(NSURL*)tokenURL {
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];
    NSURLSessionDataTask *task = [session dataTaskWithURL:tokenURL completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (data != nil) {
            NSError *JSONError;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&JSONError];
            
            NSString *token = json[@"token"];
            NSString *identity = json[@"identity"];
            NSLog(@"Logged in as %@",identity);
            
            //initialize the Twilio Video Client on the main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                self.navigationItem.title = identity;
                
                [self initializeClientWithAccessToken:token];
            });
            
        } else {
            NSString *errorMessage = [NSString stringWithFormat:@"Error retrieving access token: %@",[error localizedDescription]];
            [self displayErrorMessage:errorMessage];
            NSLog(@"%@",errorMessage);
        }
    }];
    [task resume];
    
}

- (void)initializeClientWithAccessToken:(NSString*)accessToken {
    self.videoClient = [TVIVideoClient clientWithToken:accessToken];
#if !TARGET_IPHONE_SIMULATOR
    [self startPreview];
#endif
    
}

- (void) startPreview {
    self.cameraCapturer = [[TVICameraCapturer alloc] initWithDelegate:self source:TVIVideoCaptureSourceFrontCamera];
}

#pragma mark - Display an Error

- (void) displayErrorMessage:(NSString*)errorMessage {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Error" message:errorMessage preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alertController addAction:okAction];
    [self presentViewController:alertController animated:YES completion:nil];
}


#pragma mark - Interface Builder Actions

- (IBAction)hangUp:(id)sender {
    [self.room disconnect];
}

- (IBAction)joinRoom:(id)sender {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Join Room" message:@"Enter the name of the room you would like to connect to" preferredStyle:UIAlertControllerStyleAlert];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Room Name";
    }];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UITextField *roomNameTextField = alertController.textFields.firstObject;
        //join the room
        if ([roomNameTextField.text length] > 0) {
            NSString *roomName = roomNameTextField.text;
            TVIConnectOptions *connectOptions = [TVIConnectOptions optionsWithBlock:^(TVIConnectOptionsBuilder * _Nonnull builder) {
                builder.name = roomName;
            }];
            
            self.room = [self.videoClient connectWithOptions:connectOptions delegate:self];
            self.cameraCapturer.delegate = self;
            
        }
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [alertController addAction:okAction];
    [alertController addAction:cancelAction];
    [self presentViewController:alertController animated:true completion:nil];
}


#pragma mark - TVICameraCapturerDelegate methods
- (void)cameraCapturer:(TVICameraCapturer *)capturer didStartWithSource:(TVIVideoCaptureSource)source {
    NSLog(@"%@",@"Did start camera capture with source");
}

- (void)cameraCapturer:(TVICameraCapturer *)capturer didStopRunningWithError:(NSError *)error {
    NSLog(@"%@",@"Camera capturer did stop running");
}

- (void)cameraCapturerWasInterrupted:(TVICameraCapturer *)capturer {
    NSLog(@"%@",@"Camera Capturer was interrupted");
}

- (void)cameraCapturerPreviewDidStart:(TVICameraCapturer *)capturer {
    NSLog(@"%@",@"Camera Capturer preview did start");
}

#pragma mark - TVIRoomDelegate methods

- (void)didConnectToRoom:(TVIRoom *)room {
    self.localVideoTrack = [room.localParticipant.media addVideoTrack:true capturer:self.cameraCapturer];
    self.localVideoTrack.delegate = self;
    [self.localVideoTrack attach:self.localMediaView];
}

- (void)room:(TVIRoom *)room participantDidConnect:(TVIParticipant *)participant {
    NSLog(@"Participant did connect:%@",participant.identity);
    participant.delegate = self;
}

- (void)room:(TVIRoom *)room participantDidDisconnect:(TVIParticipant *)participant {
    NSLog(@"Participant did disconnect:%@",participant.identity);
}

- (void)room:(TVIRoom *)room didDisconnectWithError:(NSError *)error {
    NSLog(@"%@",@"Did disconnect from room");
}

- (void)room:(TVIRoom *)room didFailToConnectWithError:(NSError *)error {
    NSLog(@"Did fail to connect with error: %@",error.localizedDescription);
}

#pragma mark - TVIParticipantDelegate methods
- (void)participant:(TVIParticipant *)participant addedVideoTrack:(TVIVideoTrack *)videoTrack {
    NSLog(@"Participant %@ added a video track",participant.identity);
    videoTrack.delegate = self;
    [videoTrack attach:self.remoteMediaView];
}

- (void)participant:(TVIParticipant *)participant removedVideoTrack:(TVIVideoTrack *)videoTrack {
    NSLog(@"Participant %@ removed a video track",participant.identity);
    [videoTrack detach:self.remoteMediaView];
}

#pragma mark - TVIVideoTrackDelegate methods
- (void)videoTrack:(TVIVideoTrack *)track dimensionsDidChange:(CMVideoDimensions)dimensions {
    NSLog(@"Dimensions changed to: %d x %d", dimensions.width, dimensions.height);
    [self.view setNeedsUpdateConstraints];
    
}


@end
