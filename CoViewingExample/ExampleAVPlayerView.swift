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
        self.contentMode = .scaleAspectFit
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        // It won't be possible to hookup an AVPlayer yet.
        self.contentMode = .scaleAspectFit
    }

    var playerLayer : AVPlayerLayer {
        get {
            return self.layer as! AVPlayerLayer
        }
    }

    override var contentMode: UIView.ContentMode {
        set {
            switch newValue {
            case .scaleAspectFill:
                playerLayer.videoGravity = .resizeAspectFill
            case .scaleAspectFit:
                playerLayer.videoGravity = .resizeAspect
            case .scaleToFill:
                playerLayer.videoGravity = .resize
            default:
                playerLayer.videoGravity = .resizeAspect
            }
            super.contentMode = newValue
        }
        
        get {
            return super.contentMode
        }
    }

    override class var layerClass : AnyClass {
        return AVPlayerLayer.self
    }
}
