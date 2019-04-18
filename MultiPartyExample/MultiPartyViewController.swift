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
    var remoteParticipantViews: [RemoteParticipantView] = []
    var localParticipantView: LocalParticipantView = LocalParticipantView.init(frame: CGRect.zero)

    static let kMaxRemoteParticipants = 3

    // Video SDK components
    var room: TVIRoom?
    var camera: TVICameraSource?
    var localVideoTrack: TVILocalVideoTrack?
    var localAudioTrack: TVILocalAudioTrack?

    var currentDominantSpeaker: TVIRemoteParticipant?

    // MARK: UI Element Outlets and handles
    @IBOutlet weak var containerView: UIView!
    @IBOutlet weak var audioMuteButton: UIButton!
    @IBOutlet weak var videoMuteButton: UIButton!
    @IBOutlet weak var hangupButton: UIButton!

    // MARK: UIViewController
    override func viewDidLoad() {
        super.viewDidLoad()

        logMessage(messageText: "TwilioVideo v(\(TwilioVideo.version()))")

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
                remoteParticipantView.frame = CGRect.init(origin: CGPoint.init(x: layoutFrame.minX + videoViewWidth, y: topY),
                                                          size: videoViewSize)
            case 1:
                remoteParticipantView.frame = CGRect.init(origin: CGPoint(x: layoutFrame.minX, y: topY + videoViewHeight),
                                                          size: videoViewSize)
            case 2:
                remoteParticipantView.frame = CGRect.init(origin: CGPoint(x: layoutFrame.minX + videoViewWidth, y: topY + videoViewHeight),
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
        guard let localAudioTrack = TVILocalAudioTrack(options: nil, enabled: true, name: "Microphone") else {
            logMessage(messageText: "Failed to create audio track")
            return
        }

        logMessage(messageText: "Audio track created")
        self.localAudioTrack = localAudioTrack

        updateLocalAudioState(hasAudio: localAudioTrack.isEnabled)
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
                localVideoTrack = TVILocalVideoTrack(source: camera, enabled: true, name: "Camera")

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

                camera.startCapture(with: frontCamera != nil ? frontCamera! : backCamera!) { (captureDevice, videoFormat, error) in
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
                newDevice = TVICameraSource.captureDevice(for: .back)
            } else {
                newDevice = TVICameraSource.captureDevice(for: .front)
            }

            if let newDevice = newDevice {
                camera.select(newDevice) { (captureDevice, videoFormat, error) in
                    if let error = error {
                        self.logMessage(messageText: "Error selecting capture device.\ncode = \((error as NSError).code) error = \(error.localizedDescription)")
                    } else {
                        self.localParticipantView.videoView.shouldMirror = (captureDevice.position == .front)
                    }
                }
            }
        }
    }

    @IBAction func toggleAudio(_ sender: Any) {
        if let localAudioTrack = self.localAudioTrack {
            localAudioTrack.isEnabled = !localAudioTrack.isEnabled
            updateLocalAudioState(hasAudio: localAudioTrack.isEnabled)
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
        let connectOptions = TVIConnectOptions(token: accessToken) { (builder) in

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

    func setupRemoteParticipantView(remoteParticipant: TVIRemoteParticipant) {
        // Create a `TVIVideoView` programmatically
        let remoteView = RemoteParticipantView.init(frame: CGRect.zero)

        // We will bet that a hash collision between two unique SIDs is very rare.
        remoteView.tag = remoteParticipant.hashValue
        remoteView.identity = remoteParticipant.identity
        containerView.addSubview(remoteView)
        remoteParticipantViews.append(remoteView)
    }

    func removeRemoteParticipantView(remoteParticipant: TVIRemoteParticipant) {
        let viewTag = remoteParticipant.hashValue
        if let remoteView = view.viewWithTag(viewTag) {
            remoteView.removeFromSuperview()
            remoteParticipantViews.removeAll { (item) -> Bool in
                return item == remoteView
            }
        }
    }

    func displayVideoTrack(_ videoTrack: TVIRemoteVideoTrack,
                           for participant: TVIRemoteParticipant) {
        let viewTag = participant.hashValue
        if let remoteView = view.viewWithTag(viewTag) as? RemoteParticipantView {
            // Start rendering
            videoTrack.addRenderer(remoteView.videoView);
            remoteView.hasVideo = true
        }
    }

    func removeVideoTrack(_ videoTrack: TVIRemoteVideoTrack,
                          for participant: TVIRemoteParticipant) {
        let viewTag = participant.hashValue
        if let remoteView = view.viewWithTag(viewTag) as? RemoteParticipantView {
            // Stop rendering
            videoTrack.removeRenderer(remoteView.videoView);
            remoteView.hasVideo = false
        }
    }

    func updateDominantSpeaker(dominantSpeaker: TVIRemoteParticipant?) {
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
                          for participant: TVIRemoteParticipant) {
        let viewTag = participant.hashValue
        if let remoteView = view.viewWithTag(viewTag) as? RemoteParticipantView {
            // Stop rendering
            remoteView.hasAudio = hasAudio
        }
    }

    func updateLocalAudioState(hasAudio: Bool) {
        self.localParticipantView.hasAudio = hasAudio
        audioMuteButton.isSelected = !hasAudio
    }

    func updateLocalVideoState(hasVideo: Bool) {
        self.localParticipantView.hasVideo = hasVideo
        videoMuteButton.isSelected = !hasVideo
    }

    func updateLocalNetworkQualityLevel(networkQualityLevel: TVINetworkQualityLevel) {
        logMessage(messageText: "Network Quality Level: \(networkQualityLevel.rawValue)")
        localParticipantView.networkQualityLevel = networkQualityLevel
    }
}

// MARK: TVIRoomDelegate
extension MultiPartyViewController : TVIRoomDelegate {
    func didConnect(to room: TVIRoom) {
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

        if #available(iOS 11.0, *) {
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    func room(_ room: TVIRoom, didFailToConnectWithError error: Error) {
        NSLog("Failed to connect to a Room: \(error).")

        let alertController = UIAlertController.init(title: "Connection Failed",
                                                     message: "Couldn't connect to Room \(room.name). code:\(error._code) \(error.localizedDescription)",
            preferredStyle: .alert)

        let cancelAction = UIAlertAction.init(title: "Okay", style: .default) { (alertAction) in
            self.leaveRoom(self)
        }

        alertController.addAction(cancelAction)

        self.present(alertController, animated: true) {
            self.room = nil
        }
    }

    func room(_ room: TVIRoom, didDisconnectWithError error: Error?) {
        guard let error = error else {
            return
        }

        NSLog("The Client was disconnected: \(error).")

        let alertController = UIAlertController.init(title: "Connection Failed",
                                                     message: "Disconnected from Room \(room.name). code:\(error._code) \(error.localizedDescription)",
            preferredStyle: .alert)

        let cancelAction = UIAlertAction.init(title: "Okay", style: .default) { (alertAction) in
            self.leaveRoom(self)
        }

        alertController.addAction(cancelAction)

        self.present(alertController, animated: true)
    }

    func room(_ room: TVIRoom, isReconnectingWithError error: Error) {
        logMessage(messageText: "Reconnecting to room \(room.name), error = \(String(describing: error))")
    }

    func didReconnect(to room: TVIRoom) {
        logMessage(messageText: "Reconnected to room \(room.name)")
    }

    func room(_ room: TVIRoom, participantDidConnect participant: TVIRemoteParticipant) {
        logMessage(messageText: "Participant \(participant.identity) connected with \(participant.remoteAudioTracks.count) audio and \(participant.remoteVideoTracks.count) video tracks")
        participant.delegate = self

        if remoteParticipantViews.count < MultiPartyViewController.kMaxRemoteParticipants {
            setupRemoteParticipantView(remoteParticipant: participant)
        }
    }

    func room(_ room: TVIRoom, participantDidDisconnect participant: TVIRemoteParticipant) {
        removeRemoteParticipantView(remoteParticipant: participant)
        logMessage(messageText: "Room \(room.name), Participant \(participant.identity) disconnected")
    }

    func room(_ room: TVIRoom, dominantSpeakerDidChange participant: TVIRemoteParticipant?) {
        updateDominantSpeaker(dominantSpeaker: participant)
    }
}

// MARK: TVILocalParticipantDelegate
extension MultiPartyViewController : TVILocalParticipantDelegate {
    func localParticipant(_ participant: TVILocalParticipant,
                          didChange networkQualityLevel: TVINetworkQualityLevel) {
        // Local Participant netwrk quality level has changed
        
        updateLocalNetworkQualityLevel(networkQualityLevel: networkQualityLevel)
    }
}

// MARK: TVIRemoteParticipantDelegate
extension MultiPartyViewController : TVIRemoteParticipantDelegate {
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
        displayVideoTrack(videoTrack, for: participant)
    }

    func unsubscribed(from videoTrack: TVIRemoteVideoTrack,
                      publication: TVIRemoteVideoTrackPublication,
                      for participant: TVIRemoteParticipant) {

        // We are unsubscribed from the remote Participant's video Track. We will no longer receive the
        // remote Participant's video.

        logMessage(messageText: "Unsubscribed from \(publication.trackName) video track for Participant \(participant.identity)")
        removeVideoTrack(videoTrack, for: participant)
    }

    func subscribed(to audioTrack: TVIRemoteAudioTrack,
                    publication: TVIRemoteAudioTrackPublication,
                    for participant: TVIRemoteParticipant) {

        // We are subscribed to the remote Participant's audio Track. We will start receiving the
        // remote Participant's audio now.

        logMessage(messageText: "Subscribed to \(publication.trackName) audio track for Participant \(participant.identity)")
        updateAudioState(hasAudio: true, for: participant)
    }

    func unsubscribed(from audioTrack: TVIRemoteAudioTrack,
                      publication: TVIRemoteAudioTrackPublication,
                      for participant: TVIRemoteParticipant) {

        // We are unsubscribed from the remote Participant's audio Track. We will no longer receive the
        // remote Participant's audio.

        logMessage(messageText: "Unsubscribed from \(publication.trackName) audio track for Participant \(participant.identity)")
        updateAudioState(hasAudio: false, for: participant)
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
        updateAudioState(hasAudio: true, for: participant)
    }

    func remoteParticipant(_ participant: TVIRemoteParticipant,
                           disabledAudioTrack publication: TVIRemoteAudioTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) disabled \(publication.trackName) audio track")
        updateAudioState(hasAudio: false, for: participant)
    }

    func failedToSubscribe(toAudioTrack publication: TVIRemoteAudioTrackPublication,
                           error: Error,
                           for participant: TVIRemoteParticipant) {
        logMessage(messageText: "Failed to subscribe \(publication.trackName) audio track, error = \(String(describing: error))")
    }

    func failedToSubscribe(toVideoTrack publication: TVIRemoteVideoTrackPublication,
                           error: Error,
                           for participant: TVIRemoteParticipant) {
        logMessage(messageText: "Failed to subscribe \(publication.trackName) video track, error = \(String(describing: error))")
    }
}

// MARK: TVICameraSourceDelegate
extension MultiPartyViewController : TVICameraSourceDelegate {
    func cameraSource(_ source: TVICameraSource, didFailWithError error: Error) {
        logMessage(messageText: "Camera source failed with error: \(error.localizedDescription)")
    }
}
