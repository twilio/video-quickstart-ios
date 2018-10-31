//
//  ExampleAVPlayerSource.swift
//  CoViewingExample
//
//  Copyright © 2018 Twilio Inc. All rights reserved.
//

import AVFoundation

class ExampleAVPlayerSource: NSObject {
    private let sampleQueue: DispatchQueue
    private var outputTimer: CADisplayLink? = nil
    private var videoOutput: AVPlayerItemVideoOutput? = nil

    static private var frameCounter = UInt32(0)

    init(item: AVPlayerItem) {
        sampleQueue = DispatchQueue(label: "", qos: DispatchQoS.userInteractive,
                                    attributes: DispatchQueue.Attributes(rawValue: 0),
                                    autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.workItem,
                                    target: nil)

        super.init()

        let timer = CADisplayLink(target: self,
                                selector: #selector(ExampleAVPlayerSource.displayLinkDidFire(displayLink:)))
        timer.preferredFramesPerSecond = 30
        timer.isPaused = true
        timer.add(to: RunLoop.current, forMode: RunLoop.Mode.common)
        outputTimer = timer

        // Note: It appears requesting IOSurface backing causes a crash on iPhone X / iOS 12.0.1?
        let attributes = [
//            kCVPixelBufferIOSurfacePropertiesKey as String : [],
            kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ] as [String : Any]

        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        videoOutput?.setDelegate(self, queue: sampleQueue)
        videoOutput?.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.1)

        item.add(videoOutput!)
    }

    @objc func displayLinkDidFire(displayLink: CADisplayLink) {
        guard let output = videoOutput else {
            return
        }

        let targetHostTime = displayLink.targetTimestamp
        let targetItemTime = output.itemTime(forHostTime: targetHostTime)

        if output.hasNewPixelBuffer(forItemTime: targetItemTime) {
            var presentationTime = CMTime.zero
            let pixelBuffer = output.copyPixelBuffer(forItemTime: targetItemTime, itemTimeForDisplay: &presentationTime)

            ExampleAVPlayerSource.frameCounter += 1
            if ExampleAVPlayerSource.frameCounter % 30 == 0 {
                print("Copied new pixel buffer: ", pixelBuffer as Any)
            }
        } else {
            // TODO: Consider suspending the timer and requesting a notification when media becomes available.
        }
    }

    @objc func stopTimer() {
        outputTimer?.invalidate()
    }
}

extension ExampleAVPlayerSource: AVPlayerItemOutputPullDelegate {
    func outputMediaDataWillChange(_ sender: AVPlayerItemOutput) {
        print(#function)
        // Begin to receive video frames.
        outputTimer?.isPaused = false
    }

    func outputSequenceWasFlushed(_ output: AVPlayerItemOutput) {
        // TODO: Flush and output a black frame while we wait.
    }
}
