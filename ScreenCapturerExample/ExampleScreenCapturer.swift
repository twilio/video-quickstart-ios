//
//  ExampleScreenCapturer.swift
//  ScreenCapturerExample
//
//  Copyright © 2016-2017 Twilio, Inc. All rights reserved.
//

import TwilioVideo

class ExampleScreenCapturer: NSObject, TVIVideoCapturer {

    public var isScreencast: Bool = true
    public var supportedFormats: [TVIVideoFormat]

    // Private variables
    weak var captureConsumer: TVIVideoCaptureConsumer?
    weak var view: UIView?
    var displayTimer: CADisplayLink?
    var willEnterForegroundObserver: NSObjectProtocol?
    var didEnterBackgroundObserver: NSObjectProtocol?

    // Constants
    let displayLinkFrameRate = 60
    let desiredFrameRate = 5
    let captureScaleFactor: CGFloat = 1.0

    init(aView: UIView) {
        captureConsumer = nil
        view = aView

        /* 
         * Describe the supported format.
         * For this example we cheat and assume that we will be capturing the entire screen.
         */
        let screenSize = UIScreen.main.bounds.size
        let format = TVIVideoFormat()
        format.pixelFormat = TVIPixelFormat.format32BGRA
        format.frameRate = UInt(desiredFrameRate)
        format.dimensions = CMVideoDimensions(width: Int32(screenSize.width), height: Int32(screenSize.height))
        supportedFormats = [format]

        // We don't need to call startCapture, this method is invoked when a TVILocalVideoTrack is added with this capturer.
    }

    func startCapture(_ format: TVIVideoFormat, consumer: TVIVideoCaptureConsumer) {
        if (view == nil || view?.superview == nil) {
            print("Can't capture from a nil view, or one with no superview:", view as Any)
            consumer.captureDidStart(false)
            return
        }

        print("Start capturing.")

        startTimer()
        registerNotificationObservers()

        captureConsumer = consumer;
        captureConsumer?.captureDidStart(true)
    }

    func stopCapture() {
        print("Stop capturing.")

        unregisterNotificationObservers()
        invalidateTimer()
    }

    func startTimer() {
        invalidateTimer()

        // Use a CADisplayLink timer so that our drawing is synchronized to the display vsync.
        displayTimer = CADisplayLink(target: self, selector: #selector(ExampleScreenCapturer.captureView))

        // On iOS 10.0+ use preferredFramesPerSecond, otherwise fallback to intervals assuming a 60 hz display
        if #available(iOS 10.0, *) {
            displayTimer?.preferredFramesPerSecond = desiredFrameRate
        } else {
            displayTimer?.frameInterval = displayLinkFrameRate / desiredFrameRate
        };

        displayTimer?.add(to: RunLoop.main, forMode: RunLoop.Mode.common)
        displayTimer?.isPaused = UIApplication.shared.applicationState == UIApplication.State.background
    }

    func invalidateTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    func registerNotificationObservers() {
        let notificationCenter = NotificationCenter.default;

        willEnterForegroundObserver = notificationCenter.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                                                     object: nil,
                                                                     queue: OperationQueue.main,
                                                                     using: { (Notification) in
                                                                        self.displayTimer?.isPaused = false;
        })

        didEnterBackgroundObserver = notificationCenter.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                                     object: nil,
                                                                     queue: OperationQueue.main,
                                                                     using: { (Notification) in
                                                                        self.displayTimer?.isPaused = true;
        })
    }

    func unregisterNotificationObservers() {
        let notificationCenter = NotificationCenter.default

        notificationCenter.removeObserver(willEnterForegroundObserver!)
        notificationCenter.removeObserver(didEnterBackgroundObserver!)

        willEnterForegroundObserver = nil
        didEnterBackgroundObserver = nil
    }

    @objc func captureView( timer: CADisplayLink ) {

        // This is our main drawing loop. Start by using the UIGraphics APIs to draw the UIView we want to capture.
        var contextImage: UIImage? = nil
        autoreleasepool {
            UIGraphicsBeginImageContextWithOptions((self.view?.bounds.size)!, true, captureScaleFactor)
            self.view?.drawHierarchy(in: (self.view?.bounds)!, afterScreenUpdates: false)
            contextImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
        }

        /*
         * Make a copy of the UIImage's underlying data. We do this by getting the CGImage, and its CGDataProvider.
         * Note that this technique is inefficient because it causes an extra malloc / copy to occur for every frame.
         * For a more performant solution, provide a pool of buffers and use them to back a CGBitmapContext.
         */
        let image: CGImage? = contextImage?.cgImage
        let dataProvider: CGDataProvider? = image?.dataProvider
        let data: CFData? = dataProvider?.data
        let baseAddress = CFDataGetBytePtr(data!)
        contextImage = nil

        /*
         * We own the copied CFData which will back the CVPixelBuffer, thus the data's lifetime is bound to the buffer.
         * We will use a CVPixelBufferReleaseBytesCallback callback in order to release the CFData when the buffer dies.
         */
        let unmanagedData = Unmanaged<CFData>.passRetained(data!)
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreateWithBytes(nil,
                                                  (image?.width)!,
                                                  (image?.height)!,
                                                  TVIPixelFormat.format32BGRA.rawValue,
                                                  UnsafeMutableRawPointer( mutating: baseAddress!),
                                                  (image?.bytesPerRow)!,
                                                  { releaseContext, baseAddress in
                                                    let contextData = Unmanaged<CFData>.fromOpaque(releaseContext!)
                                                    contextData.release()
                                                  },
                                                  unmanagedData.toOpaque(),
                                                  nil,
                                                  &pixelBuffer)

        if let buffer = pixelBuffer {
            // Deliver a frame to the consumer. Images drawn by UIGraphics do not need any rotation tags.
            let frame = TVIVideoFrame(timeInterval: timer.timestamp,
                                      buffer: buffer,
                                      orientation: TVIVideoOrientation.up)

            // The consumer retains the CVPixelBuffer and will own it as the buffer flows through the video pipeline.
            captureConsumer?.consumeCapturedFrame(frame!)
        } else {
            print("Capture failed with status code: \(status).")
        }
    }
}
