//
//  ViewController.swift
//  VirtualBackgroundExample
//
//  Copyright © 2025 Twilio, Inc. All rights reserved.
//

import UIKit

import TwilioVideo
import TwilioVirtualBackgroundProcessors

class ViewController: UIViewController {

    // MARK:- View Controller Members
    
    // Configure access token manually for testing, if desired! Create one manually in the console
    // at https://www.twilio.com/console/video/runtime/testing-tools
    var accessToken = "TWILIO_ACCESS_TOKEN"
  
    // Configure remote URL to fetch token from
    let tokenUrl = "http://localhost:8000/token.php"
    
    // Video SDK components
    var room: Room?
    var camera: CameraSource?
    var localVideoTrack: LocalVideoTrack?
    var localAudioTrack: LocalAudioTrack?
    var remoteParticipant: RemoteParticipant?
    var remoteView: VideoView?
    
    var backgroundProcessor: DefaultBackgroundProcessor?
    var backgroundImage: UIImage? = Settings.shared.backgroundImage
    
    // MARK:- UI Element Outlets and handles
    
    // `VideoView` created from a storyboard
    @IBOutlet weak var previewView: VideoView!

    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var roomTextField: UITextField!
    @IBOutlet weak var roomLine: UIView!
    @IBOutlet weak var roomLabel: UILabel!
    @IBOutlet weak var micButton: UIButton!
    
    deinit {
        // We are done with camera
        if let camera = self.camera {
            camera.stopCapture()
            self.camera = nil
        }
    }

    // MARK:- UIViewController
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "QuickStart"
        self.messageLabel.adjustsFontSizeToFitWidth = true;
        self.messageLabel.minimumScaleFactor = 0.75;

        if PlatformUtils.isSimulator {
            self.previewView.removeFromSuperview()
        }
        
        // Disconnect and mic button will be displayed when the Client is connected to a Room.
        self.disconnectButton.isHidden = true
        self.micButton.isHidden = true
        
