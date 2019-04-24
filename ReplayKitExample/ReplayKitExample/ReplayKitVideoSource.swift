//
//  ReplayKitVideoSource.swift
//  ReplayKitExample
//
//  Copyright © 2018 Twilio. All rights reserved.
//

import Accelerate
import CoreMedia
import CoreVideo
import Dispatch
import ReplayKit
import TwilioVideo

class ReplayKitVideoSource: NSObject, TVIVideoSource {

    /*
     * Streaming video content at 30 fps or lower is ideal. ReplayKit may produce buffers at up to 120 Hz on an iPad Pro.
     * This logic attempts to drop frames based upon timestamps. However, the approach is not ideal because timestamps
     * from ReplayKit do not seem to represent exact vSyncs that are measurable 1/60 second or 1/120 second increments.
     * For now we've increased the constant so that we will not drop frames (except for repeats) on an iPhone.
     */
    static let kDesiredFrameRate = 120

    static let kFormatFrameRate = UIScreen.main.maximumFramesPerSecond

    var screencastUsage: Bool = false
    weak var sink: TVIVideoSink?
    var videoFormat: TVIVideoFormat?

    var lastTimestamp: CMTime?
    var videoQueue: DispatchQueue?
    var timerSource: DispatchSourceTimer?
    var lastTransmitTimestamp: CMTime?
    private var lastFrameStorage: TVIVideoFrame?

    /*
     * Enable retransmission of the last sent frame. This feature consumes some memory, CPU, and bandwidth but it ensures
     * that your most recent frame eventually reaches subscribers, and that the publisher has a reasonable bandwidth estimate
     * for the next time a new frame is captured.
     */
    static let retransmitLastFrame = false
    static let kFrameRetransmitIntervalMs = Int(250)
    static let kFrameRetransmitTimeInterval = CMTime(value: CMTimeValue(kFrameRetransmitIntervalMs),
                                                     timescale: CMTimeScale(1000))
    static let kFrameRetransmitDispatchInterval = DispatchTimeInterval.milliseconds(kFrameRetransmitIntervalMs)
    static let kFrameRetransmitDispatchLeeway = DispatchTimeInterval.milliseconds(20)

    init(isScreencast: Bool) {
        screencastUsage = isScreencast
        super.init()
    }

    public var isScreencast: Bool {
        get {
            return screencastUsage
        }
    }

    func requestOutputFormat(_ outputFormat: TVIVideoFormat) {
        videoFormat = outputFormat

        if let sink = sink {
            sink.onVideoFormatRequest(videoFormat)
        }
    }

    deinit {
        // Perform teardown and free memory on the video queue to ensure that the resources will not be resurrected.
        if let captureQueue = self.videoQueue {
            captureQueue.sync {
                self.timerSource?.cancel()
                self.timerSource = nil
            }
        }
    }

    public func processVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let sink = self.sink else {
            return
        }

