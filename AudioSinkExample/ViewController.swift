//
//  ViewController.swift
//  AudioSinkExample
//
//  Copyright © 2017 Twilio Inc. All rights reserved.
//

import AVFoundation
import TwilioVideo
import UIKit

class ViewController: UIViewController {

    // MARK: View Controller Members

    // Configure access token manually for testing, if desired! Create one manually in the console
    // at https://www.twilio.com/user/account/video/dev-tools/testing-tools
    var accessToken = "TWILIO_ACCESS_TOKEN"

    // Configure remote URL to fetch token from
    var tokenUrl = "http://localhost:8000/token.php"

    // Automatically record audio for all remote
    let recordAudio = false

    // Video SDK components
    var room: TVIRoom?
    var camera: TVICameraCapturer?
    var localAudioTrack: TVILocalAudioTrack!
    var localVideoTrack: TVILocalVideoTrack!

    // Audio Sinks
    var speechRecognizer: ExampleSpeechRecognizer?

    // MARK: UI Element Outlets and handles

    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var roomTextField: UITextField!
    @IBOutlet weak var roomLine: UIView!
    @IBOutlet weak var roomLabel: UILabel!

    let previewPadding = CGFloat(10)

    override func viewDidLoad() {
        super.viewDidLoad()

        self.disconnectButton.isHidden = true
        self.roomTextField.autocapitalizationType = .none
        self.roomTextField.delegate = self

        prepareLocalMedia()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
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

        // Preparing the connect options with the access token that we fetched (or hardcoded).
        let connectOptions = TVIConnectOptions.init(token: accessToken) { (builder) in

            // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty
            // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
            builder.roomName = self.roomTextField.text
        }

        // Connect to the Room using the options we provided.
        room = TwilioVideo.connect(with: connectOptions, delegate: self)

        logMessage(messageText: "Attempting to connect to room \(String(describing: self.roomTextField.text))")

        self.showRoomUI(inRoom: true)
        self.dismissKeyboard()
    }

    @IBAction func disconnect(sender: AnyObject) {
        if let room = self.room {
            room.disconnect()
            logMessage(messageText: "Attempting to disconnect from room \(room.name)")
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        // Layout the preview view.
        if let previewView = self.camera?.previewView {
            let dimensions = previewView.videoDimensions
            var previewBounds = CGRect.init(origin: CGPoint.zero, size: CGSize.init(width: 160, height: 160))

            previewBounds = AVMakeRect(aspectRatio: CGSize.init(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height)),
                                       insideRect: previewBounds)

            previewBounds = previewBounds.integral

            previewBounds.origin = CGPoint.init(x: view.bounds.width - previewBounds.width - previewPadding,
                                                y: view.bounds.height - previewBounds.height - previewPadding)

            previewView.frame = previewBounds
        }
    }

    // Update our UI based upon if we are in a Room or not
    func showRoomUI(inRoom: Bool) {
        self.connectButton.isHidden = inRoom
        self.roomTextField.isHidden = inRoom
        self.roomLine.isHidden = inRoom
        self.roomLabel.isHidden = inRoom
        self.disconnectButton.isHidden = !inRoom
        UIApplication.shared.isIdleTimerDisabled = inRoom
    }

    func dismissKeyboard() {
        if (self.roomTextField.isFirstResponder) {
            self.roomTextField.resignFirstResponder()
        }
    }

    func logMessage(messageText: String) {
        messageLabel.text = messageText
    }

    func recognizeLocalAudio() {

    }

    func prepareLocalMedia() {

        // We will share local audio and video in the Room.

        // Create an audio track.
        localAudioTrack = TVILocalAudioTrack.init()

        if (localAudioTrack == nil) {
            logMessage(messageText: "Failed to create audio track")
        }

        // Create a video track which captures from the camera.
        if (TVICameraCapturer.isSourceAvailable(TVICameraCaptureSource.frontCamera)) {

            // We will render preview using TVICameraPreviewView.
            camera = TVICameraCapturer(source: .frontCamera, delegate: nil, enablePreview: true)
            localVideoTrack = TVILocalVideoTrack.init(capturer: camera!)

            if (localVideoTrack == nil) {
                logMessage(messageText: "Failed to create video track")
            } else {
                logMessage(messageText: "Video track created")

                if let preview = camera?.previewView {
                    let tap = UITapGestureRecognizer(target: self, action: #selector(ViewController.recognizeLocalAudio))
                    preview.addGestureRecognizer(tap)
                    view.addSubview(preview);
                }
            }
        }
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

        for remoteParticipant in room.remoteParticipants {
            remoteParticipant.delegate = self
        }

        logMessage(messageText: "Connected to room \(room.name) as \(String(describing: room.localParticipant?.identity))")
    }

    func room(_ room: TVIRoom, didDisconnectWithError error: Error?) {
        logMessage(messageText: "Disconncted from room \(room.name), error = \(String(describing: error))")

        self.room = nil

        self.showRoomUI(inRoom: false)
    }

    func room(_ room: TVIRoom, didFailToConnectWithError error: Error) {
        logMessage(messageText: "Failed to connect to room with error: \(error.localizedDescription)")
        self.room = nil

        self.showRoomUI(inRoom: false)
    }

    func room(_ room: TVIRoom, participantDidConnect participant: TVIRemoteParticipant) {
        participant.delegate = self

        logMessage(messageText: "Participant \(participant.identity) connected with \(participant.remoteDataTracks.count) data, \(participant.remoteAudioTracks.count) audio and \(participant.remoteVideoTracks.count) video tracks")
    }

    func room(_ room: TVIRoom, participantDidDisconnect participant: TVIRemoteParticipant) {
        logMessage(messageText: "Room \(room.name), Participant \(participant.identity) disconnected")
    }
}

// MARK: TVIRemoteParticipantDelegate
extension ViewController : TVIRemoteParticipantDelegate {

