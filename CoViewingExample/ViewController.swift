//
//  ViewController.swift
//  CoViewingExample
//
//  Copyright © 2018 Twilio Inc. All rights reserved.
//

import AVFoundation
import UIKit

class ViewController: UIViewController {

    // MARK: View Controller Members

    // Configure access token manually for testing, if desired! Create one manually in the console
    // at https://www.twilio.com/console/video/runtime/testing-tools
    var accessToken = "TWILIO_ACCESS_TOKEN"

    // Configure remote URL to fetch token from
    var tokenUrl = "https://username:passowrd@simple-signaling.appspot.com/access-token"

    // Video SDK components
    var room: TVIRoom?
    var camera: TVICameraCapturer?
    var localVideoTrack: TVILocalVideoTrack!
    var playerVideoTrack: TVILocalVideoTrack?
    var localAudioTrack: TVILocalAudioTrack!

    let kPlayerTrackName = "player-track"

    var audioDevice: ExampleAVPlayerAudioDevice?
    var videoPlayer: AVPlayer? = nil
    var videoPlayerAudioTap: ExampleAVPlayerAudioTap? = nil
    var videoPlayerSource: ExampleAVPlayerSource? = nil
    var videoPlayerView: ExampleAVPlayerView? = nil

    var isPresenter:Bool?

    @IBOutlet weak var localHeightConstraint: NSLayoutConstraint?
    @IBOutlet weak var localWidthConstraint: NSLayoutConstraint?
    @IBOutlet weak var remoteHeightConstraint: NSLayoutConstraint?
    @IBOutlet weak var remoteWidthConstraint: NSLayoutConstraint?

    @IBOutlet weak var presenterButton: UIButton!
    @IBOutlet weak var viewerButton: UIButton!

    @IBOutlet weak var remoteView: TVIVideoView!
    @IBOutlet weak var localView: TVIVideoView!
    @IBOutlet weak var remotePlayerView: TVIVideoView!
    @IBOutlet weak var hangupButton: UIButton!

    // http://movietrailers.apple.com/movies/paramount/interstellar/interstellar-tlr4_h720p.mov
    static let kRemoteContentUrls = [
        // Nice stereo separation in the trailer music. We only record in mono at the moment.
        "American Animals Trailer 2 (720p24, 44.1 kHz)" : URL(string: "http://movietrailers.apple.com/movies/independent/american-animals/american-animals-trailer-2_h720p.mov")!,
        "Avengers: Infinity War Trailer 3 (720p24, 44.1 kHz)" : URL(string: "https://trailers.apple.com/movies/marvel/avengers-infinity-war/avengers-infinity-war-trailer-2_h720p.mov")!,
        // HLS stream which runs into the AVPlayer / AVAudioMix issue.
        "BitDash - Parkour (HLS)" : URL(string: "https://bitdash-a.akamaihd.net/content/MI201109210084_1/m3u8s/f08e80da-bf1d-4e3d-8899-f0f6155f6efa.m3u8")!,
        // Progressive download mp4 version. Demonstrates that 48 kHz support is incorrect right now.
        "BitDash - Parkour (1080p25, 48 kHz)" : URL(string: "https://bitmovin-a.akamaihd.net/content/MI201109210084_1/MI201109210084_mpeg-4_hd_high_1080p25_10mbits.mp4")!,
        // Encoding in 1080p takes significantly more CPU than 720p
        "Interstellar Trailer 3 (720p24, 44.1 kHz)" : URL(string: "http://movietrailers.apple.com/movies/paramount/interstellar/interstellar-tlr4_h720p.mov")!,
        "Interstellar Trailer 3 (1080p24, 44.1 kHz)" : URL(string: "http://movietrailers.apple.com/movies/paramount/interstellar/interstellar-tlr4_h1080p.mov")!,
        // Most trailers have a lot of cuts... this one not as many
        "Mississippi Grind (720p24, 44.1 kHz)" : URL(string: "http://movietrailers.apple.com/movies/independent/mississippigrind/mississippigrind-tlr1_h1080p.mov")!,
        // HLS stream which runs into the AVPlayer / AVAudioMix issue.
        "Tele Quebec (HLS)" : URL(string: "https://mnmedias.api.telequebec.tv/m3u8/29880.m3u8")!,
        // Video only source, but at 30 fps which is the max frame rate that we can capture.
        "Telecom ParisTech, GPAC (720p30)" : URL(string: "https://download.tsi.telecom-paristech.fr/gpac/dataset/dash/uhd/mux_sources/hevcds_720p30_2M.mp4")!,
        "Telecom ParisTech, GPAC (1080p30)" : URL(string: "https://download.tsi.telecom-paristech.fr/gpac/dataset/dash/uhd/mux_sources/hevcds_1080p30_6M.mp4")!,
        "Twilio: What is Cloud Communications? (1080p24, 44.1 kHz)" : URL(string: "https://s3-us-west-1.amazonaws.com/avplayervideo/What+Is+Cloud+Communications.mov")!
    ]
    static let kRemoteContentURL = kRemoteContentUrls["Interstellar Trailer 3 (720p24, 44.1 kHz)"]!

