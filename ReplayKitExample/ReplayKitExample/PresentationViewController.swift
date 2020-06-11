//
//  PresentationViewController.swift
//  ReplayKitExample
//
//  Copyright © 2020 Twilio. All rights reserved.
//

import UIKit
import TwilioVideo

enum DataSourceError: Error {
    // The room is not connected.
    case notConnected
}

class PresentationViewController : UIViewController {

    static let kCellReuseId = "VideoCellReuseId"

    var cameraSource: CameraSource?
    var localVideoTrack: LocalVideoTrack?
    var localAudioTrack: LocalAudioTrack?
    var room: Room?

    var remoteParticipants: [RemoteParticipant] = []

    var statsTimer: Timer?
    weak var remoteView: VideoView?
    weak var scrollView: UIScrollView?
    var accessToken: String?
    weak var collectionView: UICollectionView?

    override func viewDidLoad() {
        super.viewDidLoad()

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        collectionView.backgroundColor = nil
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(VideoCollectionViewCell.self, forCellWithReuseIdentifier: PresentationViewController.kCellReuseId)
        self.collectionView = collectionView

        self.view.addSubview(collectionView)

        connectToPresentation()
    }

    override var prefersStatusBarHidden: Bool {
        get {
            return true
        }
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        get {
            return true
        }
    }

    func startCamera() {
        guard let device = CameraSource.captureDevice(position: .front) else {
            return
        }

        let options = CameraSourceOptions { builder in
            builder.rotationTags = .remove
        }

        let cameraFormat = VideoFormat()
        cameraFormat.frameRate = 15
        cameraFormat.dimensions = CMVideoDimensions(width: 480, height: 360)
        cameraFormat.pixelFormat = .formatYUV420BiPlanarFullRange
        guard let camera = CameraSource(options: options, delegate: self) else {
            return
        }

        guard let videoTrack = LocalVideoTrack(source: camera) else {
            return
        }

        // Crop to 360x360 square
        let sendFormat = VideoFormat()
        sendFormat.dimensions = CMVideoDimensions(width: 360, height: 360)
        camera.requestOutputFormat(sendFormat)
        camera.startCapture(device: device, format: cameraFormat) { (device, format, error) in

        }

        self.localVideoTrack = videoTrack
    }

    func publishCamera() {
        guard let participant = self.room?.localParticipant else {
            return
        }
        participant.delegate = self

        guard let videoTrack = self.localVideoTrack else {
            return
        }

        let publishOptions = LocalTrackPublicationOptions(priority: .low)
        participant.publishVideoTrack(videoTrack, publicationOptions: publishOptions)
    }

    func connectToPresentation() {
        TwilioVideoSDK.setLogLevel(.info)

        UIApplication.shared.isIdleTimerDisabled = true

        let videoOptions = VideoBandwidthProfileOptions { (builder) in
            // Minimum subscribe priority of Dominant Speaker's RemoteVideoTracks
            builder.dominantSpeakerPriority = .standard

            // Maximum bandwidth (Kbps) to be allocated to subscribed RemoteVideoTracks
            builder.maxSubscriptionBitrate = 6000

            // Max number of visible RemoteVideoTracks. Other RemoteVideoTracks will be switched off
            builder.maxTracks = 4

            // Subscription mode: collaboration, grid, presentation
            builder.mode = .presentation

            // Configure remote track's render dimensions per track priority
            let renderDimensions = VideoRenderDimensions()

            // Desired render dimensions of RemoteVideoTracks with priority low.
            renderDimensions.low = VideoDimensions(width: 640, height: 480)

            // Desired render dimensions of RemoteVideoTracks with priority standard.
            renderDimensions.standard = VideoDimensions(width: 640, height: 480)

            // Desired render dimensions of RemoteVideoTracks with priority high.
            renderDimensions.high = VideoDimensions(width: 1920, height: 1080)

            builder.renderDimensions = renderDimensions

            // Track Switch Off mode: .detected, .predicted, .disabled
            builder.trackSwitchOffMode = .predicted
        }
        let profile = BandwidthProfileOptions(videoOptions: videoOptions)
        let connectOptions = ConnectOptions(token: accessToken!) { builder in
            builder.bandwidthProfileOptions = profile

            if let audioTrack = LocalAudioTrack() {
                builder.audioTracks = [audioTrack]
                self.localAudioTrack = audioTrack
            }

            // Use the preferred signaling region
            if let signalingRegion = Settings.shared.signalingRegion {
                builder.region = signalingRegion
            }

            // Viewers will publish smaller "thumbnail" videos at lower bandwidth
            builder.encodingParameters = EncodingParameters(audioBitrate: 16, videoBitrate: 400)
        }

        self.room = TwilioVideoSDK.connect(options: connectOptions, delegate: self)

        self.startCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.scrollView?.frame = self.view.bounds
        self.scrollView?.contentInset = self.additionalSafeAreaInsets
        let contentBounds = self.view.bounds

        let width = 80
        self.collectionView?.bounds = CGRect(x: 0, y: 0, width: width, height: Int(contentBounds.size.height))
        self.collectionView?.center = CGPoint(x: width/2, y: Int(contentBounds.size.height)/2)

        if let dimensions = remoteView?.videoDimensions,
            remoteView?.hasVideoData == true {
            let contentRect = AVMakeRect(aspectRatio: CGSize(width: Int(dimensions.width),
                height: Int(dimensions.height)), insideRect: contentBounds).integral
//            let size = CGSize(width: CGFloat(dimensions.width) / scale, height: CGFloat(dimensions.height) / scale)
//            print("\(size)")
            scrollView?.contentSize = contentRect.size
            scrollView?.maximumZoomScale = 2
            scrollView?.minimumZoomScale = 1
            remoteView?.bounds = CGRect(origin: .zero, size: contentRect.size)
            remoteView?.center = CGPoint(x: contentRect.midX, y: contentRect.midY)
        }
    }

