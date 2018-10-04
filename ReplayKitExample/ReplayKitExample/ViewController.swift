//
//  ViewController.swift
//  ReplayKitExample
//
//  Copyright © 2018 Twilio. All rights reserved.
//

import UIKit
import ReplayKit
import TwilioVideo

class ViewController: UIViewController, RPBroadcastActivityViewControllerDelegate, RPBroadcastControllerDelegate, RPScreenRecorderDelegate, TVIRoomDelegate {

    @IBOutlet weak var spinner: UIActivityIndicatorView!
    @IBOutlet weak var broadcastButton: UIButton!
    @IBOutlet weak var conferenceButton: UIButton?
    @IBOutlet weak var infoLabel: UILabel?
    @IBOutlet weak var settingsButton: UIBarButtonItem?

    // Conference state.
    var screenTrack: TVILocalVideoTrack?
    var videoSource: ReplayKitVideoSource?
    var conferenceRoom: TVIRoom?

    // Broadcast state. Our extension will capture samples from ReplayKit, and publish them in a Room.
    var broadcastController: RPBroadcastController?

    var accessToken: String = "TWILIO_ACCESS_TOKEN"
    let accessTokenUrl = "http://127.0.0.1:5000/?identity=chris.ios&room=chris"

    static let kStartBroadcastButtonTitle = "Start Broadcast"
    static let kStopBroadcastButtonTitle = "Stop Broadcast"
    static let kStartConferenceButtonTitle = "Start Conference"
    static let kStopConferenceButtonTitle = "Stop Conference"
    static let kRecordingAvailableInfo = "Ready to share the screen in a Broadcast (extension), or Conference (in-app)."
    static let kRecordingNotAvailableInfo = "ReplayKit is not available at the moment. Another app might be recording, or AirPlay may be in use."

