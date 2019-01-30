//
//  ViewController.swift
//  VideoRendererExample
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

    // Video SDK components
    var room: TVIRoom?
    var camera: TVICameraSource?
    var localAudioTrack: TVILocalAudioTrack?
    var localVideoTrack: TVILocalVideoTrack?
    var localVideoRecorder: ExampleVideoRecorder?

    // MARK: UI Element Outlets and handles

    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var remoteViewStack: UIStackView!
    @IBOutlet weak var roomTextField: UITextField!
    @IBOutlet weak var roomLine: UIView!
    @IBOutlet weak var roomLabel: UILabel!

    var messageTimer: Timer!

    let kPreviewPadding = CGFloat(10)

    // How many remote videos to display.
    let kMaxRemoteVideos = Int(2)

    // Use ExampleSampleBufferView instead of TVIVideoView to render remote Participant video.
    let kUseExampleSampleBufferView = true

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "VideoRenderer Example"
        disconnectButton.isHidden = true
        disconnectButton.setTitleColor(UIColor.init(white: 0.75, alpha: 1), for: .disabled)
        connectButton.setTitleColor(UIColor.init(white: 0.75, alpha: 1), for: .disabled)
        roomTextField.autocapitalizationType = .none
        roomTextField.delegate = self

        // Prefer to work which H.264 where we can guarantee rendering of decoded video using ExampleSampleBufferView.
        Settings.shared.videoCodec = TVIH264Codec.init()
        // Use a reasonable video bandwidth limit of 1100 kbps.
        Settings.shared.maxVideoBitrate = 1024 * 1100

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
            var previewBounds = CGRect.init(origin: CGPoint.zero, size: CGSize.init(width: 160, height: 160))

            previewBounds = AVMakeRect(aspectRatio: CGSize.init(width: CGFloat(dimensions.width),
                                                                height: CGFloat(dimensions.height)),
                                       insideRect: previewBounds)

            previewBounds = previewBounds.integral
            previewView.bounds = previewBounds

            previewView.center = CGPoint.init(x: bottomRight.x - previewBounds.width / 2 - kPreviewPadding,
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
        if #available(iOS 11.0, *) {
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
                view.addSubview(preview);
            }

            camera.startCapture(with: frontCamera) { (captureDevice, videoFormat, error) in
                if let error = error {
                    self.logMessage(messageText: "Capture failed with error.\ncode = \((error as NSError).code) error = \(error.localizedDescription)")
                    self.camera?.previewView?.removeFromSuperview()
                } else {
                    // Layout the camera preview with dimensions appropriate for our orientation.
                    self.view.setNeedsLayout()
                    self.prepareVideoRecording(track: self.localVideoTrack!)
                }
            }
        }
    }

    func prepareVideoRecording(track: TVILocalVideoTrack) {
        if self.localVideoRecorder == nil {
            self.localVideoRecorder = ExampleVideoRecorder(videoTrack: track, identifier: track.name)
        }
    }

    func setupRemoteVideoView(publication: TVIRemoteVideoTrackPublication) {
        // Create `ExampleSampleBufferRenderer`, and add it to our `UIStackView`.
        let remoteView = kUseExampleSampleBufferView ?
            ExampleSampleBufferView(frame: CGRect.zero) : TVIVideoView(frame: CGRect.zero)

        // We will bet that a hash collision between two unique SIDs is very rare.
        remoteView.tag = publication.trackSid.hashValue

        // `ExampleSampleBufferRenderer` supports scaleToFill, scaleAspectFill and scaleAspectFit.
        remoteView.contentMode = .scaleAspectFit;

        // Double tap to change the content mode.
        let recognizerDoubleTap = UITapGestureRecognizer(target: self, action: #selector(ViewController.changeRemoteVideoAspect))
        recognizerDoubleTap.numberOfTapsRequired = 2
        remoteView.addGestureRecognizer(recognizerDoubleTap)

        // Start rendering, and add to our stack.
        publication.remoteTrack?.addRenderer(remoteView as! TVIVideoRenderer)
        self.remoteViewStack.addArrangedSubview(remoteView)
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
        // Workaround for UIViewContentMode not taking effect until another layout is done.
        remoteView.bounds = remoteView.bounds.insetBy(dx: 1, dy: 1)
        remoteView.bounds = remoteView.bounds.insetBy(dx: -1, dy: -1)
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
            logMessage(messageText: "Disconncted from \(room.name).\ncode = \((disconnectError as NSError).code) error = \(disconnectError.localizedDescription)")
        } else {
            logMessage(messageText: "Disconncted from \(room.name)")
        }

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

        // We are subscribed to the remote Participant's audio Track. We will start receiving the
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
}

// MARK: TVILocalParticipantDelegate
extension ViewController : TVILocalParticipantDelegate {
    func localParticipant(_ participant: TVILocalParticipant, publishedAudioTrack: TVILocalAudioTrackPublication) {
    }
}

extension ViewController : TVICameraSourceDelegate {
    func cameraSource(_ source: TVICameraSource, didFailWithError error: Error) {
        logMessage(messageText: "Capture failed with error.\ncode = \((error as NSError).code) error = \(error.localizedDescription)")
        source.previewView?.removeFromSuperview()
    }

    func cameraSourceInterruptionEnded(_ source: TVICameraSource) {
        // Layout the camera preview with dimensions appropriate for our orientation.
        self.view.setNeedsLayout()
    }

}
