//
//  ConversationViewController.m
//  Twilio Video Conversations Quickstart - Objective C


#import "ConversationViewController.h"

#import <TwilioCommon/TwilioCommon.h>
#import <TwilioConversationsClient/TwilioConversationsClient.h>


@interface ConversationViewController ()<TWCConversationDelegate, TWCParticipantDelegate, TWCLocalMediaDelegate, TWCVideoTrackDelegate, TwilioAccessManagerDelegate, TwilioConversationsClientDelegate>

@property (nonatomic, strong) TwilioAccessManager *accessManager;
@property (nonatomic, strong) TwilioConversationsClient *conversationsClient;
@property (nonatomic, strong) TWCLocalMedia *localMedia;
@property (nonatomic, strong) TWCConversation *conversation;
@property (nonatomic, strong) TWCCameraCapturer *camera;


@property (weak, nonatomic) IBOutlet UIView *localMediaView;
@property (weak, nonatomic) IBOutlet UIView *remoteMediaView;
@property (weak, nonatomic) IBOutlet UIButton *hangUpButton;
@property (weak, nonatomic) IBOutlet UILabel *statusLabel;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *inviteBarButtonItem;

@end

@implementation ConversationViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  // Do any additional setup after loading the view.
  
  NSString *accessToken = @"TWILIO_ACCESS_TOKEN";
  NSURL *tokenURL = [NSURL URLWithString:@"http://localhost:8000/token.php"];
  
  /**
   * Providing your own access token? Replace TWILIO_ACCESS_TOKEN
   * above this with your token.
   */
  
  [self initializeClientWithAccessToken:accessToken];
  
  /**
   * Using the PHP server to provide access tokens? Make sure the tokenURL is
   * pointing to the correct location - the default is
   * http://localhost:8000/token.php
   *
   * Uncomment out the following line of code:
   */
  //[self retrieveAccessTokenFromURL:tokenURL];
  
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
      
      //initialize the Twilio Conversations Client on the main thread
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
  self.accessManager = [TwilioAccessManager accessManagerWithToken:accessToken delegate:self];
  self.conversationsClient = [TwilioConversationsClient conversationsClientWithAccessManager:self.accessManager delegate:self];
  [self.conversationsClient listen];
  [self startPreview];
  
}

- (void) startPreview {
  self.localMedia = [[TWCLocalMedia alloc] initWithDelegate:self];
  
#if !TARGET_IPHONE_SIMULATOR
  /* Microphone is enabled by default, to enable Camera, we first create a Camera capturer */
  self.camera = [self.localMedia addCameraTrack];
#else
  //disable camera controls if on the simulator
  
#endif
  
  if (self.camera) {
    [self.camera.videoTrack attach:self.localMediaView];
    self.camera.videoTrack.delegate = self;
    
    [self.camera startPreview];
    [self.localMediaView addSubview:self.camera.previewView];
    self.camera.previewView.frame = self.localMediaView.bounds;
    self.camera.previewView.contentMode = UIViewContentModeScaleAspectFit;
    self.camera.previewView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
  }
  
  /* For this demonstration, we just use the default audio output. */
  [TwilioConversationsClient setAudioOutput:TWCAudioOutputDefault];
}

#pragma mark - Invite a User

- (void) inviteAUser:(NSString*)identity {
  [self.conversationsClient inviteToConversation:identity localMedia:self.localMedia handler:^(TWCConversation * _Nullable conversation, NSError * _Nullable error) {
    if (conversation != nil) {
      self.conversation = conversation;
      self.conversation.delegate = self;
    } else {
      NSString *errorMessage = [NSString stringWithFormat:@"Error inviting user(%@): %@", identity, [error localizedDescription]];
      [self displayErrorMessage:errorMessage];
      NSLog(@"%@",errorMessage);
    }
    
  }];
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
  [self.conversation disconnect];
}

- (IBAction)invite:(id)sender {
  UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Invite" message:@"Invite one of your friends!" preferredStyle:UIAlertControllerStyleAlert];
  [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
    textField.placeholder = @"Identity";
  }];
  UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
    UITextField *identityTextField = alertController.textFields.firstObject;
    //invite the user to the conversation
    if ([identityTextField.text length] > 0) {
      [self inviteAUser:identityTextField.text];
    }
  }];
  [alertController addAction:okAction];
  [self presentViewController:alertController animated:true completion:nil];
}


#pragma mark - TwilioAccessManagerDelegate methods

- (void) accessManagerTokenExpired:(TwilioAccessManager *)accessManager {
  [self displayErrorMessage:@"Twilio Access Manager Token has expired."];
  NSLog(@"Twilio Access Manager Token has expired.");
}

- (void) accessManager:(TwilioAccessManager *)accessManager error:(NSError *)error {
  NSString *errorMessage = [NSString stringWithFormat:@"Twilio Access Manager Error: %@",[error localizedDescription]];
  [self displayErrorMessage:errorMessage];
  NSLog(@"%@",errorMessage);
}

#pragma mark - TwilioConversationsClientDelegate methods

- (void)conversationsClient:(TwilioConversationsClient *)conversationsClient didReceiveInvite:(TWCIncomingInvite *)invite {
  
  //automatically accept any invitations to chat - let's be sociable!
  [invite acceptWithLocalMedia:self.localMedia completion:^(TWCConversation * _Nullable conversation, NSError * _Nullable error) {
    self.conversation = conversation;
    self.conversation.delegate = self;
  }];
  
}

- (void)conversationsClient:(TwilioConversationsClient *)conversationsClient didFailToStartListeningWithError:(NSError *)error {
  NSString *errorMessage = [NSString stringWithFormat:@"Twilio Conversations Client did fail to start listening - Error: %@",[error localizedDescription]];
  [self displayErrorMessage:errorMessage];
  NSLog(@"%@",errorMessage);
  
}

#pragma mark - TWCLocalMediaDelegate methods

- (void)localMedia:(TWCLocalMedia *)media didAddVideoTrack:(TWCVideoTrack *)videoTrack {
  NSLog(@"Added local video track");
}

#pragma mark - TWCConversationDelegate methods

- (void)conversation:(TWCConversation *)conversation didConnectParticipant:(TWCParticipant *)participant {
  self.statusLabel.text = [NSString stringWithFormat:@"Connected to: %@",participant.identity];
  participant.delegate = self;
  self.hangUpButton.enabled = YES;
}

- (void)conversation:(TWCConversation *)conversation didDisconnectParticipant:(TWCParticipant *)participant {
  self.statusLabel.text = [NSString stringWithFormat:@"Disconnected from: %@",participant.identity];
  self.hangUpButton.enabled = NO;
}

- (void)conversationEnded:(TWCConversation *)conversation {
  self.statusLabel.text = @"Conversation Ended";
  self.hangUpButton.enabled = NO;
}

#pragma mark - TWCParticipantDelegate methods

- (void)participant:(TWCParticipant *)participant addedVideoTrack:(TWCVideoTrack *)videoTrack {
  [videoTrack attach:self.remoteMediaView];
  videoTrack.delegate = self;
  
}

- (void)participant:(TWCParticipant *)participant removedVideoTrack:(TWCVideoTrack *)videoTrack {
  
}

#pragma mark - TWCVideoTrackDelegate methods

- (void)videoTrack:(TWCVideoTrack *)track dimensionsDidChange:(CMVideoDimensions)dimensions
{
  NSLog(@"Dimensions changed to: %d x %d", dimensions.width, dimensions.height);
  
  [self.view setNeedsUpdateConstraints];
}

@end
