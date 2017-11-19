//
//  SKViewController.swift
//  ARVideoKit-Example
//
//  Created by Ahmed Bekhit on 11/2/17.
//  Copyright © 2017 Ahmed Fathi Bekhit. All rights reserved.
//

import UIKit
import ARKit
import ARVideoKit
import TwilioVideo

class SKViewController: UIViewController, ARSKViewDelegate  {
    
    @IBOutlet var SKSceneView: ARSKView!
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    var isStreamingVideo:Bool = false
    
    // ARVideKit
    var recorder:RecordAR?

    // TwilioVideo
    // Configure access token for testing. Create one manually in the console
    // at https://www.twilio.com/console/video/runtime/testing-tools
    var accessToken = "TWILIO_ACCESS_TOKEN"
    var room: TVIRoom?
    weak var consumer: TVIVideoCaptureConsumer?
    var frame: TVIVideoFrame?
    
    var videoTrack: TVILocalVideoTrack?
    var audioTrack: TVILocalAudioTrack?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        SKSceneView.delegate = self
        
        // Show statistics such as fps and node count
        SKSceneView.showsFPS = true
        SKSceneView.showsNodeCount = true
        
        // Load the SKScene from 'Scene.sks'
        if let scene = SKScene(fileNamed: "Scene") {
            SKSceneView.presentScene(scene)
        }
        
        /*----👇---- ARVideoKit Configuration ----👇----*/

        // Initialize ARVideoKit recorder
        recorder = RecordAR(ARSpriteKit: SKSceneView)
        // Set the renderer's delegate to retrieve the rendered buffers
        recorder?.renderAR = self
        // Enable rendering pre-recording (to push buffers to TwilioVideo)
        recorder?.onlyRenderWhileRecording = false
        // Set frames per second rate
        recorder?.fps = .fps30
        
        
        /*----👇---- TwilioVideo Configuration ----👇----*/

        self.videoTrack = TVILocalVideoTrack.init(capturer: self)
        self.audioTrack = TVILocalAudioTrack.init()
        
        let options = TVIConnectOptions.init(token: accessToken, block: {(builder: TVIConnectOptionsBuilder) -> Void in
            if let videoTrack = self.videoTrack {
                builder.videoTracks = [videoTrack]
            }
            if let audioTrack = self.audioTrack {
                builder.audioTracks = [audioTrack]
            }
            builder.roomName = "arkit"
        })
        
        self.room = TwilioVideo.connect(with: options, delegate: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        
        // Run the view's session
        SKSceneView.session.run(configuration)
        
        // Prepare the recorder with sessions configuration
        recorder?.prepare(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        SKSceneView.session.pause()
        
        recorder?.onlyRenderWhileRecording = true
        recorder?.prepare(ARWorldTrackingConfiguration())
        
        // Switch off the orientation lock for UIViewControllers with AR Scenes
        recorder?.rest()

    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func goBack(_ sender: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }
}

//MARK: - ARVideoKit Renderer Method
extension SKViewController: RenderARDelegate {
    func frame(didRender buffer: CVPixelBuffer, with time: CMTime, using rawBuffer: CVPixelBuffer) {
        if isStreamingVideo {
            self.frame = TVIVideoFrame(timestamp: Int64(CMTimeGetSeconds(time)),
                                       buffer: buffer,
                                       orientation: TVIVideoOrientation.up)
            self.consumer?.consumeCapturedFrame(self.frame!)
        }
    }
}

// MARK: - TVIRoomDelegate
extension SKViewController: TVIRoomDelegate {
    func didConnect(to room: TVIRoom) {
        print("Connected to Room /(room.name).")
    }
    
    func room(_ room: TVIRoom, didFailToConnectWithError error: Error) {
        print("Failed to connect to a Room: \(error).")
        
        let alertController = UIAlertController.init(title: "Connection Failed",
                                                     message: "Couldn't connect to Room \(room.name). code:\(error._code) \(error.localizedDescription)",
            preferredStyle: UIAlertControllerStyle.alert)
        
        let cancelAction = UIAlertAction.init(title: "Okay", style: UIAlertActionStyle.default, handler: nil)
        alertController.addAction(cancelAction)
        
        self.present(alertController, animated: true, completion: nil)
    }
    
    func room(_ room: TVIRoom, participantDidConnect participant: TVIParticipant) {
        print("Participant \(participant.identity) connected to \(room.name).")
    }
    
    func room(_ room: TVIRoom, participantDidDisconnect participant: TVIParticipant) {
        print("Participant \(participant.identity) disconnected from \(room.name).")
    }
}

// MARK: - TVIVideoCapturer
extension SKViewController: TVIVideoCapturer {
    var isScreencast: Bool {
        // We want fluid AR content, maintaining the original frame rate.
        return false
    }
    
    var supportedFormats: [TVIVideoFormat] {
        // We only support the single capture format that ARSession provides, and we rasterize the AR scene at 1x.
        // Don't set any specific capture dimensions.
        let format = TVIVideoFormat.init()
        format.frameRate = 30
        format.pixelFormat = TVIPixelFormat.format32BGRA
        return [format]
    }
    
    func startCapture(_ format: TVIVideoFormat, consumer: TVIVideoCaptureConsumer) {
        self.consumer = consumer
        self.isStreamingVideo = true
        consumer.captureDidStart(true)
    }
    
    func stopCapture() {
        self.consumer = nil
        self.isStreamingVideo = false
    }
}

// MARK: - ARSKView Delegate Methods
extension SKViewController {
    var randoMoji:String {
        let emojis = ["👾", "🤓", "🔥", "😜", "😇", "🤣", "🤗"]
        return emojis[Int(arc4random_uniform(UInt32(emojis.count)))]
    }
    
    func view(_ view: ARSKView, nodeFor anchor: ARAnchor) -> SKNode? {
        // Create and configure a node for the anchor added to the view's session.
        let labelNode = SKLabelNode(text: randoMoji)
        labelNode.horizontalAlignmentMode = .center
        labelNode.verticalAlignmentMode = .center
        return labelNode;
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        print("didFailWithError \(error)")
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        print("ARSession was interrupted, disabling the VideoTrack.")
        self.videoTrack?.isEnabled = false
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        print("ARSession interruption ended, enabling the VideoTrack.")
        self.videoTrack?.isEnabled = true
    }
}
