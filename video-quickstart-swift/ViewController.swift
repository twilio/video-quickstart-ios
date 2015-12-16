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
        //OPTION 1- Paste access token from the quickstart https://www.twilio.com/user/account/video/getting-started
        let accessToken = "TWILIO_ACCESS_TOKEN";
        self.accessManager = TwilioAccessManager(token:accessToken, delegate:self);
        self.client = TwilioConversationsClient(accessManager: self.accessManager!, delegate: self);
        self.client?.listen();
        NSLog("The client identity is %@", (self.client?.identity)!);
        
        //OPTION 2- Retrieve access token from your own web app
        //self.retrieveAccessTokenfromServer();
        
    }
    
    func retrieveAccessTokenfromServer() {
        // Fetch Access Token form the server and initialize IPM Client - this assumes you are running
        // the PHP starter app on your local machine, as instructed in the quick start guide
        let deviceId = UIDevice.currentDevice().identifierForVendor!.UUIDString
        let urlString = "http://localhost:8000/token.php?device=\(deviceId)"
        
        // Get JSON from server
        let config = NSURLSessionConfiguration.defaultSessionConfiguration()
        let session = NSURLSession(configuration: config, delegate: nil, delegateQueue: nil)
        let url = NSURL(string: urlString)
        let request  = NSMutableURLRequest(URL: url!)
        request.HTTPMethod = "GET"
        
        // Make HTTP request
        session.dataTaskWithRequest(request, completionHandler: { data, response, error in
            if (data != nil) {
                // Parse result JSON
                let json = JSON(data: data!)
                let token = json["token"].stringValue
                // Set up Twilio Conversations client
                self.accessManager = TwilioAccessManager(token:token, delegate:self);
                self.client = TwilioConversationsClient(accessManager: self.accessManager!, delegate: self);
                self.client?.listen();
                // Update UI on main thread
                dispatch_async(dispatch_get_main_queue()) {
                    print("Successfully fetched token :\(error)")
                }
            } else {
                print("Error fetching token :\(error)")
            }
        }).resume()
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

