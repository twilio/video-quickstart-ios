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

class ReplayKitVideoSource: NSObject, TVIVideoCapturer {

    /*
     * Streaming video content at 30 fps or lower is ideal. ReplayKit may produce buffers at up to 120 Hz on an iPad Pro.
     * This logic attempts to drop frames based upon timestamps. However, the approach is not ideal because timestamps
     * from ReplayKit do not seem to represent exact vSyncs that are measurable 1/60 second or 1/120 second increments.
     * For now we've increased the constant so that we will not drop frames (except for repeats) on an iPhone.
     */
    static let kDesiredFrameRate = 120

    static let kFormatFrameRate = UIScreen.main.maximumFramesPerSecond

    // In order to save memory, our capturer may downscale the source to fit in a smaller rect.
    static let kDownScaledMaxWidthOrHeight = 640

    // Ensure that we have reasonable row alignment, especially if the downscaled width is not 640.
    static let kPixelBufferBytesPerRowAlignment = 64

    // ReplayKit provides planar NV12 CVPixelBuffers consisting of luma (Y) and chroma (UV) planes.
    static let kYPlane = 0
    static let kUVPlane = 1

    var downscaleBuffers: Bool = false
    var screencastUsage: Bool = false
    weak var captureConsumer: TVIVideoCaptureConsumer?

    var downscaleYPlaneBuffer: UnsafeMutableRawPointer?
    var downscaleYPlaneSize: Int = 0
    var downscaleUVPlaneBuffer: UnsafeMutableRawPointer?
    var downscaleUVPlaneSize: Int = 0

    var lastTimestamp: CMTime?
    var timerSource: DispatchSourceTimer?
    var lastTransmitTimestamp: CMTime?

    private var lastFrameStorage: TVIVideoFrame?

    static let kFrameRetransmitInterval = Double(0.25)
    static let kFrameRetransmitDispatchInterval = DispatchTimeInterval.milliseconds(250)
    static let kFrameRetransmitDispatchLeeway = DispatchTimeInterval.milliseconds(20)
    static let retransmitLastFrame = true
    static let useDispatchQueue = true

    init(isScreencast: Bool) {
        screencastUsage = isScreencast
    }

    public var isScreencast: Bool {
        get {
            return screencastUsage
        }
    }

    public var supportedFormats: [TVIVideoFormat] {
        get {
            /*
             * Describe the supported formats.
             * In this example we can deliver either original, or downscaled buffers.
             */
            var screenSize = UIScreen.main.bounds.size
            screenSize.width *= UIScreen.main.nativeScale
            screenSize.height *= UIScreen.main.nativeScale
            let format = TVIVideoFormat()
            format.pixelFormat = TVIPixelFormat.formatYUV420BiPlanarFullRange
            format.frameRate = UInt(ReplayKitVideoSource.kFormatFrameRate)
            format.dimensions = CMVideoDimensions(width: Int32(screenSize.width), height: Int32(screenSize.height))

            // We will downscale buffers to a 640x640 box, if requested.
            let downscaledFormat = TVIVideoFormat()
            downscaledFormat.frameRate = UInt(ReplayKitVideoSource.kFormatFrameRate)
            downscaledFormat.pixelFormat = TVIPixelFormat.formatYUV420BiPlanarFullRange
            downscaledFormat.dimensions = CMVideoDimensions(width: Int32(ReplayKitVideoSource.kDownScaledMaxWidthOrHeight), height: Int32(ReplayKitVideoSource.kDownScaledMaxWidthOrHeight))

            return [format, downscaledFormat]
        }
    }

    deinit {
        if let yBuffer = downscaleYPlaneBuffer {
            free(yBuffer)
            downscaleYPlaneBuffer = nil
            downscaleYPlaneSize = 0
        }
        if let uvBuffer = downscaleUVPlaneBuffer {
            free(uvBuffer)
            downscaleUVPlaneBuffer = nil
            downscaleUVPlaneSize = 0
        }
    }

