//
//  ViewController.swift
//  VideoQuickStart
//
//  Copyright © 2016 Twilio. All rights reserved.
//

import UIKit

import TwilioVideo

class ViewController: UIViewController {

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
    @IBOutlet weak var micButton: UIButton!

    // MARK: UIViewController
    override func viewDidLoad() {
        super.viewDidLoad()

        // LocalMedia represents the collection of tracks that we are sending to other Participants from our VideoClient.
        localMedia = TVILocalMedia()
        
        // 1.0.0-beta4 incorrectly chooses `TVIAudioOutputVoiceChatDefault` by default. We work around this by restoring the intended default value.
        let audioController = localMedia?.audioController
        audioController?.audioOutput = .videoChatDefault

        if PlatformUtils.isSimulator {
            self.previewView.removeFromSuperview()
        } else {
            // Preview our local camera track in the local video preview view.
            self.startPreview()
        }
        
        // Disconnect and mic button will be displayed when the Client is connected to a Room.
        self.disconnectButton.isHidden = true
        self.micButton.isHidden = true
        
        self.roomTextField.delegate = self
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(ViewController.dismissKeyboard))
        self.view.addGestureRecognizer(tap)
    }

    // MARK: IBActions
    @IBAction func connect(sender: AnyObject) {
        // Configure access token either from server or manually.
        // If the default wasn't changed, try fetching from server.
        if (accessToken == "TWILIO_ACCESS_TOKEN") {
            do {
                accessToken = try TokenUtils.fetchToken(url: tokenUrl)
            } catch {
                let message = "Failed to fetch access token"
                logMessage(messageText: message)
                return
            }
        }
        
        // Create a Client with the access token that we fetched (or hardcoded).
        if (client == nil) {
            client = TVIVideoClient(token: accessToken)
            if (client == nil) {
                logMessage(messageText: "Failed to create video client")
                return
            }
        }
        
        // Prepare local media which we will share with Room Participants.
        self.prepareLocalMedia()
        
        // Preparing the connect options
        let connectOptions = TVIConnectOptions { (builder) in
            
            // Use the local media that we prepared earlier.
            builder.localMedia = self.localMedia
            
            // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty 
            // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
            builder.name = self.roomTextField.text
        }
        
        // Connect to the Room using the options we provided.
        room = client?.connect(with: connectOptions, delegate: self)
        
        logMessage(messageText: "Attempting to connect to room \(self.roomTextField.text)")
        
        self.showRoomUI(inRoom: true)
        self.dismissKeyboard()
    }
    
    @IBAction func disconnect(sender: AnyObject) {
        self.room!.disconnect()
        logMessage(messageText: "Attempting to disconnect from room \(room!.name)")
    }
    
    @IBAction func toggleMic(sender: AnyObject) {
        if (self.localAudioTrack != nil) {
            self.localAudioTrack?.isEnabled = !(self.localAudioTrack?.isEnabled)!
            
            // Update the button title
            if (self.localAudioTrack?.isEnabled == true) {
                self.micButton.setTitle("Mute", for: .normal)
            } else {
                self.micButton.setTitle("Unmute", for: .normal)
            }
        }
    }

    // MARK: Private
    func startPreview() {
        if PlatformUtils.isSimulator {
            return
        }

        // Preview our local camera track in the local video preview view.
        camera = TVICameraCapturer()
        localVideoTrack = localMedia?.addVideoTrack(true, capturer: camera!)
        if (localVideoTrack == nil) {
            logMessage(messageText: "Failed to add video track")
        } else {
            // Attach view to video track for local preview
            localVideoTrack!.attach(self.previewView)

            logMessage(messageText: "Video track added to localMedia")

            // We will flip camera on tap.
            let tap = UITapGestureRecognizer(target: self, action: #selector(ViewController.flipCamera))
            self.previewView.addGestureRecognizer(tap)
        }
    }

    func flipCamera() {
        if (self.camera?.source == .frontCamera) {
            self.camera?.selectSource(.backCameraWide)
        } else {
            self.camera?.selectSource(.frontCamera)
        }
    }

    func prepareLocalMedia() {

        // We will offer local audio and video when we connect to room.

        // Adding local audio track to localMedia
        if (localAudioTrack == nil) {
            localAudioTrack = localMedia?.addAudioTrack(true)
        }

        // Adding local video track to localMedia and starting local preview if it is not already started.
        if (localMedia?.videoTracks.count == 0) {
            self.startPreview()
        }
    }

    // Update our UI based upon if we are in a Room or not
    func showRoomUI(inRoom: Bool) {
        self.connectButton.isHidden = inRoom
        self.roomTextField.isHidden = inRoom
        self.roomLine.isHidden = inRoom
        self.roomLabel.isHidden = inRoom
        self.micButton.isHidden = !inRoom
        self.disconnectButton.isHidden = !inRoom
        UIApplication.shared.isIdleTimerDisabled = inRoom
    }
    
    func dismissKeyboard() {
        if (self.roomTextField.isFirstResponder) {
            self.roomTextField.resignFirstResponder()
        }
    }
    
    func cleanupRemoteParticipant() {
        if ((self.participant) != nil) {
            if ((self.participant?.media.videoTracks.count)! > 0) {
                self.participant?.media.videoTracks[0].detach(self.remoteView)
            }
        }
        self.participant = nil
    }
    
    func logMessage(messageText: String) {
        messageLabel.text = messageText
    }
}

