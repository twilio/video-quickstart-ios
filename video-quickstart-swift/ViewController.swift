//
//  ViewController.swift
//  video-quickstart-swift
//
//  Created by Siraj Raval on 12/14/15.
//  Copyright © 2015 Twilio. All rights reserved.
//

import UIKit


class ViewController: UIViewController, TwilioAccessManagerDelegate, TwilioConversationsClientDelegate {
    
    @IBOutlet weak var inviteTextField: UITextField!
    @IBOutlet weak var inviteButton: UIButton!
    
    var client: TwilioConversationsClient? = nil;
    var accessManager: TwilioAccessManager? = nil;
    var incomingInvite: TWCIncomingInvite? = nil;

    override func viewDidLoad() {
        super.viewDidLoad()
        initializeClient();
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func didTapInvite(sender: UIButton!) {
        if(inviteTextField.text  != "") {
            NSLog("Button tapped %@", inviteTextField.text!);
        }
        
        let secondViewController = self.storyboard!.instantiateViewControllerWithIdentifier("ConversationViewController") as! ConversationViewController;

        secondViewController.inviteeIdentity = inviteTextField.text;
        secondViewController.client = self.client;
        self.presentViewController(secondViewController, animated: true, completion: nil);
    }
    
    func initializeClient() {
        let accessToken = "TWILIO_ACCESS_TOKEN";
        self.accessManager = TwilioAccessManager(token:accessToken, delegate:self);
        self.client = TwilioConversationsClient(accessManager: self.accessManager!, delegate: self);
        self.client?.listen();
        NSLog("The client identity is %@", (self.client?.identity)!);
    }
    
    //Access manager delegate
    func accessManager(accessManager: TwilioAccessManager!, error: NSError!) {
        NSLog("Access Manager");
    }
    
    func accessManagerTokenExpired(accessManager: TwilioAccessManager!) {
        NSLog("Token expired");
    }
    
    //Conversation client delegate
    func conversationsClient(conversationsClient: TwilioConversationsClient, didFailToStartListeningWithError error: NSError) {
        NSLog("Failed to listen");
    }
    
    func conversationsClient(conversationsClient: TwilioConversationsClient, inviteDidCancel invite: TWCIncomingInvite) {
        NSLog("Invite cancelled");
    }
    
    func conversationsClient(conversationsClient: TwilioConversationsClient, didReceiveInvite invite: TWCIncomingInvite) {
        NSLog("You received an invite from %@", invite.from);
        self.incomingInvite = invite;
        let secondViewController = self.storyboard!.instantiateViewControllerWithIdentifier("ConversationViewController") as! ConversationViewController
        
            secondViewController.incomingInvite = invite;
            secondViewController.client = self.client;
        self.presentViewController(secondViewController, animated: true, completion: nil);
    }
    
    func conversationsClientDidStartListeningForInvites(conversationsClient: TwilioConversationsClient) {
        NSLog("Listening for invites");
    }
    
    func conversationsClientDidStopListeningForInvites(conversationsClient: TwilioConversationsClient, error: NSError?) {
        NSLog("Stopped listening for invites");
    }

}