    override func viewDidLoad() {
        super.viewDidLoad()
        broadcastButton.setTitle(ViewController.kStartBroadcastButtonTitle, for: .normal)
        conferenceButton?.setTitle(ViewController.kStartConferenceButtonTitle, for: .normal)
        // The setter fires an availability changed event, but we check rather than rely on this implementation detail.
        RPScreenRecorder.shared().delegate = self
        checkRecordingAvailability()

        // Use RPSystemBroadcastPickerView when available (iOS 12+ devices).
        #if arch(arm64)
        if #available(iOS 12.0, *) {
            // Swap the button for an RPSystemBroadcastPickerView.
            let broadcastPickerView = RPSystemBroadcastPickerView(frame: CGRect(x: view.center.x-40,
                                                                                y: view.center.y-40,
                                                                                width: 80,
                                                                                height: 80))
            broadcastPickerView.preferredExtension = "com.twilio.ReplayKitExample.BroadcastVideoExtension"
            view.addSubview(broadcastPickerView)

            // TODO: get background image for picker view
            broadcastPickerView.backgroundColor = UIColor.red
            broadcastButton.isHidden = true
        }
        #endif
    }

    @IBAction func startBroadcast(_ sender: Any) {
        if let controller = self.broadcastController {
            controller.finishBroadcast { [unowned self] error in
                DispatchQueue.main.async {
                    self.spinner.stopAnimating()
                    self.broadcastController = nil
                    self.broadcastButton.setTitle(ViewController.kStartBroadcastButtonTitle, for: .normal)
                }
            }
        } else {
            RPScreenRecorder.shared().isMicrophoneEnabled = true
            // This extension should be the broadcast upload extension UI, not boradcast update extension
            RPBroadcastActivityViewController.load(withPreferredExtension:
            "com.twilio.ReplayKitExample.BroadcastVideoExtensionSetupUI") {
                (broadcastActivityViewController, error) in
                if let broadcastActivityViewController = broadcastActivityViewController {
                    broadcastActivityViewController.delegate = self
                    broadcastActivityViewController.modalPresentationStyle = .popover
                    self.present(broadcastActivityViewController, animated: true)
                }
            }
        }
    }

    @IBAction func startConference( sender: UIButton) {
        sender.isEnabled = false
        if self.screenTrack != nil {
            stopConference(error: nil)
        } else {
            startConference()
        }
    }

    @IBAction func pauseOrResumeBroadcast( sender: UIButton) {
        if let controller = broadcastController {
            if (controller.isPaused) {
                controller.resumeBroadcast()
            } else {
                controller.pauseBroadcast()
            }
        }
    }

    //MARK: RPBroadcastActivityViewControllerDelegate
    func broadcastActivityViewController(_ broadcastActivityViewController: RPBroadcastActivityViewController, didFinishWith broadcastController: RPBroadcastController?, error: Error?) {

        DispatchQueue.main.async {
            self.broadcastController = broadcastController
            self.broadcastController?.delegate = self
            self.conferenceButton?.isEnabled = false

            broadcastActivityViewController.dismiss(animated: true) {
                self.broadcastController?.startBroadcast { [unowned self] error in
                    // broadcast started
                    print("Broadcast controller started with error: \(String(describing: error))")
                    DispatchQueue.main.async {
                        self.spinner.startAnimating()
                        self.broadcastButton.setTitle(ViewController.kStopBroadcastButtonTitle, for: .normal)
                    }
                }
            }
        }
    }

    //MARK: RPBroadcastControllerDelegate
    func broadcastController(_ broadcastController: RPBroadcastController, didFinishWithError error: Error?) {
        // Update the button UI.
        DispatchQueue.main.async {
            self.broadcastController = nil
            self.conferenceButton?.isEnabled = true
            self.infoLabel?.isHidden = false
            self.broadcastButton.isEnabled = true
            self.broadcastButton.setTitle(ViewController.kStartBroadcastButtonTitle, for: .normal)
            self.spinner?.stopAnimating()

            if let theError = error {
                print("Broadcast did finish with error:", error as Any)
                self.infoLabel?.text = theError.localizedDescription
            } else {
                print("Broadcast did finish.")
            }
        }
    }

    func broadcastController(_ broadcastController: RPBroadcastController, didUpdateServiceInfo serviceInfo: [String : NSCoding & NSObjectProtocol]) {
        print("Broadcast did update service info: \(serviceInfo)")
    }

    func broadcastController(_ broadcastController: RPBroadcastController, didUpdateBroadcast broadcastURL: URL) {
        print("Broadcast did update URL: \(broadcastURL)")
    }

    //MARK: TVIRoomDelegate
    func didConnect(to room: TVIRoom) {
        print("Connected to Room: ", room)
    }

    func room(_ room: TVIRoom, didFailToConnectWithError error: Error) {
        stopConference(error: error)
        print("Failed to connect with error: ", error)
    }

    func room(_ room: TVIRoom, didDisconnectWithError error: Error?) {
        if let error = error {
            print("Disconnected with error: ", error)
        }

        if self.screenTrack != nil {
            stopConference(error: error)
        }
    }

    //MARK: RPScreenRecorderDelegate
    func screenRecorderDidChangeAvailability(_ screenRecorder: RPScreenRecorder) {
        // Assume we will get an error raised if we are actively broadcasting / capturing and access is "stolen".
        if (self.broadcastController == nil && screenTrack == nil) {
            checkRecordingAvailability()
        }
    }

    //MARK: Private
    func checkRecordingAvailability() {
        let isScreenRecordingAvailable = RPScreenRecorder.shared().isAvailable
        broadcastButton.isHidden = !isScreenRecordingAvailable
        conferenceButton?.isHidden = !isScreenRecordingAvailable
        infoLabel?.text = isScreenRecordingAvailable ? ViewController.kRecordingAvailableInfo : ViewController.kRecordingNotAvailableInfo
    }

    func stopConference(error: Error?) {
        // Stop recording the screen.
        let recorder = RPScreenRecorder.shared()
        recorder.stopCapture { (captureError) in
            if let error = captureError {
                print("Screen capture stop error: ", error as Any)
            } else {
                print("Screen capture stopped.")
                DispatchQueue.main.async {
                    self.conferenceButton?.isEnabled = true
                    self.infoLabel?.isHidden = false
                    self.broadcastButton.isEnabled = true
                    self.spinner.stopAnimating()
                    self.conferenceButton?.setTitle(ViewController.kStartConferenceButtonTitle, for:.normal)

                    self.videoSource = nil
                    self.screenTrack = nil

                    if let userError = error {
                        self.infoLabel?.text = userError.localizedDescription
                    }
                }
            }
        }

        if let room = conferenceRoom,
            room.state == TVIRoomState.connected {
            room.disconnect()
        } else {
            conferenceRoom = nil
        }
    }

    func startConference() {
        self.broadcastButton.isEnabled = false
        self.infoLabel?.isHidden = true

        // Start recording the screen.
        let recorder = RPScreenRecorder.shared()
        recorder.isMicrophoneEnabled = false
        recorder.isCameraEnabled = false
        videoSource = ReplayKitVideoSource()
        let constraints = TVIVideoConstraints.init { (builder) in
            builder.maxSize = CMVideoDimensions(width: Int32(ReplayKitVideoSource.kDownScaledMaxWidthOrHeight),
                                                height: Int32(ReplayKitVideoSource.kDownScaledMaxWidthOrHeight))
        }
        screenTrack = TVILocalVideoTrack(capturer: videoSource!,
                                         enabled: true,
                                         constraints: constraints,
                                         name: "Screen")

        recorder.startCapture(handler: { (sampleBuffer, type, error) in
            if error != nil {
                print("Capture error: ", error as Any)
                return
            }

            switch type {
            case RPSampleBufferType.video:
                self.videoSource?.processVideoSampleBuffer(sampleBuffer)
                break
            case RPSampleBufferType.audioApp:
                break
            case RPSampleBufferType.audioMic:
                break
            }

        }) { (error) in
            if error != nil {
                print("Screen capture error: ", error as Any)
            } else {
                print("Screen capture started.")
            }
            DispatchQueue.main.async {
                self.conferenceButton?.isEnabled = true
                if error != nil {
                    self.broadcastButton.isEnabled = true
                    self.infoLabel?.isHidden = false
                } else {
                    self.conferenceButton?.setTitle(ViewController.kStopConferenceButtonTitle, for:.normal)
                    self.spinner.startAnimating()
                    self.infoLabel?.isHidden = true
                    self.connectToRoom(name: "")
                }
            }
        }
    }

    func connectToRoom(name: String) {
        // Configure access token either from server or manually.
        // If the default wasn't changed, try fetching from server.
        if (accessToken == "TWILIO_ACCESS_TOKEN" || accessToken.isEmpty) {
            do {
                accessToken = try TokenUtils.fetchToken(url: accessTokenUrl)
            } catch {
                let message = "Failed to fetch access token."
                print(message)
                return
            }
        }

        // Preparing the connect options with the access token that we fetched (or hardcoded).
        let connectOptions = TVIConnectOptions.init(token: accessToken) { (builder) in

            builder.audioTracks = [TVILocalAudioTrack()!]

            if let videoTrack = self.screenTrack {
                builder.videoTracks = [videoTrack]
            }

            // Use the preferred codecs
            if let preferredAudioCodec = Settings.shared.audioCodec {
                builder.preferredAudioCodecs = [preferredAudioCodec]
            }
            if let preferredVideoCodec = Settings.shared.videoCodec {
                builder.preferredVideoCodecs = [preferredVideoCodec]
            }

            // Use the preferred encoding parameters
            if let encodingParameters = Settings.shared.getEncodingParameters() {
                builder.encodingParameters = encodingParameters
            }

            if (!name.isEmpty) {
                builder.roomName = name
            }
        }

        // Connect to the Room using the options we provided.
        conferenceRoom = TwilioVideo.connect(with: connectOptions, delegate: self)
    }
}
