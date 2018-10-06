//
//  ReplayKitVideoSource.swift
//  ReplayKitExample
//
//  Copyright © 2018 Twilio. All rights reserved.
//

import Accelerate
import CoreMedia
import CoreVideo
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

    // In order to save memory, our capturer may downscale the source to fit in a smaller rect.
    static let kDownScaledMaxWidthOrHeight = 640

    // Ensure that we have reasonable row alignment, especially if the downscaled width is not 640.
    static let kPixelBufferBytesPerRowAlignment = 64

    // ReplayKit provides planar NV12 CVPixelBuffers consisting of luma (Y) and chroma (UV) planes.
    static let kYPlane = 0
    static let kUVPlane = 1

    var lastTimestamp: CMTime?
    var downscaleBuffers: Bool = false
    var screencastUsage: Bool = false
    weak var captureConsumer: TVIVideoCaptureConsumer?

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
            format.frameRate = UInt(ReplayKitVideoSource.kDesiredFrameRate)
            format.dimensions = CMVideoDimensions(width: Int32(screenSize.width), height: Int32(screenSize.height))

            // We will downscale buffers to a 640x640 box, if requested.
            let downscaledFormat = TVIVideoFormat()
            downscaledFormat.frameRate = UInt(ReplayKitVideoSource.kDesiredFrameRate)
            downscaledFormat.pixelFormat = TVIPixelFormat.formatYUV420BiPlanarFullRange
            downscaledFormat.dimensions = CMVideoDimensions(width: Int32(ReplayKitVideoSource.kDownScaledMaxWidthOrHeight), height: Int32(ReplayKitVideoSource.kDownScaledMaxWidthOrHeight))

            return [format, downscaledFormat]
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
        if let sampleOrientation = CMGetAttachment(sampleBuffer, RPVideoSampleOrientationKey as CFString, nil),
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

        // Scale the Y and UV planes into the destination buffer.
        // TODO: Consider providing a temporary buffer for scaling.
        var error = vImageScale_Planar8(&sourceImageY, &destinationImageY, nil, vImage_Flags(kvImageEdgeExtend));
        if (error != kvImageNoError) {
            print("Failed to down scale luma plane.")
            return;
        }

        error = vImageScale_CbCr8(&sourceImageUV, &destinationImageUV, nil, vImage_Flags(kvImageEdgeExtend));
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

    func deliverFrame(to: TVIVideoCaptureConsumer, timestamp: CMTime, buffer: CVPixelBuffer, orientation: TVIVideoOrientation) {
        guard let frame = TVIVideoFrame(timestamp: timestamp,
                                        buffer: buffer,
                                        orientation: orientation) else {
                                            assertionFailure("We couldn't create a TVIVideoFrame with a valid CVPixelBuffer.")
                                            return
        }
        to.consumeCapturedFrame(frame)
        lastTimestamp = timestamp
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
