//
//  MultiPartyViewController.swift
//  MultiPartyExample
//
//  Copyright © 2019 Twilio, Inc. All rights reserved.
//

import UIKit
import TwilioVideo

struct CaptureDeviceUtils {

    static let kOneToOneFrameRate = UInt(24)
    static let kOneToOneVideoBitrate = UInt(1120)
    static let kMultipartyFrameRate = UInt(15)
    static let kMultipartyVideoBitrate = UInt(600)
    // Simulcast bitrate is multiplied by the number of spatial layers.
    static let kSimulcastVideoBitrate = UInt(720)
    static let kOneToOneVideoDimensions = CMVideoDimensions(width: 640, height: 480)
    static let kMultipartyVideoDimensions = CMVideoDimensions(width: 480, height: 360)
    static let kSimulcastVideoDimensions = CMVideoDimensions(width: 1280, height: 960)

    static let kFormatByRatioMinimumSize = UInt(640)
    static let kFormatByRatioMaxDelta = Float(0.4)

    /*
     * @brief Finds the smallest format that is suitably close to the ratio requested.
     *
     * @param device The AVCaptureDevice to query.
     * @param targetRatio The ratio that is preferred.
     *
     * @return A format that satisfies the request.
     */
    static func selectFormatByRatio(device: AVCaptureDevice,
                                    targetRatio: CMVideoDimensions) -> VideoFormat {
        let formats = CameraSource.supportedFormats(captureDevice: device)
        var selectedFormat = formats.firstObject as? VideoFormat

        let subscriberRatio = Float(targetRatio.width) / Float(targetRatio.height)

        for format in formats {
            guard let videoFormat = format as? VideoFormat else {
                continue
            }
            if videoFormat.pixelFormat != PixelFormat.formatYUV420BiPlanarFullRange {
                continue
            }
            let dimensions = videoFormat.dimensions
            let ratio = Float(dimensions.width) / Float(dimensions.height)

            // Find the smallest format that is close to the aspect ratio of the target
            if (dimensions.width >= kFormatByRatioMinimumSize && abs(subscriberRatio - ratio) < kFormatByRatioMaxDelta) {
                selectedFormat = videoFormat
                break
            }
        }

        return selectedFormat!
    }

    /*
     * @brief Finds the smallest format that exactly matches or contains the size requested.
     *
     * @param device The AVCaptureDevice to query.
     * @param targetSize The size that is preferred.
     *
     * @return A format that satisfies the request.
     */
    static func selectFormatBySize(device: AVCaptureDevice,
                                   targetSize: CMVideoDimensions) -> VideoFormat {
        // Arranged from smallest to largest.
        let formats = CameraSource.supportedFormats(captureDevice: device)
        var selectedFormat = formats.firstObject as? VideoFormat

        for format in formats {
            guard let videoFormat = format as? VideoFormat else {
                continue
            }
            if videoFormat.pixelFormat != PixelFormat.formatYUV420BiPlanarFullRange {
                continue
            }
            let dimensions = videoFormat.dimensions

            // Cropping might be used if there is not an exact match.
            if (dimensions.width >= targetSize.width && dimensions.height >= targetSize.height) {
                selectedFormat = videoFormat
                break
            }
        }

        return selectedFormat!
    }

    static func selectVideoFormat(multiparty: Bool, device: AVCaptureDevice) -> VideoFormat {
        let frameRate = multiparty ? CaptureDeviceUtils.kMultipartyFrameRate : CaptureDeviceUtils.kOneToOneFrameRate
        var dimensions = multiparty ? CaptureDeviceUtils.kMultipartyVideoDimensions : CaptureDeviceUtils.kOneToOneVideoDimensions
        dimensions = MultiPartyViewController.isSimulcast ? CaptureDeviceUtils.kSimulcastVideoDimensions : dimensions

        let format = CaptureDeviceUtils.selectFormatBySize(device: device, targetSize: dimensions)
        format.frameRate = frameRate
        return format
    }
}

class MultiPartyViewController: UIViewController {

    // MARK:- View Controller Members
    var roomName: String?
    var accessToken: String?
    var remoteParticipantViews: [RemoteParticipantView] = []
    var localParticipantView: LocalParticipantView = LocalParticipantView(frame: CGRect.zero)

    static let kMaxRemoteParticipants = 3

    // Video SDK components
    var room: Room?
    var camera: CameraSource?
    var localVideoTrack: LocalVideoTrack?
    var localAudioTrack: LocalAudioTrack?
    var useMultipartyMedia = false

