//
//  ConversationViewController.h
//  Twilio Video - Conversations Quickstart
//

#import <UIKit/UIKit.h>

@class TWCIncomingInvite;
@class TwilioConversationsClient;

@interface ConversationViewController : UIViewController

@property (nonatomic, strong) NSString *inviteeIdentity;
@property (nonatomic, strong) TWCIncomingInvite *incomingInvite;
@property (nonatomic, strong) TwilioConversationsClient *client;

@end
