//
//  LocalParticipantView.swift
//  MultiPartyExample
//
//  Created by Ryan Payne on 4/17/19.
//  Copyright © 2019 Twilio, Inc. All rights reserved.
//

import UIKit
import TwilioVideo

@IBDesignable
class LocalParticipantView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var videoView: TVIVideoView!
    @IBOutlet weak var noVideoImage: UIImageView!
    @IBOutlet weak var audioIndicator: UIImageView!
    @IBOutlet weak var networkQualityLevelIndicator: UIImageView!

    var recognizerDoubleTap: UITapGestureRecognizer?

    var hasAudio: Bool = false {
        willSet {
            audioIndicator.isHidden = newValue
        }
    }

    var hasVideo: Bool = false {
        willSet {
            videoView.isHidden = !newValue
            videoView.alpha = newValue ? 1.0 : 0.0
            noVideoImage.isHidden = newValue
        }
    }

    var networkQualityLevel: TVINetworkQualityLevel = .unknown {
        willSet {
            guard let networkQualityLevelImage = networkQualityIndicatorImage(forLevel: newValue) else {
                networkQualityLevelIndicator.isHidden = true
                return
            }

            networkQualityLevelIndicator.isHidden = false
            networkQualityLevelIndicator.image = networkQualityLevelImage
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }

    private func setup() {
        Bundle.main.loadNibNamed("LocalParticipantView", owner: self, options: nil)
        addSubview(contentView)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleHeight, .flexibleWidth]

        audioIndicator.layer.cornerRadius = audioIndicator.bounds.size.width / 2.0;
        audioIndicator.layer.backgroundColor = UIColor.black.withAlphaComponent(0.75).cgColor

        noVideoImage.isHidden = false
        networkQualityLevelIndicator.isHidden = true

        // `TVIVideoView` supports scaleToFill, scaleAspectFill and scaleAspectFit.
        // scaleAspectFit is the default mode when you create `TVIVideoView` programmatically.
        videoView.contentMode = .scaleAspectFit
        videoView.isHidden = true
        videoView.alpha = 0.0
        videoView.delegate = self

        // Double tap to change the content mode.
        recognizerDoubleTap = UITapGestureRecognizer(target: self, action: #selector(changeLocalVideoAspect))
        if let recognizerDoubleTap = recognizerDoubleTap {
            recognizerDoubleTap.numberOfTapsRequired = 2
            videoView.addGestureRecognizer(recognizerDoubleTap)
        }
    }

    @objc private func changeLocalVideoAspect(gestureRecognizer: UIGestureRecognizer) {
        guard let localView = gestureRecognizer.view else {
            print("Couldn't find a view attached to the tap recognizer. \(gestureRecognizer)")
            return;
        }

        if (localView.contentMode == .scaleAspectFit) {
            localView.contentMode = .scaleAspectFill
        } else {
            localView.contentMode = .scaleAspectFit
        }

    }

    private func networkQualityIndicatorImage(forLevel networkQualityLevel: TVINetworkQualityLevel) -> UIImage? {
        var tempImageName: String?

        switch networkQualityLevel {
        case .zero:
            tempImageName = "network-quality-level-0"
        case .one:
            tempImageName = "network-quality-level-1"
        case .two:
            tempImageName = "network-quality-level-2"
        case .three:
            tempImageName = "network-quality-level-3"
        case .four:
            tempImageName = "network-quality-level-4"
        case .five:
            tempImageName = "network-quality-level-5"
        case .unknown:
            break
        }

        guard let imageName = tempImageName else {
            return nil
        }

        return UIImage.init(named: imageName)
    }
}

// MARK: TVIVideoViewDelegate
extension LocalParticipantView : TVIVideoViewDelegate {
    func videoView(_ view: TVIVideoView, videoDimensionsDidChange dimensions: CMVideoDimensions) {
        self.contentView.setNeedsLayout()
    }
}
