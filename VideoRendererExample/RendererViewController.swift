//
//  RendererViewController.swift
//  VideoRendererExample
//
//  Copyright © 2019 Twilio Inc. All rights reserved.
//

import AVFoundation
import TwilioVideo
import UIKit

class RendererViewController: UIViewController {

    // MARK: View Controller Members
    var roomName: String?
    var accessToken: String?

    // Video SDK components
    var room: TVIRoom?
    var camera: TVICameraSource?
    var localAudioTrack: TVILocalAudioTrack?
    var localVideoTrack: TVILocalVideoTrack?
    var localVideoRecorder: ExampleVideoRecorder?

    // MARK: UI Element Outlets and handles

    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet weak var remoteViewStack: UIStackView!

    let kPreviewPadding = CGFloat(10)

    // How many remote videos to display.
    let kMaxRemoteVideos = Int(2)

    // Use ExampleSampleBufferView instead of TVIVideoView to render remote Participant video.
    static let kUseExampleSampleBufferView = true

    // Enable recording of the local camera.
    static let kRecordLocalVideo = false

    override func viewDidLoad() {
        super.viewDidLoad()

        disconnectButton.setTitleColor(UIColor.init(white: 0.75, alpha: 1), for: .disabled)
        disconnectButton.layer.cornerRadius = 4

        navigationItem.setHidesBackButton(true, animated: false)
        navigationController?.setNavigationBarHidden(true, animated: true)

        prepareLocalMedia()
        connect()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    // MARK: IBActions

    @IBAction func disconnect(sender: UIButton) {
        if let room = self.room {
            logMessage(messageText: "Disconnecting from \(room.name)")
            room.disconnect()
            sender.isEnabled = false

            if let camera = camera {
                camera.stopCapture()
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
        return self.room?.state == TVIRoomState.connected || self.room?.state == TVIRoomState.reconnecting
    }

    override var prefersStatusBarHidden: Bool {
        return self.room?.state == TVIRoomState.connected || self.room?.state == TVIRoomState.reconnecting
    }

    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        if (newCollection.horizontalSizeClass == .regular ||
            (newCollection.horizontalSizeClass == .compact && newCollection.verticalSizeClass == .compact)) {
            remoteViewStack.axis = .horizontal
        } else {
            remoteViewStack.axis = .vertical
        }
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

        // The example will render the camera using TVICameraPreviewView.
        let cameraSourceOptions = TVICameraSourceOptions.init { (builder) in
            builder.enablePreview = true
        }

        self.camera = TVICameraSource(options: cameraSourceOptions, delegate: self)
        if let camera = self.camera {
            localVideoTrack = TVILocalVideoTrack(source: camera)
            logMessage(messageText: "Video track created.")

            if let preview = camera.previewView {
                view.addSubview(preview);
            }

            camera.startCapture(with: frontCamera) { (captureDevice, videoFormat, error) in
                                    if let error = error {
                                        self.logMessage(messageText: "Capture failed with error.\ncode = \((error as NSError).code) error = \(error.localizedDescription)")
                                        self.camera?.previewView?.removeFromSuperview()
                                    } else {
                                        // Double tap to stop recording.
                                        if (RendererViewController.kRecordLocalVideo) {
                                            let recognizerDoubleTap = UITapGestureRecognizer(target: self, action: #selector(RendererViewController.recordingTap))
                                            recognizerDoubleTap.numberOfTapsRequired = 2
                                            self.camera?.previewView?.addGestureRecognizer(recognizerDoubleTap)
                                            self.prepareVideoRecording(track: self.localVideoTrack!)
                                        }

                                        // Layout the camera preview with dimensions appropriate for our orientation.
                                        self.view.setNeedsLayout()
                                    }
            }
        }
    }

    func connect() {

        // Preparing the connect options with the access token that we fetched (or hardcoded).
        let connectOptions = TVIConnectOptions.init(token: accessToken!) { (builder) in

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
            builder.roomName = self.roomName
        }

        // Connect to the Room using the options we provided.
        room = TwilioVideo.connect(with: connectOptions, delegate: self)

        logMessage(messageText: "Connecting to \(roomName ?? "a Room")")

        // Sometimes a Participant might not interact with their device for a long time in a conference.
        UIApplication.shared.isIdleTimerDisabled = true

        self.disconnectButton.isHidden = true
        self.disconnectButton.isEnabled = false

        self.title = self.roomName
    }

    func handleRoomDisconnected() {
        // Do any necessary cleanup when leaving the room
        self.room = nil

        if let camera = camera {
            camera.stopCapture()
            self.camera = nil
        }

        // The Client is no longer in a conference, allow the Participant's device to idle.
        UIApplication.shared.isIdleTimerDisabled = false
        navigationController?.popViewController(animated: true)
        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    func logMessage(messageText: String) {
        NSLog(messageText)
    }

    @objc func recordingTap(gestureRecognizer: UIGestureRecognizer) {
        if let recorder = self.localVideoRecorder {
            recorder.stopRecording()
            self.localVideoRecorder = nil
        }
    }

    func prepareVideoRecording(track: TVILocalVideoTrack) {
        if self.localVideoRecorder == nil {
            self.localVideoRecorder = ExampleVideoRecorder(videoTrack: track, identifier: track.name)
        }
    }

    func setupRemoteVideoView(publication: TVIRemoteVideoTrackPublication) {
        // Create `ExampleSampleBufferRenderer`, and add it to the `UIStackView`.
        let remoteView = RendererViewController.kUseExampleSampleBufferView ?
            ExampleSampleBufferView(frame: CGRect.zero) : TVIVideoView(frame: CGRect.zero)

        // We will bet that a hash collision between two unique SIDs is very rare.
        remoteView.tag = publication.trackSid.hashValue

        // `ExampleSampleBufferRenderer` supports scaleToFill, scaleAspectFill and scaleAspectFit.
        remoteView.contentMode = .scaleAspectFit;

        // Double tap to change the content mode.
        let recognizerDoubleTap = UITapGestureRecognizer(target: self, action: #selector(RendererViewController.changeRemoteVideoAspect))
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

// MARK: TVIRoomDelegate
extension RendererViewController : TVIRoomDelegate {
    func didConnect(to room: TVIRoom) {

        // Listen to events from TVIRemoteParticipants that are already connected.
        for remoteParticipant in room.remoteParticipants {
            remoteParticipant.delegate = self
        }

        self.title = room.name

        self.disconnectButton.isHidden = false
        self.disconnectButton.alpha = 0
        self.disconnectButton.isEnabled = true
        UIView.animate(withDuration: 0.3) {
            self.disconnectButton.alpha = 1.0
            self.view.backgroundColor = UIColor.black
        }

        if #available(iOS 11.0, *) {
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
        self.setNeedsStatusBarAppearanceUpdate()

        let connectMessage = "Connected to room \(room.name) as \(room.localParticipant?.identity ?? "")."
        logMessage(messageText: connectMessage)
    }

    func room(_ room: TVIRoom, didDisconnectWithError error: Error?) {
        if let disconnectError = error {
            logMessage(messageText: "Disconncted from \(room.name).\ncode = \((disconnectError as NSError).code) error = \(disconnectError.localizedDescription)")
        } else {
            logMessage(messageText: "Disconncted from \(room.name)")
        }

        self.handleRoomDisconnected()
    }

    func room(_ room: TVIRoom, didFailToConnectWithError error: Error) {
        logMessage(messageText: "Failed to connect to Room:\n\(error.localizedDescription)")

        self.handleRoomDisconnected()
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
extension RendererViewController : TVIRemoteParticipantDelegate {

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
extension RendererViewController : TVILocalParticipantDelegate {
    func localParticipant(_ participant: TVILocalParticipant, publishedAudioTrack: TVILocalAudioTrackPublication) {
    }
}

extension RendererViewController : TVICameraSourceDelegate {
    func cameraSource(_ source: TVICameraSource, didFailWithError error: Error) {
        logMessage(messageText: "Capture failed with error.\ncode = \((error as NSError).code) error = \(error.localizedDescription)")
        source.previewView?.removeFromSuperview()
    }

    func cameraSourceInterruptionEnded(_ source: TVICameraSource) {
        // Layout the camera preview with dimensions appropriate for our orientation.
        self.view.setNeedsLayout()
    }

}
