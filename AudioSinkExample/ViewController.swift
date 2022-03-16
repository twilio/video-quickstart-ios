//
//  ViewController.swift
//  AudioSinkExample
//
//  Copyright © 2017-2019 Twilio Inc. All rights reserved.
//

import AVFoundation
import TwilioVideo
import UIKit

class ViewController: UIViewController {

    // MARK:- View Controller Members

    // Configure access token manually for testing, if desired! Create one manually in the console
    // at https://www.twilio.com/console/video/runtime/testing-tools
    var accessToken = "TWILIO_ACCESS_TOKEN"

    // Configure remote URL to fetch token from
    let tokenUrl = "http://localhost:8000/token.php"

    // Automatically record audio for all `AudioTrack`s published in a Room.
    let recordAudio = true

    // Video SDK components
    var room: Room?
    var camera: CameraSource?
    var localAudioTrack: LocalAudioTrack!
    var localVideoTrack: LocalVideoTrack!

    // Audio Sinks
    var audioRecorders = Dictionary<String, ExampleAudioRecorder>()
    var speechRecognizer: ExampleSpeechRecognizer?

    // MARK:- UI Element Outlets and handles

    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var remoteViewStack: UIStackView!
    @IBOutlet weak var roomTextField: UITextField!
    @IBOutlet weak var roomLine: UIView!
    @IBOutlet weak var roomLabel: UILabel!

    // Speech UI
    weak var speechRecognizerView: UIView!
    weak var dimmingView: UIView!
    weak var speechLabel: UILabel!

    var messageTimer: Timer!

    let kPreviewPadding = CGFloat(10)
    let kTextBottomPadding = CGFloat(4)
    let kMaxRemoteVideos = Int(2)
    
