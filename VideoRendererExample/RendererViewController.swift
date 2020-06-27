//
//  RendererViewController.swift
//  VideoRendererExample
//
//  Copyright © 2020 Twilio Inc. All rights reserved.
//

import AVFoundation
import TwilioVideo
import UIKit

class RendererViewController: UIViewController {

    // MARK: View Controller Members
    var accessToken: String?
    var roomName: String?
    var publishTracks: Bool = true

    // Video SDK components
    var room: Room?
    var camera: CameraSource?
    var localAudioTrack: LocalAudioTrack?
    var localVideoTrack: LocalVideoTrack?
    var localVideoRecorder: ExampleVideoRecorder?
    var screenDimensions = CMVideoDimensions(width: Int32(exactly: UIScreen.main.currentMode!.size.width)!,
                                             height: Int32(exactly: UIScreen.main.currentMode!.size.height)!)

    var subscriberDimensions: CMVideoDimensions?

    // MARK: UI Element Outlets and handles
    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet weak var remoteViewStack: UIStackView!

    let kPreviewPadding = CGFloat(10)

    // How many remote videos to display.
    let kMaxRemoteVideos = Int(2)

    // Use ExampleSampleBufferView to render remote Participant video.
    static let kUseExampleSampleBufferView = true

    // Enable recording of the local camera.
    static let kRecordLocalVideo = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // Normalize screen dimensions to be in landscape
        if screenDimensions.height > screenDimensions.width {
            let width = screenDimensions.height
            screenDimensions.height = screenDimensions.width
            screenDimensions.width = width
        }

        disconnectButton.setTitleColor(UIColor.init(white: 0.75, alpha: 1), for: .disabled)
        disconnectButton.layer.cornerRadius = 4

        navigationItem.setHidesBackButton(true, animated: false)
        navigationController?.setNavigationBarHidden(true, animated: true)