    var currentDominantSpeaker: RemoteParticipant?

    // A timer used to unpublish the LocalAudioTrack after it has been muted for a long time.
    var inactivityTimer: Timer?

    // The number of seconds before a muted Track is considered inactive.
    static let kInactivityTimeout = 20.0

    // MARK:- UI Element Outlets and handles
    @IBOutlet weak var containerView: UIView!
    @IBOutlet weak var audioMuteButton: UIButton!
    @IBOutlet weak var videoMuteButton: UIButton!
    @IBOutlet weak var hangupButton: UIButton!

    static var isSimulcast: Bool {
        get {
            var isSimulcast = false
            if let vp8 = Settings.shared.videoCodec as? Vp8Codec {
                isSimulcast = vp8.isSimulcast
            }
            return isSimulcast
        }
    }

    static var audioBitrate: UInt {
        get {
            var bitrate = UInt(0)
            if let encodingParameters = Settings.shared.getEncodingParameters() {
                bitrate = encodingParameters.maxAudioBitrate
            }
            return bitrate
        }
    }

    static var defaultVideoBitrate: UInt {
        get {
            return MultiPartyViewController.isSimulcast ?
                CaptureDeviceUtils.kSimulcastVideoBitrate : CaptureDeviceUtils.kOneToOneVideoBitrate
        }
    }

    // MARK:- UIViewController
    override func viewDidLoad() {
        super.viewDidLoad()

        logMessage(messageText: "TwilioVideo v(\(TwilioVideoSDK.sdkVersion()))")

        title = roomName
        navigationItem.setHidesBackButton(true, animated: false)

        audioMuteButton.layer.cornerRadius = audioMuteButton.bounds.size.width / 2.0
        videoMuteButton.layer.cornerRadius = videoMuteButton.bounds.size.width / 2.0
        hangupButton.layer.cornerRadius = hangupButton.bounds.size.width / 2.0

        containerView.addSubview(localParticipantView)

        videoMuteButton.isEnabled = !PlatformUtils.isSimulator

        navigationController?.hidesBarsWhenVerticallyCompact = true

        connect()
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return room != nil
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        var layoutFrame = self.containerView.bounds
        if #available(iOS 11.0, *) {
            // Ensure the preview fits in the safe area.
            let safeAreaGuide = self.containerView.safeAreaLayoutGuide
            layoutFrame = safeAreaGuide.layoutFrame
        }

        let topY = layoutFrame.origin.y
        let totalHeight = layoutFrame.height
        let totalWidth = layoutFrame.width

        let videoViewHeight = round(totalHeight / 2)
        let videoViewWidth = round(totalWidth / 2)

        let videoViewSize = CGSize(width: videoViewWidth, height: videoViewHeight)

        // Layout local Participant
        localParticipantView.frame = CGRect(origin: CGPoint(x: layoutFrame.minX, y: topY),
                                            size: videoViewSize)

