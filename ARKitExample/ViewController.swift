//
//  ViewController.swift
//  ARKitExample
//
//  Copyright © 2016-2019 Twilio, Inc. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import TwilioVideo

class ViewController: UIViewController {

    @IBOutlet var sceneView: ARSCNView!

    override var prefersStatusBarHidden: Bool {
        return true
    }

    // Configure access token for testing. Create one manually in the console
    // at https://www.twilio.com/console/video/runtime/testing-tools
    var accessToken = "TWILIO_ACCESS_TOKEN"
    var room: Room?
    weak var sink: VideoSink?
    var frame: VideoFrame?
    var displayLink: CADisplayLink?

    var videoTrack: LocalVideoTrack?
    var audioTrack: LocalAudioTrack?

    deinit {
        stop()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Configure the ARSCNView which will be used to display the AR content.
        sceneView.delegate = self

        // Since we will also capture from the view we will limit ourselves to 30 fps.
        sceneView.preferredFramesPerSecond = 30
        // Since we are in a streaming environment, we will render at a relatively low resolution.
        sceneView.contentScaleFactor = 1

        // Show feature points, and statistics such as fps and timing information
        sceneView.showsStatistics = true
        sceneView.debugOptions =
            [SCNDebugOptions.showFeaturePoints, SCNDebugOptions.showWorldOrigin]

        // Create a new scene, and bind it to the view.
        let scene = SCNScene(named: "art.scnassets/ship.scn")!
        sceneView.scene = scene

        self.videoTrack = LocalVideoTrack(source: self)

        let format = VideoFormat()
        format.frameRate = UInt(sceneView.preferredFramesPerSecond)
        format.pixelFormat = PixelFormat.format32BGRA
        format.dimensions = CMVideoDimensions(width: Int32(UIScreen.main.bounds.size.width),
                                              height: Int32(UIScreen.main.bounds.size.height))
        self.requestOutputFormat(format);
        start()

        self.audioTrack = LocalAudioTrack()

        let options = ConnectOptions(token: accessToken, block: { (builder) in
            if let videoTrack = self.videoTrack {
                builder.videoTracks = [videoTrack]
            }
            if let audioTrack = self.audioTrack {
                builder.audioTracks = [audioTrack]
            }
            builder.roomName = "arkit"
        })

        self.room = TwilioVideoSDK.connect(options: options, delegate: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return self.room != nil
    }

    @objc func displayLinkDidFire(timer: CADisplayLink) {
        // Our capturer polls the ARSCNView's snapshot for processed AR video content, and then copies the result into a CVPixelBuffer.
        // This process is not ideal, but it is the most straightforward way to capture the output of SceneKit.
        let myImage = self.sceneView.snapshot

        guard let imageRef = myImage().cgImage else {
            return
        }

        // A VideoSource must deliver CVPixelBuffers (and not CGImages) to a VideoSink.
        if let pixelBuffer = self.copyPixelbufferFromCGImageProvider(image: imageRef) {
            self.frame = VideoFrame(timeInterval: timer.timestamp,
                                    buffer: pixelBuffer,
                                    orientation: VideoOrientation.up)
            self.sink!.onVideoFrame(self.frame!)
        }
    }

    func start() {
        // Starting capture is a two step process. We need to start the ARSession and schedule the CADisplayLinkTimer.
        let configuration = ARWorldTrackingConfiguration()
        sceneView.session.run(configuration)

        self.displayLink = CADisplayLink(target: self, selector: #selector(self.displayLinkDidFire))
        self.displayLink?.preferredFramesPerSecond = self.sceneView.preferredFramesPerSecond

        displayLink?.add(to: RunLoop.main, forMode: RunLoop.Mode.common)
    }

    func stop() {
        self.sink = nil
        self.displayLink?.invalidate()
        self.sceneView.session.pause()
    }

    /**
     * Copying the pixel buffer took ~0.026 - 0.048 msec (iPhone 7 Plus).
     * This pretty fast but still wasteful, it would be nicer to wrap the CGImage and use its CGDataProvider directly.
     **/
    func copyPixelbufferFromCGImageProvider(image: CGImage) -> CVPixelBuffer? {
        let dataProvider: CGDataProvider? = image.dataProvider
        let data: CFData? = dataProvider?.data
        let baseAddress = CFDataGetBytePtr(data!)

        /**
         * We own the copied CFData which will back the CVPixelBuffer, thus the data's lifetime is bound to the buffer.
         * We will use a CVPixelBufferReleaseBytesCallback callback in order to release the CFData when the buffer dies.
         **/
        let unmanagedData = Unmanaged<CFData>.passRetained(data!)
        var pixelBuffer: CVPixelBuffer? = nil
        let status = CVPixelBufferCreateWithBytes(nil,
                                                  image.width,
                                                  image.height,
                                                  PixelFormat.format32BGRA.rawValue,
                                                  UnsafeMutableRawPointer( mutating: baseAddress!),
                                                  image.bytesPerRow,
                                                  { releaseContext, baseAddress in
                                                    let contextData = Unmanaged<CFData>.fromOpaque(releaseContext!)
                                                    contextData.release() },
                                                  unmanagedData.toOpaque(),
                                                  nil,
                                                  &pixelBuffer)

        if (status != kCVReturnSuccess) {
            return nil;
        }

        return pixelBuffer
    }
}

// MARK:- ARSCNViewDelegate
extension ViewController: ARSCNViewDelegate {
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

// MARK:- RoomDelegate
extension ViewController: RoomDelegate {
    func roomDidConnect(room: Room) {
        print("Connected to room \(room.name) as \(room.localParticipant?.identity ?? "")")
    }

    func roomDidFailToConnect(room: Room, error: Error) {
        print("Failed to connect to a Room: \(error).")

        let alertController = UIAlertController(title: "Connection Failed",
                                                message: "Couldn't connect to Room \(room.name). code:\(error._code) \(error.localizedDescription)",
                                                preferredStyle: UIAlertController.Style.alert)

        let cancelAction = UIAlertAction(title: "Okay", style: UIAlertAction.Style.default, handler: nil)
        alertController.addAction(cancelAction)

        self.present(alertController, animated: true) {
            self.room = nil
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    func roomDidDisconnect(room: Room, error: Error?) {
        if let error = error {
            print("Disconnected from the Room with an error:", error)
        } else {
            print("Disconnected from the Room.")
        }
        self.room = nil
        self.setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    func roomIsReconnecting(room: Room, error: Error) {
        print("Reconnecting to room \(room.name), error = \(String(describing: error))")
    }

    func roomDidReconnect(room: Room) {
        print("Reconnected to room \(room.name)")
    }

    func participantDidConnect(room: Room, participant: RemoteParticipant) {
        print("Participant \(participant.identity) connected to \(room.name).")
    }

    func participantDidDisconnect(room: Room, participant: RemoteParticipant) {
        print("Participant \(participant.identity) disconnected from \(room.name).")
    }
}

// MARK:- VideoSource
extension ViewController: VideoSource {
    var isScreencast: Bool {
        // We want fluid AR content, maintaining the original frame rate.
        return false
    }

    func requestOutputFormat(_ outputFormat: VideoFormat) {
        if let sink = sink {
            sink.onVideoFormatRequest(outputFormat)
        }
    }
}
