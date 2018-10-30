//
//  ExampleAVPlayerView.swift
//  CoViewingExample
//
//  Copyright © 2018 Twilio Inc. All rights reserved.
//

import AVFoundation
import UIKit

class ExampleAVPlayerView: UIView {

    init(frame: CGRect, player: AVPlayer) {
        super.init(frame: frame)
        self.playerLayer.player = player
        self.playerLayer.videoGravity = AVLayerVideoGravity.resizeAspect
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        // It won't be possible to hookup an AVPlayer yet.
        self.playerLayer.videoGravity = AVLayerVideoGravity.resizeAspect
    }

    var playerLayer : AVPlayerLayer {
        get {
            return self.layer as! AVPlayerLayer
        }
    }

    override class var layerClass : AnyClass {
        return AVPlayerLayer.self
    }

}