        // Layout remote Participants
        var index = 0
        for remoteParticipantView in remoteParticipantViews {
            switch index {
            case 0:
                remoteParticipantView.frame = CGRect(origin: CGPoint(x: layoutFrame.minX + videoViewWidth, y: topY),
                                                     size: videoViewSize)
            case 1:
                remoteParticipantView.frame = CGRect(origin: CGPoint(x: layoutFrame.minX, y: topY + videoViewHeight),
                                                     size: videoViewSize)
            case 2:
                remoteParticipantView.frame = CGRect(origin: CGPoint(x: layoutFrame.minX + videoViewWidth, y: topY + videoViewHeight),
                                                     size: videoViewSize)
            default:
                break
            }
            index += 1
        }
    }

    func logMessage(messageText: String) {
        NSLog(messageText)
    }

    func prepareAudio() {
        // Create an audio track.
        guard let localAudioTrack = LocalAudioTrack(options: nil, enabled: true, name: "Microphone") else {
            logMessage(messageText: "Failed to create audio track")
            return
        }

        logMessage(messageText: "Audio track created")
        self.localAudioTrack = localAudioTrack

        updateLocalAudioState(hasAudio: true, isPublished: self.room == nil)
    }

    func prepareCamera() {
        if PlatformUtils.isSimulator {
            return
        }

        let frontCamera = CameraSource.captureDevice(position: .front)
        let backCamera = CameraSource.captureDevice(position: .back)

        if (frontCamera != nil || backCamera != nil) {
            // Preview our local camera track in the local video preview view.
            camera = CameraSource(delegate: self)

            if let camera = camera {
                localVideoTrack = LocalVideoTrack(source: camera, enabled: true, name: "Camera")

                guard let localVideoTrack = self.localVideoTrack else {
                    logMessage(messageText: "Failed to create video track")
                    return
                }

                logMessage(messageText: "Video track created")

                // Add renderer to video track for local preview
                localParticipantView.hasVideo = true
                localVideoTrack.addRenderer(localParticipantView.videoView)

                let recognizerSingleTap = UITapGestureRecognizer(target: self, action: #selector(MultiPartyViewController.flipCamera))
                recognizerSingleTap.numberOfTapsRequired = 1
                localParticipantView.videoView.addGestureRecognizer(recognizerSingleTap)

                if let recognizerDoubleTap = localParticipantView.recognizerDoubleTap {
                    recognizerSingleTap.require(toFail: recognizerDoubleTap)
                }

                let device = frontCamera != nil ? frontCamera! : backCamera!
                let format = CaptureDeviceUtils.selectVideoFormat(multiparty: false, device: device)

                camera.startCapture(device: device, format:format) { (captureDevice, videoFormat, error) in
                    if let error = error {
                        self.logMessage(messageText: "Capture failed with error.\ncode = \((error as NSError).code) error = \(error.localizedDescription)")
                    } else {
                        self.localParticipantView.videoView.shouldMirror = (captureDevice.position == .front)
                    }
                }
            }
        } else {
            self.logMessage(messageText:"No front or back capture source found!")
        }
    }

    @objc func flipCamera() {
        var newDevice: AVCaptureDevice?

        if let camera = camera, let captureDevice = camera.device {
            if captureDevice.position == .front {
                newDevice = CameraSource.captureDevice(position: .back)
            } else {
                newDevice = CameraSource.captureDevice(position: .front)
            }

            if let newDevice = newDevice {
                let format = CaptureDeviceUtils.selectVideoFormat(multiparty: useMultipartyMedia, device: newDevice)
                camera.selectCaptureDevice(newDevice, format: format) { (captureDevice, videoFormat, error) in
                    if let error = error {
                        self.logMessage(messageText: "Error selecting capture device.\ncode = \((error as NSError).code) error = \(error.localizedDescription)")
                    } else {
                        self.localParticipantView.videoView.shouldMirror = (captureDevice.position == .front)
                    }
                }
            }
        }
    }

    @IBAction func toggleAudio(_ sender: UIButton) {
        inactivityTimer?.invalidate()

        if let localAudioTrack = self.localAudioTrack {
            let isEnabled = !localAudioTrack.isEnabled
            localAudioTrack.isEnabled = isEnabled
            updateLocalAudioState(hasAudio: isEnabled, isPublished: true)

            // Unpublish after no activity.
            if !isEnabled {
                inactivityTimer = Timer(fire: Date(timeIntervalSinceNow: MultiPartyViewController.kInactivityTimeout), interval: 0, repeats: false, block: { (Timer) in
                    if let audioTrack = self.localAudioTrack {
                        print("Unpublishing audio track due to inactivity timer.")
                        self.room?.localParticipant?.unpublishAudioTrack(audioTrack)
                        self.localAudioTrack = nil
                    }
                })

                if let theTimer = inactivityTimer {
                    RunLoop.main.add(theTimer, forMode: .common)
                }
            }
        } else if let participant = self.room?.localParticipant {
            prepareAudio()
            if let audioTrack = self.localAudioTrack {
                updateLocalAudioState(hasAudio: true, isPublished: false)
                participant.publishAudioTrack(audioTrack)
            }
        }
    }

    @IBAction func toggleVideo(_ sender: Any) {
        if let localVideoTrack = self.localVideoTrack {
            localVideoTrack.isEnabled = !localVideoTrack.isEnabled
            updateLocalVideoState(hasVideo: localVideoTrack.isEnabled)
        }
    }

    func connect() {
        guard let accessToken = accessToken, let roomName = roomName else {
            // This should never happen becasue we are validating in
            // MainViewController
            return
        }

        // Prepare local media which we will share with Room Participants.
        prepareAudio()
        prepareCamera()

        // Preparing the connect options with the access token that we fetched (or hardcoded).
        let connectOptions = ConnectOptions(token: accessToken) { (builder) in

            // Enable Dominant Speaker functionality
            builder.isDominantSpeakerEnabled = true

            // Enable Network Quality
            builder.isNetworkQualityEnabled = true

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

            builder.encodingParameters = EncodingParameters(audioBitrate: MultiPartyViewController.audioBitrate,
                                                            videoBitrate: MultiPartyViewController.defaultVideoBitrate)

            // Use the preferred signaling region
            if let signalingRegion = Settings.shared.signalingRegion {
                builder.region = signalingRegion
            }

            // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty
            // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
            builder.roomName = roomName
        }

        // Connect to the Room using the options we provided.
        room = TwilioVideoSDK.connect(options: connectOptions, delegate: self)

        // Sometimes a Participant might not interact with their device for a long time in a conference.
        UIApplication.shared.isIdleTimerDisabled = true

        logMessage(messageText: "Attempting to connect to room: \(roomName)")
    }

    @IBAction func leaveRoom(_ sender: Any) {
        if let room = room {
            room.disconnect()
            self.room = nil
        }

        // Do any necessary cleanup when leaving the room

        if let camera = camera {
            camera.stopCapture()
            self.camera = nil
        }

        if let localVideoTrack = localVideoTrack {
            localParticipantView.hasVideo = false
            localVideoTrack.removeRenderer(localParticipantView.videoView)
            self.localVideoTrack = nil
        }

        // The Client is no longer in a conference, allow the Participant's device to idle.
        UIApplication.shared.isIdleTimerDisabled = false

        navigationController?.popViewController(animated: true)
    }

    func setupRemoteParticipantView(remoteParticipant: RemoteParticipant) {
        // Create a `VideoView` programmatically
        let remoteView = RemoteParticipantView(frame: CGRect.zero)

        // We will bet that a hash collision between two unique SIDs is very rare.
        remoteView.tag = remoteParticipant.hashValue
        remoteView.identity = remoteParticipant.identity
        containerView.addSubview(remoteView)
        remoteParticipantViews.append(remoteView)
    }

    func removeRemoteParticipantView(remoteParticipant: RemoteParticipant) {
        let viewTag = remoteParticipant.hashValue
        if let remoteView = view.viewWithTag(viewTag) {
            remoteView.removeFromSuperview()
            remoteParticipantViews.removeAll { (item) -> Bool in
                return item == remoteView
            }
        }
    }

    func displayVideoTrack(_ videoTrack: RemoteVideoTrack,
                           for participant: RemoteParticipant) {
        let viewTag = participant.hashValue
        if let remoteView = view.viewWithTag(viewTag) as? RemoteParticipantView {
            // Start rendering
            videoTrack.addRenderer(remoteView.videoView);
            remoteView.hasVideo = true
        }
    }

    func removeVideoTrack(_ videoTrack: RemoteVideoTrack,
                          for participant: RemoteParticipant) {
        let viewTag = participant.hashValue
        if let remoteView = view.viewWithTag(viewTag) as? RemoteParticipantView {
            // Stop rendering
            videoTrack.removeRenderer(remoteView.videoView);
            remoteView.hasVideo = false
        }
    }

    func updateDominantSpeaker(dominantSpeaker: RemoteParticipant?) {
        if let currentDominantSpeaker = currentDominantSpeaker {
            let viewTag = currentDominantSpeaker.hashValue
            if let remoteView = view.viewWithTag(viewTag) as? RemoteParticipantView {
                remoteView.isDominantSpeaker = false
            }
        }

        if let dominantSpeaker = dominantSpeaker {
            let viewTag = dominantSpeaker.hashValue
            if let remoteView = view.viewWithTag(viewTag) as? RemoteParticipantView {
                remoteView.isDominantSpeaker = true
            }
        }

        currentDominantSpeaker = dominantSpeaker
    }

    func updateAudioState(hasAudio: Bool,
                          for participant: RemoteParticipant) {
        let viewTag = participant.hashValue
        if let remoteView = view.viewWithTag(viewTag) as? RemoteParticipantView {
            // Stop rendering
            remoteView.hasAudio = hasAudio
        }
    }

    func updateLocalAudioState(hasAudio: Bool, isPublished: Bool) {
        self.localParticipantView.hasAudio = hasAudio
        audioMuteButton.isSelected = !hasAudio
        audioMuteButton.isEnabled = isPublished
    }

    func updateLocalVideoState(hasVideo: Bool) {
        self.localParticipantView.hasVideo = hasVideo
        videoMuteButton.isSelected = !hasVideo
    }

    func updateLocalNetworkQualityLevel(networkQualityLevel: NetworkQualityLevel) {
        logMessage(messageText: "Network Quality Level: \(networkQualityLevel.rawValue)")
        localParticipantView.networkQualityLevel = networkQualityLevel
    }

    func checkVideoSenderSettings(room: Room) {
        guard let localParticipant = room.localParticipant else {
            return
        }
        guard let camera = camera else {
            return
        }

        /*
         * Update the CameraCapturer's format and the LocalParticipant's EncodingParameters based upon the size of the Room.
         * When simulcast is not used, it is preferrable for the Participant to send a smaller video stream that may be
         * easily consumed by all subscribers. If simulcast is enabled, then the source should produce frames that are
         * large enough for the encoder to create 3 spatial layers.
         *
         * A lower frame rate is used in multi-party to reduce the cumulative receiving / decoding / rendering cost for
         * subscribed video.
         */
        let isMultiparty = room.remoteParticipants.count > 1
        if isMultiparty != useMultipartyMedia {
            useMultipartyMedia = isMultiparty

            var bitrate = isMultiparty ? CaptureDeviceUtils.kMultipartyVideoBitrate : CaptureDeviceUtils.kOneToOneVideoBitrate
            bitrate = MultiPartyViewController.isSimulcast ? CaptureDeviceUtils.kSimulcastVideoBitrate : bitrate
            localParticipant.setEncodingParameters(EncodingParameters(audioBitrate: MultiPartyViewController.audioBitrate,
                                                                      videoBitrate: bitrate))

            let format = CaptureDeviceUtils.selectVideoFormat(multiparty: isMultiparty, device: (camera.device)!)
            camera.selectCaptureDevice((camera.device)!, format: format, completion: { (device, format, error) in
                if let error = error {
                    self.logMessage(messageText: "Failed to select format \(format), error = \(String(describing: error))")
                }
            })
        }
    }
}

