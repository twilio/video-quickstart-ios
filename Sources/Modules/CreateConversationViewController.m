//
//  CreateConversationViewController.m
//  Twilio Video - Conversations Quickstart
//

#import "CreateConversationViewController.h"

#import "AppDelegate.h"
#import "ConversationViewController.h"
#import <TwilioConversationsClient/TwilioConversationsClient.h>
#import <TwilioCommon/TwilioCommon.h>

@interface CreateConversationViewController () <TwilioConversationsClientDelegate, TWCConversationDelegate, TwilioAccessManagerDelegate, UIAlertViewDelegate>

@property (weak, nonatomic) IBOutlet UILabel *listeningStatusLabel;
@property (weak, nonatomic) IBOutlet UILabel *inviteeLabel;
@property (weak, nonatomic) IBOutlet UITextField *inviteeIdentityField;
@property (weak, nonatomic) IBOutlet UIButton *createConversationButton;
@property (weak, nonatomic) UIAlertView *incomingAlert;

@property (nonatomic) TwilioConversationsClient *conversationsClient;
@property (nonatomic) TWCIncomingInvite *incomingInvite;

@property (nonatomic, strong) TwilioAccessManager *accessManager;

@end

@implementation CreateConversationViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.inviteeIdentityField addTarget:self.inviteeIdentityField
                               action:@selector(resignFirstResponder)
                               forControlEvents:UIControlEventEditingDidEndOnExit|UIControlEventEditingDidEnd];
    
    [self listenForInvites];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void)listenForInvites {
    /* TWCLogLevelOff, TWCLogLevelFatal, TWCLogLevelError, TWCLogLevelWarning, TWCLogLevelInfo, TWCLogLevelDebug, TWCLogLevelTrace, TWCLogLevelAll  */
    [TwilioConversationsClient setLogLevel:TWCLogLevelWarning];
    
    self.listeningStatusLabel.text = @"Attempting to listen for Invites...";
    if (!self.conversationsClient) {
        
#error You must provide a Twilio AccessToken to connect to the Conversations service
        // OPTION 1- Generate an access token from the quickstart portal https://www.twilio.com/user/account/video/getting-started
        NSString *accessToken = @"TWILIO_ACCESS_TOKEN";
        self.accessManager = [TwilioAccessManager accessManagerWithToken:accessToken delegate:self];
        self.conversationsClient = [TwilioConversationsClient conversationsClientWithAccessManager:self.accessManager
                                                                                          delegate:self];
        [self.conversationsClient listen];
        
        // OPTION 2- Retrieve an access token from your own web app
        //[self retrieveAccessTokenfromServer];
    }
}

-(void) retrieveAccessTokenfromServer {
    NSString *identifierForVendor = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    NSString *tokenEndpoint = @"http://localhost:8000/token.php?device=%@";
    NSString *urlString = [NSString stringWithFormat:tokenEndpoint, identifierForVendor];
    // Make JSON request to server
    NSData *jsonResponse = [NSData dataWithContentsOfURL:[NSURL URLWithString:urlString]];
    if (jsonResponse) {
        NSError *jsonError;
        NSDictionary *tokenResponse = [NSJSONSerialization JSONObjectWithData:jsonResponse
                                                                      options:kNilOptions
                                                                        error:&jsonError];
        // Handle response from server
        if (!jsonError) {
            self.accessManager = [TwilioAccessManager accessManagerWithToken:tokenResponse[@"token"] delegate:self];
            self.conversationsClient = [TwilioConversationsClient conversationsClientWithAccessManager:self.accessManager
                                                                                              delegate:self];
            [self.conversationsClient listen];
        }
    }
}

