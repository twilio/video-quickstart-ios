//
//  ParticipantView.swift
//  MultiPartyExample
//
//  Copyright © 2020 Twilio, Inc. All rights reserved.
//

import UIKit
import TwilioVideo

@IBDesignable
class ParticipantView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var containerView: UIView!
    @IBOutlet weak var videoView: VideoView!
    @IBOutlet weak var noVideoImage: UIImageView!
    @IBOutlet weak var audioIndicator: UIImageView!
    @IBOutlet weak var networkQualityLevelIndicator: UIImageView!
    @IBOutlet weak var identityContainerView: UIView!
    @IBOutlet weak var identityLabel : UILabel!

    var recognizerDoubleTap: UITapGestureRecognizer?

    var identity: String? {
        willSet {
            guard let newIdentity = newValue, !newIdentity.isEmpty else {
                identityContainerView.isHidden = true
                identityLabel.isHidden = true
                return
            }

            identityContainerView.isHidden = false
            identityLabel.isHidden = false
            identityLabel.text = newValue
        }
    }

    var isDominantSpeaker: Bool = false {
        willSet {
            if newValue == true {
                contentView.backgroundColor = UIColor.Twilio.Status.Orange
            } else {
                contentView.backgroundColor = UIColor.black
            }
        }
    }

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

    var networkQualityLevel: NetworkQualityLevel = .unknown {
        willSet {
            guard let networkQualityLevelImage = networkQualityIndicatorImage(forLevel: newValue) else {
                networkQualityLevelIndicator.isHidden = true
                return
            }

            networkQualityLevelIndicator.isHidden = false
            networkQualityLevelIndicator.image = networkQualityLevelImage
            self.setNeedsLayout()
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
        Bundle.main.loadNibNamed("ParticipantView", owner: self, options: nil)
        addSubview(contentView)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleHeight, .flexibleWidth]

        identityContainerView.layer.backgroundColor = UIColor.black.withAlphaComponent(0.5).cgColor
        identityContainerView.isHidden = true
        identityLabel.isHidden = true

        audioIndicator.layer.cornerRadius = audioIndicator.bounds.size.width / 2.0;
        audioIndicator.layer.backgroundColor = UIColor.black.withAlphaComponent(0.75).cgColor

        noVideoImage.isHidden = false
        networkQualityLevelIndicator.isHidden = true

        // `VideoView` supports scaleToFill, scaleAspectFill and scaleAspectFit.
        // scaleAspectFit is the default mode when you create `VideoView` programmatically.
        videoView.contentMode = .scaleAspectFit
        videoView.isHidden = true
        videoView.alpha = 0.0
        videoView.delegate = self

        // Double tap to change the content mode.
        recognizerDoubleTap = UITapGestureRecognizer(target: self, action: #selector(changeVideoAspect))
        if let recognizerDoubleTap = recognizerDoubleTap {
            recognizerDoubleTap.numberOfTapsRequired = 2
            videoView.addGestureRecognizer(recognizerDoubleTap)
        }
    }

    @objc private func changeVideoAspect(gestureRecognizer: UIGestureRecognizer) {
        guard let view = gestureRecognizer.view else {
            print("Couldn't find a view attached to the tap recognizer. \(gestureRecognizer)")
            return;
        }

        if (view.contentMode == .scaleAspectFit) {
            view.contentMode = .scaleAspectFill
        } else {
            view.contentMode = .scaleAspectFit
        }
    }

    private func networkQualityIndicatorImage(forLevel networkQualityLevel: NetworkQualityLevel) -> UIImage? {
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

        return UIImage(named: imageName)
    }
}

// MARK:- VideoViewDelegate
extension ParticipantView : VideoViewDelegate {
    func videoViewDimensionsDidChange(view: VideoView, dimensions: CMVideoDimensions) {
        self.contentView.setNeedsLayout()
    }
}
