//
//  ReplayKitVideoSource.swift
//  ReplayKitExample
//
//  Copyright © 2018-2019 Twilio. All rights reserved.
//

import Accelerate
import CoreMedia
import CoreVideo
import Dispatch
import ReplayKit
import TwilioVideo

class ReplayKitVideoSource: NSObject, VideoSource {

    // In order to save memory, the handler may request that the source downscale its output.
    static let kDownScaledMaxWidthOrHeight = UInt(720)
    static let kDownScaledMaxWidthOrHeightSimulcast = UInt(1280)

    // Maximum bitrate (in kbps) used to send video.
    static let kMaxVideoBitrate = UInt(1420)
    static let kMaxVideoBitrateSimulcast = UInt(3000)
    static let kMaxScreenshareBitrate = UInt(1600)

    // Maximum frame rate to send video at.
    static let kMaxVideoFrameRate = UInt(15)

    /*
     * Streaming video content at 30 fps or lower is ideal, especially in variable network conditions.
     * In order to improve the quality of screen sharing, these constants optimize for specific use cases:
     *
     *  1. App content: Stream at 15 fps to ensure fine details (spatial resolution) are maintained.
     *  2. Video content: Attempt to match the natural video cadence between kMinSyncFrameRate <= fps <= kMaxSyncFrameRate.
     *  3. Video content (24/25 in 30 (in 60)): Some apps perform a telecine by drawing to the screen using more vsyncs than are needed.
     *     When this occurs, ReplayKit generates duplicate frames, decimating the content further to 30 Hz.
     *     Duplicate video frames reduce encoder performance, increase cpu usage and lower the quality of the video stream.
     *     When the source detects telecined content, it attempts an inverse telecine to restore the natural cadence.
     */
    static let kMaxSyncFrameRate = 26
    static let kMinSyncFrameRate = 20
    static let kFrameHistorySize = 20
    // The minimum average input frame rate where IVTC is attempted.
    static let kInverseTelecineInputFrameRate = 28
    // The minimum average delivery frame rate where IVTC is attempted. Add leeway due to 24 in 30 in 60 case.
    static let kInverseTelecineMinimumFrameRate = 23
    // When video content has 3:2 pulldown (in the form of extra frames), the IVTC should only ever drop 1 sequential frame.
    var didTelecineLastFrame = false

    static let kFormatFrameRate = UIScreen.main.maximumFramesPerSecond

    var screencastUsage: Bool = false
    weak var sink: VideoSink?
    var videoFormat: VideoFormat?
    var frameSync: Bool = false

    var averageDelivered = UInt32(0)

    var lastDeliveredTimestamp: CMTime?
    var recentDeliveredFrameDeltas: [CMTime] = []
    var lastInputTimestamp: CMTime?
    var recentInputFrameDeltas: [CMTime] = []
    var videoQueue: DispatchQueue?
    var timerSource: DispatchSourceTimer?
    var lastTransmitTimestamp: CMTime?
    private var lastFrameStorage: VideoFrame?
    // ReplayKit reuses the underlying CVPixelBuffer if you release the CMSampleBuffer back to their pool.
    // Holding on to the last frame is a poor-man's workaround to prevent image corruption.
    private var lastSampleBuffer: CMSampleBuffer?
    private var lastSampleBuffer2: CMSampleBuffer?
    /*
     * Enable retransmission of the last sent frame. This feature consumes some memory, CPU, and bandwidth but it ensures
     * that your most recent frame eventually reaches subscribers, and that the publisher has a reasonable bandwidth estimate
     * for the next time a new frame is captured.
     */
    static let retransmitLastFrame = true
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

    func requestOutputFormat(_ outputFormat: VideoFormat) {
        videoFormat = outputFormat

        if let sink = sink {
            sink.onVideoFormatRequest(videoFormat)
        }
    }

    static private func formatRequestToDownscale(maxWidthOrHeight: UInt, maxFrameRate: UInt) -> VideoFormat {
        let outputFormat = VideoFormat()

        var screenSize = UIScreen.main.bounds.size
        screenSize.width *= UIScreen.main.nativeScale
        screenSize.height *= UIScreen.main.nativeScale

        if maxWidthOrHeight > 0 {
            let downscaledTarget = CGSize(width: Int(maxWidthOrHeight),
                                          height: Int(maxWidthOrHeight))
            let fitRect = AVMakeRect(aspectRatio: screenSize,
                                     insideRect: CGRect(origin: CGPoint.zero, size: downscaledTarget)).integral
            let outputSize = fitRect.size

            outputFormat.dimensions = CMVideoDimensions(width: Int32(outputSize.width), height: Int32(outputSize.height))
        } else {
            outputFormat.dimensions = CMVideoDimensions(width: Int32(screenSize.width), height: Int32(screenSize.height))
        }

        outputFormat.frameRate = maxFrameRate
        return outputFormat;
    }

