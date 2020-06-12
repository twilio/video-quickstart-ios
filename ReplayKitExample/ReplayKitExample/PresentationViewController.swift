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
    static let kLargeCellSize = 160
    static let kSmallCellSize = 78

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
        collectionView.contentInsetAdjustmentBehavior = .scrollableAxes
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

        self.cameraSource = camera
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

            builder.preferredVideoCodecs = [Vp8Codec(simulcast: true)]

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

    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        // Workaround to fix content bugs after rotating while zoomed past minimum zoom.
        if let scrollView = self.scrollView {
            scrollView.zoomScale = scrollView.minimumZoomScale
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.scrollView?.frame = self.view.bounds
        self.scrollView?.contentInset = self.additionalSafeAreaInsets
        let contentBounds = self.view.bounds

        // Manually apply insets on the axis of scrolling
        self.collectionView?.contentInset = UIEdgeInsets(top: self.view.safeAreaInsets.top,
                                                         left: 0,
                                                         bottom: self.view.safeAreaInsets.bottom,
                                                         right: 0)

        // Size the collection view
        var width = UIDevice.current.userInterfaceIdiom == .pad ?
            PresentationViewController.kLargeCellSize : PresentationViewController.kSmallCellSize
        width += 10
        self.collectionView?.bounds = CGRect(x: 0, y: 0, width: width, height: Int(contentBounds.size.height))
        self.collectionView?.center = CGPoint(x: width/2 + Int(self.view.safeAreaInsets.left),
                                              y: Int(contentBounds.size.height)/2)

        if let dimensions = remoteView?.videoDimensions,
            remoteView?.hasVideoData == true {
            let contentRect = AVMakeRect(aspectRatio: CGSize(width: Int(dimensions.width),
                height: Int(dimensions.height)), insideRect: contentBounds).integral
            scrollView?.contentSize = contentBounds.size
            scrollView?.maximumZoomScale = max(max(contentBounds.width / contentRect.width,
                                               contentBounds.height / contentRect.height),
                                               2)
            scrollView?.minimumZoomScale = 1
            remoteView?.bounds = CGRect(origin: .zero, size: contentRect.size)
            remoteView?.center = CGPoint(x: contentBounds.midX, y: contentBounds.midY)

            // Use additional insets so that the user can't pixel peep the black bars too closely.. :)
            let xInset = contentBounds.width - contentRect.width
            let yInset = contentBounds.height - contentRect.height
            scrollView?.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: yInset, right: xInset)
        }
    }

    func setupScreenshareVideo(publication: RemoteVideoTrackPublication) {
        // Creating `VideoView` programmatically
        let videoView = VideoView(frame: CGRect(origin: CGPoint.zero, size: CGSize(width: 640, height: 480)), delegate: self)
        videoView?.tag = publication.trackSid.hashValue

        let scrollView = UIScrollView()
        scrollView.contentSize = self.view.bounds.size
        scrollView.delegate = self
        scrollView.backgroundColor = nil
        scrollView.scrollsToTop = false
        scrollView.contentInsetAdjustmentBehavior = .scrollableAxes
        self.scrollView = scrollView

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
        if let scrollView = self.scrollView,
            sender.view == self.remoteView {
            if scrollView.zoomScale > scrollView.minimumZoomScale + CGFloat(Double.ulpOfOne) {
                // Zoom out to fit the entire content.
                scrollView.zoom(to: CGRect(origin: .zero, size: scrollView.contentSize), animated: true)
            } else {
                // Zoom in to aspect fill the content
                let zoomedRect = AVMakeRect(aspectRatio: scrollView.bounds.size, insideRect: self.remoteView?.bounds ?? .zero)
                scrollView.zoom(to: zoomedRect, animated: true)
            }
        }
    }

    func roomDisconnected(error: Error?) {
        // TODO: Presenting the error would be nice!

        if let source = self.cameraSource {
            source.stopCapture(completion: { error in
                print("Camera stopped.")
                self.localVideoTrack = nil
                self.cameraSource = nil

                self.navigationController?.popViewController(animated: true)
            })
        } else {
            self.navigationController?.popViewController(animated: true)
        }

        self.statsTimer?.invalidate()
        self.room = nil
        UIApplication.shared.isIdleTimerDisabled = false
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

        // Quick tap to mute/unmute UI. Long press for more options.
        if indexPath.row == 0,
            let audioTrack = self.localAudioTrack {
            let enabled = !audioTrack.isEnabled
            audioTrack.isEnabled = enabled

            // Update muting state.
            if let theCell = collectionView.cellForItem(at: indexPath) as? VideoCollectionViewCell {
                theCell.updateMute(enabled: enabled)
            }
        }

        collectionView.deselectItem(at: indexPath, animated: true)
    }

    @available(iOS 13.0, *)
    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        // Long press to disconnect or mute.
        if indexPath.row == 0 {
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { suggestedActions in
                let muteTitle = self.localAudioTrack?.isEnabled ?? false ? "Mute" : "Unmute"
                let muteIcon = self.localAudioTrack?.isEnabled ?? false ? "mic.slash.fill" : "mic.fill"

                // Create an action for muting
                let mute = UIAction(title: muteTitle, image: UIImage(systemName: muteIcon)) { action in
                    if let audioTrack = self.localAudioTrack {
                        let enabled = !audioTrack.isEnabled
                        audioTrack.isEnabled = enabled
                        // Update muting state.
                        if let theCell = collectionView.cellForItem(at: indexPath) as? VideoCollectionViewCell {
                            theCell.updateMute(enabled: enabled)
                        }
                    }
                }

                // Here we specify the "destructive" attribute to show that it’s destructive in nature
                let delete = UIAction(title: "Disconnect", image: UIImage(systemName: "phone.down.fill"), attributes: .destructive) { action in
                    self.room?.disconnect()
                }

                // Create and return a UIMenu with all of the actions as children
                return UIMenu(title: "", children: [mute, delete])
            }
        } else {
            // No actions are possible at this time. The app could mute, pin video, something else?
            return UIContextMenuConfiguration()
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return CGSize(width: PresentationViewController.kLargeCellSize, height: PresentationViewController.kLargeCellSize)
        } else {
            return CGSize(width: PresentationViewController.kSmallCellSize, height: PresentationViewController.kSmallCellSize)
        }
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
            if let videoCell = cell {
                if indexPath.row == 0 {
                    videoCell.setParticipant(participant: participant, localVideoTrack: self.localVideoTrack, localAudioTrack: self.localAudioTrack)
                } else {
                    videoCell.setParticipant(participant: participant, localVideoTrack: nil, localAudioTrack: nil)
                }
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

    func indexPathForRemoteParticipant(participant: RemoteParticipant) -> IndexPath? {
        if let index = self.remoteParticipants.index(of: participant) {
            return IndexPath(row: index + 1, section: 0)
        } else {
            return nil
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
        // Trigger a layout pass to resize the scroll view & video view contents
        self.view.setNeedsLayout()
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

        roomDisconnected(error: error)
    }

    func roomDidFailToConnect(room: Room, error: Error) {
        print("Failed to connect to Room:\n\(error.localizedDescription)")

        roomDisconnected(error: error)
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

        // The Participant might not have be visible yet if the video was never subscribed.
        if let index = self.remoteParticipants.firstIndex(of: participant) {
            self.remoteParticipants.remove(at: index)
            self.collectionView?.deleteItems(at: [IndexPath(row: index + 1, section: 0)])
        }
    }
}

// MARK:- RemoteParticipantDelegate
extension PresentationViewController : RemoteParticipantDelegate {
    func didSubscribeToVideoTrack(videoTrack: RemoteVideoTrack, publication: RemoteVideoTrackPublication, participant: RemoteParticipant) {
        // We are subscribed to the remote Participant's video Track. We will start receiving the
        // remote Participant's video frames now.

        print("Subscribed to \(publication.trackName) video track for Participant \(participant.identity)")

        // Start remote rendering, and add a touch handler.
        if (self.remoteView == nil && publication.trackName == "Screen") {
            setupScreenshareVideo(publication: publication)
        } else {
            self.remoteParticipants.append(participant)
            self.collectionView?.insertItems(at: [IndexPath(row: self.remoteParticipants.count, section: 0)])
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
        guard let indexPath = self.indexPathForRemoteParticipant(participant: participant) else {
            return
        }
        if let theCell = collectionView?.cellForItem(at: indexPath) as? VideoCollectionViewCell {
            theCell.updateVideoSwitchedOff(switchedOff: false)
        }
    }

    func remoteParticipantDidDisableVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        print( "Participant \(participant.identity) disabled \(publication.trackName) video track")
        guard let indexPath = self.indexPathForRemoteParticipant(participant: participant) else {
            return
        }
        if let theCell = collectionView?.cellForItem(at: indexPath) as? VideoCollectionViewCell {
            theCell.updateVideoSwitchedOff(switchedOff: true)
        }
    }

    func remoteParticipantDidEnableAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        print( "Participant \(participant.identity) enabled \(publication.trackName) audio track")
        // Update the audio enabled state.
        guard let indexPath = self.indexPathForRemoteParticipant(participant: participant) else {
            return
        }
        if let theCell = collectionView?.cellForItem(at: indexPath) as? VideoCollectionViewCell {
            theCell.updateMute(enabled: true)
        }
    }

    func remoteParticipantDidDisableAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        print( "Participant \(participant.identity) disabled \(publication.trackName) audio track")

        // Update the audio enabled state.
        guard let indexPath = self.indexPathForRemoteParticipant(participant: participant) else {
            return
        }
        if let theCell = collectionView?.cellForItem(at: indexPath) as? VideoCollectionViewCell {
            theCell.updateMute(enabled: false)
        }
    }

    func didFailToSubscribeToAudioTrack(publication: RemoteAudioTrackPublication, error: Error, participant: RemoteParticipant) {
        print( "FailedToSubscribe \(publication.trackName) audio track, error = \(String(describing: error))")
    }

    func didFailToSubscribeToVideoTrack(publication: RemoteVideoTrackPublication, error: Error, participant: RemoteParticipant) {
        print( "FailedToSubscribe \(publication.trackName) video track, error = \(String(describing: error))")
    }

    func remoteParticipantSwitchedOffVideoTrack(participant: RemoteParticipant, track: RemoteVideoTrack) {
        print( "remoteParticipantSwitchedOffVideoTrack \(track)")

        guard let indexPath = self.indexPathForRemoteParticipant(participant: participant) else {
            return
        }
        if let theCell = collectionView?.cellForItem(at: indexPath) as? VideoCollectionViewCell {
            theCell.updateVideoSwitchedOff(switchedOff: true)
        }
    }

    func remoteParticipantSwitchedOnVideoTrack(participant: RemoteParticipant, track: RemoteVideoTrack) {
        print( "remoteParticipantSwitchedOnVideoTrack \(track)")

        guard let indexPath = self.indexPathForRemoteParticipant(participant: participant) else {
            return
        }
        if let theCell = collectionView?.cellForItem(at: indexPath) as? VideoCollectionViewCell {
            theCell.updateVideoSwitchedOff(switchedOff: false)
        }
    }

}