        self.roomTextField.autocapitalizationType = .none
        self.roomTextField.delegate = self
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(ViewController.dismissKeyboard))
        self.view.addGestureRecognizer(tap)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.startPreview()
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return self.room != nil
    }
    
    func setupRemoteVideoView() {
        // Creating `VideoView` programmatically
        self.remoteView = VideoView(frame: CGRect.zero, delegate: self)

        self.view.insertSubview(self.remoteView!, at: 0)
        
        // `VideoView` supports scaleToFill, scaleAspectFill and scaleAspectFit
        // scaleAspectFit is the default mode when you create `VideoView` programmatically.
        self.remoteView!.contentMode = .scaleAspectFit;

        let centerX = NSLayoutConstraint(item: self.remoteView!,
                                         attribute: NSLayoutConstraint.Attribute.centerX,
                                         relatedBy: NSLayoutConstraint.Relation.equal,
                                         toItem: self.view,
                                         attribute: NSLayoutConstraint.Attribute.centerX,
                                         multiplier: 1,
                                         constant: 0);
        self.view.addConstraint(centerX)
        let centerY = NSLayoutConstraint(item: self.remoteView!,
                                         attribute: NSLayoutConstraint.Attribute.centerY,
                                         relatedBy: NSLayoutConstraint.Relation.equal,
                                         toItem: self.view,
                                         attribute: NSLayoutConstraint.Attribute.centerY,
                                         multiplier: 1,
                                         constant: 0);
        self.view.addConstraint(centerY)
        let width = NSLayoutConstraint(item: self.remoteView!,
                                       attribute: NSLayoutConstraint.Attribute.width,
                                       relatedBy: NSLayoutConstraint.Relation.equal,
                                       toItem: self.view,
                                       attribute: NSLayoutConstraint.Attribute.width,
                                       multiplier: 1,
                                       constant: 0);
        self.view.addConstraint(width)
        let height = NSLayoutConstraint(item: self.remoteView!,
                                        attribute: NSLayoutConstraint.Attribute.height,
                                        relatedBy: NSLayoutConstraint.Relation.equal,
                                        toItem: self.view,
                                        attribute: NSLayoutConstraint.Attribute.height,
                                        multiplier: 1,
                                        constant: 0);
        self.view.addConstraint(height)
    }
    
    func connectToARoom() {
        
        self.connectButton.isEnabled = true;
        
        // Preparing the connect options with the access token that we fetched (or hardcoded).
        let connectOptions = ConnectOptions(token: accessToken) { (builder) in
            
            // Use the local media that we prepared earlier.
            builder.audioTracks = self.localAudioTrack != nil ? [self.localAudioTrack!] : [LocalAudioTrack]()
            builder.videoTracks = self.localVideoTrack != nil ? [self.localVideoTrack!] : [LocalVideoTrack]()
            
            // Use the preferred audio codec
            if let preferredAudioCodec = Settings.shared.audioCodec {
                builder.preferredAudioCodecs = [preferredAudioCodec]
            }
            
            // Use Adpative Simulcast by setting builer.videoEncodingMode to .auto if preferredVideoCodec is .auto (default). The videoEncodingMode API is mutually exclusive with existing codec management APIs EncodingParameters.maxVideoBitrate and preferredVideoCodecs
            let preferredVideoCodec = Settings.shared.videoCodec
            if preferredVideoCodec == .auto {
                builder.videoEncodingMode = .auto
            } else if let codec = preferredVideoCodec.codec {
                builder.preferredVideoCodecs = [codec]
            }
            
            // Use the preferred encoding parameters
            if let encodingParameters = Settings.shared.getEncodingParameters() {
                builder.encodingParameters = encodingParameters
            }

            // Use the preferred signaling region
            if let signalingRegion = Settings.shared.signalingRegion {
                builder.region = signalingRegion
            }
            
            // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty
            // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
            builder.roomName = self.roomTextField.text
        }
        
        // Connect to the Room using the options we provided.
        room = TwilioVideoSDK.connect(options: connectOptions, delegate: self)
        
        logMessage(messageText: "Attempting to connect to room \(String(describing: self.roomTextField.text))")
        
        self.showRoomUI(inRoom: true)
        self.dismissKeyboard()
    }

    // MARK:- IBActions
    @IBAction func connect(sender: AnyObject) {
        self.connectButton.isEnabled = false;
        // Configure access token either from server or manually.
        // If the default wasn't changed, try fetching from server.
        if (accessToken == "TWILIO_ACCESS_TOKEN") {
            TokenUtils.fetchToken(from: tokenUrl) { [weak self]
                (token, error) in
                DispatchQueue.main.async {
                    if let error = error {
                        let message = "Failed to fetch access token:" + error.localizedDescription
                        self?.logMessage(messageText: message)
                        self?.connectButton.isEnabled = true;
                        return
                    }
                    self?.accessToken = token;
                    self?.connectToARoom()
                }
            }
        } else {
            self.connectToARoom()
        }
    }
    
    
    @IBAction func disconnect(sender: AnyObject) {
        self.room!.disconnect()
        logMessage(messageText: "Attempting to disconnect from room \(room!.name)")
    }
    
    @IBAction func toggleMic(sender: AnyObject) {
        if (self.localAudioTrack != nil) {
            self.localAudioTrack?.isEnabled = !(self.localAudioTrack?.isEnabled)!
            
            // Update the button title
            if (self.localAudioTrack?.isEnabled == true) {
                self.micButton.setTitle("Mute", for: .normal)
            } else {
                self.micButton.setTitle("Unmute", for: .normal)
            }
        }
    }

    // MARK:- Private
    func startPreview() {
        if PlatformUtils.isSimulator {
            return
        }

        let frontCamera = CameraSource.captureDevice(position: .front)
        let backCamera = CameraSource.captureDevice(position: .back)

        if (frontCamera != nil || backCamera != nil) {

            let options = CameraSourceOptions { (builder) in
                if #available(iOS 13.0, *) {
                    // Track UIWindowScene events for the key window's scene.
                    // The example app disables multi-window support in the .plist (see UIApplicationSceneManifestKey).
                    builder.orientationTracker = UserInterfaceTracker(scene: (UIApplication.shared.connectedScenes.first as? UIWindowScene)!)
                }
            }
            if let blurFilterRadius = Settings.shared.backgroundBlurRadius, blurFilterRadius.floatValue > 0 {
                backgroundProcessor = DefaultBackgroundProcessor(blurFilterRadius: blurFilterRadius)
                camera = CameraSource(options: options, delegate: self, backgroundProcessorDelegate: backgroundProcessor!)
                
                // Example of changing background processor property on the flight
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if let image = Settings.shared.backgroundImage {
                        self.backgroundProcessor?.backgroundImage = image
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    self.backgroundProcessor?.pauseProcessing = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
                    self.backgroundProcessor?.pauseProcessing = false
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                    self.backgroundProcessor?.blurFilterRadius = blurFilterRadius
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                    self.backgroundProcessor?.blurFilterRadius = 0.0
                }
            } else if let image = Settings.shared.backgroundImage {
                backgroundProcessor = DefaultBackgroundProcessor(backgroundImage: image)
                camera = CameraSource(options: options, delegate: self, backgroundProcessorDelegate: backgroundProcessor!)
            } else {
                camera = CameraSource(options: options, delegate: self)
            }

            localVideoTrack = LocalVideoTrack(source: camera!, enabled: true, name: "camera")

            // Add renderer to video track for local preview
            localVideoTrack!.addRenderer(self.previewView)
            logMessage(messageText: "Video track created")

            if (frontCamera != nil && backCamera != nil) {
                // We will flip camera on tap.
                let tap = UITapGestureRecognizer(target: self, action: #selector(ViewController.flipCamera))
                self.previewView.addGestureRecognizer(tap)
            }

            camera!.startCapture(device: frontCamera != nil ? frontCamera! : backCamera!) { (captureDevice, videoFormat, error) in
                if let error = error {
                    self.logMessage(messageText: "Capture failed with error.\ncode = \((error as NSError).code) error = \(error.localizedDescription)")
                } else {
                    self.previewView.shouldMirror = (captureDevice.position == .front)
                }
            }
        }
        else {
            self.logMessage(messageText:"No front or back capture device found!")
        }
    }

    @objc func flipCamera() {
        var newDevice: AVCaptureDevice?

        if let camera = self.camera, let captureDevice = camera.device {
            if captureDevice.position == .front {
                newDevice = CameraSource.captureDevice(position: .back)
            } else {
                newDevice = CameraSource.captureDevice(position: .front)
            }

            if let newDevice = newDevice {
                camera.selectCaptureDevice(newDevice) { (captureDevice, videoFormat, error) in
                    if let error = error {
                        self.logMessage(messageText: "Error selecting capture device.\ncode = \((error as NSError).code) error = \(error.localizedDescription)")
                    } else {
                        self.previewView.shouldMirror = (captureDevice.position == .front)
                    }
                }
            }
        }
    }

    func prepareLocalMedia() {

        // We will share local audio and video when we connect to the Room.

        // Create an audio track.
        if (localAudioTrack == nil) {
            localAudioTrack = LocalAudioTrack(options: nil, enabled: true, name: "Microphone")

            if (localAudioTrack == nil) {
                logMessage(messageText: "Failed to create audio track")
            }
        }

        // Create a video track which captures from the camera.
        if (localVideoTrack == nil) {
            self.startPreview()
        }
   }

    // Update our UI based upon if we are in a Room or not
    func showRoomUI(inRoom: Bool) {
        self.connectButton.isHidden = inRoom
        self.roomTextField.isHidden = inRoom
        self.roomLine.isHidden = inRoom
        self.roomLabel.isHidden = inRoom
        self.micButton.isHidden = !inRoom
        self.disconnectButton.isHidden = !inRoom
        self.navigationController?.setNavigationBarHidden(inRoom, animated: true)
        UIApplication.shared.isIdleTimerDisabled = inRoom

        // Show / hide the automatic home indicator on modern iPhones.
        self.setNeedsUpdateOfHomeIndicatorAutoHidden()
    }
    
    @objc func dismissKeyboard() {
        if (self.roomTextField.isFirstResponder) {
            self.roomTextField.resignFirstResponder()
        }
    }
    
    func logMessage(messageText: String) {
        NSLog(messageText)
        messageLabel.text = messageText
    }

    func renderRemoteParticipant(participant : RemoteParticipant) -> Bool {
        // This example renders the first subscribed RemoteVideoTrack from the RemoteParticipant.
        let videoPublications = participant.remoteVideoTracks
        for publication in videoPublications {
            if let subscribedVideoTrack = publication.remoteTrack,
                publication.isTrackSubscribed {
                setupRemoteVideoView()
                subscribedVideoTrack.addRenderer(self.remoteView!)
                self.remoteParticipant = participant
                return true
            }
        }
        return false
    }

    func renderRemoteParticipants(participants : Array<RemoteParticipant>) {
        for participant in participants {
            // Find the first renderable track.
            if participant.remoteVideoTracks.count > 0,
                renderRemoteParticipant(participant: participant) {
                break
            }
        }
    }

    func cleanupRemoteParticipant() {
        if self.remoteParticipant != nil {
            self.remoteView?.removeFromSuperview()
            self.remoteView = nil
            self.remoteParticipant = nil
        }
    }
}

