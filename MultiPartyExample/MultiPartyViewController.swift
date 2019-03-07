//
//  MultiPartyViewController.swift
//  MultiPartyExample
//
//  Copyright © 2019 Twilio, Inc. All rights reserved.
//

import UIKit
import TwilioVideo

class MultiPartyViewController: UIViewController {

    // MARK: View Controller Members
    var roomName: String?
    var accessToken: String?

    // Video SDK components
    var room: TVIRoom?
    var camera: TVICameraSource?
    var localVideoTrack: TVILocalVideoTrack?
    var localAudioTrack: TVILocalAudioTrack?

    // MARK: UI Element Outlets and handles
    @IBOutlet weak var messageLabel: UILabel!

    // MARK: UIViewController
    override func viewDidLoad() {
        super.viewDidLoad()

        messageLabel.adjustsFontSizeToFitWidth = true;
        messageLabel.minimumScaleFactor = 0.75;
        logMessage(messageText: "TwilioVideo v(\(TwilioVideo.version()))")

        navigationItem.leftBarButtonItem = UIBarButtonItem.init(title: "Disconnect", style: .plain, target: self, action: #selector(leaveRoom(sender:)))

        connect()
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return room != nil
    }

    func logMessage(messageText: String) {
        NSLog(messageText)
        messageLabel.text = messageText
    }

    func prepareLocalMedia() {

    }

    func connect() {
        guard let accessToken = accessToken, let roomName = roomName else {
            // This should never happen becasue we are validating in
            // MainViewController
            return
        }

        // Prepare local media which we will share with Room Participants.
        prepareLocalMedia()

        // Preparing the connect options with the access token that we fetched (or hardcoded).
        let connectOptions = TVIConnectOptions.init(token: accessToken) { (builder) in

            // Enable Dominant Speaker functionality
            builder.isDominantSpeakerEnabled = true

            // Use the local media that we prepared earlier.
            if let localAudioTrack = self.localAudioTrack {
                builder.audioTracks = [localAudioTrack]
            }

            if let localVideoTrack = self.localVideoTrack {
                builder.videoTracks = [localVideoTrack]
            }

            // Use the preferred audio codec
            if let preferredAudioCodec = Settings.shared.audioCodec {
                builder.preferredAudioCodecs = [preferredAudioCodec]
            }

            // Use the preferred video codec
            if let preferredVideoCodec = Settings.shared.videoCodec {
                builder.preferredVideoCodecs = [preferredVideoCodec]
            }

            // Use the preferred encoding parameters
            if let encodingParameters = Settings.shared.getEncodingParameters() {
                builder.encodingParameters = encodingParameters
            }

            // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty
            // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
            builder.roomName = roomName
        }

        // Connect to the Room using the options we provided.
        room = TwilioVideo.connect(with: connectOptions, delegate: self)

        logMessage(messageText: "Attempting to connect to room: \(roomName)")
    }

    @objc func leaveRoom(sender: AnyObject) {
        if let room = room {
            room.disconnect()
            self.room = nil
        }

        // Do any necessary cleanup when leaving the room


        navigationController?.popViewController(animated: true)
    }
}

// MARK: TVIRoomDelegate
extension MultiPartyViewController : TVIRoomDelegate {
    func didConnect(to room: TVIRoom) {
        logMessage(messageText: "Connected to room \(room.name) as \(String(describing: room.localParticipant?.identity))")
        NSLog("Room: \(room.name) SID: \(room.sid)")

    }

    func room(_ room: TVIRoom, didFailToConnectWithError error: Error) {
        NSLog("Failed to connect to a Room: \(error).")

        let alertController = UIAlertController.init(title: "Connection Failed",
                                                     message: "Couldn't connect to Room \(room.name). code:\(error._code) \(error.localizedDescription)",
            preferredStyle: .alert)

        let cancelAction = UIAlertAction.init(title: "Okay", style: .default) { (alertAction) in
            self.leaveRoom(sender: self)
        }

        alertController.addAction(cancelAction)

        self.present(alertController, animated: true) {
            self.room = nil
            if #available(iOS 11.0, *) {
                self.setNeedsUpdateOfHomeIndicatorAutoHidden()
            }
        }
    }

    func room(_ room: TVIRoom, didDisconnectWithError error: Error?) {

    }

    func room(_ room: TVIRoom, isReconnectingWithError error: Error) {

    }

    func didReconnect(to room: TVIRoom) {

    }

    func room(_ room: TVIRoom, participantDidConnect participant: TVIRemoteParticipant) {

    }

    func room(_ room: TVIRoom, participantDidDisconnect participant: TVIRemoteParticipant) {

    }

    func room(_ room: TVIRoom, dominantSpeakerDidChange participant: TVIRemoteParticipant?) {

    }
}