// MARK: UITextFieldDelegate
extension ViewController : UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.connect(sender: textField)
        return true
    }
}

// MARK: TVIRoomDelegate
extension ViewController : TVIRoomDelegate {
    func didConnect(to room: TVIRoom) {
        
        // At the moment, this example only supports rendering one Participant at a time.
        
        logMessage(messageText: "Connected to room \(room.name) as \(room.localParticipant?.identity)")
        
        if (room.participants.count > 0) {
            self.participant = room.participants[0]
            self.participant?.delegate = self
        }
    }
    
    func room(_ room: TVIRoom, didDisconnectWithError error: Error?) {
        logMessage(messageText: "Disconncted from room \(room.name), error = \(error)")
        
        self.cleanupRemoteParticipant()
        self.room = nil
        
        self.showRoomUI(inRoom: false)
    }
    
    func room(_ room: TVIRoom, didFailToConnectWithError error: Error) {
        logMessage(messageText: "Failed to connect to room with error")
        self.room = nil
        
        self.showRoomUI(inRoom: false)
    }
    
    func room(_ room: TVIRoom, participantDidConnect participant: TVIParticipant) {
        if (self.participant == nil) {
            self.participant = participant
            self.participant?.delegate = self
        }
       logMessage(messageText: "Room \(room.name), Participant \(participant.identity) connected")
    }
    
    func room(_ room: TVIRoom, participantDidDisconnect participant: TVIParticipant) {
        if (self.participant == participant) {
            cleanupRemoteParticipant()
        }
        logMessage(messageText: "Room \(room.name), Participant \(participant.identity) disconnected")
    }
}

// MARK: TVIParticipantDelegate
extension ViewController : TVIParticipantDelegate {
    func participant(_ participant: TVIParticipant, addedVideoTrack videoTrack: TVIVideoTrack) {
        logMessage(messageText: "Participant \(participant.identity) added video track")

        if (self.participant == participant) {
            videoTrack.attach(self.remoteView)
        }
    }
    
    func participant(_ participant: TVIParticipant, removedVideoTrack videoTrack: TVIVideoTrack) {
        logMessage(messageText: "Participant \(participant.identity) removed video track")

        if (self.participant == participant) {
            videoTrack.detach(self.remoteView)
        }
    }
    
    func participant(_ participant: TVIParticipant, addedAudioTrack audioTrack: TVIAudioTrack) {
        logMessage(messageText: "Participant \(participant.identity) added audio track")

    }
    
    func participant(_ participant: TVIParticipant, removedAudioTrack audioTrack: TVIAudioTrack) {
        logMessage(messageText: "Participant \(participant.identity) removed audio track")
    }
    
    func participant(_ participant: TVIParticipant, enabledTrack track: TVITrack) {
        var type = ""
        if (track is TVIVideoTrack) {
            type = "video"
        } else {
            type = "audio"
        }
        logMessage(messageText: "Participant \(participant.identity) enabled \(type) track")
    }
    
    func participant(_ participant: TVIParticipant, disabledTrack track: TVITrack) {
        var type = ""
        if (track is TVIVideoTrack) {
            type = "video"
        } else {
            type = "audio"
        }
        logMessage(messageText: "Participant \(participant.identity) disabled \(type) track")
    }
}