// MARK:- UITextFieldDelegate
extension ViewController : UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.connect(sender: textField)
        return true
    }
}

// MARK:- RoomDelegate
extension ViewController : RoomDelegate {
    func roomDidConnect(room: Room) {
        logMessage(messageText: "Connected to room \(room.name) as \(room.localParticipant?.identity ?? "")")

        // This example only renders 1 RemoteVideoTrack at a time. Listen for all events to decide which track to render.
        for remoteParticipant in room.remoteParticipants {
            remoteParticipant.delegate = self
        }
    }

    func roomDidDisconnect(room: Room, error: Error?) {
        logMessage(messageText: "Disconnected from room \(room.name), error = \(String(describing: error))")
        
        self.cleanupRemoteParticipant()
        self.room = nil
        
        self.showRoomUI(inRoom: false)
    }

    func roomDidFailToConnect(room: Room, error: Error) {
        logMessage(messageText: "Failed to connect to room with error = \(String(describing: error))")
        self.room = nil
        
        self.showRoomUI(inRoom: false)
    }

    func roomIsReconnecting(room: Room, error: Error) {
        logMessage(messageText: "Reconnecting to room \(room.name), error = \(String(describing: error))")
    }

    func roomDidReconnect(room: Room) {
        logMessage(messageText: "Reconnected to room \(room.name)")
    }

