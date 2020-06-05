//
//  CoreImagePixelBufferInput.swift
//  ReplayKitExample
//
//  Copyright © 2020 Twilio. All rights reserved.
//

import CoreImage
import CoreGraphics
import CoreVideo

class CoreImagePixelBufferInput {
    let context = CIContext(options: [CIContextOption.outputColorSpace: NSNull(),
                                      CIContextOption.workingColorSpace: NSNull()]);

    /// Avoids reallocating memory.
    var pixelBufferPool: CVPixelBufferPool?

    func createPixelBufferPool(width: Int32, height: Int32, maxBufferCount: Int32) -> CVPixelBufferPool? {
        print("Creating a CVPixelBufferPool with size=\(width)x\(height), maxBuffers=\(maxBufferCount).")
        var outputPool: CVPixelBufferPool? = nil

        let poolAttributes: NSDictionary = [
            kCVPixelBufferPoolMinimumBufferCountKey: 1,
            kCVPixelBufferPoolAllocationThresholdKey: maxBufferCount
        ]
        
        let pixelBufferAttributes: NSDictionary = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: NSDictionary()
        ]
        let status = CVPixelBufferPoolCreate(nil,
                                             poolAttributes,
                                             pixelBufferAttributes,
                                             &outputPool)
        if status != kCVReturnSuccess {
            // TODO: Throw?
        }

        return outputPool
    }

    func scale(input: CVPixelBuffer, maxWidthOrHeight: UInt) -> CVPixelBuffer? {
        let inWidth = CVPixelBufferGetWidth(input)
        let inHeight = CVPixelBufferGetHeight(input)

        let ciImage = CIImage(cvPixelBuffer: input)
        let scaleHeight = CGFloat(maxWidthOrHeight) / CGFloat(inHeight)
        let scaleWidth = CGFloat(maxWidthOrHeight) / CGFloat(inWidth)
        let scaleFactor = min(scaleWidth, scaleHeight)
        let outWidth = Int32(CGFloat(inWidth) * scaleFactor)
        let outHeight = Int32(CGFloat(inHeight) * scaleFactor)

        var scaled: CIImage
        scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))

        // Update buffer pool
        if pixelBufferPool == nil {
            pixelBufferPool = createPixelBufferPool(width: outWidth, height: outHeight, maxBufferCount: 1)
        }

        // Dequeue and scale.
        var copy: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pixelBufferPool!, nil, &copy)
        if let theCopy = copy {
            context.render(scaled, to: theCopy)
        } else {
            print("Buffer creation failed: \(status)")
        }
        return copy;
    }

}