    override func viewDidLoad() {
        super.viewDidLoad()

        let red = UIColor(red: 226.0/255.0,
                          green: 29.0/255.0,
                          blue: 37.0/255.0,
                          alpha: 1.0)

        presenterButton.backgroundColor = red
        self.remotePlayerView.contentMode = UIView.ContentMode.scaleAspectFit
        self.remotePlayerView.isHidden = true
        self.hangupButton.backgroundColor = red
        self.hangupButton.titleLabel?.textColor = UIColor.white
        self.hangupButton.isHidden = true

        presenterButton.layer.cornerRadius = 4;
        viewerButton.layer.cornerRadius = 4;
        hangupButton.layer.cornerRadius = 2;

        self.localView.contentMode = UIView.ContentMode.scaleAspectFit
        self.localView.delegate = self
        self.localWidthConstraint = self.localView.constraints.first
        self.localHeightConstraint = self.localView.constraints.last
        self.remoteView.contentMode = UIView.ContentMode.scaleAspectFit
        self.remoteView.delegate = self
        self.remoteHeightConstraint = self.remoteView.constraints.first
        self.remoteWidthConstraint = self.remoteView.constraints.last
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        if let playerView = videoPlayerView {
            playerView.frame = CGRect(origin: CGPoint.zero, size: self.view.bounds.size)
        }
    }

    override func updateViewConstraints() {
        super.updateViewConstraints()

        if self.localView.hasVideoData {
            let localDimensions = self.localView.videoDimensions
            if localDimensions.width > localDimensions.height {
                self.localWidthConstraint?.constant = 128
                self.localHeightConstraint?.constant = 96
            } else {
                self.localWidthConstraint?.constant = 96
                self.localHeightConstraint?.constant = 128
            }
        }

        if self.remoteView.hasVideoData {
            let remoteDimensions = self.remoteView.videoDimensions
            if remoteDimensions.width > remoteDimensions.height {
                self.remoteWidthConstraint?.constant = 128
                self.remoteHeightConstraint?.constant = 96
            } else {
                self.remoteWidthConstraint?.constant = 96
                self.remoteHeightConstraint?.constant = 128
            }
        }
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        get {
            return self.room != nil
        }
    }

    override var prefersStatusBarHidden: Bool {
        get {
            return self.room != nil
        }
    }

    @IBAction func startPresenter(_ sender: Any) {
        if self.audioDevice == nil {
            let device = ExampleAVPlayerAudioDevice()
            TwilioVideo.audioDevice =  device
            self.audioDevice = device
        }
        isPresenter = true
        if self.remotePlayerView != nil {
            self.remotePlayerView.removeFromSuperview()
            self.remotePlayerView = nil
        }
        connect(name: "presenter")
    }

    @IBAction func startViewer(_ sender: Any) {
        self.audioDevice = nil
        TwilioVideo.audioDevice = TVIDefaultAudioDevice()
        isPresenter = false
        connect(name: "viewer")
    }

    @IBAction func hangup(_ sender: Any) {
        self.room?.disconnect()
    }

    func logMessage(messageText: String) {
        print(messageText)
    }