#pragma mark - UI Actions & Segues
- (IBAction)createConversationButtonClicked:(id)sender {
    if (self.inviteeIdentityField.text.length > 0) {
        [self.inviteeIdentityField resignFirstResponder];

        /* Present the conversation ViewController and initiate the Conversation once the view appears */
        [self performSegueWithIdentifier:@"TSQSegueStartConversation" sender:self];
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"TSQSegueStartConversation"]) {
        ConversationViewController *conversationVC = (ConversationViewController *)segue.destinationViewController;
        conversationVC.inviteeIdentity = self.inviteeIdentityField.text;
        conversationVC.client = self.conversationsClient;
    }
    else if ([segue.identifier isEqualToString:@"TSQSegueAcceptInvite"]) {
        ConversationViewController *conversationVC = (ConversationViewController *)segue.destinationViewController;
        conversationVC.incomingInvite = self.incomingInvite;
        conversationVC.client = self.conversationsClient;
    }
}

#pragma mark - UIAlertViewDelegate
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 0) {
        /* Reject, do nothing */
        [self.incomingInvite reject];
    }
    else {
        /* Accept, present the Conversation ViewController and accept the Invite when it is shown */
        [self performSegueWithIdentifier:@"TSQSegueAcceptInvite" sender:self];
    }

    self.incomingInvite = nil;
}

#pragma mark - TwilioConversationsClientDelegate
/* This method is invoked when an attempt to connect to Twilio and listen for Converation invites has succeeded */
- (void)conversationsClientDidStartListeningForInvites:(TwilioConversationsClient *)conversationsClient {
    NSLog(@"Now listening for Conversation invites...");
    
    self.listeningStatusLabel.text = @"Listening for Invites";

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.listeningStatusLabel.hidden = YES;
        self.inviteeLabel.hidden = NO;
        self.inviteeIdentityField.hidden = NO;
        self.createConversationButton.hidden = NO;
    });
}

/* This method is invoked when an attempt to connect to Twilio and listen for Converation invites has failed */
- (void)conversationsClient:(TwilioConversationsClient *)conversationsClient didFailToStartListeningWithError:(NSError *)error {
    NSLog(@"Failed to listen for Conversation invites: %@", error);

    self.listeningStatusLabel.text = @"Failed to start listening for Invites";
}

/* This method is invoked when the SDK stops listening for Conversations invites */
- (void)conversationsClientDidStopListeningForInvites:(TwilioConversationsClient *)conversationsClient error:(NSError *)error {
    if (!error) {
        NSLog(@"Successfully stopped listening for Conversation invites");
        self.conversationsClient = nil;
    } else {
        NSLog(@"Stopped listening for Conversation invites (error): %ld", (long)error.code);
    }
}

/* This method is invoked when an incoming Conversation invite is received */
- (void)conversationsClient:(TwilioConversationsClient *)conversationsClient didReceiveInvite:(TWCIncomingInvite *)invite {
    NSLog(@"Conversations invite received: %@", invite);

    /* 
     In this example we don't allow you to accept an invite while:
        1. A conversation is already in progress.
        2. Another invite is already being presented to the user.
     If you wish to accept an invite during a conversation, end the active conversation first and then accept the new invite.
     */

    if (self.incomingInvite || self.navigationController.visibleViewController != self) {
        [invite reject];
        return;
    }

    self.incomingInvite = invite;

    NSString *incomingFrom = [NSString stringWithFormat:@"Incoming invite from %@", invite.from];
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:nil
                                                        message:incomingFrom
                                                       delegate:self
                                              cancelButtonTitle:@"Reject"
                                              otherButtonTitles:@"Accept", nil];
    [alertView show];
    self.incomingAlert = alertView;
}

- (void)conversationsClient:(TwilioConversationsClient *)conversationsClient inviteDidCancel:(TWCIncomingInvite *)invite
{
    [self.incomingAlert dismissWithClickedButtonIndex:0 animated:YES];
    self.incomingInvite = nil;
}

#pragma mark -  TwilioAccessManagerDelegate

- (void)accessManagerTokenExpired:(TwilioAccessManager *)accessManager {
    NSLog(@"Token expired. Please update access manager with new token.");
}

- (void)accessManager:(TwilioAccessManager *)accessManager error:(NSError *)error {
    NSLog(@"AccessManager encountered an error : %ld", (long)error.code);
}

@end