    static func encodingParameters(codec: VideoCodec, isScreencast: Bool) -> (EncodingParameters, VideoFormat) {
        let audioBitrate = UInt(0)
        var videoBitrate = kMaxVideoBitrate
        var maxWidthOrHeight = isScreencast ? UInt(0) : kDownScaledMaxWidthOrHeight
        let maxFrameRate = kMaxVideoFrameRate

        if let vp8Codec = codec as? Vp8Codec {
            videoBitrate = vp8Codec.isSimulcast ? kMaxVideoBitrateSimulcast : kMaxVideoBitrate
            if (!isScreencast) {
                maxWidthOrHeight = vp8Codec.isSimulcast ? kDownScaledMaxWidthOrHeightSimulcast : kDownScaledMaxWidthOrHeight
            }
        }

        return (EncodingParameters(audioBitrate: audioBitrate, videoBitrate: UInt(1024) * videoBitrate),
                formatRequestToDownscale(maxWidthOrHeight: maxWidthOrHeight, maxFrameRate: maxFrameRate))
    }

    deinit {
        // Perform teardown and free memory on the video queue to ensure that the resources will not be resurrected.
        if let captureQueue = self.videoQueue {
            captureQueue.sync {
                self.timerSource?.cancel()
                self.timerSource = nil
                self.lastSampleBuffer = nil
                self.lastSampleBuffer2 = nil
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

        // Frame dropping & inverse telecine (IVTC) logic.
        let lastTimestamp = lastInputTimestamp
        let currentTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        lastInputTimestamp = currentTimestamp

        // Frame sync & IVTC logic is engaged when screencast is not used.
        if let lastTimestamp = lastTimestamp,
            !screencastUsage {
            let delta = CMTimeSubtract(currentTimestamp, lastTimestamp)

            // Update input stats.
            if recentInputFrameDeltas.count == ReplayKitVideoSource.kFrameHistorySize {
                recentInputFrameDeltas.removeFirst()
            }
            recentInputFrameDeltas.append(delta)

            var total = CMTime.zero
            for dataPoint in recentInputFrameDeltas {
                total = CMTimeAdd(total, dataPoint)
            }
            let averageInput = Int32(round(Double(recentInputFrameDeltas.count) / total.seconds))

            let deltaSeconds = delta.seconds
            if frameSync == false,
                averageDelivered >= ReplayKitVideoSource.kMinSyncFrameRate,
                averageDelivered <= ReplayKitVideoSource.kMaxSyncFrameRate {
                frameSync = true

                if let format = videoFormat {
                    format.frameRate = UInt(ReplayKitVideoSource.kMaxSyncFrameRate)
                    requestOutputFormat(format)
                }

                print("Frame sync detected at rate: \(averageDelivered)")
            } else if frameSync,
                averageDelivered < ReplayKitVideoSource.kMinSyncFrameRate || averageDelivered > ReplayKitVideoSource.kMaxSyncFrameRate {
                frameSync = false

                if let format = videoFormat {
                    format.frameRate = UInt(15)
                    requestOutputFormat(format)
                }

                print("Frame sync stopped at rate: \(averageDelivered)")
            } else if averageInput >= ReplayKitVideoSource.kInverseTelecineInputFrameRate,
                averageDelivered >= ReplayKitVideoSource.kInverseTelecineMinimumFrameRate {
                if let lastSample = lastSampleBuffer,
                    didTelecineLastFrame == false,
                    ReplayKitVideoSource.compareSamples(first: lastSample, second: sampleBuffer) {
                    didTelecineLastFrame = true
                    print("Dropping frame due to IVTC. Delta: \(deltaSeconds)")
                    return
                } else if didTelecineLastFrame {
                    didTelecineLastFrame = false
                    print("After telecine: \(deltaSeconds) Delivered: \(averageDelivered)")
                }
            } else {
                print("Delta: \(deltaSeconds) Input: \(averageInput) Delivered: \(averageDelivered)")
            }
        }

        /*
         * Check rotation tags. Extensions see these tags, but `RPScreenRecorder` does not appear to set them.
         * On iOS 12.0, rotation tags other than up are set by extensions.
         */
        var videoOrientation = VideoOrientation.up
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

        // Hold on to the previous sample buffer to prevent tearing.
        lastSampleBuffer2 = lastSampleBuffer
        lastSampleBuffer = sampleBuffer
    }

    /*
     * The IVTC algorithm must know when a given frame is a duplicate of a previous frame. This implementation simply
     * compares the chroma channels of each image to determine equality. Occasional false positives are worth the
     * performance benefit of skipping the luma (Y) plane, which is twice the size of the chroma (UV) plane.
     */
    static func compareSamples(first: CMSampleBuffer, second: CMSampleBuffer) -> Bool {
        guard let firstPixelBuffer = CMSampleBufferGetImageBuffer(first) else {
            return false
        }
        guard let secondPixelBuffer = CMSampleBufferGetImageBuffer(second) else {
            return false
        }

        // Assumption: Only NV12 is supported.
        guard CVPixelBufferGetWidth(firstPixelBuffer) == CVPixelBufferGetWidth(secondPixelBuffer) else {
            return false
        }
        guard CVPixelBufferGetHeight(firstPixelBuffer) == CVPixelBufferGetHeight(secondPixelBuffer) else {
            return false
        }

        CVPixelBufferLockBaseAddress(firstPixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(secondPixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(firstPixelBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(secondPixelBuffer, .readOnly)
        }

        // Only the chroma plane is compared.
        let planeIndex = 1
        guard let baseAddress1 = CVPixelBufferGetBaseAddressOfPlane(firstPixelBuffer, planeIndex) else {
            return false
        }
        guard let baseAddress2 = CVPixelBufferGetBaseAddressOfPlane(secondPixelBuffer, planeIndex) else {
            return false
        }
        let width = CVPixelBufferGetWidthOfPlane(firstPixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(firstPixelBuffer, planeIndex)

        for row in 0...height {
            let rowOffset = row * CVPixelBufferGetBytesPerRowOfPlane(firstPixelBuffer, planeIndex)
            if memcmp(baseAddress1.advanced(by: rowOffset), baseAddress2.advanced(by: rowOffset), width) != 0 {
                return false
            }
        }

        return true
    }

    func deliverFrame(to: VideoSink, timestamp: CMTime, buffer: CVPixelBuffer, orientation: VideoOrientation, forceReschedule: Bool) {
        guard let frame = VideoFrame(timestamp: timestamp,
                                     buffer: buffer,
                                     orientation: orientation) else {
                                        assertionFailure("We couldn't create a VideoFrame with a valid CVPixelBuffer.")
                                        return
        }
        to.onVideoFrame(frame)

        // Frame retransmission logic.
        if (ReplayKitVideoSource.retransmitLastFrame) {
            lastFrameStorage = frame
            lastTransmitTimestamp = CMClockGetTime(CMClockGetHostTimeClock())
            dispatchRetransmissions(forceReschedule: forceReschedule)
        }

        // Update delivery stats
        if let lastTimestamp = lastDeliveredTimestamp,
            !screencastUsage {
            let delta = CMTimeSubtract(timestamp, lastTimestamp)

            if recentDeliveredFrameDeltas.count == ReplayKitVideoSource.kFrameHistorySize {
                recentDeliveredFrameDeltas.removeFirst()
            }
            recentDeliveredFrameDeltas.append(delta)

            var total = CMTime.zero
            for dataPoint in recentDeliveredFrameDeltas {
                total = CMTimeAdd(total, dataPoint)
            }
            averageDelivered = UInt32(round(Double(recentDeliveredFrameDeltas.count) / total.seconds))
        }

        lastDeliveredTimestamp = timestamp
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

    static func imageOrientationToVideoOrientation(imageOrientation: CGImagePropertyOrientation) -> VideoOrientation {
        let videoOrientation: VideoOrientation

        // Note: The source does not attempt to "undo" mirroring. So far I have not encountered mirrored tags from ReplayKit sources.
        switch imageOrientation {
        case .up:
            videoOrientation = VideoOrientation.up
        case .upMirrored:
            videoOrientation = VideoOrientation.up
        case .left:
            videoOrientation = VideoOrientation.left
        case .leftMirrored:
            videoOrientation = VideoOrientation.left
        case .right:
            videoOrientation = VideoOrientation.right
        case .rightMirrored:
            videoOrientation = VideoOrientation.right
        case .down:
            videoOrientation = VideoOrientation.down
        case .downMirrored:
            videoOrientation = VideoOrientation.down
        }

        return videoOrientation
    }
}