    func connect(name: String) {
        // Configure access token either from server or manually.
        // If the default wasn't changed, try fetching from server.
        if (accessToken == "TWILIO_ACCESS_TOKEN") {
            let urlStringWithRole = tokenUrl + "?identity=" + name
            do {
                accessToken = try String(contentsOf:URL(string: urlStringWithRole)!)
            } catch {
                let message = "Failed to fetch access token"
                print(message)
                return
            }
        }

        // Prepare local media which we will share with Room Participants.
        self.prepareLocalMedia()
        // Preparing the connect options with the access token that we fetched (or hardcoded).
        let connectOptions = TVIConnectOptions.init(token: accessToken) { (builder) in

            // Use the local media that we prepared earlier.
            builder.videoTracks = self.localVideoTrack != nil ? [self.localVideoTrack!] : []
            builder.audioTracks = self.localAudioTrack != nil ? [self.localAudioTrack!] : [TVILocalAudioTrack]()

            // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty
            // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
            builder.roomName = "twilio"

            // Restrict video bandwidth used by viewers to improve presenter video.
            if name == "viewer" {
                builder.encodingParameters = TVIEncodingParameters(audioBitrate: 0, videoBitrate: 1024 * 900)
            }
        }

        // Connect to the Room using the options we provided.
        room = TwilioVideo.connect(with: connectOptions, delegate: self)
        print("Attempting to connect to:", connectOptions.roomName as Any)

        self.showRoomUI(inRoom: true)
    }

    func prepareLocalMedia() {
        // All Participants share local audio and video when they connect to the Room.
        // Create an audio track.
        if (localAudioTrack == nil) {
            localAudioTrack = TVILocalAudioTrack.init()

            if (localAudioTrack == nil) {
                print("Failed to create audio track")
            }
        }

        // Create a camera video Track.
        #if !targetEnvironment(simulator)
        if (localVideoTrack == nil) {
            // Preview our local camera track in the local video preview view.

            camera = TVICameraCapturer(source: .frontCamera, delegate: nil)
            let constraints = TVIVideoConstraints.init { (builder) in
                builder.maxSize = TVIVideoConstraintsSize480x360
                builder.maxFrameRate = TVIVideoConstraintsFrameRate24
            }

            localVideoTrack = TVILocalVideoTrack(capturer: camera!,
                                                 enabled: true,
                                                 constraints: constraints,
                                                 name: "camera")
            localVideoTrack.addRenderer(self.localView)
            // We use the front facing camera only. Set mirroring each time since the renderer might be reused.
            localView.shouldMirror = true
        }
        #endif
    }

    func showRoomUI(inRoom: Bool) {
        self.hangupButton.isHidden = !inRoom
        self.localView.isHidden = !inRoom
        if (self.isPresenter == false) {
            self.remotePlayerView.isHidden = !inRoom
        }
        self.remoteView.isHidden = !inRoom
        self.presenterButton.isHidden = inRoom
        self.viewerButton.isHidden = inRoom
        self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        self.setNeedsStatusBarAppearanceUpdate()
    }

    func startVideoPlayer() {
        if let player = self.videoPlayer {
            player.play()
            return
        }

        let asset = AVAsset(url: ViewController.kRemoteContentURL)
        let assetKeysToPreload = [
            "hasProtectedContent",
            "playable",
            "tracks"
        ]
        print("Created asset with tracks:", asset.tracks as Any)

        let playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: assetKeysToPreload)
        // Prevent excessive resource usage when the content is HLS. We will downscale large progressively streamed content.
        playerItem.preferredMaximumResolution = ExampleAVPlayerSource.kFrameOutputMaxRect.size
        // Register as an observer of the player item's status property
        playerItem.addObserver(self,
                               forKeyPath: #keyPath(AVPlayerItem.status),
                               options: [.old, .new],
                               context: nil)

        playerItem.addObserver(self,
                               forKeyPath: #keyPath(AVPlayerItem.tracks),
                               options: [.old, .new],
                               context: nil)

        let player = AVPlayer(playerItem: playerItem)
        player.volume = Float(0)
        videoPlayer = player