// MARK:- RoomDelegate
extension MultiPartyViewController : RoomDelegate {

    func roomDidConnect(room: Room) {
        logMessage(messageText: "Connected to room \(room.name) as \(room.localParticipant?.identity ?? "").")
        NSLog("Room: \(room.name) SID: \(room.sid)")
        title = room.name

        // Set the delegate of the local participant in the `didConnect` callback to ensure that no events are missed
        room.localParticipant?.delegate = self

        // Iterate over the current room participants and display them
        for remoteParticipant in room.remoteParticipants {
            remoteParticipant.delegate = self

            if remoteParticipantViews.count < MultiPartyViewController.kMaxRemoteParticipants {
                setupRemoteParticipantView(remoteParticipant: remoteParticipant)
            }
        }

        checkVideoSenderSettings(room: room)

        if #available(iOS 11.0, *) {
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    func roomDidFailToConnect(room: Room, error: Error) {
        NSLog("Failed to connect to a Room: \(error).")

        inactivityTimer?.invalidate()

        let alertController = UIAlertController(title: "Connection Failed",
                                                message: "Couldn't connect to Room \(room.name). code:\(error._code) \(error.localizedDescription)",
            preferredStyle: .alert)

        let cancelAction = UIAlertAction(title: "Okay", style: .default) { (alertAction) in
            self.leaveRoom(self)
        }

        alertController.addAction(cancelAction)

        self.present(alertController, animated: true) {
            self.room = nil
        }
    }

    func roomDidDisconnect(room: Room, error: Error?) {
        inactivityTimer?.invalidate()

        guard let error = error else {
            return
        }

        NSLog("The Client was disconnected: \(error).")

        let alertController = UIAlertController(title: "Connection Failed",
                                                message: "Disconnected from Room \(room.name). code:\(error._code) \(error.localizedDescription)",
            preferredStyle: .alert)

        let cancelAction = UIAlertAction(title: "Okay", style: .default) { (alertAction) in
            self.leaveRoom(self)
        }

        alertController.addAction(cancelAction)

        self.present(alertController, animated: true)
    }

    func roomIsReconnecting(room: Room, error: Error) {
        logMessage(messageText: "Reconnecting to room \(room.name), error = \(String(describing: error))")
    }

    func roomDidReconnect(room: Room) {
        logMessage(messageText: "Reconnected to room \(room.name)")
    }

    func participantDidConnect(room: Room, participant: RemoteParticipant) {
        logMessage(messageText: "Participant \(participant.identity) connected with \(participant.remoteAudioTracks.count) audio and \(participant.remoteVideoTracks.count) video tracks")
        participant.delegate = self

        if remoteParticipantViews.count < MultiPartyViewController.kMaxRemoteParticipants {
            setupRemoteParticipantView(remoteParticipant: participant)
        }

        checkVideoSenderSettings(room: room)
    }

    func participantDidDisconnect(room: Room, participant: RemoteParticipant) {
        logMessage(messageText: "Room \(room.name), Participant \(participant.identity) disconnected")

        removeRemoteParticipantView(remoteParticipant: participant)
        checkVideoSenderSettings(room: room)
    }

    func dominantSpeakerDidChange(room: Room, participant: RemoteParticipant?) {
        updateDominantSpeaker(dominantSpeaker: participant)
    }
}

// MARK:- LocalParticipantDelegate
extension MultiPartyViewController : LocalParticipantDelegate {
    func localParticipantNetworkQualityLevelDidChange(participant: LocalParticipant, networkQualityLevel: NetworkQualityLevel) {
        // Local Participant netwrk quality level has changed
        updateLocalNetworkQualityLevel(networkQualityLevel: networkQualityLevel)
    }

