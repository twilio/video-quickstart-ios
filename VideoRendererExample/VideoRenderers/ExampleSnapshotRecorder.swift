//
//  ExampleSnapshotRecorder.swift
//  VideoRendererExample
//
//  Copyright © 2017 Twilio Inc. All rights reserved.
//

import CoreImage
import Foundation
import TwilioVideo

class ExampleSnapshotRecorder : NSObject, TVIVideoRenderer {
    var lastImageBuffer: CVImageBuffer?
    var captureSemaphore = DispatchSemaphore.init(value: 1)

    // Register pixel formats that we can convert to a UIImage.
    var optionalPixelFormats: [NSNumber] = [NSNumber.init(value: TVIPixelFormat.formatYUV420BiPlanarFullRange.rawValue),
                                            NSNumber.init(value: TVIPixelFormat.formatYUV420BiPlanarVideoRange.rawValue),
                                            NSNumber.init(value: TVIPixelFormat.format32BGRA.rawValue),
                                            NSNumber.init(value: TVIPixelFormat.format32ARGB.rawValue)]

    func captureSnapshot() -> UIImage? {
        // TODO: Maybe we don't want to wait forever for the smaphore?
        captureSemaphore.wait()
        let lastBuffer = lastImageBuffer
        captureSemaphore.signal()

        if let imageBuffer = lastBuffer {
            return ExampleSnapshotRecorder.convertPixelBufferToImage(buffer: imageBuffer)
        } else {
            return nil
        }
    }

    class func convertPixelBufferToImage(buffer: CVPixelBuffer) -> UIImage? {
        /*
         * Use CoreImage to convert a CVPixelBuffer which may be in RGB or video pixel formats to an RGB UIImage.
         * This may be somewhat wasteful, but is sufficient considering the recorder only needs a single frame at a time.
         */
        let ciImage = CIImage.init(cvPixelBuffer: buffer)
        let context = CIContext.init()
        let rect = CGRect.init(x: 0,
                               y: 0,
                               width: CVPixelBufferGetWidth(buffer),
                               height: CVPixelBufferGetHeight(buffer))

        if let cgImage = context.createCGImage(ciImage, from: rect) {
            return UIImage.init(cgImage: cgImage)
        } else {
            return nil
        }
    }
}

extension ExampleSnapshotRecorder {
    func renderFrame(_ frame: TVIVideoFrame) {
        captureSemaphore.wait()
        lastImageBuffer = frame.imageBuffer
        captureSemaphore.signal()
    }

    func updateVideoSize(_ videoSize: CMVideoDimensions, orientation: TVIVideoOrientation) {
        // Nothing to do.
    }
}
