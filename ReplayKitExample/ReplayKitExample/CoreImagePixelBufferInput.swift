//
//  CoreImagePixelBufferInput.swift
//  ReplayKitExample
//
//  Created by Chris Eagleston on 5/29/20.
//  Copyright © 2020 Twilio. All rights reserved.
//

import CoreImage
import CoreGraphics
import CoreVideo

class CoreImagePixelBufferInput {
    let context = CIContext(options: [CIContextOption.outputColorSpace: NSNull(),
                                      CIContextOption.workingColorSpace: NSNull()]);

    func cropRotateScale(input: CVPixelBuffer, orientation: CGImagePropertyOrientation, cropRect: CGRect?) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: input)
        let undoneOrientation = CoreImagePixelBufferInput.undoImageOrientation(imageOrientation: orientation)
//        let scaleFactor = ReplayKitVideoSource.kDownScaledMinWidthOrHeightSimulcast / CGFloat(CVPixelBufferGetWidth(input))
        let scaleFactor = CGFloat(ReplayKitVideoSource.kDownScaledMaxWidthOrHeightSimulcast) / CGFloat(CVPixelBufferGetHeight(input))
        var scaled: CIImage
        if let rect = cropRect {
            let cropped = ciImage.cropped(to: rect)
            scaled = cropped.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
        } else {
            scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
        }
        let rotatedAndScaled = scaled.oriented(undoneOrientation)

        var copy: CVPixelBuffer?

        switch undoneOrientation {
        case .up:
            fallthrough
        case .upMirrored:
            fallthrough
        case .down:
            fallthrough
        case .downMirrored:
            CVPixelBufferCreate(
                nil,
//                540,
//                960,
                Int(CGFloat(CVPixelBufferGetWidth(input)) * scaleFactor),
                Int(CGFloat(CVPixelBufferGetHeight(input)) * scaleFactor),
                CVPixelBufferGetPixelFormatType(input),
                CVBufferGetAttachments(input, .shouldPropagate),
                &copy)
        default:
            CVPixelBufferCreate(
                nil,
//                960,
//                540,
                Int(CGFloat(CVPixelBufferGetHeight(input)) * scaleFactor),
                Int(CGFloat(CVPixelBufferGetWidth(input)) * scaleFactor),
                CVPixelBufferGetPixelFormatType(input),
                CVBufferGetAttachments(input, .shouldPropagate),
                &copy)
        }

        context.render(rotatedAndScaled, to: copy!)
        return copy;
    }

    func cropAndScale(input: CVPixelBuffer, cropRect: CGRect?) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: input)
        let scaleFactor: CGFloat
        let width: Int
        let height: Int
        if (CVPixelBufferGetHeight(input) > CVPixelBufferGetWidth(input)) {
            scaleFactor = 540.0 / CGFloat(CVPixelBufferGetWidth(input))
            width = 540
//                height = 960
            height = 1170
        } else {
            scaleFactor = 540.0 / CGFloat(CVPixelBufferGetHeight(input))
            height = 540
//                width = 960
            width = 1170
        }
        var scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))

        if cropRect != nil {
            let cropped = ciImage.cropped(to: cropRect!)
            scaled = cropped.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
        }

        var copy: CVPixelBuffer?
        CVPixelBufferCreate(
            nil,
            width,
            height,
            CVPixelBufferGetPixelFormatType(input),
            CVBufferGetAttachments(input, .shouldPropagate),
            &copy)
        context.render(scaled, to: copy!)
        return copy
    }

    private static func undoImageOrientation(imageOrientation: CGImagePropertyOrientation) -> CGImagePropertyOrientation {
        let undoneOrientation: CGImagePropertyOrientation

        switch imageOrientation {
        case .up:
            undoneOrientation = .up
        case .upMirrored:
            undoneOrientation = .upMirrored
        case .left:
            undoneOrientation = .right
        case .leftMirrored:
            undoneOrientation = .rightMirrored
        case .right:
            undoneOrientation = .left
        case .rightMirrored:
            undoneOrientation = .rightMirrored
        case .down:
            undoneOrientation = .down
        case .downMirrored:
            undoneOrientation = .downMirrored
        }

        return undoneOrientation
    }

}
