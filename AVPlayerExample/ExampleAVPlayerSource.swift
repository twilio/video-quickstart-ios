//
//  ExampleAVPlayerSource.swift
//  AVPlayerExample
//
//  Copyright © 2018 Twilio Inc. All rights reserved.
//

import AVFoundation
import TwilioVideo

/*
 * This capturer manages an AVPlayerVideoItemOutput, attempting to output each frame that becomes available
 * for presentation. By default, a CADisplayLink timer is used to sample at the natural cadence of the display.
 * When there is no more content to sample, the capturer suspends its timer and waits for callbacks via
 * AVPlayerItemOutputPullDelegate to resume. In some cases, downscaling is used to reduce CPU and memory consumption.
 *
 * Please be aware that AVPlayer and its playback pipeline prepare content for presentation on your device, including
 * mapping frames to the display. For example, when playing 23.976 or 24 fps content a technique known as 3:2 pulldown
 * is used to time video samples for a 60 Hz iPhone display. Our capturer tags the frames with the best timing infromation
 * that it has available - the presentation timestamps provided by AVPlayerVideoItemOutput.
 */
class ExampleAVPlayerSource: NSObject, TVIVideoCapturer {

    private var captureConsumer: TVIVideoCaptureConsumer? = nil
    // Track how often we are receiving content. If no new frames are coming there is no need to sample the output.
    private var lastPresentationTimestamp: CMTime?
    // Display timer which fires at the natural cadence of our display. Sampling typically occurs within these timer callbacks.
    private var outputTimer: CADisplayLink? = nil
    // Dispatch timer which fires at a pre-determined cadence `kFrameOutputInterval`.
    private var timerSource: DispatchSourceTimer? = nil
    var videoOutput: AVPlayerItemVideoOutput? = nil
    private let videoSampleQueue: DispatchQueue

    // Frame output/sampling interval for a DispatchSource. Note: 60 Hz = 16667, 23.976 Hz = 41708
    static let kFrameOutputInterval = DispatchTimeInterval.microseconds(16667)
    static let kFrameOutputLeeway = DispatchTimeInterval.milliseconds(0)
    // How much time we will wait without receiving any frames before suspending output/sampling.
    static let kFrameOutputSuspendTimeout = Double(1.0)
    // The largest dimension we will output for streaming using the Video SDK.
    static let kFrameOutputMaxDimension = CGFloat(960.0)
    // A bounding box which represents the largest video we will output for streaming.
    static let kFrameOutputMaxRect = CGRect(x: 0, y: 0, width: kFrameOutputMaxDimension, height: kFrameOutputMaxDimension)

    // Use a CADisplayLink, or a DispatchSourceTimer (experimental) for sampling.
    static private var useDisplayLinkTimer = true

    init(item: AVPlayerItem) {
        videoSampleQueue = DispatchQueue(label: "com.twilio.avplayersource", qos: DispatchQoS.userInteractive,
                                         attributes: DispatchQueue.Attributes(rawValue: 0),
                                         autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.workItem,
                                         target: nil)
        super.init()

        let presentationSize = item.presentationSize
        let presentationPixels = presentationSize.width * presentationSize.height
        print("Prepare for player item with size:", presentationSize, " pixels:", presentationPixels);

        /*
         * We might request buffers downscaled for streaming. The output will always be 8-bit 4:2:0 NV12.
         */
        let attributes: [String : Any]

        if (presentationSize.width > ExampleAVPlayerSource.kFrameOutputMaxDimension ||
            presentationSize.height > ExampleAVPlayerSource.kFrameOutputMaxDimension) {
            let streamingRect = AVMakeRect(aspectRatio: presentationSize, insideRect: ExampleAVPlayerSource.kFrameOutputMaxRect)
            print("Requesting downscaling to:", streamingRect.size, ".");

            attributes = [
                kCVPixelBufferWidthKey as String : Int(streamingRect.width),
                kCVPixelBufferHeightKey as String : Int(streamingRect.height),
                kCVPixelBufferIOSurfacePropertiesKey as String : [ : ],
                kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                ] as [String : Any]
        } else {
            attributes = [
                kCVPixelBufferIOSurfacePropertiesKey as String : [ : ],
                kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                ] as [String : Any]
        }

        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        videoOutput?.setDelegate(self, queue: videoSampleQueue)

        if ExampleAVPlayerSource.useDisplayLinkTimer {
            addDisplayTimer()
        }
        videoOutput?.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.02)

