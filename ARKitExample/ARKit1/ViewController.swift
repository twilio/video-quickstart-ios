//
//  ViewController.swift
//  ARKit1
//
//  Created by Lizzie Siegle on 8/10/17.
//  Copyright © 2017 Lizzie Siegle. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import TwilioVideo

class ViewController: UIViewController, ARSCNViewDelegate {

    @IBOutlet var sceneView: ARSCNView!
    var accessToken = "ACCESS-TOKEN"
    var room: TVIRoom?
    weak var consumer: TVIVideoCaptureConsumer?
    var frame: TVIVideoFrame?
    var displayLink: CADisplayLink?
    var screencast: Bool?
    
    var supportedFormats = [TVIVideoFormat]()
    var videoTrack: TVILocalVideoTrack?
    var audioTrack: TVILocalAudioTrack?
    
    //    let ReleaseBytes: CVPixelBufferReleaseBytesCallback = { _, ptr in
    //        if let ptr = ptr {
    //            free(UnsafeMutableRawPointer(mutating: ptr))
    //        }
    //    }
    override func viewDidLoad() {
        super.viewDidLoad()
        // Set the view's delegate
        
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        self.screencast = false
        self.sceneView.preferredFramesPerSecond = 30
        self.sceneView.contentScaleFactor = 1
        
        // Create a new scene
        let scene = SCNScene(named: "art.scnassets/ship.scn")!
        
        
        
        // Set the scene to the view
        self.sceneView.scene = scene
        self.supportedFormats = [TVIVideoFormat()] //idk about init()
        
        sceneView.debugOptions =
            [ARSCNDebugOptions.showFeaturePoints, ARSCNDebugOptions.showWorldOrigin] //show feature points
        
        let capturer: TVIVideoCapturer = TVIScreenCapturer.init(view: self.sceneView!)
        self.videoTrack = TVILocalVideoTrack.init(capturer: capturer)
        self.audioTrack = TVILocalAudioTrack.init()
        let token = accessToken
        let options = TVIConnectOptions.init(token: token, block: {(builder: TVIConnectOptionsBuilder) -> Void in
            builder.videoTracks = [self.videoTrack!]
            builder.roomName = "Arkit"
            
        })
        self.room = TwilioVideo.connect(with: options, delegate: self as? TVIRoomDelegate)
    }
    
    func startCapture(format: TVIVideoFormat, consumer: TVIVideoCaptureConsumer) {
        self.consumer = consumer
        self.displayLink = CADisplayLink(target: self, selector: #selector(self.displayLinkDidFire))
        self.displayLink?.preferredFramesPerSecond = self.sceneView.preferredFramesPerSecond
        // Set to half of screen refresh, which should be 30fps.
        //[_displayLink set:30];
        displayLink?.add(to: RunLoop.main, forMode: RunLoopMode.commonModes)
        consumer.captureDidStart(true)
    }
    
    @objc func displayLinkDidFire() {
        let myImage = self.sceneView.snapshot
        print("\(NSStringFromCGSize(myImage().size))")
        let imageRef = myImage().cgImage!
        let pixelBuffer = self.pixelBufferFromCGImage1(fromCGImage1: imageRef)
        self.frame = TVIVideoFrame(timestamp: Int64((displayLink?.timestamp)! * 1000000), buffer: pixelBuffer, orientation: TVIVideoOrientation.up)
        self.consumer?.consumeCapturedFrame(self.frame!)
    }
    
    func pixelBufferFromCGImage1(fromCGImage1 image: CGImage) -> CVPixelBuffer {
        let frameSize = CGSize(width: image.width, height: image.height)
        let options: [AnyHashable: Any]? = [kCVPixelBufferCGImageCompatibilityKey: false, kCVPixelBufferCGBitmapContextCompatibilityKey: false]
        var pixelBuffer: CVPixelBuffer? = nil
        let status: CVReturn? = CVPixelBufferCreate(kCFAllocatorDefault, Int(frameSize.width), Int(frameSize.height), kCVPixelFormatType_32ARGB, (options! as CFDictionary), &pixelBuffer)
        if status != kCVReturnSuccess {
            return NSNull.self as! CVPixelBuffer
        }
        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let data = CVPixelBufferGetBaseAddress(pixelBuffer!)
        let rgbColorSpace: CGColorSpace? = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: data, width: Int(frameSize.width), height: Int(frameSize.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace!, bitmapInfo: (CGImageAlphaInfo.noneSkipLast.rawValue))
        context?.draw(image, in: CGRect(x:0, y:0, width: image.width, height: image.height))
        //CGContextRelease(context!)
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        return pixelBuffer!
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingSessionConfiguration() //need
        
        // Run the view's session
        sceneView.session.run(configuration) //need
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
    
    /*
     // Override to create and configure nodes for anchors added to the view's session.
     func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
     let node = SCNNode()
     
     return node
     }
     */
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        print("didFailWithError \(error)")
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        print("interrupted")
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        print("interruptionended")
        
    }
}

