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

        // TODO: Add KVO observer?
        let player = AVPlayer(url: ViewController.kRemoteContentURL)
        videoPlayer = player

        let playerView = ExampleAVPlayerView(frame: CGRect.zero, player: player)
        videoPlayerView = playerView

        // We will rely on frame based layout to size and position `self.videoPlayerView`.
        self.view.insertSubview(playerView, at: 0)
        self.view.setNeedsLayout()
    }

    func stopVideoPlayer() {
        videoPlayer?.pause()
        videoPlayer = nil

        // Remove player UI
        videoPlayerView?.removeFromSuperview()
        videoPlayerView = nil
    }
}