        item.add(videoOutput!)
    }

    func outputFrame(itemTimestamp: CMTime) {
        guard let output = videoOutput else {
            return
        }
        guard let consumer = captureConsumer else {
            return
        }
        if !output.hasNewPixelBuffer(forItemTime: itemTimestamp) {
            // TODO: Consider suspending the timer and requesting a notification when media becomes available.
//            print("No frame for host timestamp:", CACurrentMediaTime(), "\n",
//                  "Last presentation timestamp was:", lastPresentationTimestamp != nil ? lastPresentationTimestamp! : CMTime.zero)
            return
        }

        var presentationTimestamp = CMTime.zero
        let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTimestamp,
                                                 itemTimeForDisplay: &presentationTimestamp)
        if let buffer = pixelBuffer {
            if let lastTime = lastPresentationTimestamp {
                // TODO: Use this info for 3:2 pulldown to re-construct the proper timestamps without display cadence?
//                let delta = presentationTimestamp - lastTime
//                print("Frame delta was:", delta)
//                let movieTime = CVBufferGetAttachment(buffer, kCVBufferMovieTimeKey, nil)
//                print("Movie time was:", movieTime as Any)
            }
            lastPresentationTimestamp = presentationTimestamp

            guard let frame = TVIVideoFrame(timestamp: presentationTimestamp,
                                            buffer: buffer,
                                            orientation: TVIVideoOrientation.up) else {
                                                assertionFailure("We couldn't create a TVIVideoFrame with a valid CVPixelBuffer.")
                                                return
            }
            consumer.consumeCapturedFrame(frame)
        }

        if ExampleAVPlayerSource.useDisplayLinkTimer {
            outputTimer?.isPaused = false
        } else if timerSource == nil {
            startTimerSource(hostTime: CACurrentMediaTime())
        }
    }

    func startTimerSource(hostTime: CFTimeInterval) {
        print(#function)

        let source = DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags.strict,
                                                    queue: videoSampleQueue)
        timerSource = source

        source.setEventHandler(handler: {
            if let output = self.videoOutput {
                let currentHostTime = CACurrentMediaTime()
                let currentItemTime = output.itemTime(forHostTime: currentHostTime)
                self.outputFrame(itemTimestamp: currentItemTime)
            }
        })

        // Thread safe cleanup of temporary storage, in case of cancellation.
        source.setCancelHandler(handler: {
        })

        // Schedule a first time source for the full interval.
        let deadline = DispatchTime.now() + ExampleAVPlayerSource.kFrameOutputInterval
        source.schedule(deadline: deadline,
                        repeating: ExampleAVPlayerSource.kFrameOutputInterval,
                        leeway: ExampleAVPlayerSource.kFrameOutputLeeway)
        source.resume()
    }

    func addDisplayTimer() {
        let timer = CADisplayLink(target: self,
                                  selector: #selector(ExampleAVPlayerSource.displayLinkDidFire(displayLink:)))
        // Fire at the native v-sync cadence of our display. This is what AVPlayer is targeting anyways.
        timer.preferredFramesPerSecond = 0
        timer.isPaused = true
        timer.add(to: RunLoop.current, forMode: RunLoop.Mode.common)
        outputTimer = timer
    }

    @objc func displayLinkDidFire(displayLink: CADisplayLink) {
        if let output = self.videoOutput {
            // We want the video content targeted for the next v-sync.
            let targetHostTime = displayLink.targetTimestamp
            let currentItemTime = output.itemTime(forHostTime: targetHostTime)
            self.outputFrame(itemTimestamp: currentItemTime)
        }
    }

    @objc func stopTimerSource() {
        print(#function)

        timerSource?.cancel()
        timerSource = nil
    }

    func stopDisplayTimer() {
        outputTimer?.invalidate()
        outputTimer = nil
    }

    public var isScreencast: Bool {
        get {
            return false
        }
    }

    public var supportedFormats: [TVIVideoFormat] {
        get {
            let format = TVIVideoFormat()
            format.dimensions = CMVideoDimensions(width: 640, height: 360)
            format.frameRate = 30
            format.pixelFormat = TVIPixelFormat.formatYUV420BiPlanarFullRange
            return [format]
        }
    }

    func startCapture(_ format: TVIVideoFormat, consumer: TVIVideoCaptureConsumer) {
        print(#function)

        self.captureConsumer = consumer;
        consumer.captureDidStart(true)
    }

    func stopCapture() {
        print(#function)

        if ExampleAVPlayerSource.useDisplayLinkTimer {
            stopDisplayTimer()
        } else {
            stopTimerSource()
        }
        self.captureConsumer = nil
    }
}

extension ExampleAVPlayerSource: AVPlayerItemOutputPullDelegate {

    func outputMediaDataWillChange(_ sender: AVPlayerItemOutput) {
        print(#function)

        // Begin to receive video frames.
        let videoOutput = sender as! AVPlayerItemVideoOutput
        let currentHostTime = CACurrentMediaTime()
        let currentItemTime = videoOutput.itemTime(forHostTime: currentHostTime)

        // We might have been called back so late that the output already has a frame ready.
        let hasFrame = videoOutput.hasNewPixelBuffer(forItemTime: currentItemTime)
        if hasFrame {
            outputFrame(itemTimestamp: currentItemTime)
        } else if ExampleAVPlayerSource.useDisplayLinkTimer {
            outputTimer?.isPaused = false
        } else {
            startTimerSource(hostTime: currentHostTime);
        }
    }

    func outputSequenceWasFlushed(_ output: AVPlayerItemOutput) {
        print(#function)

        // TODO: Flush and output a black frame while we wait?
    }
}