    deinit {
        // We are done with camera
        if let camera = self.camera {
            camera.stopCapture()
            self.camera = nil
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "AudioSink Example"
        disconnectButton.isHidden = true
        disconnectButton.setTitleColor(UIColor(white: 0.75, alpha: 1), for: .disabled)
        connectButton.setTitleColor(UIColor(white: 0.75, alpha: 1), for: .disabled)
        roomTextField.autocapitalizationType = .none
        roomTextField.delegate = self

        if (recordAudio == false) {
            navigationItem.leftBarButtonItem = nil
        }

        prepareLocalMedia()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    func connectToARoom() {
        connectButton.isEnabled = true
        // Preparing the connect options with the access token that we fetched (or hardcoded).
        let connectOptions = ConnectOptions(token: accessToken) { (builder) in

            if let audioTrack = self.localAudioTrack {
                builder.audioTracks = [audioTrack]
            }
            if let videoTrack = self.localVideoTrack {
                builder.videoTracks = [videoTrack]
            }

            // Use the preferred audio codec
            if let preferredAudioCodec = Settings.shared.audioCodec {
                builder.preferredAudioCodecs = [preferredAudioCodec]
            }

            // Use Adpative Simulcast by setting builer.videoEncodingMode to .auto if preferredVideoCodec is .auto (default). The videoEncodingMode API is mutually exclusive with existing codec management APIs EncodingParameters.maxVideoBitrate and preferredVideoCodecs
            let preferredVideoCodec = Settings.shared.videoCodec
            if preferredVideoCodec == .auto {
                builder.videoEncodingMode = .auto
            } else if let codec = preferredVideoCodec.codec {
                builder.preferredVideoCodecs = [codec]
            }

            // Use the preferred encoding parameters
            if let encodingParameters = Settings.shared.getEncodingParameters() {
                builder.encodingParameters = encodingParameters
            }

            // Use the preferred signaling region
            if let signalingRegion = Settings.shared.signalingRegion {
                builder.region = signalingRegion
            }

            // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty
            // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
            builder.roomName = self.roomTextField.text
        }

        // Connect to the Room using the options we provided.
        room = TwilioVideoSDK.connect(options: connectOptions, delegate: self)

        logMessage(messageText: "Connecting to \(roomTextField.text ?? "a Room")")

        self.showRoomUI(inRoom: true)
        self.dismissKeyboard()
    }

    // MARK:- IBActions
    @IBAction func connect(sender: AnyObject) {
        connectButton.isEnabled = false
        // Configure access token either from server or manually.
        // If the default wasn't changed, try fetching from server.
        if (accessToken == "TWILIO_ACCESS_TOKEN") {
            TokenUtils.fetchToken(from: tokenUrl) { [weak self]
                (token, error) in
                DispatchQueue.main.async {
                    if let error = error {
                        let message = "Failed to fetch access token:" + error.localizedDescription
                        self?.logMessage(messageText: message)
                        self?.connectButton.isEnabled = true
                        return
                    }
                    self?.accessToken = token;
                    self?.connectToARoom()
                }
            }
        } else {
            self.connectToARoom()
        }
    }

    @IBAction func disconnect(sender: UIButton) {
        if let room = self.room {
            logMessage(messageText: "Disconnecting from \(room.name)")
            room.disconnect()
            sender.isEnabled = false
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        var bottomRight = CGPoint(x: view.bounds.width, y: view.bounds.height)
        var layoutWidth = view.bounds.width
        // Ensure the preview fits in the safe area.
        let safeAreaGuide = self.view.safeAreaLayoutGuide
        let layoutFrame = safeAreaGuide.layoutFrame
        bottomRight.x = layoutFrame.origin.x + layoutFrame.width
        bottomRight.y = layoutFrame.origin.y + layoutFrame.height
        layoutWidth = layoutFrame.width

        // Layout the speech label.
        if let speechLabel = self.speechLabel {
            speechLabel.preferredMaxLayoutWidth = layoutWidth - (kPreviewPadding * 2)

            let constrainedSize = CGSize(width: view.bounds.width,
                                         height: view.bounds.height)
            let fittingSize = speechLabel.sizeThatFits(constrainedSize)
            let speechFrame = CGRect(x: 0,
                                     y: bottomRight.y - fittingSize.height - kTextBottomPadding,
                                     width: view.bounds.width,
                                     height: (view.bounds.height - bottomRight.y) + fittingSize.height + kTextBottomPadding)
            speechLabel.frame = speechFrame.integral
        }

        // Layout the preview view.
        if let previewView = self.camera?.previewView {
            let dimensions = previewView.videoDimensions
            var previewBounds = CGRect(origin: CGPoint.zero, size: CGSize(width: 160, height: 160))
            previewBounds = AVMakeRect(aspectRatio: CGSize(width: CGFloat(dimensions.width),
                                                           height: CGFloat(dimensions.height)),
                                       insideRect: previewBounds)

            previewBounds = previewBounds.integral
            previewView.bounds = previewBounds
            previewView.center = CGPoint(x: bottomRight.x - previewBounds.width / 2 - kPreviewPadding,
                                         y: bottomRight.y - previewBounds.height / 2 - kPreviewPadding)

            if let speechLabel = self.speechLabel {
                previewView.center.y = speechLabel.frame.minY - (2.0 * kPreviewPadding) - (previewBounds.height / 2.0);
            }
        }
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return self.room != nil
    }

    override var prefersStatusBarHidden: Bool {
        return self.room != nil
    }

    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        if (newCollection.horizontalSizeClass == .regular ||
            (newCollection.horizontalSizeClass == .compact && newCollection.verticalSizeClass == .compact)) {
            remoteViewStack.axis = .horizontal
        } else {
            remoteViewStack.axis = .vertical
        }
    }

    // Update our UI based upon if we are in a Room or not
    func showRoomUI(inRoom: Bool) {
        self.connectButton.isHidden = inRoom
        self.connectButton.isEnabled = !inRoom
        self.roomTextField.isHidden = inRoom
        self.roomLine.isHidden = inRoom
        self.roomLabel.isHidden = inRoom
        self.disconnectButton.isHidden = !inRoom
        self.disconnectButton.isEnabled = inRoom
        UIApplication.shared.isIdleTimerDisabled = inRoom
        self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        self.setNeedsStatusBarAppearanceUpdate()

        self.navigationController?.setNavigationBarHidden(inRoom, animated: true)
    }

    func showSpeechRecognitionUI(view: UIView, message: String) {
        // Create a dimmer view for the Participant being recognized.
        let dimmer = UIView(frame: view.bounds)
        dimmer.alpha = 0
        dimmer.backgroundColor = UIColor(white: 1, alpha: 0.26)
        dimmer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(dimmer)
        self.dimmingView = dimmer
        self.speechRecognizerView = view

        // Create a label which will be added to the stack and display recognized speech.
        let messageLabel = UILabel()
        messageLabel.font = UIFont.boldSystemFont(ofSize: 16)
        messageLabel.textColor = UIColor.white
        messageLabel.backgroundColor = UIColor(red: 226/255, green: 29/255, blue: 37/255, alpha: 1)
        messageLabel.alpha = 0
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = NSTextAlignment.center

        self.view.addSubview(messageLabel)
        self.speechLabel = messageLabel

        // Force a layout to position the speech label before animations.
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()

        UIView.animate(withDuration: 0.4, animations: {
            self.view.setNeedsLayout()

            messageLabel.text = message
            dimmer.alpha = 1.0
            messageLabel.alpha = 1.0
            view.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
            self.disconnectButton.alpha = 0

            self.view.layoutIfNeeded()
        })
    }

    func hideSpeechRecognitionUI(view: UIView) {
        guard let dimmer = self.dimmingView else {
            return
        }

        self.view.setNeedsLayout()

        UIView.animate(withDuration: 0.4, animations: {
            dimmer.alpha = 0.0
            view.transform = CGAffineTransform.identity
            self.speechLabel?.alpha = 0.0
            self.disconnectButton.alpha = 1.0
            self.view.layoutIfNeeded()
        }, completion: { (complete) in
            if (complete) {
                self.speechLabel?.removeFromSuperview()
                self.speechLabel = nil
                dimmer.removeFromSuperview()
                self.dimmingView = nil
                self.speechRecognizerView = nil
                UIView.animate(withDuration: 0.4, animations: {
                    self.view.setNeedsLayout()
                    self.view.layoutIfNeeded()
                })
            }
        })
    }

    func dismissKeyboard() {
        if (self.roomTextField.isFirstResponder) {
            self.roomTextField.resignFirstResponder()
        }
    }

    func logMessage(messageText: String) {
        NSLog(messageText)
        messageLabel.text = messageText

        if (messageLabel.alpha < 1.0) {
            self.messageLabel.isHidden = false
            UIView.animate(withDuration: 0.4, animations: {
                self.messageLabel.alpha = 1.0
            })
        }

        // Hide the message with a delay.
        self.messageTimer?.invalidate()
        let timer = Timer(timeInterval: TimeInterval(6), repeats: false) { (timer) in
            if (self.messageLabel.isHidden == false) {
                UIView.animate(withDuration: 0.6, animations: {
                    self.messageLabel.alpha = 0
                }, completion: { (complete) in
                    if (complete) {
                        self.messageLabel.isHidden = true
                    }
                })
            }
        }

        self.messageTimer = timer
        RunLoop.main.add(timer, forMode: RunLoop.Mode.common)
    }

    // MARK:- Speech Recognition
    func stopRecognizingAudio() {
        if let recognizer = self.speechRecognizer {
            recognizer.stopRecognizing()
            self.speechRecognizer = nil

            if let view = self.speechRecognizerView {
                hideSpeechRecognitionUI(view: view)
            }
        }
    }

    @objc func recognizeRemoteAudio(gestureRecognizer: UIGestureRecognizer) {
        guard let remoteView = gestureRecognizer.view else {
            print("Couldn't find a view attached to the tap recognizer. \(gestureRecognizer)")
            return;
        }
        guard let room = self.room else {
            print("We are no longer connected to the Room!")
            return
        }

        // Find the Participant.
        let hashedSid = remoteView.tag
        for remoteParticipant in room.remoteParticipants {
            for videoTrackPublication in remoteParticipant.remoteVideoTracks {
                if (videoTrackPublication.trackSid.hashValue == hashedSid) {
                    if let audioTrack = remoteParticipant.remoteAudioTracks.first?.remoteTrack {
                        recognizeRemoteParticipantAudio(audioTrack: audioTrack,
                                                        sid: remoteParticipant.remoteAudioTracks.first!.trackSid,
                                                        name: remoteParticipant.identity,
                                                        view: remoteView)
                    }
                }
            }
        }
    }

    func recognizeRemoteParticipantAudio(audioTrack: RemoteAudioTrack, sid: String, name: String, view: UIView) {
        if (self.speechRecognizer != nil) {
            stopRecognizingAudio()
        } else {
            showSpeechRecognitionUI(view: view, message: "Listening to \(name)...")

            recognizeAudio(audioTrack: audioTrack, identifier: sid)
        }
    }

    @objc func recognizeLocalAudio() {
        if (self.speechRecognizer != nil) {
            stopRecognizingAudio()
        } else if let audioTrack = self.localAudioTrack {
            // Known issue - local audio is not available in a Peer-to-Peer Room unless there are >= 1 RemoteParticipants.

            if let room = self.room,
                room.state == .connected || room.state == .reconnecting {

                if let view = self.camera?.previewView {
                    showSpeechRecognitionUI(view: view,
                                            message: "Listening to \(room.localParticipant?.identity ?? "yourself")...")
                }

                recognizeAudio(audioTrack: audioTrack, identifier: audioTrack.name)
            }
        }
    }

    func recognizeAudio(audioTrack: AudioTrack, identifier: String) {
        self.speechRecognizer = ExampleSpeechRecognizer(audioTrack: audioTrack,
                                                        identifier: identifier,
                                                     resultHandler: { (result, error) in
                                                                if let validResult = result {
                                                                    self.speechLabel?.text = validResult.bestTranscription.formattedString
                                                                } else if let error = error {
                                                                    self.speechLabel?.text = error.localizedDescription
                                                                    self.stopRecognizingAudio()
                                                                }

                                                                UIView.animate(withDuration: 0.1, animations: {
                                                                    self.view.setNeedsLayout()
                                                                    self.view.layoutIfNeeded()
                                                                })
        })
    }

    func prepareLocalMedia() {
        // Create an audio track.
        localAudioTrack = LocalAudioTrack()
        if (localAudioTrack == nil) {
            logMessage(messageText: "Failed to create audio track!")
            return
        }

        // Create a video track which captures from the front camera.
        guard let frontCamera = CameraSource.captureDevice(position: .front) else {
            logMessage(messageText: "Front camera is not available, using microphone only.")
            return
        }

        // We will render the camera using CameraPreviewView.
        let cameraSourceOptions = CameraSourceOptions() { (builder) in
            builder.enablePreview = true
        }

        self.camera = CameraSource(options: cameraSourceOptions, delegate: self)
        if let camera = self.camera {
            localVideoTrack = LocalVideoTrack(source: camera)
            logMessage(messageText: "Video track created.")

            if let preview = camera.previewView {
                let tap = UITapGestureRecognizer(target: self, action: #selector(ViewController.recognizeLocalAudio))
                preview.addGestureRecognizer(tap)
                view.addSubview(preview);
            }

            camera.startCapture(device: frontCamera) { (captureDevice, videoFormat, error) in
                if let error = error {
                    self.logMessage(messageText: "Capture failed with error.\ncode = \((error as NSError).code) error = \(error.localizedDescription)")
                    self.camera?.previewView?.removeFromSuperview()
                } else {
                    // Layout the camera preview with dimensions appropriate for our orientation.
                    self.view.setNeedsLayout()
                }
            }
        }
    }

    func setupRemoteVideoView(publication: RemoteVideoTrackPublication) {
        // Create a `VideoView` programmatically, and add to our `UIStackView`
        if let remoteView = VideoView(frame: CGRect.zero, delegate:nil) {
            // We will bet that a hash collision between two unique SIDs is very rare.
            remoteView.tag = publication.trackSid.hashValue

            // `VideoView` supports scaleToFill, scaleAspectFill and scaleAspectFit.
            // scaleAspectFit is the default mode when you create `VideoView` programmatically.
            remoteView.contentMode = .scaleAspectFit;

            // Double tap to change the content mode.
            let recognizerDoubleTap = UITapGestureRecognizer(target: self, action: #selector(ViewController.changeRemoteVideoAspect))
            recognizerDoubleTap.numberOfTapsRequired = 2
            remoteView.addGestureRecognizer(recognizerDoubleTap)

            // Single tap to recognize remote audio.
            let recognizerTap = UITapGestureRecognizer(target: self, action: #selector(ViewController.recognizeRemoteAudio))
            recognizerTap.require(toFail: recognizerDoubleTap)
            remoteView.addGestureRecognizer(recognizerTap)

            // Start rendering, and add to our stack.
            publication.remoteTrack?.addRenderer(remoteView)
            self.remoteViewStack.addArrangedSubview(remoteView)
        }
    }

    func removeRemoteVideoView(publication: RemoteVideoTrackPublication) {
        let viewTag = publication.trackSid.hashValue
        if let remoteView = self.remoteViewStack.viewWithTag(viewTag) {
            // Stop rendering, we don't want to receive any more frames.
            publication.remoteTrack?.removeRenderer(remoteView as! VideoRenderer)
            // Automatically removes us from the UIStackView's arranged subviews.
            remoteView.removeFromSuperview()
        }
    }

    @objc func changeRemoteVideoAspect(gestureRecognizer: UIGestureRecognizer) {
        guard let remoteView = gestureRecognizer.view else {
            print("Couldn't find a view attached to the tap recognizer. \(gestureRecognizer)")
            return;
        }

        if (remoteView.contentMode == .scaleAspectFit) {
            remoteView.contentMode = .scaleAspectFill
        } else {
            remoteView.contentMode = .scaleAspectFit
        }
    }
}

// MARK:- UITextFieldDelegate
extension ViewController : UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.connect(sender: textField)
        return true
    }
}

// MARK:- RoomDelegate
extension ViewController : RoomDelegate {
    func roomDidConnect(room: Room) {
        // Listen to events from existing `RemoteParticipant`s
        for remoteParticipant in room.remoteParticipants {
            remoteParticipant.delegate = self
        }

        // Wait until our LocalAudioTrack is assigned a SID to record it.
        if (recordAudio) {
            if let localParticipant = room.localParticipant {
                localParticipant.delegate = self
            }

            if let localAudioPublication = room.localParticipant?.localAudioTracks.first,
               let localAudioTrack = localAudioPublication.localTrack {
                let trackSid = localAudioPublication.trackSid
                self.audioRecorders[trackSid] = ExampleAudioRecorder(audioTrack: localAudioTrack,
                                                                     identifier: trackSid)
            }
        }

        var connectMessage = "Connected to room \(room.name) as \(room.localParticipant?.identity ?? "")."
        connectMessage.append("\nTap a video to recognize speech.")
        if (self.audioRecorders.count > 0) {
            connectMessage.append("\nRecording local audio...")
        }
        logMessage(messageText: connectMessage)
    }

    func roomDidDisconnect(room: Room, error: Error?) {
        if let disconnectError = error {
            logMessage(messageText: "Disconnected from \(room.name).\ncode = \((disconnectError as NSError).code) error = \(disconnectError.localizedDescription)")
        } else {
            logMessage(messageText: "Disconnected from \(room.name)")
        }

        for recorder in self.audioRecorders.values {
            recorder.stopRecording()
        }
        self.audioRecorders.removeAll()

        // Stop speech recognition!
        stopRecognizingAudio()

        self.room = nil

        self.showRoomUI(inRoom: false)
    }

    func roomDidFailToConnect(room: Room, error: Error) {
        logMessage(messageText: "Failed to connect to Room:\n\(error.localizedDescription)")
        self.room = nil

        self.showRoomUI(inRoom: false)
    }

    func roomIsReconnecting(room: Room, error: Error) {
        logMessage(messageText: "Reconnecting to room \(room.name), error = \(String(describing: error))")
    }

    func roomDidReconnect(room: Room) {
        logMessage(messageText: "Reconnected to room \(room.name)")
    }

    func participantDidConnect(room: Room, participant: RemoteParticipant) {
        participant.delegate = self

        logMessage(messageText: "Participant \(participant.identity) connected with \(participant.remoteAudioTracks.count) audio and \(participant.remoteVideoTracks.count) video tracks")
    }

    func participantDidDisconnect(room: Room, participant: RemoteParticipant) {
        logMessage(messageText: "Room \(room.name), Participant \(participant.identity) disconnected")
    }
}

// MARK:- RemoteParticipantDelegate
extension ViewController : RemoteParticipantDelegate {
    func remoteParticipantDidPublishVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        // Remote Participant has offered to share the video Track.

        logMessage(messageText: "Participant \(participant.identity) published \(publication.trackName) video track")
    }

    func remoteParticipantDidUnpublishVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        // Remote Participant has stopped sharing the video Track.

        logMessage(messageText: "Participant \(participant.identity) unpublished \(publication.trackName) video track")
    }

    func remoteParticipantDidPublishAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        // Remote Participant has offered to share the audio Track.

        logMessage(messageText: "Participant \(participant.identity) published \(publication.trackName) audio track")
    }

    func remoteParticipantDidUnpublishAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        // Remote Participant has stopped sharing the audio Track.

        logMessage(messageText: "Participant \(participant.identity) unpublished \(publication.trackName) audio track")
    }

    func didSubscribeToVideoTrack(videoTrack: RemoteVideoTrack, publication: RemoteVideoTrackPublication, participant: RemoteParticipant) {
        // We are subscribed to the remote Participant's video Track. We will start receiving the
        // remote Participant's video frames now.

        logMessage(messageText: "Subscribed to \(publication.trackName) video track for Participant \(participant.identity)")

        // Start remote rendering, and add a touch handler.
        if (self.remoteViewStack.arrangedSubviews.count < kMaxRemoteVideos) {
            setupRemoteVideoView(publication: publication)
        }
    }

    func didUnsubscribeFromVideoTrack(videoTrack: RemoteVideoTrack, publication: RemoteVideoTrackPublication, participant: RemoteParticipant) {
        // We are unsubscribed from the remote Participant's video Track. We will no longer receive the
        // remote Participant's video.

        logMessage(messageText: "Unsubscribed from \(publication.trackName) video track for Participant \(participant.identity)")

        // Stop remote rendering.
        removeRemoteVideoView(publication: publication)
    }

    func didSubscribeToAudioTrack(audioTrack: RemoteAudioTrack, publication: RemoteAudioTrackPublication, participant: RemoteParticipant) {
        // We are subscribed to the remote Participant's audio Track. We will start receiving the
        // remote Participant's audio now.

        logMessage(messageText: "Subscribed to \(publication.trackName) audio track for Participant \(participant.identity)")

        if (self.recordAudio) {
            self.audioRecorders[publication.trackSid] = ExampleAudioRecorder(audioTrack: audioTrack,
                                                                             identifier: publication.trackSid)
        }
    }

    func didUnsubscribeFromAudioTrack(audioTrack: RemoteAudioTrack, publication: RemoteAudioTrackPublication, participant: RemoteParticipant) {
        // We are unsubscribed from the remote Participant's audio Track. We will no longer receive the
        // remote Participant's audio.

        logMessage(messageText: "Unsubscribed from \(publication.trackName) audio track for Participant \(participant.identity)")

        if let recorder = self.audioRecorders[publication.trackSid] {
            recorder.stopRecording()
            self.audioRecorders.removeValue(forKey: publication.trackSid)
        }

        if (self.speechRecognizer?.identifier == publication.trackSid) {
            self.speechRecognizer?.stopRecognizing()
            self.speechRecognizer = nil
        }
    }

    func remoteParticipantDidEnableVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) enabled \(publication.trackName) video track")
    }

    func remoteParticipantDidDisableVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) disabled \(publication.trackName) video track")
    }

    func remoteParticipantDidEnableAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) enabled \(publication.trackName) audio track")
    }

    func remoteParticipantDidDisableAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        // We will continue to record silence and/or recognize audio while a Track is disabled.
        logMessage(messageText: "Participant \(participant.identity) disabled \(publication.trackName) audio track")
    }

    func didFailToSubscribeToAudioTrack(publication: RemoteAudioTrackPublication, error: Error, participant: RemoteParticipant) {
        logMessage(messageText: "FailedToSubscribe \(publication.trackName) audio track, error = \(String(describing: error))")
    }

    func didFailToSubscribeToVideoTrack(publication: RemoteVideoTrackPublication, error: Error, participant: RemoteParticipant) {
        logMessage(messageText: "FailedToSubscribe \(publication.trackName) video track, error = \(String(describing: error))")
    }
}

// MARK:- LocalParticipantDelegate
extension ViewController : LocalParticipantDelegate {
    func localParticipantDidPublishAudioTrack(participant: LocalParticipant, audioTrackPublication: LocalAudioTrackPublication) {
        // We expect to publish our AudioTrack at Room connect time, but handle a late publish just to be sure.
        if (recordAudio) {
            let trackSid = audioTrackPublication.trackSid
            self.audioRecorders[trackSid] = ExampleAudioRecorder(audioTrack: audioTrackPublication.localTrack!,
                                                                 identifier: trackSid)
            logMessage(messageText: "Recording local audio...")
        }
    }
}

// MARK:- CameraSourceDelegate
extension ViewController : CameraSourceDelegate {
    func cameraSourceDidFail(source: CameraSource, error: Error) {
        logMessage(messageText: "Camera source failed with error: \(error.localizedDescription)")
        source.previewView?.removeFromSuperview()
    }
}
