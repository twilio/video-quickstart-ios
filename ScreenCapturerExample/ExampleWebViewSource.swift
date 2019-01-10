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
        guard let window = webView.window else {
            return
        }

        let configuration = WKSnapshotConfiguration()
        // Configure a width (in points) appropriate for our desired scale factor.
        configuration.snapshotWidth = NSNumber(value: Double(webView.bounds.width * ExampleWebViewSource.kCaptureScaleFactor / window.screen.scale))
        webView.takeSnapshot(with:configuration, completionHandler: { (image, error) in
            if let deliverableImage = image {
                self.deliverCapturedImage(image: deliverableImage,
                                          orientation: TVIVideoOrientation.up,
                                          timestamp: timer.timestamp)
            } else if let theError = error {
                print("Snapshot error:", theError as Any)
            }
        })
    }

    private func deliverCapturedImage(image: UIImage,
                                      orientation: TVIVideoOrientation,
                                      timestamp: CFTimeInterval) {
        /*
         * Make a (shallow) copy of the UIImage's underlying data. We do this by getting the CGImage, and its CGDataProvider.
         * In some cases, the bitmap's pixel format is not compatible with CVPixelBuffer and we need to repack the pixels.
         */
        guard let cgImage = image.cgImage else {
            return
        }

        let alphaInfo = cgImage.alphaInfo
        let byteOrderInfo = CGBitmapInfo(rawValue: cgImage.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue)
        let dataProvider = cgImage.dataProvider
        let data = dataProvider?.data
        let baseAddress = CFDataGetBytePtr(data!)!
        // The underlying data is marked as immutable, but we are the owner of this CGImage and can do as we please...
        let mutableBaseAddress = UnsafeMutablePointer<UInt8>(mutating: baseAddress)

        let pixelFormat: TVIPixelFormat

        switch byteOrderInfo {
        case .byteOrder32Little:
            // Encountered on iOS simulators.
            // Note: We do not account for the pre-multiplied alpha leaving the images too dim.
            // This problem could be solved using vImageUnpremultiplyData_RGBA8888 to operate in-place on the pixels.
            assert(alphaInfo == .premultipliedFirst || alphaInfo == .noneSkipFirst)
            pixelFormat = TVIPixelFormat.format32BGRA
        case .byteOrder32Big:
            // Never encountered with snapshots on iOS, but maybe on macOS?
            assert(alphaInfo == .premultipliedFirst || alphaInfo == .noneSkipFirst)
            pixelFormat = TVIPixelFormat.format32ARGB
        case .byteOrder16Little:
            pixelFormat = TVIPixelFormat.format32BGRA
            assert(false)
        case .byteOrder16Big:
            pixelFormat = TVIPixelFormat.format32BGRA
            assert(false)
        default:
            // The pixels are formatted in the default order for CoreGraphics, which on iOS is kCVPixelFormatType_32RGBA.
            // This format is included in Core Video for completeness, and creating a buffer returns kCVReturnInvalidPixelFormat.
            // We will instead repack the memory from RGBA to BGRA, which is supported by Core Video (and Twilio Video).
            // Note: While UIImages captured on a device claim to have pre-multiplied alpha, the alpha channel is always opaque (0xFF).
            pixelFormat = TVIPixelFormat.format32BGRA
            assert(alphaInfo == .premultipliedLast || alphaInfo == .noneSkipLast)

            for row in 0 ..< cgImage.height {
                let rowByteAddress = mutableBaseAddress.advanced(by: row * cgImage.bytesPerRow)

                for pixel in stride(from: 0, to: cgImage.width * 4, by: 4) {
                    // Swap the red and blue channels.
                    let red = rowByteAddress[pixel]
                    rowByteAddress[pixel] = rowByteAddress[pixel + 2]
                    rowByteAddress[pixel+2] = red
                }
            }
        }

        /*
         * We own the copied CFData which will back the CVPixelBuffer, thus the data's lifetime is bound to the buffer.
         * We will use a CVPixelBufferReleaseBytesCallback in order to release the CFData when the buffer dies.
         */
        let unmanagedData = Unmanaged<CFData>.passRetained(data!)
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreateWithBytes(nil,
                                                  cgImage.width,
                                                  cgImage.height,
                                                  pixelFormat.rawValue,
                                                  mutableBaseAddress,
                                                  cgImage.bytesPerRow,
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
