//
//  ViewController.swift
//  ARKitExample
//
//  Created by Lizzie Siegle on 8/10/17.
//  Copyright © 2016-2017 Twilio, Inc. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import TwilioVideo

class ViewController: UIViewController, ARSCNViewDelegate, TVIRoomDelegate {

    @IBOutlet var sceneView: ARSCNView!
    var accessToken = "ACCESS-TOKEN"
    var room: TVIRoom?
    weak var consumer: TVIVideoCaptureConsumer?
    var frame: TVIVideoFrame?
    var displayLink: CADisplayLink?

    var supportedFormats = [TVIVideoFormat]()
    var videoTrack: TVILocalVideoTrack?
    var audioTrack: TVILocalAudioTrack?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Configure the ARSCNView which will be used to display the AR content.
        // Since we will also capture from the view we will limit ourselves to 30 fps.
        sceneView.delegate = self

        // TODO: Revisit these settings.
        // Since we are in a streaming environment, we will render at a relatively low resolution.
        sceneView.preferredFramesPerSecond = 30
        sceneView.contentScaleFactor = 1

        // Show feature points, and statistics such as fps and timing information
        sceneView.showsStatistics = true
        sceneView.debugOptions =
            [ARSCNDebugOptions.showFeaturePoints, ARSCNDebugOptions.showWorldOrigin]

        // Create a new scene, and bind it to the view.
        let scene = SCNScene(named: "art.scnassets/ship.scn")!
        sceneView.scene = scene

        // We only support the single capture format that our ARSession will give us.
        // Since ARSession doesn't seem to give us any way to query its output format, we will assume 1280x720x30
        let format = TVIVideoFormat.init()
        format.dimensions = CMVideoDimensions.init(width: 1280, height: 720)
        format.frameRate = UInt(sceneView.preferredFramesPerSecond)
        format.pixelFormat = TVIPixelFormat.format32BGRA
        self.supportedFormats = []
        
        self.videoTrack = TVILocalVideoTrack.init(capturer: self)
        self.audioTrack = TVILocalAudioTrack.init()

        let options = TVIConnectOptions.init(token: accessToken, block: {(builder: TVIConnectOptionsBuilder) -> Void in
            builder.videoTracks = [self.videoTrack!]
            builder.audioTracks = [self.audioTrack!]
            builder.roomName = "Arkit"
        })

        // TODO: Implement basic delegate callbacks.
        self.room = TwilioVideo.connect(with: options, delegate: self)
    }
    
    @objc func displayLinkDidFire() {
        let snapshotDate = NSDate.init(timeIntervalSinceNow: 0)
        let myImage = self.sceneView.snapshot
        print("Downloading the snapshot took. \(snapshotDate.timeIntervalSinceNow * -1000) msec")

        // TODO: Don't log this all the time.
        print("\(NSStringFromCGSize(myImage().size))")

        let imageRef = myImage().cgImage

        // As a TVIVideoCapturer, we must deliver CVPixelBuffers and not CGImages to the consumer.
        if (imageRef == nil) {
            return
        }

        let date = NSDate.init(timeIntervalSinceNow: 0)
//        let pixelBuffer = self.copyPixelBufferFromCGImageContext(image: imageRef!)
        let pixelBuffer = self.copyPixelbufferFromCGImageProvider(image: imageRef!)
        print("Copying the pixel buffer took. \(date.timeIntervalSinceNow * -1000) msec")

        self.frame = TVIVideoFrame(timestamp: Int64((displayLink?.timestamp)! * 1000000),
                                   buffer: pixelBuffer,
                                   orientation: TVIVideoOrientation.up)
        self.consumer?.consumeCapturedFrame(self.frame!)
    }

    // Copying via CGContext drawing takes ~ 0.75 - 1.5 msec (iPhone 7 Plus)
    func copyPixelBufferFromCGImageContext(image: CGImage) -> CVPixelBuffer {
        let frameSize = CGSize(width: image.width, height: image.height)
        let options: [AnyHashable: Any]? = [kCVPixelBufferCGImageCompatibilityKey: false, kCVPixelBufferCGBitmapContextCompatibilityKey: false]
        var pixelBuffer: CVPixelBuffer? = nil
        let status: CVReturn? = CVPixelBufferCreate(kCFAllocatorDefault, Int(frameSize.width), Int(frameSize.height), kCVPixelFormatType_32BGRA, (options! as CFDictionary), &pixelBuffer)
        if status != kCVReturnSuccess {
            // TODO: Is this correct?
            return NSNull.self as! CVPixelBuffer
        }

        // Copy the content by drawing it into the CVPixelBuffer.
        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

        let data = CVPixelBufferGetBaseAddress(pixelBuffer!)
        let rgbColorSpace: CGColorSpace? = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: data, width: Int(frameSize.width), height: Int(frameSize.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace!, bitmapInfo: (CGImageAlphaInfo.noneSkipLast.rawValue))
        context?.draw(image, in: CGRect(x:0, y:0, width: image.width, height: image.height))

        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        return pixelBuffer!
    }

    // Copying the pixel buffer took. 0.026 - 0.042 msec
    func copyPixelbufferFromCGImageProvider(image: CGImage) -> CVPixelBuffer {
        let dataProvider: CGDataProvider? = image.dataProvider
        let data: CFData? = dataProvider?.data
        let baseAddress = CFDataGetBytePtr(data!)

        /*
         * We own the copied CFData which will back the CVPixelBuffer, thus the data's lifetime is bound to the buffer.
         * We will use a CVPixelBufferReleaseBytesCallback callback in order to release the CFData when the buffer dies.
         */
        let unmanagedData = Unmanaged<CFData>.passRetained(data!)
        var pixelBuffer: CVPixelBuffer? = nil
        let status = CVPixelBufferCreateWithBytes(nil,
                                                  image.width,
                                                  image.height,
                                                  TVIPixelFormat.format32BGRA.rawValue,
                                                  UnsafeMutableRawPointer( mutating: baseAddress!),
                                                  image.bytesPerRow,
                                                  { releaseContext, baseAddress in
                                                    let contextData = Unmanaged<CFData>.fromOpaque(releaseContext!)
                                                    contextData.release() },
                                                  unmanagedData.toOpaque(),
                                                  nil,
                                                  &pixelBuffer)

        if (status != kCVReturnSuccess) {
            return nil as CVPixelBuffer!;
        }

        return pixelBuffer!
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // TODO: Move the session starting to startCapture
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        
        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    // MARK: - ARSCNViewDelegate
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        print("didFailWithError \(error)")
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        print("interrupted")
        self.videoTrack?.isEnabled = false
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        print("interruption ended")
        self.videoTrack?.isEnabled = true
    }
}

// MARK: - TVIVideoCapturer

extension ViewController: TVIVideoCapturer {
    var isScreencast: Bool {
        // We want fluid AR content, maintaining the original frame rate.
        return false
    }

    func startCapture(_ format: TVIVideoFormat, consumer: TVIVideoCaptureConsumer) {
        self.consumer = consumer

        // Starting capture is a two step process. We need to schedule the DisplayLink timer, and start the ARSession.
        self.displayLink = CADisplayLink(target: self, selector: #selector(self.displayLinkDidFire))
        self.displayLink?.preferredFramesPerSecond = self.sceneView.preferredFramesPerSecond

        displayLink?.add(to: RunLoop.main, forMode: RunLoopMode.commonModes)
        consumer.captureDidStart(true)
    }

    func stopCapture() {
        self.consumer = nil
        self.displayLink?.invalidate()
        self.sceneView.session.pause()
    }
}