        if (publishTracks) {
            prepareLocalMedia()
        }
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
        return self.room?.state == Room.State.connected || self.room?.state == Room.State.reconnecting
    }

    override var prefersStatusBarHidden: Bool {
        return self.room?.state == Room.State.connected || self.room?.state == Room.State.reconnecting
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
        // Create an audio track. Encode the Participant's screen dimensions in the Track's name.
        localAudioTrack = LocalAudioTrack(options: nil, enabled: true, name: "{\(screenDimensions.width), \(screenDimensions.height)}")
        if (localAudioTrack == nil) {
            logMessage(messageText: "Failed to create audio track!")
            return
        }

        // Create a video track which captures from the front camera.
        guard let frontCamera = CameraSource.captureDevice(position: .front) else {
            logMessage(messageText: "Front camera is not available, using microphone only.")
            return
        }

        // The example will render the camera using CameraPreviewView.
        let cameraSourceOptions = CameraSourceOptions { builder in
            builder.enablePreview = true
        }

        self.camera = CameraSource(options: cameraSourceOptions, delegate: self)
        if let camera = self.camera {
            localVideoTrack = LocalVideoTrack(source: camera)
            logMessage(messageText: "Video track created.")

            if let preview = camera.previewView {
                view.addSubview(preview);
            }

            let videoFormat = selectVideoFormat(device: frontCamera, subscriberDimensions: CMVideoDimensions(width: 640, height: 480))
            camera.startCapture(device: frontCamera, format: videoFormat, completion: { (captureDevice, videoFormat, error) in
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
            })
        }
    }

    func connect() {

        // Preparing the connect options with the access token that we fetched (or hardcoded).
        let connectOptions = ConnectOptions(token: accessToken!) { (builder) in

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
        room = TwilioVideoSDK.connect(options: connectOptions, delegate: self)

        logMessage(messageText: "Connecting to \(roomName ?? "a Room")")

        // Sometimes a Participant might not interact with their device for a long time in a conference.
        UIApplication.shared.isIdleTimerDisabled = true

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

    func prepareVideoRecording(track: LocalVideoTrack) {
        if self.localVideoRecorder == nil {
            self.localVideoRecorder = ExampleVideoRecorder(videoTrack: track, identifier: track.name)
        }
    }

    func setupRemoteVideoView(publication: RemoteVideoTrackPublication) {
        // Create `ExampleSampleBufferRenderer`, and add it to the `UIStackView`.
        let remoteView = RendererViewController.kUseExampleSampleBufferView ?
            ExampleSampleBufferView(frame: CGRect.zero) : VideoView(frame: CGRect.zero)

        // We will bet that a hash collision between two unique SIDs is very rare.
        remoteView.tag = publication.trackSid.hashValue

        // `ExampleSampleBufferRenderer` supports scaleToFill, scaleAspectFill and scaleAspectFit.
        remoteView.contentMode = .scaleAspectFit;

        // Double tap to change the content mode.
        let recognizerDoubleTap = UITapGestureRecognizer(target: self, action: #selector(RendererViewController.changeRemoteVideoAspect))
        recognizerDoubleTap.numberOfTapsRequired = 2
        remoteView.addGestureRecognizer(recognizerDoubleTap)

        // Start rendering, and add to our stack.
        publication.remoteTrack?.addRenderer(remoteView as! VideoRenderer)
        self.remoteViewStack.addArrangedSubview(remoteView)
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
        // Workaround for UIViewContentMode not taking effect until another layout is done.
        remoteView.bounds = remoteView.bounds.insetBy(dx: 1, dy: 1)
        remoteView.bounds = remoteView.bounds.insetBy(dx: -1, dy: -1)
    }

    @objc func hudTapped(gestureRecognizer: UIGestureRecognizer) {
        let finalAlpha = self.disconnectButton.alpha == 0.0 ? 1.0 : 0.0
        UIView.animate(withDuration: 0.25) {
            self.disconnectButton.alpha = CGFloat(finalAlpha)
        }
    }

    func updateSourceFormatForSubscriber() {
        if let camera = self.camera {
            let videoFormat = selectVideoFormat(device: camera.device!, subscriberDimensions: subscriberDimensions!)
            camera.selectCaptureDevice(camera.device!, format: videoFormat, completion: { (captureDevice, videoFormat, error) in
                if let error = error {
                    self.logMessage(messageText: "Capture failed with error.\ncode = \((error as NSError).code) error = \(error.localizedDescription)")
                    self.camera?.previewView?.removeFromSuperview()
                } else {
                    if let dimensions = self.subscriberDimensions {
                        let ratio = Float(dimensions.width) / Float(dimensions.height)
                        if ratio > 1.95 {
                            let formatRequest = VideoFormat()
                            formatRequest.dimensions = videoFormat.dimensions
                            formatRequest.dimensions.height = 496
                            self.camera?.requestOutputFormat(formatRequest)
                        }
                    }
                    // Layout the camera preview with dimensions appropriate for our orientation.
                    self.view.setNeedsLayout()
                }
            })
        }
    }

    func selectVideoFormat(device: AVCaptureDevice,
                           subscriberDimensions: CMVideoDimensions) -> VideoFormat {
        let formats = CameraSource.supportedFormats(captureDevice: device)
        var selectedFormat = formats.firstObject as? VideoFormat

        let subscriberRatio = Float(subscriberDimensions.width) / Float(subscriberDimensions.height)

        for format in formats {
            guard let videoFormat = format as? VideoFormat else {
                continue
            }
            if videoFormat.pixelFormat != PixelFormat.formatYUV420BiPlanarFullRange {
                continue
            }
            let dimensions = videoFormat.dimensions
            let ratio = Float(dimensions.width) / Float(dimensions.height)

            // Find the smallest format that is close to the aspect ratio of the subscriber's display
            if (dimensions.width >= 640 && abs(subscriberRatio - ratio) < 0.4) {
                selectedFormat = videoFormat
                break
            }
        }

        return selectedFormat!
    }
}

// MARK: RoomDelegate
extension RendererViewController : RoomDelegate {
    func roomDidConnect(room: Room) {
        // Listen to events from RemoteParticipants that are already connected.
        for remoteParticipant in room.remoteParticipants {
            remoteParticipant.delegate = self

            if room.remoteParticipants.count == 1 {
                updateSubscriberDimensions(participant: remoteParticipant)
            }
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

        let hudTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(RendererViewController.hudTapped))
        hudTapRecognizer.numberOfTapsRequired = 1
        self.view.addGestureRecognizer(hudTapRecognizer)

        let connectMessage = "Connected to room \(room.name) as \(room.localParticipant?.identity ?? "")."
        logMessage(messageText: connectMessage)
    }

    func roomDidDisconnect(room: Room, error: Error?) {
        if let disconnectError = error {
            logMessage(messageText: "Disconncted from \(room.name).\ncode = \((disconnectError as NSError).code) error = \(disconnectError.localizedDescription)")
        } else {
            logMessage(messageText: "Disconncted from \(room.name)")
        }

        self.handleRoomDisconnected()
    }

    func roomDidFailToConnect(room: Room, error: Error) {
        logMessage(messageText: "Failed to connect to Room:\n\(error.localizedDescription)")

        self.handleRoomDisconnected()
    }

    func participantDidConnect(room: Room, participant: RemoteParticipant) {
        participant.delegate = self

        logMessage(messageText: "Participant \(participant.identity) connected with \(participant.remoteAudioTracks.count) audio and \(participant.remoteVideoTracks.count) video tracks")

        if (subscriberDimensions == nil) {
            updateSubscriberDimensions(participant: participant)
        }
    }

    func updateSubscriberDimensions(participant: RemoteParticipant) {
        guard let subscriberDimensionsName = participant.audioTracks.first?.trackName else {
            return
        }
        let cgSize = NSCoder.cgSize(for: subscriberDimensionsName)
        subscriberDimensions = CMVideoDimensions(width: Int32(cgSize.width),
                                                 height: Int32(cgSize.height))

        updateSourceFormatForSubscriber()
    }

    func participantDidDisconnect(room: Room, participant: RemoteParticipant) {
        logMessage(messageText: "Room \(room.name), Participant \(participant.identity) disconnected")

        if (room.remoteParticipants.count == 0) {
            subscriberDimensions = CMVideoDimensions(width: 640, height: 480)
            updateSourceFormatForSubscriber()
            subscriberDimensions = nil
        }
    }
}

// MARK: RemoteParticipantDelegate
extension RendererViewController : RemoteParticipantDelegate {

    func remoteParticipantDidPublishVideoTrack(participant: RemoteParticipant,
                                               publication: RemoteVideoTrackPublication) {

        // Remote Participant has offered to share the video Track.

        logMessage(messageText: "Participant \(participant.identity) published \(publication.trackName) video track")
    }

    func remoteParticipantDidUnpublishVideoTrack(participant: RemoteParticipant,
                                                 publication: RemoteVideoTrackPublication) {

        // Remote Participant has stopped sharing the video Track.

        logMessage(messageText: "Participant \(participant.identity) unpublished \(publication.trackName) video track")
    }

    func remoteParticipantDidPublishAudioTrack(participant: RemoteParticipant,
                                               publication: RemoteAudioTrackPublication) {

        // Remote Participant has offered to share the audio Track.

        logMessage(messageText: "Participant \(participant.identity) published \(publication.trackName) audio track")
    }

    func remoteParticipantDidUnpublishAudioTrack(participant: RemoteParticipant,
                                                 publication: RemoteAudioTrackPublication) {

        // Remote Participant has stopped sharing the audio Track.

        logMessage(messageText: "Participant \(participant.identity) unpublished \(publication.trackName) audio track")
    }

    func didSubscribeToVideoTrack(videoTrack: RemoteVideoTrack,
                                  publication: RemoteVideoTrackPublication,
                                  participant: RemoteParticipant) {
        // We are subscribed to the remote Participant's audio Track. We will start receiving the
        // remote Participant's video frames now.

        logMessage(messageText: "Subscribed to \(publication.trackName) video track for Participant \(participant.identity)")

        // Start remote rendering, and add a touch handler.
        if (self.remoteViewStack.arrangedSubviews.count < kMaxRemoteVideos) {
            setupRemoteVideoView(publication: publication)
        }
    }

    func didUnsubscribeFromVideoTrack(videoTrack: RemoteVideoTrack,
                                      publication: RemoteVideoTrackPublication,
                                      participant: RemoteParticipant) {
        // We are unsubscribed from the remote Participant's video Track. We will no longer receive the
        // remote Participant's video.

        logMessage(messageText: "Unsubscribed from \(publication.trackName) video track for Participant \(participant.identity)")

        // Stop remote rendering.
        removeRemoteVideoView(publication: publication)
    }

    func didSubscribeToAudioTrack(audioTrack: RemoteAudioTrack,
                                  publication: RemoteAudioTrackPublication,
                                  participant: RemoteParticipant) {
        // We are subscribed to the remote Participant's audio Track. We will start receiving the
        // remote Participant's audio now.

        logMessage(messageText: "Subscribed to \(publication.trackName) audio track for Participant \(participant.identity)")
    }

    func didUnsubscribeFromAudioTrack(audioTrack: RemoteAudioTrack, publication: RemoteAudioTrackPublication, participant: RemoteParticipant) {
        // We are unsubscribed from the remote Participant's audio Track. We will no longer receive the
        // remote Participant's audio.

        logMessage(messageText: "Unsubscribed from \(publication.trackName) audio track for Participant \(participant.identity)")
    }

    func remoteParticipantDidEnableVideoTrack(participant: RemoteParticipant,
                                              publication: RemoteVideoTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) enabled \(publication.trackName) video track")
    }

    func remoteParticipantDidDisableVideoTrack(participant: RemoteParticipant,
                                               publication: RemoteVideoTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) disabled \(publication.trackName) video track")
    }

    func remoteParticipantDidEnableAudioTrack(participant: RemoteParticipant,
                                              publication: RemoteAudioTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) enabled \(publication.trackName) audio track")
    }

    func remoteParticipantDidDisableAudioTrack(participant: RemoteParticipant,
                                               publication: RemoteAudioTrackPublication) {
        // We will continue to record silence and/or recognize audio while a Track is disabled.
        logMessage(messageText: "Participant \(participant.identity) disabled \(publication.trackName) audio track")
    }
}

// MARK: LocalParticipantDelegate
extension RendererViewController : LocalParticipantDelegate {
    func localParticipantDidPublishAudioTrack(participant: LocalParticipant,
                                              audioTrackPublication publishedAudioTrack: LocalAudioTrackPublication) {
    }
}

extension RendererViewController : CameraSourceDelegate {
    func cameraSourceDidFail(source: CameraSource, error: Error) {
        logMessage(messageText: "Capture failed with error.\ncode = \((error as NSError).code) error = \(error.localizedDescription)")
        source.previewView?.removeFromSuperview()
    }

    func cameraSourceInterruptionEnded(source: CameraSource) {
        // Layout the camera preview with dimensions appropriate for our orientation.
        self.view.setNeedsLayout()
    }

}
