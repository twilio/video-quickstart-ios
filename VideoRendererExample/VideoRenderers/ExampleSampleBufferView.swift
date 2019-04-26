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

protocol ExampleSampleBufferRendererDelegate {
    func bufferViewVideoChanged(view: ExampleSampleBufferView,
                                dimensions: CMVideoDimensions,
                                orientation: TVIVideoOrientation)
}

class ExampleSampleBufferView : UIView, TVIVideoRenderer {

    public var videoDimensions: CMVideoDimensions
    public var videoOrientation: TVIVideoOrientation

    var isRendering = UIApplication.shared.applicationState != .background
    var outputFormatDescription: CMFormatDescription?
    // Allows the renderer to enqueue frames from a background thread without accessing self.layer directly.
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
        videoOrientation = TVIVideoOrientation.up

        super.init(frame: frame)

        cachedDisplayLayer = super.layer as? AVSampleBufferDisplayLayer
        let center = NotificationCenter.default

        center.addObserver(self, selector: #selector(ExampleSampleBufferView.willEnterForeground),
                           name: UIApplication.willEnterForegroundNotification, object: nil)
        center.addObserver(self, selector: #selector(ExampleSampleBufferView.didEnterBackground),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(ExampleSampleBufferView.willResignActive),
                           name: UIApplication.willResignActiveNotification, object: nil)

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

    override var contentMode: UIView.ContentMode {
        get {
            return super.contentMode
        }
        set {
            // Map UIViewContentMode to AVLayerVideoGravity. The layer supports a subset of possible content modes.
            switch newValue {
            case .scaleAspectFill:
                displayLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
            case .scaleAspectFit:
                displayLayer.videoGravity = AVLayerVideoGravity.resizeAspect
            case .scaleToFill:
                displayLayer.videoGravity = AVLayerVideoGravity.resize
            default:
                displayLayer.videoGravity = AVLayerVideoGravity.resize
            }
            setNeedsLayout()

            super.contentMode = newValue
        }
    }
}

extension ExampleSampleBufferView {
    @objc func willEnterForeground(_: NSNotification) {

        if (displayLayer.status == AVQueuedSampleBufferRenderingStatus.failed) {
            // TODO: Restore failed sample buffer view. AVErrorOperationInterrupted.
        }

        isRendering = true
    }

    @objc func didEnterBackground(_: NSNotification) {
        isRendering = false
        displayLayer.flushAndRemoveImage()
    }

    @objc func willResignActive(_: NSNotification) {
        // TODO: - Should we stop rendering when resigning active?
        // AVSampleBufferDisplayLayer seems capable of handling this case.
    }
}

extension ExampleSampleBufferView {

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
        DispatchQueue.main.async {
            // Update properties to help with View layout.
            let orientationChanged = orientation != self.videoOrientation
            let animate = orientationChanged && (videoSize.width == self.videoDimensions.width && videoSize.height == self.videoDimensions.height)
            self.videoDimensions = videoSize
            self.videoOrientation = orientation

            // TODO: Should we be doing this here, or delegating to a view controller?
            [UIView .animate(withDuration: animate ? 0.3 : 0, animations: {
                let size = videoSize
                let scaleFactor = size.height > size.width ? CGFloat(size.height) / CGFloat(size.width) : CGFloat(size.width) / CGFloat(size.height)
                switch (orientation) {
                case TVIVideoOrientation.up:
                    self.transform = CGAffineTransform.identity;
                    break
                case TVIVideoOrientation.left:
                    let scale = CGAffineTransform.init(scaleX: scaleFactor,
                                                       y: scaleFactor)
                    self.transform = CGAffineTransform(rotationAngle: CGFloat.pi / 2).concatenating(scale)
                    break
                case TVIVideoOrientation.down:
                    self.transform = CGAffineTransform(rotationAngle: CGFloat.pi)
                    break
                case TVIVideoOrientation.right:
                    let scale = CGAffineTransform.init(scaleX: scaleFactor,
                                                       y: scaleFactor)
                    self.transform = CGAffineTransform(rotationAngle: CGFloat.pi * 3 / 2).concatenating(scale)
                    break
                }
            })];
        }
    }

    func detectFormatChange(imageBuffer: CVPixelBuffer) -> Bool {
        var didChange = false
        if (self.outputFormatDescription == nil ||
            CMVideoFormatDescriptionMatchesImageBuffer(self.outputFormatDescription!, imageBuffer: imageBuffer) == false) {
            let status = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                                      imageBuffer: imageBuffer,
                                                                      formatDescriptionOut: &self.outputFormatDescription)

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
        var sampleTiming = CMSampleTimingInfo.init(duration: CMTime.invalid,
                                                   presentationTimeStamp: frame.timestamp,
                                                   decodeTimeStamp: CMTime.invalid)

        // Create a CMSampleBuffer
        var sampleBuffer: CMSampleBuffer?

        let status = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                              imageBuffer: imageBuffer,
                                                              formatDescription: self.outputFormatDescription!,
                                                              sampleTiming: &sampleTiming,
                                                              sampleBufferOut: &sampleBuffer)

        // Enqueue the frame for display via AVSampleBufferDisplayLayer.
        if (status != kCVReturnSuccess) {
            print("Couldn't create a SampleBuffer. Status=\(status)")
            return
        } else if let sampleBuffer = sampleBuffer,
                  let displayLayer = cachedDisplayLayer,
            let sampleAttachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) as NSArray? {
            // Force immediate display of the buffer, since our renderer receives them just in time.
            let firstAttachment  = sampleAttachments.firstObject as! NSMutableDictionary?
            firstAttachment?[kCMSampleAttachmentKey_DisplayImmediately] = true

            displayLayer.enqueue(sampleBuffer)
        }
    }
}