    func localParticipantDidPublishAudioTrack(participant: LocalParticipant, audioTrackPublication: LocalAudioTrackPublication) {
        updateLocalAudioState(hasAudio: audioTrackPublication.isTrackEnabled, isPublished: true)
    }

    func localParticipantDidFailToPublishAudioTrack(participant: LocalParticipant, audioTrack: LocalAudioTrack, error: Error) {
        self.localAudioTrack = nil
        updateLocalAudioState(hasAudio: false, isPublished: false)
        logMessage(messageText: "Failed to publish audio track, error = \(String(describing: error))")
    }
}

// MARK:- RemoteParticipantDelegate
extension MultiPartyViewController : RemoteParticipantDelegate {
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
        displayVideoTrack(videoTrack, for: participant)
    }

    func didUnsubscribeFromVideoTrack(videoTrack: RemoteVideoTrack, publication: RemoteVideoTrackPublication, participant: RemoteParticipant) {
        // We are unsubscribed from the remote Participant's video Track. We will no longer receive the
        // remote Participant's video.

        logMessage(messageText: "Unsubscribed from \(publication.trackName) video track for Participant \(participant.identity)")
        removeVideoTrack(videoTrack, for: participant)
    }

    func didSubscribeToAudioTrack(audioTrack: RemoteAudioTrack, publication: RemoteAudioTrackPublication, participant: RemoteParticipant) {
        // We are subscribed to the remote Participant's audio Track. We will start receiving the
        // remote Participant's audio now.

        logMessage(messageText: "Subscribed to \(publication.trackName) audio track for Participant \(participant.identity)")
        updateAudioState(hasAudio: true, for: participant)
    }

