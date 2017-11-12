//
//  ExampleSampleBufferView.swift
//  VideoRendererExample
//
//  Copyright © 2017 Twilio Inc. All rights reserved.
//

import AVFoundation
import Foundation
import UIKit
import TwilioVideo

class ExampleSampleBufferRenderer : UIView {

    required init?(coder aDecoder: NSCoder) {
        // TODO: Register for application lifecycle observers.
        videoDimensions = CMVideoDimensions(width: 0, height: 0)
        super.init(coder: aDecoder)
    }

    override init(frame: CGRect) {
        // TODO: Register for application lifecycle observers.
        videoDimensions = CMVideoDimensions(width: 0, height: 0)
        super.init(frame: frame)
    }

    deinit {
        // TODO: Unregister for application lifecycle observers.
    }

    var optionalPixelFormats: [NSNumber] = [NSNumber.init(value: TVIPixelFormat.formatYUV420BiPlanarFullRange.rawValue),
                                            NSNumber.init(value: TVIPixelFormat.formatYUV420BiPlanarVideoRange.rawValue),
                                            NSNumber.init(value: TVIPixelFormat.format32BGRA.rawValue)]

    var displayLayer: AVSampleBufferDisplayLayer {
        get {
            return self.layer as! AVSampleBufferDisplayLayer
        }
    }

    public var videoDimensions: CMVideoDimensions

    override class var layerClass: Swift.AnyClass {
        get {
            return AVSampleBufferDisplayLayer.self
        }
    }

    override var contentMode: UIViewContentMode {
        get {
            return super.contentMode
        }
        set {
            switch newValue {
            case .scaleAspectFill:
                displayLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
            case .scaleAspectFit:
                displayLayer.videoGravity = AVLayerVideoGravityResizeAspect
            case .scaleToFill:
                displayLayer.videoGravity = AVLayerVideoGravityResize
            default:
                displayLayer.videoGravity = AVLayerVideoGravityResize
            }

            super.contentMode = contentMode
        }
    }

    var outputFormatDescription: CMFormatDescription?
}

extension ExampleSampleBufferRenderer : TVIVideoRenderer {

    func renderFrame(_ frame: TVIVideoFrame) {
        if (displayLayer.error != nil) {
            return
        } else if (displayLayer.isReadyForMoreMediaData == false) {
            return
        } else if (CVPixelBufferGetPixelFormatType(frame.imageBuffer) == TVIPixelFormat.formatYUV420PlanarFullRange.rawValue ||
                   CVPixelBufferGetPixelFormatType(frame.imageBuffer) == TVIPixelFormat.formatYUV420PlanarVideoRange.rawValue) {
            print("Unsupperted pixel format!");
            return
        }

        let imageBuffer = frame.imageBuffer

        DispatchQueue.main.async {
            // Ensure that we have a valid CMVideoFormatDescription.
            if (self.outputFormatDescription == nil ||
                CMVideoFormatDescriptionMatchesImageBuffer(self.outputFormatDescription!, imageBuffer) == false) {
                CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, imageBuffer, &self.outputFormatDescription)
            }

            // Create a CMSampleBuffer
            var sampleBuffer: CMSampleBuffer?
            // TODO: What is an appropriate timescale?
            var sampleTiming = CMSampleTimingInfo.init(duration: kCMTimeInvalid,
                                                       presentationTimeStamp: CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 1000),
                                                       decodeTimeStamp: kCMTimeInvalid)

            let status = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
                                                                  imageBuffer,
                                                                  self.outputFormatDescription!,
                                                                  &sampleTiming,
                                                                  &sampleBuffer)

            // Enqueue the frame for display via AVSampleBufferDisplayLayer.
            if (status != kCVReturnSuccess) {
                return
            } else if let sampleBuffer = sampleBuffer {
                self.displayLayer.enqueue(sampleBuffer)
            }
        }
    }

    func updateVideoSize(_ videoSize: CMVideoDimensions, orientation: TVIVideoOrientation) {
        // Update size property to help with View layout.
        DispatchQueue.main.async {
            self.videoDimensions = videoSize
        }
    }
}
