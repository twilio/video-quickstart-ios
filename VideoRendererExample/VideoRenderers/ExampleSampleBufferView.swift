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

class ExampleSampleBufferRenderer : UIView, TVIVideoRenderer {

    public var videoDimensions: CMVideoDimensions

    var isRendering = UIApplication.shared.applicationState != .background
    var outputFormatDescription: CMFormatDescription?
    // Allows us to enqueue to the layer from a background thread without accessing self.layer directly.
    var cachedDisplayLayer : AVSampleBufferDisplayLayer?

    /*
     * Register pixel formats that are known to work with AVSampleBufferDisplayLayer.
     * At a minimum, the CVPixelBuffers are expected to be backed by an IOSurface so we will not support
     * every possible input from CoreVideo.
     */
    var optionalPixelFormats: [NSNumber] = [NSNumber.init(value: TVIPixelFormat.formatYUV420BiPlanarFullRange.rawValue),
                                            NSNumber.init(value: TVIPixelFormat.formatYUV420BiPlanarVideoRange.rawValue),
                                            NSNumber.init(value: TVIPixelFormat.format32BGRA.rawValue),
                                            NSNumber.init(value: TVIPixelFormat.format32ARGB.rawValue)]

    required init?(coder aDecoder: NSCoder) {
        // This example does not support storyboards.
        assert(false, "Unsupported.")
        return nil
    }

    override init(frame: CGRect) {
        videoDimensions = CMVideoDimensions(width: 0, height: 0)

        super.init(frame: frame)

        cachedDisplayLayer = super.layer as? AVSampleBufferDisplayLayer
        let center = NotificationCenter.default

        center.addObserver(self, selector: #selector(ExampleSampleBufferRenderer.willEnterForeground),
                           name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
        center.addObserver(self, selector: #selector(ExampleSampleBufferRenderer.didEnterBackground),
                           name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
        center.addObserver(self, selector: #selector(ExampleSampleBufferRenderer.willResignActive),
                           name: NSNotification.Name.UIApplicationWillResignActive, object: nil)

//        [_sampleView addObserver:self forKeyPath:@"layer.status" options:NSKeyValueObservingOptionNew context:NULL];
    }

    deinit {
        outputFormatDescription = nil

        NotificationCenter.default.removeObserver(self)

//        [self.sampleView removeObserver:self forKeyPath:@"layer.status"];
    }

    var displayLayer: AVSampleBufferDisplayLayer {
        get {
            return self.layer as! AVSampleBufferDisplayLayer
        }
    }

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
            // Map UIViewContentMode to AVLayerVideoGravity. The layer supports a subset of possible content modes.
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
            setNeedsLayout()

            super.contentMode = newValue
        }
    }
}

extension ExampleSampleBufferRenderer {
    func willEnterForeground(_: NSNotification) {

        if (displayLayer.status == AVQueuedSampleBufferRenderingStatus.failed) {
            // TODO: Restore failed sample buffer view. AVErrorOperationInterrupted.
        }

        isRendering = true
    }

    func didEnterBackground(_: NSNotification) {
        isRendering = false
        displayLayer.flushAndRemoveImage()
    }

    func willResignActive(_: NSNotification) {
        // TODO: - Should we stop rendering when resigning active?
        // AVSampleBufferDisplayLayer seems capable of handling this case.
    }
}

extension ExampleSampleBufferRenderer {

    func renderFrame(_ frame: TVIVideoFrame) {
        let pixelFormat = CVPixelBufferGetPixelFormatType(frame.imageBuffer)

        // Unfortunately I420 is not directly supported by AVSampleBufferDisplayLayer.
        // This example renderer does not attempt to support I420, but please see ExampleVideoRecorder for an example of
        // performing an I420 to NV12 format conversion. Doing so efficiently for a renderer would require maintaining
        // a CVPixelBufferPool of NV12 frames which are ready to be displayed.
        if (self.isRendering == false ) {
            return
        } else if (pixelFormat == TVIPixelFormat.formatYUV420PlanarFullRange.rawValue ||
                   pixelFormat == TVIPixelFormat.formatYUV420PlanarVideoRange.rawValue) {
            print("Unsupported I420 pixel format!");
            return
        }

        // Enqueuing a frame to AVSampleDisplayLayer may cause UIKit related accesses if the resolution has changed.
        // When a format change occurs ensure that we synchronize with the main queue to deliver the first frame.
        if (detectFormatChange(imageBuffer: frame.imageBuffer) && !Thread.isMainThread) {
            DispatchQueue.main.sync {
                self.enqueueFrame(frame: frame)
            }
        } else {
            enqueueFrame(frame: frame)
        }
    }

    func updateVideoSize(_ videoSize: CMVideoDimensions, orientation: TVIVideoOrientation) {
        // Update size property to help with View layout.
        DispatchQueue.main.async {
            self.videoDimensions = videoSize
        }
    }

    func detectFormatChange(imageBuffer: CVPixelBuffer) -> Bool {
        var didChange = false
        if (self.outputFormatDescription == nil ||
            CMVideoFormatDescriptionMatchesImageBuffer(self.outputFormatDescription!, imageBuffer) == false) {
            let status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, imageBuffer, &self.outputFormatDescription)

            if let format = self.outputFormatDescription {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format)
                let pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer)
                let utf16 = [
                    UInt16((pixelFormat >> 24) & 0xFF),
                    UInt16((pixelFormat >> 16) & 0xFF),
                    UInt16((pixelFormat >> 8) & 0xFF),
                    UInt16((pixelFormat & 0xFF)) ]
                let pixelFormatString = String(utf16CodeUnits: utf16, count: 4)
                print("Detected format change: \(dimensions.width) x \(dimensions.height) - \(pixelFormatString)")
                didChange = true
            } else {
                print("Failed to create output format description with status: \(status)")
            }
        }
        return didChange
    }

    // TODO: Return OSStatus?
    func enqueueFrame(frame: TVIVideoFrame) {
        let imageBuffer = frame.imageBuffer

        if (self.cachedDisplayLayer?.error != nil) {
            return
        } else if (self.cachedDisplayLayer?.isReadyForMoreMediaData == false) {
            print("AVSampleBufferDisplayLayer is not ready for more frames.");
            return
        }

        // Use the frame's timestamp as the presentation timestamp. We will display immediately.
        // Our uncompressed buffers do not need to be decoded.
        var sampleTiming = CMSampleTimingInfo.init(duration: kCMTimeInvalid,
                                                   presentationTimeStamp: frame.timestamp,
                                                   decodeTimeStamp: kCMTimeInvalid)

        // Create a CMSampleBuffer
        var sampleBuffer: CMSampleBuffer?

        let status = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
                                                              imageBuffer,
                                                              self.outputFormatDescription!,
                                                              &sampleTiming,
                                                              &sampleBuffer)

        // Enqueue the frame for display via AVSampleBufferDisplayLayer.
        if (status != kCVReturnSuccess) {
            print("Couldn't create a SampleBuffer. Status=\(status)")
            return
        } else if let sampleBuffer = sampleBuffer,
                  let displayLayer = cachedDisplayLayer,
                  let sampleAttachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true) as NSArray? {
            // Force immediate display of the buffer, since our renderer receives them just in time.
            let firstAttachment  = sampleAttachments.firstObject as! NSMutableDictionary?
            firstAttachment?[kCMSampleAttachmentKey_DisplayImmediately] = true

            displayLayer.enqueue(sampleBuffer)
        }
    }
}