    func remoteParticipant(_ participant: TVIRemoteParticipant,
                           publishedVideoTrack publication: TVIRemoteVideoTrackPublication) {

        // Remote Participant has offered to share the video Track.

        logMessage(messageText: "Participant \(participant.identity) published \(publication.trackName) video track")
    }

    func remoteParticipant(_ participant: TVIRemoteParticipant,
                           unpublishedVideoTrack publication: TVIRemoteVideoTrackPublication) {

        // Remote Participant has stopped sharing the video Track.

        logMessage(messageText: "Participant \(participant.identity) unpublished \(publication.trackName) video track")
    }

    func remoteParticipant(_ participant: TVIRemoteParticipant,
                           publishedAudioTrack publication: TVIRemoteAudioTrackPublication) {

        // Remote Participant has offered to share the audio Track.

        logMessage(messageText: "Participant \(participant.identity) published \(publication.trackName) audio track")
    }

    func remoteParticipant(_ participant: TVIRemoteParticipant,
                           unpublishedAudioTrack publication: TVIRemoteAudioTrackPublication) {

        // Remote Participant has stopped sharing the audio Track.

        logMessage(messageText: "Participant \(participant.identity) unpublished \(publication.trackName) audio track")
    }

    func remoteParticipant(_ participant: TVIRemoteParticipant,
                           publishedDataTrack publication: TVIRemoteDataTrackPublication) {

        // Remote Participant has offered to share the data Track.

        logMessage(messageText: "Participant \(participant.identity) published \(publication.trackName) data track")
    }

    func remoteParticipant(_ participant: TVIRemoteParticipant,
                           unpublishedDataTrack publication: TVIRemoteDataTrackPublication) {

        // Remote Participant has stopped sharing the data Track.

        logMessage(messageText: "Participant \(participant.identity) unpublished \(publication.trackName) data track")
    }

    func subscribed(to videoTrack: TVIRemoteVideoTrack,
                    publication: TVIRemoteVideoTrackPublication,
                    for participant: TVIRemoteParticipant) {

        // We are subscribed to the remote Participant's audio Track. We will start receiving the
        // remote Participant's video frames now.

        logMessage(messageText: "Subscribed to \(publication.trackName) video track for Participant \(participant.identity)")

//        if (self.remoteParticipant == participant) {
//            setupRemoteVideoView()
//            videoTrack.addRenderer(self.remoteView!)
//        }
    }

    func unsubscribed(from videoTrack: TVIRemoteVideoTrack,
                      publication: TVIRemoteVideoTrackPublication,
                      for participant: TVIRemoteParticipant) {

        // We are unsubscribed from the remote Participant's video Track. We will no longer receive the
        // remote Participant's video.

        logMessage(messageText: "Unsubscribed from \(publication.trackName) video track for Participant \(participant.identity)")

//        if (self.remoteParticipant == participant) {
//            videoTrack.removeRenderer(self.remoteView!)
//            self.remoteView?.removeFromSuperview()
//            self.remoteView = nil
//        }
    }

    func subscribed(to audioTrack: TVIRemoteAudioTrack,
                    publication: TVIRemoteAudioTrackPublication,
                    for participant: TVIRemoteParticipant) {

        // We are subscribed to the remote Participant's audio Track. We will start receiving the
        // remote Participant's audio now.

        logMessage(messageText: "Subscribed to \(publication.trackName) audio track for Participant \(participant.identity)")
    }

    func unsubscribed(from audioTrack: TVIRemoteAudioTrack,
                      publication: TVIRemoteAudioTrackPublication,
                      for participant: TVIRemoteParticipant) {

        // We are unsubscribed from the remote Participant's audio Track. We will no longer receive the
        // remote Participant's audio.

        logMessage(messageText: "Unsubscribed from \(publication.trackName) audio track for Participant \(participant.identity)")
    }

    func subscribed(to dataTrack: TVIRemoteDataTrack,
                    publication: TVIRemoteDataTrackPublication,
                    for participant: TVIRemoteParticipant) {

        // We are subscribed to the remote Participant's data Track. We will start receiving the
        // remote Participant's data messages now.

        logMessage(messageText: "Subscribed to \(publication.trackName) data track for Participant \(participant.identity)")
    }

    func unsubscribed(from dataTrack: TVIRemoteDataTrack,
                      publication: TVIRemoteDataTrackPublication,
                      for participant: TVIRemoteParticipant) {

        // We are unsubscribed from the remote Participant's data Track. We will no longer receive the
        // remote Participant's data messages.

        logMessage(messageText: "Unsubscribed from \(publication.trackName) data track for Participant \(participant.identity)")
    }

    func remoteParticipant(_ participant: TVIRemoteParticipant,
                           enabledVideoTrack publication: TVIRemoteVideoTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) enabled \(publication.trackName) video track")
    }

    func remoteParticipant(_ participant: TVIRemoteParticipant,
                           disabledVideoTrack publication: TVIRemoteVideoTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) disabled \(publication.trackName) video track")
    }

    func remoteParticipant(_ participant: TVIRemoteParticipant,
                           enabledAudioTrack publication: TVIRemoteAudioTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) enabled \(publication.trackName) audio track")
    }

    func remoteParticipant(_ participant: TVIRemoteParticipant,
                           disabledAudioTrack publication: TVIRemoteAudioTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) disabled \(publication.trackName) audio track")
    }
}

