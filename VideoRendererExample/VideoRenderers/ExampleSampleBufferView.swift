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

    var outputFormatDescription: CMFormatDescription?

    var isRendering = UIApplication.shared.applicationState != .background

    let useDisplayLink = true
    var displayLink : CADisplayLink?
    var displayFrameQueue : CMSimpleQueue?

    var optionalPixelFormats: [NSNumber] = [NSNumber.init(value: TVIPixelFormat.formatYUV420BiPlanarFullRange.rawValue),
                                            NSNumber.init(value: TVIPixelFormat.formatYUV420BiPlanarVideoRange.rawValue),
                                            NSNumber.init(value: TVIPixelFormat.format32BGRA.rawValue)]

    required init?(coder aDecoder: NSCoder) {
        // This example does not support storyboards.
        return nil
    }

    override init(frame: CGRect) {
        videoDimensions = CMVideoDimensions(width: 0, height: 0)

        if (useDisplayLink) {
            CMSimpleQueueCreate(kCFAllocatorDefault, 64, &displayFrameQueue)
        }

        super.init(frame: frame)

        let center = NotificationCenter.default

        center.addObserver(self, selector: #selector(ExampleSampleBufferRenderer.willEnterForeground),
                           name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
        center.addObserver(self, selector: #selector(ExampleSampleBufferRenderer.didEnterBackground),
                           name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
        center.addObserver(self, selector: #selector(ExampleSampleBufferRenderer.willResignActive),
                           name: NSNotification.Name.UIApplicationWillResignActive, object: nil)

        if (useDisplayLink) {
            startTimer()
        }
//        [_sampleView addObserver:self forKeyPath:@"layer.status" options:NSKeyValueObservingOptionNew context:NULL];
    }

    deinit {
        outputFormatDescription = nil

        NotificationCenter.default.removeObserver(self)

        while let dequeuedFrame = CMSimpleQueueDequeue(displayFrameQueue!) {
            let unmanagedFrame: Unmanaged<TVIVideoFrame> = Unmanaged.fromOpaque(dequeuedFrame)
            _ = unmanagedFrame.takeRetainedValue()
        }

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
        self.displayLink?.isPaused = isRendering
    }

    func didEnterBackground(_: NSNotification) {
        isRendering = false
        self.displayLink?.isPaused = isRendering
        self.displayLayer.flushAndRemoveImage()
    }

    func willResignActive(_: NSNotification) {
        // TODO: - CE Do we care about this?
    }

    func startTimer() {
        invalidateTimer()

        let displayLink = CADisplayLink(target: self, selector: #selector(ExampleSampleBufferRenderer.timerFired))
        displayLink.preferredFramesPerSecond = 60
        displayLink.add(to: RunLoop.main, forMode: RunLoopMode.commonModes)
        displayLink.isPaused = !isRendering
        self.displayLink = displayLink
    }

    func invalidateTimer() {
        if let timer = displayLink {
            timer.invalidate()
            displayLink = nil
        }
    }

    func timerFired(timer: CADisplayLink) {
        // Drain the queue. We will only display the most recent frame at the back of the queue.
        var frameToDisplay: TVIVideoFrame?
        while let dequeuedFrame = CMSimpleQueueDequeue(displayFrameQueue!) {
            let unmanagedFrame: Unmanaged<TVIVideoFrame> = Unmanaged.fromOpaque(dequeuedFrame)
            frameToDisplay = unmanagedFrame.takeRetainedValue()
        }
        if let frameToDisplay = frameToDisplay {
            enqueueFrame(frame: frameToDisplay)
        }
    }
}

extension ExampleSampleBufferRenderer {

    func renderFrame(_ frame: TVIVideoFrame) {
        let pixelFormat = CVPixelBufferGetPixelFormatType(frame.imageBuffer)

        if (self.isRendering == false ) {
            return
        } else if (pixelFormat == TVIPixelFormat.formatYUV420PlanarFullRange.rawValue ||
                   pixelFormat == TVIPixelFormat.formatYUV420PlanarVideoRange.rawValue) {
            print("Unsupported I420 pixel format!");
            return
        }

        if (useDisplayLink) {
            if let queue = displayFrameQueue {
                let unmanagedFrame = Unmanaged.passRetained(frame)
                let status = CMSimpleQueueEnqueue(queue, unmanagedFrame.toOpaque())
                if (status != kCVReturnSuccess) {
                    print("Couldn't enqueue status: \(status).")
                }
            }
        } else {
            DispatchQueue.main.async {
                self.enqueueFrame(frame: frame)
            }
        }
    }

    func updateVideoSize(_ videoSize: CMVideoDimensions, orientation: TVIVideoOrientation) {
        // Update size property to help with View layout.
        DispatchQueue.main.async {
            self.videoDimensions = videoSize
        }
    }

    // TODO: Return OSStatus?
    func enqueueFrame(frame: TVIVideoFrame) {
        let imageBuffer = frame.imageBuffer

        if (self.displayLayer.error != nil) {
            return
        } else if (self.displayLayer.isReadyForMoreMediaData == false) {
            print("AVSampleBufferDisplayLayer is not ready for more frames.");
            return
        }

        // Ensure that we have a valid CMVideoFormatDescription.
        if (self.outputFormatDescription == nil ||
            CMVideoFormatDescriptionMatchesImageBuffer(self.outputFormatDescription!, imageBuffer) == false) {
            CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, imageBuffer, &self.outputFormatDescription)

            if let format = self.outputFormatDescription {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format)
                let pixelFormat = CVPixelBufferGetPixelFormatType(frame.imageBuffer)
                let utf16 = [
                    UInt16((pixelFormat >> 24) & 0xFF),
                    UInt16((pixelFormat >> 16) & 0xFF),
                    UInt16((pixelFormat >> 8) & 0xFF),
                    UInt16((pixelFormat & 0xFF)) ]
                let pixelFormatString = String(utf16CodeUnits: utf16, count: 4)
                print("Detected format change: \(dimensions.width) x \(dimensions.height) - \(pixelFormatString)")
            }
        }

        // Represent TVIVideoFrame timestamps with microsecond timescale.
        // Our uncompressed buffers do not need to be decoded.
        var sampleTiming = CMSampleTimingInfo.init(duration: kCMTimeInvalid,
                                                   presentationTimeStamp: CMTime.init(value: frame.timestamp,
                                                                                      timescale: CMTimeScale(1000000)),
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
        } else if let sampleBuffer = sampleBuffer {

            // Force immediate display of the Buffer.
            let sampleAttachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true) as NSArray!
            let firstAttachment  = sampleAttachments?.firstObject as! NSMutableDictionary?
            firstAttachment?[kCMSampleAttachmentKey_DisplayImmediately] = true

            self.displayLayer.enqueue(sampleBuffer)
        }
    }
}
