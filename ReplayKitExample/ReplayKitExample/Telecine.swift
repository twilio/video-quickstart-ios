//
//  Telecine.swift
//  ReplayKitExample
//
//  Created by Chris Eagleston on 8/10/19.
//  Copyright © 2019 Twilio. All rights reserved.
//

import Foundation

class InverseTelecine60p {
    enum TelecineSequence {
        // No duplicate has been detected yet.
        case Detecting
        // Waiting to try again.
        case Wait
        case Content2
        case Content3
    }

    enum Result {
        case dropFrame
        case deliverFrame
    }

    private var sequence = TelecineSequence.Detecting
    private var frameCounter = UInt16(0)
    private var sequenceCounter = UInt64(0)

    public func process(input: CMSampleBuffer, last: CMSampleBuffer) -> (Result, CMTime) {
        let inputTimestamp = CMSampleBufferGetPresentationTimeStamp(input)
        var result = Result.deliverFrame

        switch sequence {
        case .Detecting:
            if InverseTelecine60p.compareSamples(first: input, second: last) {
                frameCounter += 1
                if (frameCounter == 2) {
                    print("Found the 3 duplicate frames, looking for 2 more.")
                    self.sequence = .Content2
                    frameCounter = 0
                }
            } else {
                frameCounter = 0
            }
            break
        case .Content2:
            if InverseTelecine60p.compareSamples(first: input, second: last) {
                if frameCounter == 0 {
                    print("\(sequenceCounter + 1): frame 1 of 2 was a duplicate.")
                    self.sequence = .Detecting
                    sequenceCounter = 0
                } else if frameCounter == 1 {
                    self.sequence = .Content3
                    frameCounter = 0
                    result = .dropFrame
                }
            } else if frameCounter == 0 {
                // Deliver
                frameCounter = 1
            } else if frameCounter == 1 {
                print("\(sequenceCounter + 1): frame 2 of 2 was not a duplicate.")
                self.sequence = .Detecting
                sequenceCounter = 0
                frameCounter = 0
            }
            break
        case .Content3:
            if InverseTelecine60p.compareSamples(first: input, second: last) {
                if frameCounter == 0 {
                    print("\(sequenceCounter + 1): frame 1 of 3 was a duplicate.")
                    result = .dropFrame
                    self.sequence = .Detecting
                    sequenceCounter = 0
                    frameCounter = 0
                } else if frameCounter == 1 {
                    frameCounter = 2
                    result = .dropFrame
                } else {
                    self.sequence = .Content2
                    frameCounter = 0
                    sequenceCounter += 1
                    result = .dropFrame
                    print("Completed sequence \(sequenceCounter)")
                }
            } else if frameCounter == 0 {
                // Deliver
                frameCounter = 1
            } else if frameCounter == 1 {
                print("\(sequenceCounter + 1): frame \(frameCounter + 1) of 3 was not a duplicate.")
                self.sequence = .Detecting
                sequenceCounter = 0
                frameCounter = 0
            } else {
                print("\(sequenceCounter + 1): frame \(frameCounter + 1) of 3 was not a duplicate.")
                self.sequence = .Detecting
                sequenceCounter = 0
                frameCounter = 0
            }
            break
        case .Wait:
            frameCounter += 1
            break
        }

        // Wait to lock on to several iterations of the sequence.
        if sequenceCounter <= 2 {
            result = .deliverFrame
        }

        return (result as Result, inputTimestamp)
    }

    /// The IVTC algorithm must know when a given frame is a duplicate of a previous frame. This implementation
    /// compares the chroma channels of each image to determine equality. Occasional false positives are worth the
    /// performance benefit of skipping the luma (Y) plane, which is twice the size of the chroma (UV) plane.
    ///
    /// - Parameters:
    ///   - first: The first sample.
    ///   - second: The second sample.
    /// - Returns: `true` if the samples are the same, and `false` if they are not.
    private static func compareSamples(first: CMSampleBuffer, second: CMSampleBuffer) -> Bool {
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
}
