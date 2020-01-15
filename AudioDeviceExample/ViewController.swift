//
//  ViewController.swift
//  AudioDeviceExample
//
//  Copyright © 2018-2019 Twilio Inc. All rights reserved.
//

import TwilioVideo
import UIKit

class ViewController: UIViewController {

    // MARK:- View Controller Members

    // Configure access token manually for testing, if desired! Create one manually in the console
    // at https://www.twilio.com/console/video/runtime/testing-tools
    var accessToken = "TWILIO_ACCESS_TOKEN"

    // Configure remote URL to fetch token from
    let tokenUrl = "http://localhost:8000/token.php"

    // Video SDK components
    var room: Room?
    var camera: CameraSource?
    var localVideoTrack: LocalVideoTrack!
    var localAudioTrack: LocalAudioTrack!
    var audioDevice: AudioDevice = ExampleCoreAudioDevice()

    // MARK:- UI Element Outlets and handles

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
    static let engineAudioDeviceText = "AVAudioEngine Device"
    
    deinit {
        // We are done with camera
        if let camera = self.camera {
            camera.stopCapture()
            self.camera = nil
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "AudioDevice Example"
        disconnectButton.isHidden = true
        musicButton.isHidden = true
        disconnectButton.setTitleColor(UIColor(white: 0.75, alpha: 1), for: .disabled)
        connectButton.setTitleColor(UIColor(white: 0.75, alpha: 1), for: .disabled)
        roomTextField.autocapitalizationType = .none
        roomTextField.delegate = self
        logMessage(messageText: ViewController.coreAudioDeviceText + " selected")
        audioDeviceButton.setTitle("CoreAudio Device", for: .normal)

        prepareLocalMedia()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    @IBAction func selectAudioDevice() {
        var coreAudioDeviceButton : UIAlertAction!
        var audioEngineDeviceButton : UIAlertAction?

        var selectedButton : UIAlertAction!

        let alertController = UIAlertController(title: "Select Audio Device", message: nil, preferredStyle: .actionSheet)

        // ExampleCoreAudioDevice
        coreAudioDeviceButton = UIAlertAction(title: ViewController.coreAudioDeviceText,
                                              style: .default,
                                              handler: { (action) -> Void in
                                                self.coreAudioDeviceSelected()
        })
        alertController.addAction(coreAudioDeviceButton!)

        // EngineAudioDevice
        var audioEngineDeviceTitle = ""
        if #available(iOS 11.0, *) {
            audioEngineDeviceTitle = ViewController.engineAudioDeviceText
        } else {
            audioEngineDeviceTitle = "AVAudioEngine Device (iOS 11+ only)"
        }
        audioEngineDeviceButton = UIAlertAction(title: audioEngineDeviceTitle,
                                                style: .default,
                                                handler: { (action) -> Void in
                                                    self.avAudioEngineDeviceSelected()
        })

        // EXampleAVAudioEngineDevice is supported only on iOS 11+
        if let deviceButton = audioEngineDeviceButton {
            if #available(iOS 11.0, *) {
                deviceButton.isEnabled = true
            } else {
                deviceButton.isEnabled = false
            }
        }

        alertController.addAction(audioEngineDeviceButton!)

        if (self.audioDevice is ExampleCoreAudioDevice) {
            selectedButton = coreAudioDeviceButton
        } else if #available(iOS 11.0, *) {
            if (self.audioDevice is ExampleAVAudioEngineDevice) {
                selectedButton = audioEngineDeviceButton
            }
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

    func coreAudioDeviceSelected() {
        /*
         * To set an audio device on Video SDK, it is necessary to destroyed the media engine first. By cleaning up the
         * Room and Tracks the media engine gets destroyed.
         */
        self.unprepareLocalMedia()

        self.audioDevice = ExampleCoreAudioDevice()
        self.audioDeviceButton.setTitle(ViewController.coreAudioDeviceText, for: .normal)
        self.logMessage(messageText: ViewController.coreAudioDeviceText + " Selected")

        self.prepareLocalMedia()
    }

    func avAudioEngineDeviceSelected() {
        if #available(iOS 11.0, *) {
            /*
             * To set an audio device on Video SDK, it is necessary to destroyed the media engine first. By cleaning up the
             * Room and Tracks the media engine gets destroyed.
             */
            self.unprepareLocalMedia()

            self.audioDevice = ExampleAVAudioEngineDevice()
            self.audioDeviceButton.setTitle(ViewController.engineAudioDeviceText, for: .normal)
            self.logMessage(messageText: ViewController.coreAudioDeviceText + " Selected")

            self.prepareLocalMedia()
        }
    }

