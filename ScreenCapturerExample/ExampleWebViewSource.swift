//
//  ExampleWebViewSource.swift
//  ScreenCapturerExample
//
//  Copyright © 2016-2019 Twilio, Inc. All rights reserved.
//

import TwilioVideo
import WebKit

@available(iOS 11.0, *)
class ExampleWebViewSource: NSObject {

    // TVIVideoSource
    public var isScreencast: Bool = true
    public weak var sink: TVIVideoSink? = nil

    // Private variables
    weak var view: WKWebView?
    var displayTimer: CADisplayLink?
    var willEnterForegroundObserver: NSObjectProtocol?
    var didEnterBackgroundObserver: NSObjectProtocol?

    // Constants
    static let kCaptureFrameRate = 5
    static let kCaptureScaleFactor: CGFloat = 1.0

    init(aView: WKWebView) {
        sink = nil
        view = aView
    }

    func startCapture() {
        if (view == nil || view?.superview == nil) {
            print("Can't capture from a nil view, or one with no superview:", view as Any)
            return
        }

        print("Start capturing.")

        startTimer()
        registerNotificationObservers()
    }

    func stopCapture() {
        print("Stop capturing.")

        unregisterNotificationObservers()
        invalidateTimer()
    }

    private func startTimer() {
        invalidateTimer()

        // Use a CADisplayLink timer so that our drawing is synchronized to the display vsync.
        displayTimer = CADisplayLink(target: self, selector: #selector(ExampleWebViewSource.captureView))
        displayTimer?.preferredFramesPerSecond = ExampleWebViewSource.kCaptureFrameRate
        displayTimer?.add(to: RunLoop.main, forMode: RunLoop.Mode.common)
        displayTimer?.isPaused = UIApplication.shared.applicationState == UIApplication.State.background
    }

    private func invalidateTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func registerNotificationObservers() {
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

    private func unregisterNotificationObservers() {
        let notificationCenter = NotificationCenter.default

        notificationCenter.removeObserver(willEnterForegroundObserver!)
        notificationCenter.removeObserver(didEnterBackgroundObserver!)

        willEnterForegroundObserver = nil
        didEnterBackgroundObserver = nil
    }

    @objc func captureView( timer: CADisplayLink ) {
        guard let webView = self.view else {
            return
        }

        let configuration = WKSnapshotConfiguration()
        // Configure a width appropriate for our scale factor.
        configuration.snapshotWidth = NSNumber(value: Double(webView.bounds.width * ExampleWebViewSource.kCaptureScaleFactor))
        webView.takeSnapshot(with:configuration, completionHandler: { (image, error) in
            if let deliverableImage = image {
                // TODO: Neither BGRA or ARGB are correct, is this ABGR?
                self.deliverCapturedImage(image: deliverableImage,
                                          format: TVIPixelFormat.format32BGRA,
                                          orientation: TVIVideoOrientation.up,
                                          timestamp: timer.timestamp)
            } else if let theError = error {
                print("Snapshot error:", theError as Any)
            }
        })
    }

    private func deliverCapturedImage(image: UIImage, format: TVIPixelFormat, orientation: TVIVideoOrientation, timestamp: CFTimeInterval) {
        /*
         * Make a copy of the UIImage's underlying data. We do this by getting the CGImage, and its CGDataProvider.
         * Note that this technique is inefficient because it causes an extra malloc / copy to occur for every frame.
         * For a more performant solution, provide a pool of buffers and use them to back a CGBitmapContext.
         */
        let image: CGImage? = image.cgImage
        let dataProvider: CGDataProvider? = image?.dataProvider
        let data: CFData? = dataProvider?.data
        let baseAddress = CFDataGetBytePtr(data!)

        /*
         * We own the copied CFData which will back the CVPixelBuffer, thus the data's lifetime is bound to the buffer.
         * We will use a CVPixelBufferReleaseBytesCallback callback in order to release the CFData when the buffer dies.
         */
        let unmanagedData = Unmanaged<CFData>.passRetained(data!)
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreateWithBytes(nil,
                                                  (image?.width)!,
                                                  (image?.height)!,
                                                  format.rawValue,
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
            // Deliver a frame to the consumer.
            let frame = TVIVideoFrame(timeInterval: timestamp,
                                      buffer: buffer,
                                      orientation: orientation)

            // The consumer retains the CVPixelBuffer and will own it as the buffer flows through the video pipeline.
            self.sink?.onVideoFrame(frame!)
        } else {
            print("Video source failed with status code: \(status).")
        }
    }
}

@available(iOS 11.0, *)
extension ExampleWebViewSource: TVIVideoSource {
    func requestOutputFormat(_ outputFormat: TVIVideoFormat) {
        /*
         * This class doesn't explicitly support different scaling factors or frame rates.
         * That being said, we won't disallow cropping and/or scaling if its absolutely needed.
         */
        self.sink?.onVideoFormatRequest(outputFormat)
    }
}