    func didUnsubscribeFromAudioTrack(audioTrack: RemoteAudioTrack, publication: RemoteAudioTrackPublication, participant: RemoteParticipant) {
        // We are unsubscribed from the remote Participant's audio Track. We will no longer receive the
        // remote Participant's audio.

        logMessage(messageText: "Unsubscribed from \(publication.trackName) audio track for Participant \(participant.identity)")
        updateAudioState(hasAudio: false, for: participant)
    }

    func remoteParticipantDidEnableVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) enabled \(publication.trackName) video track")
    }

    func remoteParticipantDidDisableVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) disabled \(publication.trackName) video track")
    }

    func remoteParticipantDidEnableAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) enabled \(publication.trackName) audio track")
        updateAudioState(hasAudio: true, for: participant)
    }

    func remoteParticipantDidDisableAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) disabled \(publication.trackName) audio track")
        updateAudioState(hasAudio: false, for: participant)
    }

    func didFailToSubscribeToAudioTrack(publication: RemoteAudioTrackPublication, error: Error, participant: RemoteParticipant) {
        logMessage(messageText: "Failed to subscribe \(publication.trackName) audio track, error = \(String(describing: error))")
    }

    func didFailToSubscribeToVideoTrack(publication: RemoteVideoTrackPublication, error: Error, participant: RemoteParticipant) {
        logMessage(messageText: "Failed to subscribe \(publication.trackName) video track, error = \(String(describing: error))")
    }
}

// MARK:- CameraSourceDelegate
extension MultiPartyViewController : CameraSourceDelegate {
    func cameraSourceDidFail(source: CameraSource, error: Error) {
        logMessage(messageText: "Camera source failed with error: \(error.localizedDescription)")
    }
}