        let playerView = ExampleAVPlayerView(frame: CGRect.zero, player: player)
        videoPlayerView = playerView

        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handlePlayerTap))
        tapRecognizer.numberOfTapsRequired = 2
        videoPlayerView?.addGestureRecognizer(tapRecognizer)

        // We will rely on frame based layout to size and position `self.videoPlayerView`.
        self.view.insertSubview(playerView, at: 0)
        self.view.setNeedsLayout()
        UIView.animate(withDuration: 0.2) {
            self.view.backgroundColor = UIColor.black
        }
    }

    @objc func handlePlayerTap(recognizer: UITapGestureRecognizer) {
        if let view = self.videoPlayerView {
            view.contentMode = view.contentMode == .scaleAspectFit ? .scaleAspectFill : .scaleAspectFit
        }
    }

    func setupVideoSource(item: AVPlayerItem) {
        videoPlayerSource = ExampleAVPlayerSource(item: item)

        // Create and publish video track.
        if let track = TVILocalVideoTrack(capturer: videoPlayerSource!,
                                          enabled: true,
                                          constraints: nil,
                                          name: kPlayerTrackName) {
            playerVideoTrack = track
            self.room!.localParticipant!.publishVideoTrack(track)
        }
    }

    func setupAudioMix(player: AVPlayer, playerItem: AVPlayerItem) {
        let audioAssetTrack = firstAudioAssetTrack(playerItem: playerItem)
        print("Setup audio mix with AssetTrack:", audioAssetTrack != nil ? audioAssetTrack as Any : " none")

        let audioMix = AVMutableAudioMix()

        let inputParameters = AVMutableAudioMixInputParameters(track: audioAssetTrack)
        // TODO: Memory management of the MTAudioProcessingTap.
        inputParameters.audioTapProcessor = audioDevice!.createProcessingTap()?.takeUnretainedValue()
        audioMix.inputParameters = [inputParameters]
        playerItem.audioMix = audioMix
    }

    func firstAudioAssetTrack(playerItem: AVPlayerItem) -> AVAssetTrack? {
        var audioAssetTracks: [AVAssetTrack] = []
        for playerItemTrack in playerItem.tracks {
            if let assetTrack = playerItemTrack.assetTrack,
                assetTrack.mediaType == AVMediaType.audio {
                audioAssetTracks.append(assetTrack)
            }
        }
        return audioAssetTracks.first
    }

    func updateAudioMixParameters(playerItem: AVPlayerItem) {
        // Update the audio mix to point to the first AVAssetTrack that we find.
        if let audioAssetTrack = firstAudioAssetTrack(playerItem: playerItem),
            let inputParameters = playerItem.audioMix?.inputParameters.first {
            let mutableInputParameters = inputParameters as! AVMutableAudioMixInputParameters
            mutableInputParameters.trackID = audioAssetTrack.trackID
            print("Update the mix input parameters to use Track Id:", audioAssetTrack.trackID as Any, "\n",
                  "Asset:", audioAssetTrack.asset as Any, "\n",
                  "Audio Fallbacks:", audioAssetTrack.associatedTracks(ofType: AVAssetTrack.AssociationType.audioFallback), "\n",
                  "isPlayable:", audioAssetTrack.isPlayable)
        } else {
            // TODO
        }
    }

    func stopVideoPlayer() {
        videoPlayer?.pause()
        videoPlayer = nil

        // Remove player UI
        videoPlayerView?.removeFromSuperview()
        videoPlayerView = nil
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        // Only handle observations for the playerItemContext
//        if object != videoPlayer?.currentItem {
//            super.observeValue(forKeyPath: keyPath,
//                               of: object,
//                               change: change,
//                               context: context)
//            return
//        }

        if keyPath == #keyPath(AVPlayerItem.status) {
            let status: AVPlayerItem.Status

            // Get the status change from the change dictionary
            if let statusNumber = change?[.newKey] as? NSNumber {
                status = AVPlayerItem.Status(rawValue: statusNumber.intValue)!
            } else {
                status = .unknown
            }

            // Switch over the status
            switch status {
            case .readyToPlay:
                // Player item is ready to play.
                print("Ready. Playing asset with tracks: ", videoPlayer?.currentItem?.asset.tracks as Any)
                // Defer video source setup until we've loaded the asset so that we can determine downscaling for progressive streaming content.
                if self.videoPlayerSource == nil {
                    setupVideoSource(item: object as! AVPlayerItem)
                }
                videoPlayer?.play()
                break
            case .failed:
                // Player item failed. See error.
                // TODO: Show in the UI.
                print("Playback failed with error:", videoPlayer?.currentItem?.error as Any)
                break
            case .unknown:
                // Player item is not yet ready.
                print("Player status unknown.")
                break
            }
        } else if keyPath == #keyPath(AVPlayerItem.tracks) {
            let playerItem = object as! AVPlayerItem
            print("Player item tracks are:", playerItem.tracks as Any)

            // Configure our audio capturer to receive audio samples from the AVPlayerItem.
            if playerItem.audioMix == nil,
                firstAudioAssetTrack(playerItem: playerItem) != nil {
                setupAudioMix(player: videoPlayer!, playerItem: playerItem)
            } else {
                // TODO: Possibly update the existing mix?
            }
        }
    }
}

