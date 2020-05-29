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

    func cropRotateScale(input: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> CVPixelBuffer {
                    let cgImageOrientation = orientation
                    videoOrientation
                        = ReplayKitVideoSource.imageOrientationToVideoOrientation(imageOrientation: cgImageOrientation!)
                    let ciImage = CIImage(cvPixelBuffer: sourcePixelBuffer)
                    let undoneOrientation = ReplayKitVideoSource.undoImageOrientation(imageOrientation: cgImageOrientation!)
                    let scaleFactor = ReplayKitVideoSource.kDownScaledMinWidthOrHeightSimulcast / CGFloat(CVPixelBufferGetWidth(sourcePixelBuffer))
                    let cropRect = CGRect(x: 0, y: 0, width: 886, height: 1576)
                    let cropped = ciImage.cropped(to: cropRect)
                    let scaled = cropped.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
        //            let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
                    let rotatedAndScaled = scaled.oriented(undoneOrientation)

                    var copy: CVPixelBuffer?

                    if videoOrientation == .up || videoOrientation == .down {
                        CVPixelBufferCreate(
                            nil,
                            540,
                            960,
        //                    Int(CGFloat(CVPixelBufferGetWidth(sourcePixelBuffer)) * scaleFactor),
        //                    Int(CGFloat(CVPixelBufferGetHeight(sourcePixelBuffer)) * scaleFactor),
                            CVPixelBufferGetPixelFormatType(sourcePixelBuffer),
                            CVBufferGetAttachments(sourcePixelBuffer, .shouldPropagate),
                            &copy)
                    } else {
                        CVPixelBufferCreate(
                            nil,
                            960,
                            540,
        //                    Int(CGFloat(CVPixelBufferGetHeight(sourcePixelBuffer)) * scaleFactor),
        //                    Int(CGFloat(CVPixelBufferGetWidth(sourcePixelBuffer)) * scaleFactor),
                            CVPixelBufferGetPixelFormatType(sourcePixelBuffer),
                            CVBufferGetAttachments(sourcePixelBuffer, .shouldPropagate),
                            &copy)
                    }

                    context.render(rotatedAndScaled, to: copy!)
    }
}