    func participantDidConnect(room: Room, participant: RemoteParticipant) {
        // Listen for events from all Participants to decide which RemoteVideoTrack to render.
        participant.delegate = self

        logMessage(messageText: "Participant \(participant.identity) connected with \(participant.remoteAudioTracks.count) audio and \(participant.remoteVideoTracks.count) video tracks")
    }

    func participantDidDisconnect(room: Room, participant: RemoteParticipant) {
        logMessage(messageText: "Room \(room.name), Participant \(participant.identity) disconnected")

        // Nothing to do in this example. Subscription events are used to add/remove renderers.
    }
}

// MARK:- RemoteParticipantDelegate
extension ViewController : RemoteParticipantDelegate {

    func remoteParticipantDidPublishVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        // Remote Participant has offered to share the video Track.
        
        logMessage(messageText: "Participant \(participant.identity) published \(publication.trackName) video track")
    }

    func remoteParticipantDidUnpublishVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        // Remote Participant has stopped sharing the video Track.

        logMessage(messageText: "Participant \(participant.identity) unpublished \(publication.trackName) video track")
    }

    func remoteParticipantDidPublishAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        // Remote Participant has offered to share the audio Track.

        logMessage(messageText: "Participant \(participant.identity) published \(publication.trackName) audio track")
    }

    func remoteParticipantDidUnpublishAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        // Remote Participant has stopped sharing the audio Track.

        logMessage(messageText: "Participant \(participant.identity) unpublished \(publication.trackName) audio track")
    }

    func didSubscribeToVideoTrack(videoTrack: RemoteVideoTrack, publication: RemoteVideoTrackPublication, participant: RemoteParticipant) {
        // The LocalParticipant is subscribed to the RemoteParticipant's video Track. Frames will begin to arrive now.

        logMessage(messageText: "Subscribed to \(publication.trackName) video track for Participant \(participant.identity)")

        if (self.remoteParticipant == nil) {
            _ = renderRemoteParticipant(participant: participant)
        }
    }
    
    func didUnsubscribeFromVideoTrack(videoTrack: RemoteVideoTrack, publication: RemoteVideoTrackPublication, participant: RemoteParticipant) {
        // We are unsubscribed from the remote Participant's video Track. We will no longer receive the
        // remote Participant's video.
        
        logMessage(messageText: "Unsubscribed from \(publication.trackName) video track for Participant \(participant.identity)")

        if self.remoteParticipant == participant {
            cleanupRemoteParticipant()

            // Find another Participant video to render, if possible.
            if var remainingParticipants = room?.remoteParticipants,
                let index = remainingParticipants.firstIndex(of: participant) {
                remainingParticipants.remove(at: index)
                renderRemoteParticipants(participants: remainingParticipants)
            }
        }
    }

    func didSubscribeToAudioTrack(audioTrack: RemoteAudioTrack, publication: RemoteAudioTrackPublication, participant: RemoteParticipant) {
        // We are subscribed to the remote Participant's audio Track. We will start receiving the
        // remote Participant's audio now.
       
        logMessage(messageText: "Subscribed to \(publication.trackName) audio track for Participant \(participant.identity)")
    }
    
    func didUnsubscribeFromAudioTrack(audioTrack: RemoteAudioTrack, publication: RemoteAudioTrackPublication, participant: RemoteParticipant) {
        // We are unsubscribed from the remote Participant's audio Track. We will no longer receive the
        // remote Participant's audio.
        
        logMessage(messageText: "Unsubscribed from \(publication.trackName) audio track for Participant \(participant.identity)")
    }

    func remoteParticipantDidEnableVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) enabled \(publication.trackName) video track")
    }

    func remoteParticipantDidDisableVideoTrack(participant: RemoteParticipant, publication: RemoteVideoTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) disabled \(publication.trackName) video track")
    }

    func remoteParticipantDidEnableAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) enabled \(publication.trackName) audio track")
    }

    func remoteParticipantDidDisableAudioTrack(participant: RemoteParticipant, publication: RemoteAudioTrackPublication) {
        logMessage(messageText: "Participant \(participant.identity) disabled \(publication.trackName) audio track")
    }

    func didFailToSubscribeToAudioTrack(publication: RemoteAudioTrackPublication, error: Error, participant: RemoteParticipant) {
        logMessage(messageText: "FailedToSubscribe \(publication.trackName) audio track, error = \(String(describing: error))")
    }

    func didFailToSubscribeToVideoTrack(publication: RemoteVideoTrackPublication, error: Error, participant: RemoteParticipant) {
        logMessage(messageText: "FailedToSubscribe \(publication.trackName) video track, error = \(String(describing: error))")
    }
}

// MARK:- VideoViewDelegate
extension ViewController : VideoViewDelegate {
    func videoViewDimensionsDidChange(view: VideoView, dimensions: CMVideoDimensions) {
        self.view.setNeedsLayout()
    }
}

// MARK:- CameraSourceDelegate
extension ViewController : CameraSourceDelegate {
    func cameraSourceDidFail(source: CameraSource, error: Error) {
        logMessage(messageText: "Camera source failed with error: \(error.localizedDescription)")
    }
}