    // MARK:- IBActions
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
        let connectOptions = ConnectOptions(token: accessToken) { (builder) in

            if let videoTrack = self.localVideoTrack {
                builder.videoTracks = [videoTrack]
            }

            // We will share a local audio track only if ExampleAVAudioEngineDevice is selected.
            if let audioTrack = self.localAudioTrack {
                builder.audioTracks = [audioTrack]
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

    @IBAction func disconnect(sender: UIButton) {
        if let room = self.room {
            logMessage(messageText: "Disconnecting from \(room.name)")
            room.disconnect()
            sender.isEnabled = false
        }
    }


    @IBAction func playMusic(sender: UIButton) {
        if #available(iOS 11.0, *) {
            if let audioDevice = self.audioDevice as? ExampleAVAudioEngineDevice {
                audioDevice.playMusic()
            }
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        // Layout the preview view.
        if let previewView = self.camera?.previewView {
            var bottomRight = CGPoint(x: view.bounds.width, y: view.bounds.height)
            if #available(iOS 11.0, *) {
                // Ensure the preview fits in the safe area.
                let safeAreaGuide = self.view.safeAreaLayoutGuide
                let layoutFrame = safeAreaGuide.layoutFrame
                bottomRight.x = layoutFrame.origin.x + layoutFrame.width
                bottomRight.y = layoutFrame.origin.y + layoutFrame.height
            }

            let dimensions = previewView.videoDimensions
            var previewBounds = CGRect(origin: CGPoint.zero, size: CGSize(width: 160, height: 160))
            previewBounds = AVMakeRect(aspectRatio: CGSize(width: CGFloat(dimensions.width),
                                                           height: CGFloat(dimensions.height)),
                                       insideRect: previewBounds)

            previewBounds = previewBounds.integral
            previewView.bounds = previewBounds
            previewView.center = CGPoint(x: bottomRight.x - previewBounds.width / 2 - kPreviewPadding,
                                         y: bottomRight.y - previewBounds.height / 2 - kPreviewPadding)
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
        self.audioDeviceButton.isHidden = inRoom
        self.audioDeviceButton.isEnabled = !inRoom

        if #available(iOS 11.0, *) {
            if ((self.audioDevice as? ExampleAVAudioEngineDevice) != nil) {
                self.musicButton.isHidden = !inRoom
                self.musicButton.isEnabled = inRoom
            }
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

        self.messageTimer = Timer(timeInterval: TimeInterval(6),
                                  target: self,
                                  selector: #selector(hideMessageLabel),
                                  userInfo: nil,
                                  repeats: false)
        RunLoop.main.add(self.messageTimer, forMode: RunLoop.Mode.common)
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
         * The important thing to remember when using a custom AudioDevice is that the device must be set
         * before performing any other actions with the SDK (such as creating Tracks, or connecting to a Room).
         */
        TwilioVideoSDK.audioDevice = self.audioDevice

        if #available(iOS 11.0, *) {
            // Only the ExampleAVAudioEngineDevice supports local audio capturing.
            if (TwilioVideoSDK.audioDevice is ExampleAVAudioEngineDevice) {
                localAudioTrack = LocalAudioTrack()
            }
        }

        /*
         * ExampleCoreAudioDevice is a playback only device. Because of this, any attempts to create a
         * LocalAudioTrack will result in an exception being thrown. In this example we will only share video
         * (where available) and not audio.
         */
        guard let frontCamera = CameraSource.captureDevice(position: .front) else {
            logMessage(messageText: "Front camera is not available, using audio only.")
            return
        }

        // We will render the camera using CameraPreviewView.
        let cameraSourceOptions = CameraSourceOptions() { (builder) in
            builder.enablePreview = true
        }

        camera = CameraSource(options: cameraSourceOptions, delegate: self)
        localVideoTrack = LocalVideoTrack(source: camera!)

        if (localVideoTrack == nil) {
            logMessage(messageText: "Failed to create video track!")
        } else {
            logMessage(messageText: "Video track created.")

            if let preview = camera?.previewView {
                view.addSubview(preview);
            }

            camera!.startCapture(device: frontCamera) { (captureDevice, videoFormat, error) in
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

    func unprepareLocalMedia() {
        self.room = nil
        self.localAudioTrack = nil
        self.localVideoTrack = nil
        self.camera?.previewView?.removeFromSuperview()
        self.camera = nil;
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

        let connectMessage = "Connected to room \(room.name) as \(room.localParticipant?.identity ?? "")."
        logMessage(messageText: connectMessage)
    }

    func roomDidDisconnect(room: Room, error: Error?) {
        if let disconnectError = error {
            logMessage(messageText: "Disconnected from \(room.name).\ncode = \((disconnectError as NSError).code) error = \(disconnectError.localizedDescription)")
        } else {
            logMessage(messageText: "Disconnected from \(room.name)")
        }

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
    }

    func didUnsubscribeFromAudioTrack(audioTrack: RemoteAudioTrack, publication: RemoteAudioTrackPublication, participant: RemoteParticipant) {
        // We are unsubscribed from the remote Participant's audio Track. We will no longer receive the
        // remote Participant's audio.

        logMessage(messageText: "Unsubscribed from \(publication.trackName) audio track for Participant \(participant.identity)")
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

// MARK:- CameraSourceDelegate
extension ViewController : CameraSourceDelegate {
    func cameraSourceDidFail(source: CameraSource, error: Error) {
        logMessage(messageText: "Camera source failed with error: \(error.localizedDescription)")
        source.previewView?.removeFromSuperview()
    }
}
