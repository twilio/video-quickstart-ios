//
//  ConversationViewController.swift
//  video-quickstart-swift
//
//  Created by Siraj Raval on 12/15/15.
//  Copyright © 2015 Twilio. All rights reserved.
//

import UIKit

class ConversationViewController: UIViewController, TWCLocalMediaDelegate, TWCVideoTrackDelegate, TWCParticipantDelegate, TWCConversationDelegate {
    var localMedia: TWCLocalMedia? = nil;
    var camera: TWCCameraCapturer? = nil;
    var conversation: TWCConversation? = nil;
    var incomingInvite: TWCIncomingInvite? = nil;
    var outgoingInvite: TWCOutgoingInvite? = nil;
    var client: TwilioConversationsClient? = nil;
    var inviteeIdentity: String? = nil;

    @IBOutlet weak var remoteVideo: UIView!
    @IBOutlet weak var localVideo: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NSLog("Conversation started!");
        self.localMedia = TWCLocalMedia(delegate: self);
        self.camera = self.localMedia?.addCameraTrack();
        if((self.camera) != nil) {
            self.camera?.videoTrack?.attach(localVideo)
            self.camera?.videoTrack?.delegate = self;
        }
    }
    
    override func viewDidAppear(animated: Bool) {
        if(self.incomingInvite != nil) {
            self.incomingInvite?.acceptWithLocalMedia((self.localMedia)!, completion: self.acceptHandler());
        } else {
            NSLog("you invited %@", self.inviteeIdentity!);
            self.sendConversationInvite();
        }
    }

    func acceptHandler() -> TWCInviteAcceptanceBlock {
        return { (conversation: TWCConversation?, error: NSError?) in
            if let conversation = conversation {
                conversation.delegate = self;
                self.conversation = conversation
                print("Yay")
            } else {
                print("Boo")
            }
        }
    }
    
    func sendConversationInvite() {
        if(self.client != nil) {
            self.outgoingInvite = self.client?.inviteToConversation(self.inviteeIdentity!, localMedia: self.localMedia!, handler: self.acceptHandler());
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    //TWCLocalMediaDelegate
    func localMedia(media: TWCLocalMedia, didAddVideoTrack videoTrack: TWCVideoTrack) {
        NSLog("Tracked added");
    }
    
    //participant delegate
    func participant(participant: TWCParticipant, addedVideoTrack videoTrack: TWCVideoTrack) {
        NSLog("Video added for participant: %@", participant.identity);
        videoTrack.attach(remoteVideo);
        videoTrack.delegate = self;
    }
    
    func conversation(conversation: TWCConversation, didConnectParticipant participant: TWCParticipant) {
        NSLog("Participant connected: %@", participant.identity);
        participant.delegate = self;
    }

    @IBAction func flipCameraButtonPressed(sender: AnyObject) {
        NSLog("flip camera");
        self.camera?.flipCamera();
    }
    @IBAction func pauseButtonPressed(sender: AnyObject) {
        if(self.camera?.videoTrack?.enabled == true) {
            self.camera?.videoTrack?.enabled = false;
        } else {
            self.camera?.videoTrack?.enabled = true;
        }
        NSLog("pause");
    }
    
    @IBAction func muteButtonPressed(sender: AnyObject) {
        if(self.conversation?.localMedia?.microphoneMuted == true) {
            self.conversation?.localMedia?.microphoneMuted = false;
        } else {
            self.conversation?.localMedia?.microphoneMuted = true;
        }
        NSLog("mute");
    }
    
    @IBAction func hangupButtonPressed(sender: AnyObject) {
        self.conversation?.disconnect();
        self.incomingInvite?.reject();
        NSLog("hangup");
    }
}
