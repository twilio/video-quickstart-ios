//
//  ViewController.swift
//  ExampleDataTrack
//
//  Created by Piyush Tank on 11/2/17.
//  Copyright © 2017 Twilio. All rights reserved.
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
    var room: TVIRoom?
    var participant: TVIParticipant?
    
    // MARK: UI Element Outlets and handles
    
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var roomTextField: UITextField!
    @IBOutlet weak var roomLine: UIView!
    @IBOutlet weak var roomLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.disconnectButton.isHidden = true
        self.roomTextField.autocapitalizationType = .none
        self.roomTextField.delegate = self
    }

    // MARK: IBActions
    @IBAction func connect(sender: AnyObject) {
//        // Configure access token either from server or manually.
//        // If the default wasn't changed, try fetching from server.
//        if (accessToken == "TWILIO_ACCESS_TOKEN") {
//            do {
//                accessToken = try TokenUtils.fetchToken(url: tokenUrl)
//            } catch {
//                let message = "Failed to fetch access token"
//                logMessage(messageText: message)
//                return
//            }
//        }
//
//        // Prepare local media which we will share with Room Participants.
//        self.prepareLocalMedia()
//
//        // Preparing the connect options with the access token that we fetched (or hardcoded).
//        let connectOptions = TVIConnectOptions.init(token: accessToken) { (builder) in
//
//            let dataTrack = TVILocalDataTrack.track()
//            builder.dataTracks = TVILocalDataTrack.t
//
//            // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty
//            // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
//            builder.roomName = self.roomTextField.text
//        }
//
//        // Connect to the Room using the options we provided.
//        room = TwilioVideo.connect(with: connectOptions, delegate: self)
//
//        logMessage(messageText: "Attempting to connect to room \(String(describing: self.roomTextField.text))")
//
//        self.showRoomUI(inRoom: true)
//        self.dismissKeyboard()
    }
    
    func prepareLocalMedia() {
//        
//        // We will share local data track when we connect to the Room.
//        
//        localDataTrack = TVILocal
//        
//        // Create an audio track.
//        if (localAudioTrack == nil) {
//            localAudioTrack = TVILocalAudioTrack.init()
//            
//            if (localAudioTrack == nil) {
//                logMessage(messageText: "Failed to create audio track")
//            }
//        }
//        
//        // Create a video track which captures from the camera.
//        if (localVideoTrack == nil) {
//            self.startPreview()
//        }
    }


}

