//
//  ViewController.swift
//  AudioDeviceExample
//
//  Copyright © 2018 Twilio Inc. All rights reserved.
//

import TwilioVideo
import UIKit

class ViewController: UIViewController {

    // MARK: View Controller Members

    // Configure access token manually for testing, if desired! Create one manually in the console
    // at https://www.twilio.com/console/video/runtime/testing-tools
    var accessToken = "TWILIO_ACCESS_TOKEN"

    // Configure remote URL to fetch token from
    let tokenUrl = "http://localhost:8000/token.php"

    // Video SDK components
    var room: TVIRoom?
    var camera: TVICameraCapturer?
    var localVideoTrack: TVILocalVideoTrack!
    var localAudioTrack: TVILocalAudioTrack!
    var audioDevice: TVIAudioDevice = ExampleCoreAudioDevice()

    // MARK: UI Element Outlets and handles

    @IBOutlet weak var audioDeviceButton: UIButton!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet weak var musicButton: UIButton!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var remoteViewStack: UIStackView!
    @IBOutlet weak var roomTextField: UITextField!
    @IBOutlet weak var roomLine: UIView!
    @IBOutlet weak var roomLabel: UILabel!

    var messageTimer: Timer!

    let kPreviewPadding = CGFloat(10)
    let kTextBottomPadding = CGFloat(4)
    let kMaxRemoteVideos = Int(2)

    static let coreAudioDeviceText = "CoreAudio Device"
    static let engineAudioDeviceText = "AudioEngine Device"

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "AudioDevice Example"
        disconnectButton.isHidden = true
        musicButton.isHidden = true
        disconnectButton.setTitleColor(UIColor.init(white: 0.75, alpha: 1), for: .disabled)
        connectButton.setTitleColor(UIColor.init(white: 0.75, alpha: 1), for: .disabled)
        roomTextField.autocapitalizationType = .none
        roomTextField.delegate = self
        logMessage(messageText: ViewController.coreAudioDeviceText + " Device selected")
        audioDeviceButton.setTitle("CoreAudio Device", for: .normal)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    @IBAction func selectAudioDevice() {
        var coreAudioDeviceButton : UIAlertAction!
        var engineAudioDeviceButton : UIAlertAction?

        var selectedButton : UIAlertAction!

        let alertController = UIAlertController(title: "Select Audio Device", message: nil, preferredStyle: .actionSheet)

        // ExampleCoreAudioDevice
        coreAudioDeviceButton = UIAlertAction(title: ViewController.coreAudioDeviceText,
                                              style: .default,
                                              handler: { (action) -> Void in
            self.audioDevice = ExampleCoreAudioDevice()
            self.audioDeviceButton.setTitle("CoreAudio Device", for: .normal)
            self.logMessage(messageText: ViewController.coreAudioDeviceText + " Device Selected")
        })
        alertController.addAction(coreAudioDeviceButton!)

        // EngineAudioDevice
        var audioEngineDeviceTitle = ""
        if #available(iOS 11.0, *) {
            audioEngineDeviceTitle = "AVAudioEngine Device"
        } else {
            audioEngineDeviceTitle = "AVAudioEngine Device (iOS 11+ only)"
        }
        engineAudioDeviceButton = UIAlertAction(title: audioEngineDeviceTitle,
                                                style: .default,
                                                handler: { (action) -> Void in
            self.audioDevice = ExampleAudioEngineDevice()
            self.audioDeviceButton.setTitle("AudioEngine Device", for: .normal)
            self.logMessage(messageText: ViewController.engineAudioDeviceText + " Device Selected")
        })

