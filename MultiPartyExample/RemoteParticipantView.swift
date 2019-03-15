//
//  RemoteParticipantView.swift
//  MultiPartyExample
//
//  Copyright © 2019 Twilio, Inc. All rights reserved.
//

import UIKit
import TwilioVideo

@IBDesignable
class RemoteParticipantView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var containerView: UIView!
    @IBOutlet weak var videoView: TVIVideoView!
    @IBOutlet weak var noVideoImage: UIImageView!
    @IBOutlet weak var audioIndicator: UIImageView!
    @IBOutlet weak var identityLabel : UILabel!

    var identity: String? {
        willSet {
            identityLabel.text = newValue
        }
    }

    var isDominantSpeaker: Bool = false {
        willSet {
            if newValue == true {
                contentView.backgroundColor = UIColor.red
            } else {
                contentView.backgroundColor = UIColor.white
            }
        }
    }

    var hasAudio: Bool = false {
        willSet {
            if newValue == true {
                audioIndicator.image = UIImage.init(imageLiteralResourceName: "audio-unmuted-white")
            } else {
                audioIndicator.image = UIImage.init(imageLiteralResourceName: "audio-muted-white")
            }
        }
    }

    var hasVideo: Bool = false {
        willSet {
            videoView.isHidden = !newValue
            videoView.alpha = newValue ? 1.0 : 0.0
            noVideoImage.isHidden = newValue
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
        Bundle.main.loadNibNamed("RemoteParticipantView", owner: self, options: nil)
        addSubview(contentView)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleHeight, .flexibleWidth]

        identityLabel.layer.backgroundColor = UIColor.black.withAlphaComponent(0.5).cgColor

        audioIndicator.layer.cornerRadius = audioIndicator.bounds.size.width / 2.0;
        audioIndicator.layer.backgroundColor = UIColor.black.withAlphaComponent(0.5).cgColor
        audioIndicator.image = UIImage.init(imageLiteralResourceName: "audio-muted-white")

        noVideoImage.isHidden = true

        // `TVIVideoView` supports scaleToFill, scaleAspectFill and scaleAspectFit.
        // scaleAspectFit is the default mode when you create `TVIVideoView` programmatically.
        videoView.contentMode = .scaleAspectFit
        videoView.isHidden = true
        videoView.alpha = 0.0
        videoView.delegate = self

        // Double tap to change the content mode.
        let recognizerDoubleTap = UITapGestureRecognizer(target: self, action: #selector(changeRemoteVideoAspect))
        recognizerDoubleTap.numberOfTapsRequired = 2
        videoView.addGestureRecognizer(recognizerDoubleTap)
    }

    @objc private func changeRemoteVideoAspect(gestureRecognizer: UIGestureRecognizer) {
        guard let remoteView = gestureRecognizer.view else {
            print("Couldn't find a view attached to the tap recognizer. \(gestureRecognizer)")
            return;
        }

        if (remoteView.contentMode == .scaleAspectFit) {
            remoteView.contentMode = .scaleAspectFill
        } else {
            remoteView.contentMode = .scaleAspectFit
        }
    }
}

// MARK: TVIVideoViewDelegate
extension RemoteParticipantView : TVIVideoViewDelegate {
    func videoView(_ view: TVIVideoView, videoDimensionsDidChange dimensions: CMVideoDimensions) {
        self.contentView.setNeedsLayout()
    }
}
