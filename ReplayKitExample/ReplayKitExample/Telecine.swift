//
//  Telecine.swift
//  ReplayKitExample
//
//  Created by Chris Eagleston on 8/10/19.
//  Copyright © 2019 Twilio. All rights reserved.
//

import Foundation
import CoreMedia
import CoreVideo

enum TelecineResult {
    case dropFrame
    case deliverFrame
}

protocol InverseTelecine {
    func process(input: CMSampleBuffer, last: CMSampleBuffer) -> (TelecineResult, CMTime)
}

class InverseTelecine60p : InverseTelecine {
    enum TelecineSequence {
        /// No duplicate has been detected yet.
        case Detecting
        /// Waiting to try again.
        case Wait
        /// Sequences that are 2 or 3 duplicate frames long, with occasional single frame sequences interspersed.
        case Content
    }

    private var sequence = TelecineSequence.Detecting
    private var frameCounter = UInt16(0)
    private var sequenceCounter = UInt64(0)
    private var lastSequenceLength = UInt16(0)

    public func process(input: CMSampleBuffer, last: CMSampleBuffer) -> (TelecineResult, CMTime) {
        let inputTimestamp = CMSampleBufferGetPresentationTimeStamp(input)
        var result = TelecineResult.deliverFrame

        switch sequence {
        case .Detecting:
            if InverseTelecine60p.compareSamples(first: input, second: last) {
                frameCounter += 1
                if (frameCounter == 2) {
                    print("Found 3 duplicate frames, looking for more 2 or 3 length content.")
                    self.sequence = .Content
                    frameCounter = 0
                }
            } else {
                frameCounter = 0
            }
            break
        case .Content:
            if InverseTelecine60p.compareSamples(first: input, second: last) {
                if frameCounter == 0 {
                    print("\(sequenceCounter + 1): frame 1 was a duplicate.")
                    self.sequence = .Detecting
                    sequenceCounter = 0
                    lastSequenceLength = 0
                } else if frameCounter < 3 {
                    frameCounter += 1
                    result = .dropFrame
                } else {
                    print("\(sequenceCounter + 1): has more than 3 duplicate frames.")
                    self.sequence = .Detecting
                    sequenceCounter = 0
                    lastSequenceLength = 0
                    frameCounter = 0
                }
            } else if frameCounter == 1 && lastSequenceLength == 1 {
                print("\(sequenceCounter + 1): length is only 1 frame.")
                self.sequence = .Detecting
                sequenceCounter = 0
                lastSequenceLength = 0
                frameCounter = 0
            } else {
                // Deliver, end of sequence.
                sequenceCounter += 1
                lastSequenceLength = frameCounter
                print("Completed sequence \(sequenceCounter) with \(frameCounter) frames")
                frameCounter = 1
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

        return (result as TelecineResult, inputTimestamp)
    }

    /// The IVTC algorithm must know when a given frame is a duplicate of a previous frame. This implementation
    /// compares the chroma channels of each image to determine equality. Occasional false positives are worth the
    /// performance benefit of skipping the luma (Y) plane, which is twice the size of the chroma (UV) plane.
    ///
    /// - Parameters:
    ///   - first: The first sample.
    ///   - second: The second sample.
    /// - Returns: `true` if the samples are the same, and `false` if they are not.
    public static func compareSamples(first: CMSampleBuffer, second: CMSampleBuffer) -> Bool {
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

class InverseTelecine30p : InverseTelecine {
    enum TelecineSequence {
        // No duplicate has been detected yet.
        case Detecting
        // Waiting to try again.
        case Wait
        // A content sequence is 3 to 6 distinct frames followed by a duplicate frame.
        case Content
    }

    private var sequence = TelecineSequence.Detecting
    private var contentFrames = UInt16(0)
    private var sequenceCounter = UInt64(0)
    private var lastInputTimestamp: CMTime?

    public func process(input: CMSampleBuffer, last: CMSampleBuffer) -> (TelecineResult, CMTime) {
        var result = TelecineResult.deliverFrame
        let inputTimestamp = CMSampleBufferGetPresentationTimeStamp(input)
        var adjustedTimestamp = inputTimestamp
        guard let lastTimestamp = lastInputTimestamp else {
            lastInputTimestamp = inputTimestamp
            return (.deliverFrame, adjustedTimestamp)
        }
        lastInputTimestamp = inputTimestamp
        let delta = CMTimeSubtract(inputTimestamp, lastTimestamp)

        switch sequence {
        case .Detecting:
            if InverseTelecine60p.compareSamples(first: input, second: last) {
                self.sequence = .Content
                contentFrames = 0
            } else {
                contentFrames += 1
                // TODO: Transition to wait state.
            }
            break
        case .Content:
            if InverseTelecine60p.compareSamples(first: input, second: last) {
                if contentFrames >= 3 && contentFrames <= 6 {
                    contentFrames = 0
                    sequenceCounter += 1
                    result = .dropFrame
                    print("Completed sequence \(sequenceCounter)")
                } else {
                    print("\(sequenceCounter + 1): frame \(contentFrames) was a duplicate.")
                    self.sequence = .Detecting
                    contentFrames = 0
                    sequenceCounter = 0
                }
            } else if contentFrames == 0 {
                contentFrames += 1
                // Pull the frame following the duplicate back 1/60 second, so as to not have a 4/60 second gap.
                let halfDelta = CMTimeMultiplyByRatio(delta, multiplier: 1, divisor: 2)
                adjustedTimestamp = inputTimestamp - halfDelta
                print("After duplicate frame: \((delta + halfDelta).seconds) Timestamp: \(adjustedTimestamp.seconds)")
            } else if contentFrames <= 6 {
                // Deliver
                contentFrames += 1
            } else {
                print("\(sequenceCounter + 1): frames 1-7 contained no duplicates.")
                self.sequence = .Detecting
                sequenceCounter = 0
                contentFrames = 0
            }
            break
        case .Wait:
            contentFrames = 0
            break
        }

        // Wait to lock on to several iterations of the sequence.
        if sequenceCounter <= 4 {
            result = .deliverFrame
        }

        return (result as TelecineResult, adjustedTimestamp)
    }
}
