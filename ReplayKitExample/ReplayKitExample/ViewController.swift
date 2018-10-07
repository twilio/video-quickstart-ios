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
    // Treat this view as generic, since RPSystemBroadcastPickerView is only available on iOS 12.0 and above.
    @IBOutlet weak var broadcastPickerView: UIView?
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
    let accessTokenUrl = "http://127.0.0.1:5000/"

    static let kBroadcastExtensionBundleId = "com.twilio.ReplayKitExample.BroadcastVideoExtension"
    static let kBroadcastExtensionSetupUiBundleId = "com.twilio.ReplayKitExample.BroadcastVideoExtensionSetupUI"

    static let kStartBroadcastButtonTitle = "Start Broadcast"
    static let kInProgressBroadcastButtonTitle = "Broadcasting"
    static let kStopBroadcastButtonTitle = "Stop Broadcast"
    static let kStartConferenceButtonTitle = "Start Conference"
    static let kStopConferenceButtonTitle = "Stop Conference"
    static let kRecordingAvailableInfo = "Ready to share the screen in a Broadcast (extension), or Conference (in-app)."
    static let kRecordingNotAvailableInfo = "ReplayKit is not available at the moment. Another app might be recording, or AirPlay may be in use."

    // An application has a much higher memory limit than an extension. You may choose to deliver full sized buffers instead.
    static let kDownscaleBuffers = false

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        broadcastButton.setTitle(ViewController.kStartBroadcastButtonTitle, for: .normal)
        conferenceButton?.setTitle(ViewController.kStartConferenceButtonTitle, for: .normal)
        broadcastButton.layer.cornerRadius = 4
        conferenceButton?.layer.cornerRadius = 4

        // The setter fires an availability changed event, but we check rather than rely on this implementation detail.
        RPScreenRecorder.shared().delegate = self
        checkRecordingAvailability()

        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIScreenCapturedDidChange, object: UIScreen.main, queue: OperationQueue.main) { (notification) in
            if self.broadcastPickerView != nil && self.screenTrack == nil {
                let isCaptured = UIScreen.main.isCaptured
                let title = isCaptured ? ViewController.kInProgressBroadcastButtonTitle : ViewController.kStartBroadcastButtonTitle
                self.broadcastButton.setTitle(title, for: .normal)
                self.conferenceButton?.isEnabled = !isCaptured
                isCaptured ? self.spinner.startAnimating() : self.spinner.stopAnimating()
            }
        }

        // Use RPSystemBroadcastPickerView when available (iOS 12+ devices).
        if #available(iOS 12.0, *) {
            setupPickerView()
        }
    }

    @available(iOS 12.0, *)
    func setupPickerView() {
        // Swap the button for an RPSystemBroadcastPickerView.
        // TODO: Use #if targetEnvironment(simulator) after upgrading the examples to Swift 4.2.
        #if arch(arm64)
        let pickerView = RPSystemBroadcastPickerView(frame: CGRect(x: 0,
                                                                   y: 0,
                                                                   width: view.bounds.width,
                                                                   height: 80))
        pickerView.translatesAutoresizingMaskIntoConstraints = false
        pickerView.preferredExtension = ViewController.kBroadcastExtensionBundleId
        view.addSubview(pickerView)

        self.broadcastPickerView = pickerView
        broadcastButton.isEnabled = false
        broadcastButton.titleEdgeInsets = UIEdgeInsets(top: 34, left: 0, bottom: 0, right: 0)

        let centerX = NSLayoutConstraint(item:pickerView,
                                         attribute: NSLayoutAttribute.centerX,
                                         relatedBy: NSLayoutRelation.equal,
                                         toItem: broadcastButton,
                                         attribute: NSLayoutAttribute.centerX,
                                         multiplier: 1,
                                         constant: 0);
        self.view.addConstraint(centerX)
        let centerY = NSLayoutConstraint(item: pickerView,
                                         attribute: NSLayoutAttribute.centerY,
                                         relatedBy: NSLayoutRelation.equal,
                                         toItem: broadcastButton,
                                         attribute: NSLayoutAttribute.centerY,
                                         multiplier: 1,
                                         constant: -10);
        self.view.addConstraint(centerY)
        let width = NSLayoutConstraint(item: pickerView,
                                       attribute: NSLayoutAttribute.width,
                                       relatedBy: NSLayoutRelation.equal,
                                       toItem: self.broadcastButton,
                                       attribute: NSLayoutAttribute.width,
                                       multiplier: 1,
                                       constant: 0);
        self.view.addConstraint(width)
        let height = NSLayoutConstraint(item: pickerView,
                                        attribute: NSLayoutAttribute.height,
                                        relatedBy: NSLayoutRelation.equal,
                                        toItem: self.broadcastButton,
                                        attribute: NSLayoutAttribute.height,
                                        multiplier: 1,
                                        constant: 0);
        self.view.addConstraint(height)
        #endif
    }

    // This action is only invoked on iOS 11.x. On iOS 12.0 this is handled by RPSystemBroadcastPickerView.
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
            // This extension should be the broadcast upload extension UI, not broadcast update extension
            RPBroadcastActivityViewController.load(withPreferredExtension:ViewController.kBroadcastExtensionSetupUiBundleId) {
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

    //MARK: RPBroadcastActivityViewControllerDelegate
    func broadcastActivityViewController(_ broadcastActivityViewController: RPBroadcastActivityViewController, didFinishWith broadcastController: RPBroadcastController?, error: Error?) {

        DispatchQueue.main.async {
            self.broadcastController = broadcastController
            self.broadcastController?.delegate = self
            self.conferenceButton?.isEnabled = false
            self.infoLabel?.text = ""

            broadcastActivityViewController.dismiss(animated: true) {
                self.startBroadcast()
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
            if let picker = self.broadcastPickerView {
                picker.isHidden = false
                self.broadcastButton.isHidden = false
            } else {
                self.broadcastButton.isEnabled = true
            }
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
        } else {
            conferenceRoom = nil
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

    func startBroadcast() {
        self.broadcastController?.startBroadcast { [unowned self] error in
            DispatchQueue.main.async {
                if let theError = error {
                    print("Broadcast controller failed to start with error:", theError as Any)
                } else {
                    print("Broadcast controller started.")
                    self.spinner.startAnimating()
                    self.broadcastButton.setTitle(ViewController.kStopBroadcastButtonTitle, for: .normal)
                }
            }
        }
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
                    if let picker = self.broadcastPickerView {
                        picker.isHidden = false
                        self.broadcastButton.isHidden = false
                    } else {
                        self.broadcastButton.isEnabled = true
                    }
                    self.spinner.stopAnimating()
                    self.broadcastButton.setTitle(ViewController.kStartBroadcastButtonTitle, for: UIControlState.normal)
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
        if let picker = self.broadcastPickerView {
            picker.isHidden = true
            broadcastButton.setTitle("", for: .normal)
            broadcastButton.isHidden = true
        }
        self.broadcastPickerView?.isHidden = true
        self.infoLabel?.isHidden = true
        self.infoLabel?.text = ""

        // Start recording the screen.
        let recorder = RPScreenRecorder.shared()
        recorder.isMicrophoneEnabled = false
        recorder.isCameraEnabled = false

        // Our source produces either downscaled buffers with smoother motion, or an HD screen recording.
        videoSource = ReplayKitVideoSource(isScreencast: !ViewController.kDownscaleBuffers)
        let constraints = TVIVideoConstraints.init { (builder) in
            if (ViewController.kDownscaleBuffers) {
                builder.maxSize = CMVideoDimensions(width: Int32(ReplayKitVideoSource.kDownScaledMaxWidthOrHeight),
                                                    height: Int32(ReplayKitVideoSource.kDownScaledMaxWidthOrHeight))
            } else {
                builder.minSize = CMVideoDimensions(width: Int32(ReplayKitVideoSource.kDownScaledMaxWidthOrHeight + 1),
                                                    height: Int32(ReplayKitVideoSource.kDownScaledMaxWidthOrHeight + 1))
                var screenSize = UIScreen.main.bounds.size
                screenSize.width *= UIScreen.main.nativeScale
                screenSize.height *= UIScreen.main.nativeScale
                builder.maxSize = CMVideoDimensions(width: Int32(screenSize.width),
                                                    height: Int32(screenSize.height))
            }
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
                // We use `TVIDefaultAudioDevice` to capture and playback audio for conferencing.
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
                    self.broadcastButton.setTitle(ViewController.kStartBroadcastButtonTitle, for: UIControlState.normal)
                    self.broadcastPickerView?.isHidden = false
                    self.broadcastButton.isHidden = false
                    self.conferenceButton?.setTitle(ViewController.kStartConferenceButtonTitle, for:.normal)
                    self.infoLabel?.isHidden = false
                    self.infoLabel?.text = error!.localizedDescription
                    self.videoSource = nil
                    self.screenTrack = nil
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
                stopConference(error: error)
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
