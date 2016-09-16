//
//  ViewController.swift
//  VideoQuickStart
//
//  Created by Piyush Tank on 9/15/16.
//  Copyright © 2016 Twilio. All rights reserved.
//

import UIKit

import TwilioVideo

class ViewController: UIViewController, UITextFieldDelegate {

    // MARK: View Controller Members
    
    // Configure access token manually for testing, if desired! Create one manually in the console
    // at https://www.twilio.com/user/account/video/dev-tools/testing-tools
    var accessToken = "TWILIO_ACCESS_TOKEN"
  
    // Configure remote URL to fetch token from
    var tokenUrl = "http://localhost:8000/token.php"
    
    // Video SDK components
    var client: TVIVideoClient?
    var room: TVIRoom?
    var localMedia: TVILocalMedia?
    var camera: TVICameraCapturer?
    var localVideoTrack: TVILocalVideoTrack?
    var localAudioTrack: TVILocalAudioTrack?
    var participant: TVIParticipant?
    
    // MARK: UI Element Outlets and handles
    @IBOutlet weak var remoteView: UIView!
    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var roomTextField: UITextField!
    @IBOutlet weak var roomLine: UIView!
    @IBOutlet weak var roomLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()

        // LocalMedia represents the collection of tracks that we are sending to other Participants from our VideoClient.
        localMedia = TVILocalMedia()
        
        // Preview our local camera track in the local video preview view.
        self.startPreview()
        
        // Disconnect button will be displayed when client is connected to a room.
        self.disconnectButton.isHidden = true
        