        guard let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            assertionFailure("SampleBuffer did not have an ImageBuffer")
            return
        }
        // The source only supports NV12 (full-range) buffers.
        let pixelFormat = CVPixelBufferGetPixelFormatType(sourcePixelBuffer);
        if (pixelFormat != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            assertionFailure("Extension assumes the incoming frames are of type NV12")
            return
        }

        // Discover the dispatch queue that we are operating on.
        if videoQueue == nil {
            videoQueue = ExampleCoreAudioDeviceGetCurrentQueue()
        }

        // Frame dropping logic.
        if let lastTimestamp = lastTimestamp {
            let currentTimestmap = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let delta = CMTimeSubtract(currentTimestmap, lastTimestamp).seconds
            let threshold = Double(1.0 / Double(ReplayKitVideoSource.kDesiredFrameRate))

            if (delta < threshold) {
                print("Dropping frame with delta. ", delta as Any)
                return
            }
        }

        /*
         * Check rotation tags. Extensions see these tags, but `RPScreenRecorder` does not appear to set them.
         * On iOS 12.0, rotation tags other than up are set by extensions.
         */
        var videoOrientation = TVIVideoOrientation.up
        if let sampleOrientation = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil),
            let coreSampleOrientation = sampleOrientation.uint32Value {
            videoOrientation
                = ReplayKitVideoSource.imageOrientationToVideoOrientation(imageOrientation: CGImagePropertyOrientation(rawValue: coreSampleOrientation)!)
        }

        /*
         * Return the original pixel buffer without any downscaling or cropping applied.
         * You may use a format request to crop and/or scale the buffers produced by this class.
         */
        deliverFrame(to: sink,
                     timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                     buffer: sourcePixelBuffer,
                     orientation: videoOrientation,
                     forceReschedule: false)
    }

    func deliverFrame(to: TVIVideoSink, timestamp: CMTime, buffer: CVPixelBuffer, orientation: TVIVideoOrientation, forceReschedule: Bool) {
        guard let frame = TVIVideoFrame(timestamp: timestamp,
                                        buffer: buffer,
                                        orientation: orientation) else {
                                            assertionFailure("We couldn't create a TVIVideoFrame with a valid CVPixelBuffer.")
                                            return
        }
        to.onVideoFrame(frame)
        lastTimestamp = timestamp

        // Frame retransmission logic.
        if (ReplayKitVideoSource.retransmitLastFrame) {
            lastFrameStorage = frame
            lastTransmitTimestamp = CMClockGetTime(CMClockGetHostTimeClock())
            dispatchRetransmissions(forceReschedule: forceReschedule)
        }
    }

    func dispatchRetransmissions(forceReschedule: Bool) {
        if let source = timerSource,
            source.isCancelled == false,
            forceReschedule == false {
            // No work to do, wait for the next timer to fire and re-evaluate.
            return
        }
        // We require a queue to create a timer source.
        guard let currentQueue = videoQueue else {
            return
        }

        let source = DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags.strict,
                                                    queue: currentQueue)
        timerSource = source

        // Generally, this timer is invoked in kFrameRetransmitDispatchInterval when no frames are sent.
        source.setEventHandler(handler: {
            if let frame = self.lastFrameStorage,
                let sink = self.sink,
                let lastHostTimestamp = self.lastTransmitTimestamp {
                let currentTimestamp = CMClockGetTime(CMClockGetHostTimeClock())
                let delta = CMTimeSubtract(currentTimestamp, lastHostTimestamp)

                if delta >= ReplayKitVideoSource.kFrameRetransmitTimeInterval {
                    print("Delivering frame since send-delta is greather than threshold. delta=", delta.seconds)
                    // Reconstruct a new timestamp, advancing by our relative read of host time.
                    self.deliverFrame(to: sink,
                                      timestamp: CMTimeAdd(frame.timestamp, delta),
                                      buffer: frame.imageBuffer,
                                      orientation: frame.orientation,
                                      forceReschedule: true)
                } else {
                    // Reschedule for when the next retransmission might be required.
                    let remaining = ReplayKitVideoSource.kFrameRetransmitTimeInterval.seconds - delta.seconds
                    let deadline = DispatchTime.now() + DispatchTimeInterval.milliseconds(Int(remaining * 1000.0))
                    self.timerSource?.schedule(deadline: deadline, leeway: ReplayKitVideoSource.kFrameRetransmitDispatchLeeway)
                }
            }
        })

        // Thread safe cleanup of temporary storage, in case of cancellation. Normally, we reschedule.
        source.setCancelHandler(handler: {
            self.lastFrameStorage = nil
        })

        // Schedule a first time source for the full interval.
        let deadline = DispatchTime.now() + ReplayKitVideoSource.kFrameRetransmitDispatchInterval
        source.schedule(deadline: deadline, leeway: ReplayKitVideoSource.kFrameRetransmitDispatchLeeway)
        source.activate()
    }

    static func imageOrientationToVideoOrientation(imageOrientation: CGImagePropertyOrientation) -> TVIVideoOrientation {
        let videoOrientation: TVIVideoOrientation

        // Note: The source does not attempt to "undo" mirroring. So far I have not encountered mirrored tags from ReplayKit sources.
        switch imageOrientation {
        case .up:
            videoOrientation = TVIVideoOrientation.up
        case .upMirrored:
            videoOrientation = TVIVideoOrientation.up
        case .left:
            videoOrientation = TVIVideoOrientation.left
        case .leftMirrored:
            videoOrientation = TVIVideoOrientation.left
        case .right:
            videoOrientation = TVIVideoOrientation.right
        case .rightMirrored:
            videoOrientation = TVIVideoOrientation.right
        case .down:
            videoOrientation = TVIVideoOrientation.down
        case .downMirrored:
            videoOrientation = TVIVideoOrientation.down
        }

        return videoOrientation
    }
}
