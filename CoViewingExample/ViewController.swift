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

    var audioDevice: ExampleAVPlayerAudioDevice = ExampleAVPlayerAudioDevice()
    var videoPlayer: AVPlayer? = nil
    var videoPlayerAudioTap: ExampleAVPlayerAudioTap? = nil
    var videoPlayerSource: ExampleAVPlayerSource? = nil
    var videoPlayerView: ExampleAVPlayerView? = nil

    var isPresenter:Bool?

    @IBOutlet weak var presenterButton: UIButton!
    @IBOutlet weak var viewerButton: UIButton!

    @IBOutlet weak var remoteView: TVIVideoView!
    @IBOutlet weak var localView: TVIVideoView!
    @IBOutlet weak var remotePlayerView: TVIVideoView!
    @IBOutlet weak var hangupButton: UIButton!

    static var useAudioDevice = true
    static let kRemoteContentURL = URL(string: "https://s3-us-west-1.amazonaws.com/avplayervideo/What+Is+Cloud+Communications.mov")!

    override func viewDidLoad() {
        super.viewDidLoad()

        // We use the front facing camera for Co-Viewing.
        let red = UIColor(red: 226.0/255.0,
                          green: 29.0/255.0,
                          blue: 37.0/255.0,
                          alpha: 1.0)

        localView.shouldMirror = true
        presenterButton.backgroundColor = red
        presenterButton.titleLabel?.textColor = UIColor.white
        viewerButton.backgroundColor = red
        viewerButton.titleLabel?.textColor = UIColor.white
        self.remotePlayerView.contentMode = UIView.ContentMode.scaleAspectFit
        self.remotePlayerView.isHidden = true
        self.hangupButton.backgroundColor = red
        self.hangupButton.titleLabel?.textColor = UIColor.white
        self.hangupButton.isHidden = true

        presenterButton.layer.cornerRadius = 4;
        viewerButton.layer.cornerRadius = 4;
        hangupButton.layer.cornerRadius = 2;

        self.localView.contentMode = UIView.ContentMode.scaleAspectFit
        self.remoteView.contentMode = UIView.ContentMode.scaleAspectFit
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

    @IBAction func startPresenter(_ sender: Any) {
        self.audioDevice = ExampleAVPlayerAudioDevice()
        TwilioVideo.audioDevice =  self.audioDevice
        isPresenter = true
        connect(name: "presenter")
    }

    @IBAction func startViewer(_ sender: Any) {
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
            builder.videoTracks = self.localVideoTrack != nil ? [self.localVideoTrack!] : [TVILocalVideoTrack]()
            builder.audioTracks = self.localAudioTrack != nil ? [self.localAudioTrack!] : [TVILocalAudioTrack]()

            // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty
            // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
            builder.roomName = "twilio"
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
            localVideoTrack = TVILocalVideoTrack.init(capturer: camera!)
            localVideoTrack.addRenderer(self.localView)
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
    }

    func startVideoPlayer() {
        if let player = self.videoPlayer {
            player.play()
            return
        }

        let playerItem = AVPlayerItem(url: ViewController.kRemoteContentURL)
        let player = AVPlayer(playerItem: playerItem)
        videoPlayer = player

        let playerView = ExampleAVPlayerView(frame: CGRect.zero, player: player)
        videoPlayerView = playerView

        // We will rely on frame based layout to size and position `self.videoPlayerView`.
        self.view.insertSubview(playerView, at: 0)
        self.view.setNeedsLayout()

        // TODO: Add KVO observer instead?
        player.play()

        // Configure our video capturer to receive video samples from the AVPlayerItem.
        videoPlayerSource = ExampleAVPlayerSource(item: playerItem)

        // Configure our audio capturer to receive audio samples from the AVPlayerItem.
        let audioMix = AVMutableAudioMix()
        let itemAsset = playerItem.asset
        print("Created asset with tracks: ", itemAsset.tracks as Any)

        if let assetAudioTrack = itemAsset.tracks(withMediaType: AVMediaType.audio).first {
            let inputParameters = AVMutableAudioMixInputParameters(track: assetAudioTrack)

            // TODO: Memory management of the MTAudioProcessingTap.
            if ViewController.useAudioDevice {
                inputParameters.audioTapProcessor = audioDevice.createProcessingTap()?.takeUnretainedValue()
                player.volume = Float(0)
            } else {
                let processor = ExampleAVPlayerAudioTap()
                videoPlayerAudioTap = processor
                inputParameters.audioTapProcessor = ExampleAVPlayerAudioTap.mediaToolboxAudioProcessingTapCreate(audioTap: processor)
            }

            audioMix.inputParameters = [inputParameters]
            playerItem.audioMix = audioMix
            // Create and publish video track.
            if let track = TVILocalVideoTrack(capturer: videoPlayerSource!,
                enabled: true,
                constraints: nil,
                name: kPlayerTrackName) {
                playerVideoTrack = track
                self.room!.localParticipant!.publishVideoTrack(track)
            }

        } else {
            // Abort, retry, fail?
        }
    }

    func stopVideoPlayer() {
        videoPlayer?.pause()
        videoPlayer = nil

        // Remove player UI
        videoPlayerView?.removeFromSuperview()
        videoPlayerView = nil
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
        self.showRoomUI(inRoom: false)
        self.localVideoTrack = nil;
        self.localAudioTrack = nil;
        self.playerVideoTrack = nil;
    }

    func room(_ room: TVIRoom, didFailToConnectWithError error: Error) {
        logMessage(messageText: "Failed to connect to Room:\n\(error.localizedDescription)")

        self.room = nil

        self.showRoomUI(inRoom: false)
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