    func startCapture(_ format: TVIVideoFormat, consumer: TVIVideoCaptureConsumer) {
        captureConsumer = consumer

        if (format.dimensions.width == ReplayKitVideoSource.kDownScaledMaxWidthOrHeight &&
            format.dimensions.height == ReplayKitVideoSource.kDownScaledMaxWidthOrHeight) {
            downscaleBuffers = true
        }

        consumer.captureDidStart(true)
        print("Start capturing with format:", format)
    }

    func stopCapture() {
        captureConsumer = nil
        // TODO: Should reading/writing/cancellation be synchronized with the source's dispatch queue?
        timerSource?.cancel()
        timerSource = nil
        print("Stop capturing.")
    }

    public func processVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let consumer = self.captureConsumer else {
            return
        }
        guard let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            assertionFailure("SampleBuffer did not have an ImageBuffer")
            return
        }
        // We only support NV12 (full-range) buffers.
        let pixelFormat = CVPixelBufferGetPixelFormatType(sourcePixelBuffer);
        if (pixelFormat != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            assertionFailure("Extension assumes the incoming frames are of type NV12")
            return
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

        // Return the original pixel buffer without downscaling.
        if (!downscaleBuffers) {
            deliverFrame(to: consumer,
                         timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                         buffer: sourcePixelBuffer,
                         orientation: videoOrientation)
            return
        }

        // Compute the downscaled rect for our destination (in whole pixels). Note: it would be better to round to even values.
        let rect = AVMakeRect(aspectRatio: CGSize(width: CVPixelBufferGetWidth(sourcePixelBuffer),
                                                  height: CVPixelBufferGetHeight(sourcePixelBuffer)),
                              insideRect: CGRect(x: 0,
                                                 y: 0,
                                                 width: ReplayKitVideoSource.kDownScaledMaxWidthOrHeight,
                                                 height: ReplayKitVideoSource.kDownScaledMaxWidthOrHeight))
        let size = rect.integral.size

        // We will allocate a CVPixelBuffer to hold the downscaled contents.
        // TODO: Consider copying attributes such as CVImageBufferTransferFunction, CVImageBufferYCbCrMatrix and CVImageBufferColorPrimaries.
        // On an iPhone X running iOS 12.0 these buffers are tagged with ITU_R_709_2 primaries and a ITU_R_601_4 matrix.
        var outPixelBuffer: CVPixelBuffer? = nil
        let attributes = NSDictionary(object: ReplayKitVideoSource.kPixelBufferBytesPerRowAlignment,
                                      forKey: NSString(string: kCVPixelBufferBytesPerRowAlignmentKey))

        var status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width),
                                         Int(size.height),
                                         pixelFormat,
                                         attributes,
                                         &outPixelBuffer);
        if (status != kCVReturnSuccess) {
            print("Failed to create pixel buffer");
            return
        }

        let destinationPixelBuffer = outPixelBuffer!

        status = CVPixelBufferLockBaseAddress(sourcePixelBuffer, CVPixelBufferLockFlags.readOnly);
        status = CVPixelBufferLockBaseAddress(destinationPixelBuffer, []);

        // Prepare source pointers.
        var sourceImageY = vImage_Buffer(data: CVPixelBufferGetBaseAddressOfPlane(sourcePixelBuffer, ReplayKitVideoSource.kYPlane),
                                         height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(sourcePixelBuffer, ReplayKitVideoSource.kYPlane)),
                                         width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(sourcePixelBuffer, ReplayKitVideoSource.kYPlane)),
                                         rowBytes: CVPixelBufferGetBytesPerRowOfPlane(sourcePixelBuffer, ReplayKitVideoSource.kYPlane))

        var sourceImageUV = vImage_Buffer(data: CVPixelBufferGetBaseAddressOfPlane(sourcePixelBuffer, ReplayKitVideoSource.kUVPlane),
                                          height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(sourcePixelBuffer, ReplayKitVideoSource.kUVPlane)),
                                          width:vImagePixelCount(CVPixelBufferGetWidthOfPlane(sourcePixelBuffer, ReplayKitVideoSource.kUVPlane)),
                                          rowBytes: CVPixelBufferGetBytesPerRowOfPlane(sourcePixelBuffer, ReplayKitVideoSource.kUVPlane))

        // Prepare destination pointers.
        var destinationImageY = vImage_Buffer(data: CVPixelBufferGetBaseAddressOfPlane(destinationPixelBuffer, ReplayKitVideoSource.kYPlane),
                                              height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(destinationPixelBuffer, ReplayKitVideoSource.kYPlane)),
                                              width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(destinationPixelBuffer, ReplayKitVideoSource.kYPlane)),
                                              rowBytes: CVPixelBufferGetBytesPerRowOfPlane(destinationPixelBuffer, ReplayKitVideoSource.kYPlane))

        var destinationImageUV = vImage_Buffer(data: CVPixelBufferGetBaseAddressOfPlane(destinationPixelBuffer, ReplayKitVideoSource.kUVPlane),
                                               height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(destinationPixelBuffer, ReplayKitVideoSource.kUVPlane)),
                                               width: vImagePixelCount( CVPixelBufferGetWidthOfPlane(destinationPixelBuffer, ReplayKitVideoSource.kUVPlane)),
                                               rowBytes: CVPixelBufferGetBytesPerRowOfPlane(destinationPixelBuffer, ReplayKitVideoSource.kUVPlane))

        // Scale the Y and UV planes into the destination buffers, providing the intermediate scaling buffers to vImage.
        preallocateScalingBuffers(sourceY: &sourceImageY,
                                  sourceUV: &sourceImageUV,
                                  destinationY: &destinationImageY,
                                  destinationUV: &destinationImageUV)

        var error = vImageScale_Planar8(&sourceImageY, &destinationImageY, downscaleYPlaneBuffer, vImage_Flags(kvImageEdgeExtend));
        if (error != kvImageNoError) {
            print("Failed to down scale luma plane.")
            return;
        }

        error = vImageScale_CbCr8(&sourceImageUV, &destinationImageUV, downscaleUVPlaneBuffer, vImage_Flags(kvImageEdgeExtend));
        if (error != kvImageNoError) {
            print("Failed to down scale chroma plane.")
            return;
        }

        status = CVPixelBufferUnlockBaseAddress(outPixelBuffer!, [])
        status = CVPixelBufferUnlockBaseAddress(sourcePixelBuffer, CVPixelBufferLockFlags.readOnly)

        deliverFrame(to: consumer,
                     timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                     buffer: destinationPixelBuffer,
                     orientation: videoOrientation)
    }

    func preallocateScalingBuffers(sourceY: UnsafePointer<vImage_Buffer>,
                                   sourceUV: UnsafePointer<vImage_Buffer>,
                                   destinationY: UnsafePointer<vImage_Buffer>,
                                   destinationUV: UnsafePointer<vImage_Buffer>) {
        // Size the buffers required for vImage scaling. As source requirements change, we might need to reallocate them.
        let yBufferSize = vImageScale_Planar8(sourceY, destinationY, nil, vImage_Flags(kvImageGetTempBufferSize))
        assert(yBufferSize > 0)

        if (downscaleYPlaneBuffer == nil) {
            downscaleYPlaneBuffer = malloc(yBufferSize)
            downscaleYPlaneSize = yBufferSize
        } else if (downscaleYPlaneBuffer != nil && yBufferSize > downscaleYPlaneSize) {
            free(downscaleYPlaneBuffer)
            downscaleYPlaneBuffer = malloc(yBufferSize)
            downscaleYPlaneSize = yBufferSize
        } else {
            assert(downscaleYPlaneBuffer != nil)
            assert(downscaleYPlaneSize > 0)
        }

        let uvBufferSize = vImageScale_CbCr8(sourceUV, destinationUV, nil, vImage_Flags(kvImageGetTempBufferSize))
        if (downscaleUVPlaneBuffer == nil) {
            downscaleUVPlaneBuffer = malloc(uvBufferSize)
            downscaleUVPlaneSize = uvBufferSize
        } else if (downscaleUVPlaneBuffer != nil && uvBufferSize > downscaleUVPlaneSize) {
            free(downscaleUVPlaneBuffer)
            downscaleUVPlaneBuffer = malloc(uvBufferSize)
            downscaleUVPlaneSize = uvBufferSize
        } else {
            assert(downscaleUVPlaneBuffer != nil)
            assert(downscaleUVPlaneSize > 0)
        }
    }

    func deliverFrame(to: TVIVideoCaptureConsumer, timestamp: CMTime, buffer: CVPixelBuffer, orientation: TVIVideoOrientation) {
        guard let frame = TVIVideoFrame(timestamp: timestamp,
                                        buffer: buffer,
                                        orientation: orientation) else {
                                            assertionFailure("We couldn't create a TVIVideoFrame with a valid CVPixelBuffer.")
                                            return
        }
        to.consumeCapturedFrame(frame)
        lastTimestamp = timestamp

        // Frame retransmission logic.
        if (ReplayKitVideoSource.retransmitLastFrame) {
            if ReplayKitVideoSource.useDispatchQueue {
                lastFrameStorage = frame
                lastTransmitTimestamp = CMClockGetTime(CMClockGetHostTimeClock())
                dispatchRetransmissions()
            }
        }
    }

    func dispatchRetransmissions() {
        // This is a workaround for the fact that we can't provide our own serial queue to ReplayKit.
        let currentQueue = ExampleCoreAudioDeviceGetCurrentQueue()

        var source: DispatchSourceTimer?
        if timerSource == nil {
            source = DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags.strict,
                                                    queue: currentQueue)

            // Generally, this timer is invoked in kFrameRetransmitDispatchInterval when no frames are sent.
            source?.setEventHandler(handler: {
                if let frame = self.lastFrameStorage,
                    let consumer = self.captureConsumer,
                    let lastHostTimestamp = self.lastTransmitTimestamp {
                    let currentTimestamp = CMClockGetTime(CMClockGetHostTimeClock())
                    let delta = CMTimeSubtract(currentTimestamp, lastHostTimestamp)
                    let threshold = Double(4.0 / 60.0)

                    if delta.seconds >= threshold {
                        print("Delivering frame since send-delta is greather than threshold. delta=", delta.seconds)
                        // Reconstruct a new timestamp, advancing by our relative read of host time.
                        self.deliverFrame(to: consumer,
                                          timestamp: CMTimeAdd(frame.timestamp, delta),
                                          buffer: frame.imageBuffer,
                                          orientation: frame.orientation)
                    } else {
                        self.dispatchRetransmissions()
                    }
                }
            })

            // Thread safe cleanup of temporary storage, in case of cancellation. Normally, we reschedule.
            source?.setCancelHandler(handler: {
                self.lastFrameStorage = nil
            })

            timerSource = source
        }

        let deadline = DispatchTime.now() + ReplayKitVideoSource.kFrameRetransmitDispatchInterval
        timerSource?.schedule(deadline: deadline, leeway: ReplayKitVideoSource.kFrameRetransmitDispatchLeeway)
        source?.resume()
    }

    static func imageOrientationToVideoOrientation(imageOrientation: CGImagePropertyOrientation) -> TVIVideoOrientation {
        let videoOrientation: TVIVideoOrientation

        // Note: We do not attempt to "undo" mirroring. So far I have not encountered mirrored tags from ReplayKit sources.
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