// MARK: TVIRoomDelegate
extension ViewController : TVIRoomDelegate {
    func didConnect(to room: TVIRoom) {

        // Listen to events from existing `TVIRemoteParticipant`s
        for remoteParticipant in room.remoteParticipants {
            remoteParticipant.delegate = self
        }

        if (room.remoteParticipants.count > 0 && self.isPresenter!) {
            stopVideoPlayer()
            startVideoPlayer()
        }

        let connectMessage = "Connected to room \(room.name) as \(room.localParticipant?.identity ?? "")."
        logMessage(messageText: connectMessage)

        self.showRoomUI(inRoom: true)
    }

    func room(_ room: TVIRoom, didDisconnectWithError error: Error?) {
        if let disconnectError = error {
            logMessage(messageText: "Disconnected from \(room.name).\ncode = \((disconnectError as NSError).code) error = \(disconnectError.localizedDescription)")
        } else {
            logMessage(messageText: "Disconnected from \(room.name)")
        }


        stopVideoPlayer()
        self.localVideoTrack = nil;
        self.localAudioTrack = nil;
        self.playerVideoTrack = nil;
        self.room = nil
        self.showRoomUI(inRoom: false)
        self.accessToken = "TWILIO_ACCESS_TOKEN"
    }

    func room(_ room: TVIRoom, didFailToConnectWithError error: Error) {
        logMessage(messageText: "Failed to connect to Room:\n\(error.localizedDescription)")

        self.room = nil
        self.localVideoTrack = nil;
        self.localAudioTrack = nil;
        self.showRoomUI(inRoom: false)
        self.accessToken = "TWILIO_ACCESS_TOKEN"
    }

    func room(_ room: TVIRoom, participantDidConnect participant: TVIRemoteParticipant) {
        participant.delegate = self

        logMessage(messageText: "Participant \(participant.identity) connected with \(participant.remoteAudioTracks.count) audio and \(participant.remoteVideoTracks.count) video tracks")

        if (room.remoteParticipants.count == 1 && self.isPresenter!) {
            stopVideoPlayer()
            startVideoPlayer()
        }
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
        if (videoTrack.name == self.kPlayerTrackName) {
            self.remotePlayerView.isHidden = false
            videoTrack.addRenderer(self.remotePlayerView)
            UIView.animate(withDuration: 0.2) {
                self.view.backgroundColor = UIColor.black
            }
        } else {
            videoTrack.addRenderer(self.remoteView)
        }
    }

    func unsubscribed(from videoTrack: TVIRemoteVideoTrack,
                      publication: TVIRemoteVideoTrackPublication,
                      for participant: TVIRemoteParticipant) {

        // We are unsubscribed from the remote Participant's video Track. We will no longer receive the
        // remote Participant's video.

        logMessage(messageText: "Unsubscribed from \(publication.trackName) video track for Participant \(participant.identity)")

        // Stop remote rendering.

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

extension ViewController : TVIVideoViewDelegate {
    func videoViewDidReceiveData(_ view: TVIVideoView) {
        if view == self.localView || view == self.remoteView {
            self.view.setNeedsUpdateConstraints()
        }
    }
    func videoView(_ view: TVIVideoView, videoDimensionsDidChange dimensions: CMVideoDimensions) {
        if view == self.localView || view == self.remoteView {
            self.view.setNeedsUpdateConstraints()
        }
    }
}
