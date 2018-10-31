//
//  ViewController.swift
//  CoViewingExample
//
//  Copyright © 2018 Twilio Inc. All rights reserved.
//

import AVFoundation
import UIKit

class ViewController: UIViewController {

    var videoPlayer: AVPlayer? = nil
    var videoPlayerView: ExampleAVPlayerView? = nil
    var videoPlayerSource: ExampleAVPlayerSource? = nil

    static let kRemoteContentURL = URL(string: "https://s3-us-west-1.amazonaws.com/avplayervideo/What+Is+Cloud+Communications.mov")!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if videoPlayer == nil {
            startVideoPlayer()
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        if let playerView = videoPlayerView {
            playerView.frame = CGRect(origin: CGPoint.zero, size: self.view.bounds.size)
        }
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
//            inputParameters.audioTapProcessor = self
            audioMix.inputParameters = [inputParameters]
            playerItem.audioMix = audioMix
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
