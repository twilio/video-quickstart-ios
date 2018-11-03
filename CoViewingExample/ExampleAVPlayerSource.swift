//
//  ExampleAVPlayerSource.swift
//  CoViewingExample
//
//  Copyright © 2018 Twilio Inc. All rights reserved.
//

import AVFoundation
import TwilioVideo

class ExampleAVPlayerSource: NSObject, TVIVideoCapturer {

    private let sampleQueue: DispatchQueue
    private var outputTimer: CADisplayLink? = nil
    private var videoOutput: AVPlayerItemVideoOutput? = nil
    private var captureConsumer: TVIVideoCaptureConsumer? = nil

    private var frameCounter = UInt32(0)

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

        // We request NV12 buffers downscaled to 480p for streaming.
        let attributes = [
            // Note: It appears requesting IOSurface backing causes a crash on iPhone X / iOS 12.0.1.
            // kCVPixelBufferIOSurfacePropertiesKey as String : [],
            kCVPixelBufferWidthKey as String : 640,
            kCVPixelBufferHeightKey as String : 360,
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

            if let consumer = self.captureConsumer,
                let buffer = pixelBuffer {
                guard let frame = TVIVideoFrame(timestamp: targetItemTime,
                                                buffer: buffer,
                                                orientation: TVIVideoOrientation.up) else {
                                                    assertionFailure("We couldn't create a TVIVideoFrame with a valid CVPixelBuffer.")
                                                    return
                }

                consumer.consumeCapturedFrame(frame)
            }
        } else {
            // TODO: Consider suspending the timer and requesting a notification when media becomes available.
        }
    }

    @objc func stopTimer() {
        outputTimer?.invalidate()
    }

    public var isScreencast: Bool {
        get {
            return false
        }
    }

    public var supportedFormats: [TVIVideoFormat] {
        get {
            return [TVIVideoFormat()]
        }
    }

    func startCapture(_ format: TVIVideoFormat, consumer: TVIVideoCaptureConsumer) {
        DispatchQueue.main.async {
            self.captureConsumer = consumer;
            consumer.captureDidStart(true)
        }
    }

    func stopCapture() {
        DispatchQueue.main.async {
            self.captureConsumer = nil
        }
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
