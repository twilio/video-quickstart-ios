//
//  VideoCollectionViewCell.swift
//  ReplayKitExample
//
//  Created by Chris Eagleston on 6/9/20.
//  Copyright © 2020 Twilio. All rights reserved.
//

import UIKit
import TwilioVideo

class VideoCollectionViewCell : UICollectionViewCell {
    weak var videoView: VideoView?
    var videoTrack: VideoTrack?
    var participant: Participant?
    weak var iconImageView: UIImageView?

    static let kImagePadding = CGFloat(2)

    override func prepareForReuse() {
        // Stop rendering the Track.
        if let view = videoView {
            videoTrack?.removeRenderer(view)
        }

        iconImageView?.removeFromSuperview()
        iconImageView = nil
    }

    override var isHighlighted: Bool {
        set {
            super.isHighlighted = newValue
            if newValue {
                self.videoView?.alpha = 0.94
            } else {
                self.videoView?.alpha = 1.0
            }
        }

        get {
            return super.isHighlighted
        }
    }

    override var isSelected: Bool {
        set {
            super.isSelected = newValue
            if newValue {
                self.videoView?.alpha = 0.94
            } else {
                self.videoView?.alpha = 1.0
            }
        }

        get {
            return super.isSelected
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        videoView?.frame = self.bounds

        if let imageView = iconImageView {
            let imageSize = imageView.intrinsicContentSize
            imageView.frame = CGRect(origin: CGPoint(x: VideoCollectionViewCell.kImagePadding, y: self.bounds.size.height - imageSize.height - VideoCollectionViewCell.kImagePadding),
                                     size: imageSize)
        }
    }

    func setParticipant(participant: Participant, localVideoTrack: LocalVideoTrack?, localAudioTrack: LocalAudioTrack?) {
        var videoView = self.videoView
        if videoView == nil {
            videoView = VideoView(frame: .zero)
            videoView?.contentMode = .scaleAspectFill
            videoView?.shouldMirror = true
            self.contentView.addSubview(videoView!)
            self.videoView = videoView
        }

        if let videoTrack = localVideoTrack {
            self.videoTrack = videoTrack
        } else {
            for trackPublication in participant.videoTracks {
                if let videoTrack = trackPublication.videoTrack {
                    self.videoTrack = videoTrack
                }
            }
        }

        if let audioTrack = localAudioTrack,
            !audioTrack.isEnabled {
            if #available(iOS 13.0, *) {
                let imageView = UIImageView(image: UIImage(systemName: "mic.slash.fill"))
                imageView.tintColor = UIColor(red: 226.0/255.0,
                                              green: 29.0/255.0,
                                              blue: 37.0/255.0,
                                              alpha: 1.0)
                self.contentView.addSubview(imageView)
                self.iconImageView = imageView
            }
        }

        self.videoTrack?.addRenderer(videoView!)
    }
}