    func setupScreenshareVideo(publication: RemoteVideoTrackPublication) {
        // Creating `VideoView` programmatically
        let videoView = VideoView(frame: CGRect(origin: CGPoint.zero, size: CGSize(width: 640, height: 480)), delegate: self)
        videoView?.tag = publication.trackSid.hashValue

        let scrollView = UIScrollView()
        scrollView.contentSize = CGSize(width: 640, height: 480)
        scrollView.delegate = self
        scrollView.backgroundColor = nil
        scrollView.scrollsToTop = false
        scrollView.contentInsetAdjustmentBehavior = .always
        self.scrollView = scrollView

        // self.view.insertSubview(remoteView!, at: 0)
        self.view.insertSubview(scrollView, at: 0)
        self.scrollView?.addSubview(videoView!)

        videoView?.contentMode = .scaleAspectFit

        publication.videoTrack?.addRenderer(videoView!)

        let recognizer = UITapGestureRecognizer(target: self, action: #selector(tappedScreenParticipant(sender:)))
        recognizer.numberOfTapsRequired = 2;
        videoView?.addGestureRecognizer(recognizer)

        self.remoteView = videoView
    }

    @objc func tappedScreenParticipant(sender: UITapGestureRecognizer) {
        if let view = sender.view {
            view.contentMode = view.contentMode == UIView.ContentMode.scaleAspectFit ?
                UIView.ContentMode.scaleAspectFill : UIView.ContentMode.scaleAspectFit
        }
    }
}

// MARK:- LocalParticipantDelegate
extension PresentationViewController : LocalParticipantDelegate {
    func localParticipantDidPublishVideoTrack(participant: LocalParticipant, videoTrackPublication: LocalVideoTrackPublication) {
        print("localParticipantDidPublishVideoTrack: \(videoTrackPublication.trackSid)")

        #if DEBUG
        statsTimer = Timer(fire: Date(timeIntervalSinceNow: 1), interval: 10, repeats: true, block: { (Timer) in
            guard let room = self.room else {
                self.statsTimer?.invalidate()
                return
            }
            room.getStats({ (reports: [StatsReport]) in
                for report in reports {
                    if let videoStats = report.localVideoTrackStats.first {
                        print("Capture \(videoStats.captureDimensions) @ \(videoStats.captureFrameRate) fps.")
                        print("Send \(videoStats.dimensions) @ \(videoStats.frameRate) fps. RTT = \(videoStats.roundTripTime) ms")
                    }
                    for candidatePair in report.iceCandidatePairStats {
                        if candidatePair.isActiveCandidatePair {
                            print("Send = \(candidatePair.availableOutgoingBitrate)")
                            print("Receive = \(candidatePair.availableIncomingBitrate)")
                        }
                    }
                }
            })
        })

        if let theTimer = statsTimer {
            RunLoop.main.add(theTimer, forMode: .common)
        }
        #endif
    }
}

// MARK:- UIScrollViewDelegate
extension PresentationViewController : UIScrollViewDelegate {
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        print("scrollViewDidZoom \(scrollView)")
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        print("scrollViewDidScroll")
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return self.remoteView
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        print("scrollViewDidEndZooming with view \(view!) at scale \(scale)")
    }
}