        self.roomTextField.delegate = self;
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(ViewController.dismissKeyboard))
        self.view.addGestureRecognizer(tap)
    }
    
    func startPreview() {
        if PlatformUtils.isSimulator {
            return;
        }
        
        // Preview our local camera track in the local video preview view.
        camera = TVICameraCapturer()
        localVideoTrack = localMedia?.addVideoTrack(true, capturer: camera!)
        if (localVideoTrack == nil) {
            messageLabel.text = "Failed to add video track"
        } else {
            // Attach view to video track for local preview
            localVideoTrack!.attach(self.previewView)
            
            messageLabel.text = "Video track added to localMedia"
            
            // We will flip camera on tap.
            let tap = UITapGestureRecognizer(target: self, action: #selector(ViewController.flipCamera))
            self.previewView.addGestureRecognizer(tap)
        }
    }
    
    func flipCamera() {
        self.camera?.flipCamera()
    }
    
    func prepareLocalMedia() {
        
        // We will offer local audio and video when we connect to room.
        
        // Adding local audio track to localMedia
        localAudioTrack = localMedia?.addAudioTrack(true)
        
        // Adding local video track to localMedia and starting local preview if it is not already started.
        if (localMedia?.videoTracks.count == 0) {
            self.startPreview()
        }
    }
    
    @IBAction func connect(sender: AnyObject) {
        // Configure access token either from server or manually.
        // If the default wasn't changed, try fetching from server.
        if (accessToken == "TWILIO_ACCESS_TOKEN") {
            accessToken = TokenUtils.fetchToken(url: tokenUrl)
        }
        
        // Creating a video client with the use of the access token.
        if (client == nil) {
            client = TVIVideoClient(token: accessToken)
            if (client == nil) {
                messageLabel.text = "Failed to create video client"
                return;
            }
        }
        
        // Preparing local media to offer in when we connect to room.
        self.prepareLocalMedia()
        
        // Preparing the connect options
        let connectOptions = TVIConnectOptions { (builder) in
            
            // We will set the prepared local media in connect options.
            builder.localMedia = self.localMedia;
            
            // Room where where client will attempt to connect to. Please note that if you pass an empty room `name`, 
            // client will create a room for you. You can get room's name/sid by quierrying name property on Room 
            // `connect` API returns.
            builder.name = self.roomTextField.text
        }
        
        // Attempting to connect to room with connect options
        room = client?.connect(with: connectOptions, delegate: self)
        
        messageLabel.text = "Attempting to connect to room \(self.roomTextField.text)"
        
        self.toggleView()
        self.dismissKeyboard()
    }
    
    @IBAction func disconnect(sender: AnyObject) {
        self.room!.disconnect()
        messageLabel.text = "Attempting to disconnect from room \(room!.name)"
    }
    
    
    // Reset the client ui status
    func toggleView() {
        self.roomTextField.isHidden = !self.roomTextField.isHidden
        self.connectButton.isHidden = !self.connectButton.isHidden
        self.disconnectButton.isHidden = !self.disconnectButton.isHidden
        self.roomLine.isHidden = !self.roomLine.isHidden
        self.roomLabel.isHidden = !self.roomLabel.isHidden
    }
    
    func dismissKeyboard() {
        if (self.roomTextField.isFirstResponder) {
            self.roomTextField.resignFirstResponder()
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.connect(sender: textField)
        return true;
    }
}

//MARK: TVIRoomDelegate
extension ViewController : TVIRoomDelegate {
    func didConnect(to room: TVIRoom) {
        messageLabel.text = "Connected to room \(room.name)"
        
        if (room.participants.count > 0) {
            self.participant = room.participants[0]
            self.participant?.delegate = self
        }
    }
    
    func room(_ room: TVIRoom, didDisconnectWithError error: Error?) {
        messageLabel.text = "Disconncted from room \(room.name), error = \(error)"
        self.participant = nil
        self.room = nil
        
        self.toggleView()
    }
    
    func room(_ room: TVIRoom, didFailToConnectWithError error: Error) {
        messageLabel.text = "Failed to connect to room with error"
        self.room = nil
        
        self.toggleView()
    }
    
    func room(_ room: TVIRoom, participantDidConnect participant: TVIParticipant) {
        if (self.participant == nil) {
            self.participant = participant
            self.participant?.delegate = self
        }
        messageLabel.text = "Room \(room.name), Participant \(participant.identity) connected"

    }
    
    func room(_ room: TVIRoom, participantDidDisconnect participant: TVIParticipant) {
        if (self.participant == participant) {
            participant.media.videoTracks[0].detach(self.remoteView)
            self.participant = nil
        }
        messageLabel.text = "Room \(room.name), Participant \(participant.identity) disconnected"

    }
}

//MARK: TVIParticipantDelegate
extension ViewController : TVIParticipantDelegate {
    func participant(_ participant: TVIParticipant, addedVideoTrack videoTrack: TVIVideoTrack) {
        messageLabel.text = "Participant \(participant.identity) added video track"

        if (self.participant == participant) {
            videoTrack.attach(self.remoteView)
        }
    }
    
    func participant(_ participant: TVIParticipant, removedVideoTrack videoTrack: TVIVideoTrack) {
        messageLabel.text = "Participant \(participant.identity) removed video track"

        if (self.participant == participant) {
            videoTrack.detach(self.remoteView)
        }
    }
    
    func participant(_ participant: TVIParticipant, addedAudioTrack audioTrack: TVIAudioTrack) {
        messageLabel.text = "Participant \(participant.identity) added audio track"

    }
    
    func participant(_ participant: TVIParticipant, removedAudioTrack audioTrack: TVIAudioTrack) {
        messageLabel.text = "Participant \(participant.identity) removed audio track"
    }
    
    func participant(_ participant: TVIParticipant, enabledTrack track: TVITrack) {
        var type = ""
        if (track is TVIVideoTrack) {
            type = "video"
        } else {
            type = "audio"
        }
        messageLabel.text = "Participant \(participant.identity) enabled \(type) track"
    }
    
    func participant(_ participant: TVIParticipant, disabledTrack track: TVITrack) {
        var type = ""
        if (track is TVIVideoTrack) {
            type = "video"
        } else {
            type = "audio"
        }
        messageLabel.text = "Participant \(participant.identity) disabled \(type) track"
    }
}
