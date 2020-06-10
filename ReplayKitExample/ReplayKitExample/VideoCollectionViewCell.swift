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

    override func prepareForReuse() {
        // Stop rendering the Track.
        if let view = videoView {
            videoTrack?.removeRenderer(view)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        videoView?.frame = self.bounds
    }

    func setParticipant(participant: Participant, localVideoTrack: LocalVideoTrack?) {
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

        self.videoTrack?.addRenderer(videoView!)
    }
}