extension PresentationViewController : UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if otherGestureRecognizer.view == self.scrollView {
            return true
        } else {
            return false
        }
    }
}

// MARK:- UICollectionViewDelegateFlowLayout
extension PresentationViewController : UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        print("didSelectItemAtIndexPath: \(indexPath)")
        // TODO: Update local audio track enabled/disabled state here.

        if indexPath.row == 0,
            let audioTrack = self.localAudioTrack {
            audioTrack.isEnabled = !audioTrack.isEnabled
        }

        // TODO: It would be nice to have the ability to pin remote Participants or maybe your own video.
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: 72, height: 72)
    }
}

// MARK:- UICollectionViewDataSource
extension PresentationViewController : UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let room = self.room else {
            return 0
        }

        guard room.localParticipant != nil else {
            return 0
        }

        return 1 + self.remoteParticipants.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PresentationViewController.kCellReuseId,
                                                      for: indexPath) as? VideoCollectionViewCell

        do {
            let participant = try self.participantForIndexPath(index: indexPath)
            if cell != nil {
                cell?.setParticipant(participant: participant, localVideoTrack: indexPath.row == 0 ? self.localVideoTrack : nil)
            }
        } catch DataSourceError.notConnected {
            print("The Room does not exist!")
        } catch {

        }

        return cell!
    }

    func participantForIndexPath(index: IndexPath) throws -> Participant {
        guard let room = self.room else {
            throw DataSourceError.notConnected
        }

        if index.row == 0 {
            return room.localParticipant!
        } else {
            return self.remoteParticipants[index.row - 1]
        }
    }
}

// MARK:- CameraSourceDelegate
extension PresentationViewController : CameraSourceDelegate {
    func cameraSourceWasInterrupted(source: CameraSource, reason: AVCaptureSession.InterruptionReason) {
        self.localVideoTrack?.isEnabled = false
    }

    func cameraSourceInterruptionEnded(source: CameraSource) {
        self.localVideoTrack?.isEnabled = true
    }
}

// MARK:- VideoViewDelegate
extension PresentationViewController : VideoViewDelegate {
    func videoViewDidReceiveData(view: VideoView) {
        if view == self.remoteView {
            self.scrollView?.isScrollEnabled = true
            self.view.setNeedsLayout()
        }
    }

    func videoViewDimensionsDidChange(view: VideoView, dimensions: CMVideoDimensions) {
        // TODO: Are updates needed here?
        let scale = UIScreen.main.nativeScale
        scrollView?.contentSize = CGSize(width: CGFloat(dimensions.width) / scale, height: CGFloat(dimensions.height) / scale)
        scrollView?.maximumZoomScale = 2
    }
}

// MARK:- RoomDelegate
extension PresentationViewController : RoomDelegate {
    func roomDidConnect(room: Room) {
        // Listen to events from existing `RemoteParticipant`s
        for remoteParticipant in room.remoteParticipants {
            remoteParticipant.delegate = self
        }

        let connectMessage = "Connected to room \(room.name) as \(room.localParticipant?.identity ?? "")."
        print(connectMessage)

        self.publishCamera()

        self.collectionView?.insertItems(at: [IndexPath(row: 0, section: 0)])
    }

    func roomDidDisconnect(room: Room, error: Error?) {
        if let disconnectError = error {
            print("Disconnected from \(room.name).\ncode = \((disconnectError as NSError).code) error = \(disconnectError.localizedDescription)")
        } else {
            print("Disconnected from \(room.name)")
        }

        self.room = nil
        self.statsTimer?.invalidate()
    }

    func roomDidFailToConnect(room: Room, error: Error) {
        print("Failed to connect to Room:\n\(error.localizedDescription)")

        self.room = nil
    }

    func roomIsReconnecting(room: Room, error: Error) {
        print("Reconnecting to room \(room.name), error = \(String(describing: error))")
    }

    func roomDidReconnect(room: Room) {
        print("Reconnected to room \(room.name)")
    }

    func participantDidConnect(room: Room, participant: RemoteParticipant) {
        participant.delegate = self

        print("Participant \(participant.identity) connected with \(participant.remoteAudioTracks.count) audio and \(participant.remoteVideoTracks.count) video tracks")
    }

