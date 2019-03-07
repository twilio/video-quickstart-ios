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


    // MARK: Private
    func logMessage(messageText: String) {
        NSLog(messageText)
        messageLabel.text = messageText
    }

    func prepareCamera() {
        if PlatformUtils.isSimulator {
            return
        }

        let frontCamera = TVICameraSource.captureDevice(for: .front)
        let backCamera = TVICameraSource.captureDevice(for: .back)

        if (frontCamera != nil || backCamera != nil) {
            // Preview our local camera track in the local video preview view.
            camera = TVICameraSource(delegate: self)

            if let camera = camera {
                localVideoTrack = TVILocalVideoTrack.init(source: camera, enabled: true, name: "Camera")

                // Add renderer to video track for local preview
//                localVideoTrack!.addRenderer(self.previewView)
                logMessage(messageText: "Video track created")

                if (frontCamera != nil && backCamera != nil) {
                    // We will flip camera on tap.
//                    let tap = UITapGestureRecognizer(target: self, action: #selector(ViewController.flipCamera))
//                    self.previewView.addGestureRecognizer(tap)
                }

                camera.startCapture(with: frontCamera != nil ? frontCamera! : backCamera!) { (captureDevice, videoFormat, error) in
                    if let error = error {
                        self.logMessage(messageText: "Capture failed with error.\ncode = \((error as NSError).code) error = \(error.localizedDescription)")
                    } else {
//                        self.previewView.shouldMirror = (captureDevice.position == .front)
                    }
                }
            }
        }
        else {
            self.logMessage(messageText:"No front or back capture source found!")
        }
    }

    @objc func flipCamera() {
        var newDevice: AVCaptureDevice?

        if let camera = camera, let captureDevice = camera.device {
            if captureDevice.position == .front {
                newDevice = TVICameraSource.captureDevice(for: .back)
            } else {
                newDevice = TVICameraSource.captureDevice(for: .front)
            }

            if let newDevice = newDevice {
                camera.select(newDevice) { (captureDevice, videoFormat, error) in
                    if let error = error {
                        self.logMessage(messageText: "Error selecting capture device.\ncode = \((error as NSError).code) error = \(error.localizedDescription)")
                    } else {
//                        self.previewView.shouldMirror = (captureDevice.position == .front)
                    }
                }
            }
        }
    }

    func prepareLocalMedia() {
        // We will share local audio and video when we connect to the Room.

        // Create an audio track.
        if (localAudioTrack == nil) {
            localAudioTrack = TVILocalAudioTrack.init(options: nil, enabled: true, name: "Microphone")

            if (localAudioTrack == nil) {
                logMessage(messageText: "Failed to create audio track")
            }
        }

        // Create a video track which captures from the camera.
        if (localVideoTrack == nil) {
            prepareCamera()
        }
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

// MARK: TVIVideoViewDelegate
extension MultiPartyViewController : TVIVideoViewDelegate {
    func videoView(_ view: TVIVideoView, videoDimensionsDidChange dimensions: CMVideoDimensions) {
        self.view.setNeedsLayout()
    }
}

// MARK: TVICameraSourceDelegate
extension MultiPartyViewController : TVICameraSourceDelegate {
    func cameraSource(_ source: TVICameraSource, didFailWithError error: Error) {
        logMessage(messageText: "Camera source failed with error: \(error.localizedDescription)")
    }
}
