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
    weak var iconImageView: UIImageView?
    weak var videoPlaceholderImageView: UIImageView?

    static let kImagePadding = CGFloat(2)

    override func prepareForReuse() {
        // Stop rendering the Track.
        if let view = videoView {
            videoTrack?.removeRenderer(view)
            videoTrack = nil
        }

        iconImageView?.removeFromSuperview()
        iconImageView = nil

        videoPlaceholderImageView?.removeFromSuperview()
        videoPlaceholderImageView = nil
    }

    override var isHighlighted: Bool {
        set {
            super.isHighlighted = newValue
            if newValue {
                self.videoView?.alpha = 0.94
                self.backgroundColor = .white
            } else {
                self.videoView?.alpha = 1.0
                self.backgroundColor = nil
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
                self.backgroundColor = .white
            } else {
                self.videoView?.alpha = 1.0
                self.backgroundColor = nil
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

        if let imageView = videoPlaceholderImageView {
            imageView.frame = self.contentView.bounds
        }
    }

    func setParticipant(participant: Participant, localVideoTrack: LocalVideoTrack?, localAudioTrack: LocalAudioTrack?) {
        var videoView = self.videoView
        if videoView == nil {
            videoView = VideoView(frame: .zero)
            videoView?.contentMode = .scaleAspectFill
            self.contentView.addSubview(videoView!)
            self.videoView = videoView
        }

        let mirror: Bool
        if let videoTrack = localVideoTrack {
            self.videoTrack = videoTrack
            mirror = true
        } else {
            mirror = false
            let trackPublication = participant.videoTracks.first
            if let videoTrack = trackPublication?.videoTrack {
                self.videoTrack = videoTrack
            }
        }

        if let audioTrack = localAudioTrack,
            !audioTrack.isEnabled {
            updateMute(enabled: false)
        } else {
            if let trackPublication = participant.audioTracks.first {
                updateMute(enabled: trackPublication.isTrackEnabled)
            }
        }

        self.videoTrack?.addRenderer(videoView!)
        videoView?.shouldMirror = mirror
    }

    func updateMute(enabled: Bool) {
        if #available(iOS 13.0, *) {
            if !enabled {
                let imageView = UIImageView(image: UIImage(systemName: "mic.slash.fill"))
                imageView.tintColor = UIColor(red: 226.0/255.0,
                                              green: 29.0/255.0,
                                              blue: 37.0/255.0,
                                              alpha: 1.0)
                self.contentView.addSubview(imageView)
                self.iconImageView = imageView
                self.setNeedsLayout()
            } else {
                self.iconImageView?.removeFromSuperview()
                self.iconImageView = nil
            }
        }
    }

    func updateVideoSwitchedOff(switchedOff: Bool) {
        if #available(iOS 13.0, *) {
            if switchedOff {
                let imageView = UIImageView(image: UIImage(systemName: "video.slash.fill"))
                imageView.tintColor = UIColor(red: 226.0/255.0,
                                              green: 29.0/255.0,
                                              blue: 37.0/255.0,
                                              alpha: 1.0)
                imageView.contentMode = .center
                self.contentView.addSubview(imageView)
                self.videoPlaceholderImageView = imageView
                self.videoPlaceholderImageView?.backgroundColor = UIColor(white: 0, alpha: 0.8)
                self.setNeedsLayout()
            } else {
                self.videoPlaceholderImageView?.removeFromSuperview()
                self.videoPlaceholderImageView = nil
            }
        }
    }
}

class VideoCollectionView : UICollectionView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let hitView = super.hitTest(point, with: event) {
            return hitView as? VideoCollectionViewCell
        } else {
            return nil
        }
    }
}