    func participantDidDisconnect(room: Room, participant: RemoteParticipant) {
        print("Room \(room.name), Participant \(participant.identity) disconnected")

        if let index = self.remoteParticipants.firstIndex(of: participant) {
            self.remoteParticipants.remove(at: index)
            self.collectionView?.reloadData()
        }
    }
}

// MARK:- RemoteParticipantDelegate
extension PresentationViewController : RemoteParticipantDelegate {
    func remoteParticipantDidPublishVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        // Remote Participant has offered to share the video Track.

        print("Participant \(participant.identity) published \(publication.trackName) video track")
    }

    func remoteParticipantDidUnpublishVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        // Remote Participant has stopped sharing the video Track.

        print( "Participant \(participant.identity) unpublished \(publication.trackName) video track")
    }

    func remoteParticipantDidPublishAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        // Remote Participant has offered to share the audio Track.

        print( "Participant \(participant.identity) published \(publication.trackName) audio track")
    }

    func remoteParticipantDidUnpublishAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        // Remote Participant has stopped sharing the audio Track.

        print("Participant \(participant.identity) unpublished \(publication.trackName) audio track")
    }

    func didSubscribeToVideoTrack(videoTrack: RemoteVideoTrack, publication: RemoteVideoTrackPublication, participant: RemoteParticipant) {
        // We are subscribed to the remote Participant's video Track. We will start receiving the
        // remote Participant's video frames now.

        print("Subscribed to \(publication.trackName) video track for Participant \(participant.identity)")

        // Start remote rendering, and add a touch handler.
        if (self.remoteView == nil && publication.trackName == "Screen") {
            setupScreenshareVideo(publication: publication)
        } else {
            self.remoteParticipants.append(participant)
            self.collectionView?.reloadData()
        }
    }

    func didUnsubscribeFromVideoTrack(videoTrack: RemoteVideoTrack, publication: RemoteVideoTrackPublication, participant: RemoteParticipant) {
        // We are unsubscribed from the remote Participant's video Track. We will no longer receive the
        // remote Participant's video.

        print("Unsubscribed from \(publication.trackName) video track for Participant \(participant.identity)")

        // Stop remote rendering.
        if (publication.trackSid.hashValue == self.remoteView?.tag) {
            self.remoteView?.removeFromSuperview()
            self.remoteView = nil

            self.scrollView?.removeFromSuperview()
            self.scrollView = nil
        }
    }

    func didSubscribeToAudioTrack(audioTrack: RemoteAudioTrack, publication: RemoteAudioTrackPublication, participant: RemoteParticipant) {
        // We are subscribed to the remote Participant's audio Track. We will start receiving the
        // remote Participant's audio now.

        print( "Subscribed to \(publication.trackName) audio track for Participant \(participant.identity)")
    }

    func didUnsubscribeFromAudioTrack(audioTrack: RemoteAudioTrack, publication: RemoteAudioTrackPublication, participant: RemoteParticipant) {
        // We are unsubscribed from the remote Participant's audio Track. We will no longer receive the
        // remote Participant's audio.

        print( "Unsubscribed from \(publication.trackName) audio track for Participant \(participant.identity)")
    }

    func remoteParticipantDidEnableVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        print( "Participant \(participant.identity) enabled \(publication.trackName) video track")
    }

    func remoteParticipantDidDisableVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        print( "Participant \(participant.identity) disabled \(publication.trackName) video track")
    }

    func remoteParticipantDidEnableAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        print( "Participant \(participant.identity) enabled \(publication.trackName) audio track")
    }

    func remoteParticipantDidDisableAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        // We will continue to record silence and/or recognize audio while a Track is disabled.
        print( "Participant \(participant.identity) disabled \(publication.trackName) audio track")
    }

    func didFailToSubscribeToAudioTrack(publication: RemoteAudioTrackPublication, error: Error, participant: RemoteParticipant) {
        print( "FailedToSubscribe \(publication.trackName) audio track, error = \(String(describing: error))")
    }

    func didFailToSubscribeToVideoTrack(publication: RemoteVideoTrackPublication, error: Error, participant: RemoteParticipant) {
        print( "FailedToSubscribe \(publication.trackName) video track, error = \(String(describing: error))")
    }

    func remoteParticipantSwitchedOffVideoTrack(participant: RemoteParticipant, track: RemoteVideoTrack) {
        print( "remoteParticipantSwitchedOffVideoTrack \(track)")
    }

    func remoteParticipantSwitchedOnVideoTrack(participant: RemoteParticipant, track: RemoteVideoTrack) {
        print( "remoteParticipantSwitchedOnVideoTrack \(track)")
    }

}
