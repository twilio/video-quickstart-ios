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
    // at https://www.twilio.com/console/video/runtime/testing-tools
    var accessToken = "TWILIO_ACCESS_TOKEN"

    // Configure remote URL to fetch token from
    let tokenUrl = "http://localhost:8000/token.php"

    // Automatically record audio for all `TVIAudioTrack`s published in a Room.
    let recordAudio = true

    // Video SDK components
    var room: TVIRoom?
    var camera: TVICameraSource?
    var localAudioTrack: TVILocalAudioTrack!
    var localVideoTrack: TVILocalVideoTrack!

    // Audio Sinks
    var audioRecorders = Dictionary<String, ExampleAudioRecorder>()
    var speechRecognizer: ExampleSpeechRecognizer?

    // MARK: UI Element Outlets and handles

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

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "AudioSink Example"
        disconnectButton.isHidden = true
        disconnectButton.setTitleColor(UIColor.init(white: 0.75, alpha: 1), for: .disabled)
        connectButton.setTitleColor(UIColor.init(white: 0.75, alpha: 1), for: .disabled)
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

            if let audioTrack = self.localAudioTrack {
                builder.audioTracks = [audioTrack]
            }
            if let videoTrack = self.localVideoTrack {
                builder.videoTracks = [videoTrack]
            }

            // Use the preferred codecs
            if let preferredAudioCodec = Settings.shared.audioCodec {
                builder.preferredAudioCodecs = [preferredAudioCodec]
            }
            if let preferredVideoCodec = Settings.shared.videoCodec {
                builder.preferredVideoCodecs = [preferredVideoCodec]
            }

            // Use the preferred encoding parameters
            if let encodingParameters = Settings.shared.getEncodingParameters() {
                builder.encodingParameters = encodingParameters
            }

            // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty
            // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
            builder.roomName = self.roomTextField.text
        }

        // Connect to the Room using the options we provided.
        room = TwilioVideo.connect(with: connectOptions, delegate: self)

        logMessage(messageText: "Connecting to \(roomTextField.text ?? "a Room")")

        self.showRoomUI(inRoom: true)
        self.dismissKeyboard()
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
        if #available(iOS 11.0, *) {
            // Ensure the preview fits in the safe area.
            let safeAreaGuide = self.view.safeAreaLayoutGuide
            let layoutFrame = safeAreaGuide.layoutFrame
            bottomRight.x = layoutFrame.origin.x + layoutFrame.width
            bottomRight.y = layoutFrame.origin.y + layoutFrame.height
            layoutWidth = layoutFrame.width
        }

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
            var previewBounds = CGRect.init(origin: CGPoint.zero, size: CGSize.init(width: 160, height: 160))
            previewBounds = AVMakeRect(aspectRatio: CGSize.init(width: CGFloat(dimensions.width),
                                                                height: CGFloat(dimensions.height)),
                                       insideRect: previewBounds)

            previewBounds = previewBounds.integral
            previewView.bounds = previewBounds
            previewView.center = CGPoint.init(x: bottomRight.x - previewBounds.width / 2 - kPreviewPadding,
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
        if #available(iOS 11.0, *) {
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
        self.setNeedsStatusBarAppearanceUpdate()

        self.navigationController?.setNavigationBarHidden(inRoom, animated: true)
    }

    func showSpeechRecognitionUI(view: UIView, message: String) {
        // Create a dimmer view for the Participant being recognized.
        let dimmer = UIView.init(frame: view.bounds)
        dimmer.alpha = 0
        dimmer.backgroundColor = UIColor.init(white: 1, alpha: 0.26)
        dimmer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(dimmer)
        self.dimmingView = dimmer
        self.speechRecognizerView = view

        // Create a label which will be added to the stack and display recognized speech.
        let messageLabel = UILabel.init()
        messageLabel.font = UIFont.boldSystemFont(ofSize: 16)
        messageLabel.textColor = UIColor.white
        messageLabel.backgroundColor = UIColor.init(red: 226/255, green: 29/255, blue: 37/255, alpha: 1)
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
            view.transform = CGAffineTransform.init(scaleX: 1.08, y: 1.08)
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
        messageLabel.text = messageText

        if (messageLabel.alpha < 1.0) {
            self.messageLabel.isHidden = false
            UIView.animate(withDuration: 0.4, animations: {
                self.messageLabel.alpha = 1.0
            })
        }

        // Hide the message with a delay.
        self.messageTimer?.invalidate()
        let timer = Timer.init(timeInterval: TimeInterval(6), repeats: false) { (timer) in
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

    // MARK: Speech Recognition
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

    func recognizeRemoteParticipantAudio(audioTrack: TVIRemoteAudioTrack, sid: String, name: String, view: UIView) {
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
            
            if (self.room?.state == TVIRoomState.connected) {
                if let view = self.camera?.previewView {
                    showSpeechRecognitionUI(view: view,
                                            message: "Listening to \(room?.localParticipant?.identity ?? "yourself")...")
                }

                recognizeAudio(audioTrack: audioTrack, identifier: audioTrack.name)
            }
        }
    }

    func recognizeAudio(audioTrack: TVIAudioTrack, identifier: String) {
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
        localAudioTrack = TVILocalAudioTrack.init()
        if (localAudioTrack == nil) {
            logMessage(messageText: "Failed to create audio track!")
            return
        }

        // Create a video track which captures from the front camera.
        guard let frontCamera = TVICameraSource.captureDevice(for: .front) else {
            logMessage(messageText: "Front camera is not available, using microphone only.")
            return
        }

        // We will render the camera using TVICameraPreviewView.
        let cameraSourceOptions = TVICameraSourceOptions.init { (builder) in
            builder.enablePreview = true
        }

        self.camera = TVICameraSource(options: cameraSourceOptions, delegate: self)
        if let camera = self.camera {
            localVideoTrack = TVILocalVideoTrack.init(source: camera)
            logMessage(messageText: "Video track created.")

            if let preview = camera.previewView {
                let tap = UITapGestureRecognizer(target: self, action: #selector(ViewController.recognizeLocalAudio))
                preview.addGestureRecognizer(tap)
                view.addSubview(preview);
            }

            camera.startCapture(with: frontCamera) { (captureDevice, videoFormat, error) in
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

    func setupRemoteVideoView(publication: TVIRemoteVideoTrackPublication) {
        // Create a `TVIVideoView` programmatically, and add to our `UIStackView`
        if let remoteView = TVIVideoView.init(frame: CGRect.zero, delegate:nil) {
            // We will bet that a hash collision between two unique SIDs is very rare.
            remoteView.tag = publication.trackSid.hashValue

            // `TVIVideoView` supports scaleToFill, scaleAspectFill and scaleAspectFit.
            // scaleAspectFit is the default mode when you create `TVIVideoView` programmatically.
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

    func removeRemoteVideoView(publication: TVIRemoteVideoTrackPublication) {
        let viewTag = publication.trackSid.hashValue
        if let remoteView = self.remoteViewStack.viewWithTag(viewTag) {
            // Stop rendering, we don't want to receive any more frames.
            publication.remoteTrack?.removeRenderer(remoteView as! TVIVideoRenderer)
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

        // Listen to events from existing `TVIRemoteParticipant`s
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
                self.audioRecorders[trackSid] = ExampleAudioRecorder.init(audioTrack: localAudioTrack,
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

    func room(_ room: TVIRoom, didDisconnectWithError error: Error?) {
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

    func room(_ room: TVIRoom, didFailToConnectWithError error: Error) {
        logMessage(messageText: "Failed to connect to Room:\n\(error.localizedDescription)")
        self.room = nil

        self.showRoomUI(inRoom: false)
    }

    func room(_ room: TVIRoom, participantDidConnect participant: TVIRemoteParticipant) {
        participant.delegate = self

        logMessage(messageText: "Participant \(participant.identity) connected with \(participant.remoteAudioTracks.count) audio and \(participant.remoteVideoTracks.count) video tracks")
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

    func subscribed(to videoTrack: TVIRemoteVideoTrack,
                    publication: TVIRemoteVideoTrackPublication,
                    for participant: TVIRemoteParticipant) {

        // We are subscribed to the remote Participant's video Track. We will start receiving the
        // remote Participant's video frames now.

        logMessage(messageText: "Subscribed to \(publication.trackName) video track for Participant \(participant.identity)")

        // Start remote rendering, and add a touch handler.
        if (self.remoteViewStack.arrangedSubviews.count < kMaxRemoteVideos) {
            setupRemoteVideoView(publication: publication)
        }
    }

    func unsubscribed(from videoTrack: TVIRemoteVideoTrack,
                      publication: TVIRemoteVideoTrackPublication,
                      for participant: TVIRemoteParticipant) {

        // We are unsubscribed from the remote Participant's video Track. We will no longer receive the
        // remote Participant's video.

        logMessage(messageText: "Unsubscribed from \(publication.trackName) video track for Participant \(participant.identity)")

        // Stop remote rendering.
        removeRemoteVideoView(publication: publication)
    }

    func subscribed(to audioTrack: TVIRemoteAudioTrack,
                    publication: TVIRemoteAudioTrackPublication,
                    for participant: TVIRemoteParticipant) {

        // We are subscribed to the remote Participant's audio Track. We will start receiving the
        // remote Participant's audio now.

        logMessage(messageText: "Subscribed to \(publication.trackName) audio track for Participant \(participant.identity)")

        if (self.recordAudio) {
            self.audioRecorders[publication.trackSid] = ExampleAudioRecorder.init(audioTrack: audioTrack,
                                                                                  identifier: publication.trackSid)
        }
    }

    func unsubscribed(from audioTrack: TVIRemoteAudioTrack,
                      publication: TVIRemoteAudioTrackPublication,
                      for participant: TVIRemoteParticipant) {

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
        // We will continue to record silence and/or recognize audio while a Track is disabled.
        logMessage(messageText: "Participant \(participant.identity) disabled \(publication.trackName) audio track")
    }

    func failedToSubscribe(toAudioTrack publication: TVIRemoteAudioTrackPublication,
                           error: Error,
                           for participant: TVIRemoteParticipant) {
        logMessage(messageText: "FailedToSubscribe \(publication.trackName) audio track, error = \(String(describing: error))")
    }

    func failedToSubscribe(toVideoTrack publication: TVIRemoteVideoTrackPublication,
                           error: Error,
                           for participant: TVIRemoteParticipant) {
        logMessage(messageText: "FailedToSubscribe \(publication.trackName) video track, error = \(String(describing: error))")
    }
}

// MARK: TVILocalParticipantDelegate
extension ViewController : TVILocalParticipantDelegate {
    func localParticipant(_ participant: TVILocalParticipant, publishedAudioTrack: TVILocalAudioTrackPublication) {
        // We expect to publish our AudioTrack at Room connect time, but handle a late publish just to be sure.
        if (recordAudio) {
            let trackSid = publishedAudioTrack.trackSid
            self.audioRecorders[trackSid] = ExampleAudioRecorder.init(audioTrack: publishedAudioTrack.localTrack!,
                                                                      identifier: trackSid)
            logMessage(messageText: "Recording local audio...")
        }
    }
}

// MARK: TVICameraSourceDelegate
extension ViewController : TVICameraSourceDelegate {
    func cameraSource(_ source: TVICameraSource, didFailWithError error: Error) {
        logMessage(messageText: "Camera source failed with error: \(error.localizedDescription)")
        source.previewView?.removeFromSuperview()
    }
}