        if #available(iOS 11.0, *) {
            if let deviceButton = engineAudioDeviceButton {
                deviceButton.isEnabled = true
            }
        } else {
            if let deviceButton = engineAudioDeviceButton {
                deviceButton.isEnabled = false
            }
        }

        alertController.addAction(engineAudioDeviceButton!)

        if (self.audioDevice.isKind(of: ExampleCoreAudioDevice.self)) {
            selectedButton = coreAudioDeviceButton
        } else if (self.audioDevice.isKind(of: ExampleAudioEngineDevice.self)) {
            selectedButton = engineAudioDeviceButton
        }

        if UIDevice.current.userInterfaceIdiom == .pad {
            alertController.popoverPresentationController?.sourceView = self.audioDeviceButton
            alertController.popoverPresentationController?.sourceRect = self.audioDeviceButton.bounds
        } else {
            selectedButton?.setValue("true", forKey: "checked")

            // Adding the cancel action
            let cancelButton = UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) -> Void in })
            alertController.addAction(cancelButton)
        }
        self.navigationController!.present(alertController, animated: true, completion: nil)
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

        prepareLocalMedia()

        // Preparing the connect options with the access token that we fetched (or hardcoded).
        let connectOptions = TVIConnectOptions.init(token: accessToken) { (builder) in

            // This example does not share audio since the ExampleCoreAudioDevice is playback only.
            if let videoTrack = self.localVideoTrack {
                builder.videoTracks = [videoTrack]
            }

            if let audioTrack = self.localAudioTrack {
                builder.audioTracks = [audioTrack]
            }

            // Use the preferred codecs
            if let preferredAudioCodec = Settings.shared.audioCodec {
                builder.preferredAudioCodecs = [preferredAudioCodec.rawValue]
            }
            if let preferredVideoCodec = Settings.shared.videoCodec {
                builder.preferredVideoCodecs = [preferredVideoCodec.rawValue]
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


    @IBAction func playMusic(sender: UIButton) {
        if #available(iOS 11.0, *) {
            if let audioDevie = self.audioDevice as? ExampleAudioEngineDevice {
                audioDevie.playMusic()
            }
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
            previewView.bounds = previewBounds

            previewView.center = CGPoint.init(x: view.bounds.width - previewBounds.width / 2 - kPreviewPadding,
                                              y: view.bounds.height - previewBounds.height / 2 - kPreviewPadding)
        }
    }

    override func prefersHomeIndicatorAutoHidden() -> Bool {
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
            if ((self.audioDevice as? ExampleAudioEngineDevice) != nil) {
                self.musicButton.isHidden = !inRoom
                self.musicButton.isEnabled = inRoom
            }
            self.audioDeviceButton.isHidden = inRoom
            self.audioDeviceButton.isEnabled = !inRoom

            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
        self.setNeedsStatusBarAppearanceUpdate()

        self.navigationController?.setNavigationBarHidden(inRoom, animated: true)
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

        self.messageTimer = Timer.init(timeInterval: TimeInterval(6),
                                       target: self,
                                       selector: #selector(hideMessageLabel),
                                       userInfo: nil,
                                       repeats: false)
        RunLoop.main.add(self.messageTimer, forMode: .commonModes)
    }

    @objc func hideMessageLabel() {
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

    func prepareLocalMedia() {
        /*
         * The important thing to remember when using a custom TVIAudioDevice is that the device must be set
         * before performing any other actions with the SDK (such as creating Tracks, or connecting to a Room).
         */
        TwilioVideo.audioDevice = self.audioDevice

        if #available(iOS 11.0, *) {
            // Only the ExampleAudioEngineDevice supports local audio capturing.
            if ((TwilioVideo.audioDevice as? ExampleAudioEngineDevice) != nil) {
                localAudioTrack = TVILocalAudioTrack()
            }
        }

        /*
         * ExampleCoreAudioDevice is a playback only device. Because of this, any attempts to create a
         * TVILocalAudioTrack will result in an exception being thrown. In this example we will only share video
         * (where available) and not audio.
         */
        if (TVICameraCapturer.isSourceAvailable(TVICameraCaptureSource.frontCamera)) {

            // We will render the camera using TVICameraPreviewView.
            camera = TVICameraCapturer(source: .frontCamera, delegate: self, enablePreview: true)
            localVideoTrack = TVILocalVideoTrack.init(capturer: camera!)

            if (localVideoTrack == nil) {
                logMessage(messageText: "Failed to create video track!")
            } else {
                logMessage(messageText: "Video track created.")

                if let preview = camera?.previewView {
                    view.addSubview(preview);
                }
            }
        } else {
            logMessage(messageText: "Front camera is not available, using audio playback only.")
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

    func changeRemoteVideoAspect(gestureRecognizer: UIGestureRecognizer) {
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

        let connectMessage = "Connected to room \(room.name) as \(room.localParticipant?.identity ?? "")."
        logMessage(messageText: connectMessage)
    }

    func room(_ room: TVIRoom, didDisconnectWithError error: Error?) {
        if let disconnectError = error {
            logMessage(messageText: "Disconnected from \(room.name).\ncode = \((disconnectError as NSError).code) error = \(disconnectError.localizedDescription)")
        } else {
            logMessage(messageText: "Disconnected from \(room.name)")
        }

        self.room = nil
        self.localAudioTrack = nil
        self.localVideoTrack = nil
        self.camera?.previewView .removeFromSuperview()
        self.camera = nil;

        self.showRoomUI(inRoom: false)
    }

    func room(_ room: TVIRoom, didFailToConnectWithError error: Error) {
        logMessage(messageText: "Failed to connect to Room:\n\(error.localizedDescription)")

        self.room = nil
        self.localAudioTrack = nil
        self.localVideoTrack = nil
        self.camera?.previewView .removeFromSuperview()
        self.camera = nil;

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
    }

    func unsubscribed(from audioTrack: TVIRemoteAudioTrack,
                      publication: TVIRemoteAudioTrackPublication,
                      for participant: TVIRemoteParticipant) {

        // We are unsubscribed from the remote Participant's audio Track. We will no longer receive the
        // remote Participant's audio.

        logMessage(messageText: "Unsubscribed from \(publication.trackName) audio track for Participant \(participant.identity)")
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

extension ViewController : TVICameraCapturerDelegate {
    func cameraCapturer(_ capturer: TVICameraCapturer, didStartWith source: TVICameraCaptureSource) {
        // Layout the camera preview with dimensions appropriate for our orientation.
        self.view.setNeedsLayout()
    }

    func cameraCapturer(_ capturer: TVICameraCapturer, didFailWithError error: Error) {
        logMessage(messageText: "Capture failed with error.\ncode = \((error as NSError).code) error = \(error.localizedDescription)")
        capturer.previewView.removeFromSuperview()
    }
}

