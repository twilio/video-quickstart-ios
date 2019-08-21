//
//  ViewController.swift
//  ReplayKitExample
//
//  Copyright © 2018-2019 Twilio. All rights reserved.
//

import AVKit
import UIKit
import ReplayKit
import TwilioVideo

class ViewController: UIViewController {

    @IBOutlet weak var spinner: UIActivityIndicatorView!
    @IBOutlet weak var broadcastButton: UIButton!
    // Treat this view as generic, since RPSystemBroadcastPickerView is only available on iOS 12.0 and above.
    @IBOutlet weak var broadcastPickerView: UIView?
    @IBOutlet weak var conferenceButton: UIButton?
    @IBOutlet weak var infoLabel: UILabel?
    @IBOutlet weak var settingsButton: UIBarButtonItem?

    // Conference state.
    var screenTrack: LocalVideoTrack?
    var videoSource: ReplayKitVideoSource?
    var conferenceRoom: Room?

    // Broadcast state. Our extension will capture samples from ReplayKit, and publish them in a Room.
    var broadcastController: RPBroadcastController?

    var accessToken: String = "TWILIO_ACCESS_TOKEN"
    let tokenUrl = "http://127.0.0.1:5000/"

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

        self.navigationController?.navigationBar.barTintColor = UIColor(red: 226.0/255.0,
                                                                        green: 29.0/255.0,
                                                                        blue: 37.0/255.0,
                                                                        alpha: 1.0)
        self.navigationController?.navigationBar.tintColor = UIColor.white
        self.navigationController?.navigationBar.barStyle = UIBarStyle.black

        // The setter fires an availability changed event, but we check rather than rely on this implementation detail.
        RPScreenRecorder.shared().delegate = self
        checkRecordingAvailability()

        NotificationCenter.default.addObserver(forName: UIScreen.capturedDidChangeNotification, object: UIScreen.main, queue: OperationQueue.main) { (notification) in
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    @IBAction func pickDocument(_ sender: Any) {
        let documents = [AVFileType.mov.rawValue, AVFileType.mp4.rawValue, AVFileType.m4v.rawValue]
        let pickerVC = UIDocumentPickerViewController(documentTypes: documents, in: .`import`)
        pickerVC.delegate = self
        self.navigationController?.present(pickerVC, animated: true, completion: nil)
    }

    @available(iOS 12.0, *)
    func setupPickerView() {
        // Swap the button for an RPSystemBroadcastPickerView.
        #if !targetEnvironment(simulator)
        let pickerView = RPSystemBroadcastPickerView(frame: CGRect(x: 0,
                                                                   y: 0,
                                                                   width: view.bounds.width,
                                                                   height: 80))
        pickerView.translatesAutoresizingMaskIntoConstraints = false
        pickerView.preferredExtension = ViewController.kBroadcastExtensionBundleId

        // Theme the picker view to match the white that we want.
        if let button = pickerView.subviews.first as? UIButton {
            button.imageView?.tintColor = UIColor.white
        }

        view.addSubview(pickerView)

        self.broadcastPickerView = pickerView
        broadcastButton.isEnabled = false
        broadcastButton.titleEdgeInsets = UIEdgeInsets(top: 34, left: 0, bottom: 0, right: 0)

        let centerX = NSLayoutConstraint(item:pickerView,
                                         attribute: NSLayoutConstraint.Attribute.centerX,
                                         relatedBy: NSLayoutConstraint.Relation.equal,
                                         toItem: broadcastButton,
                                         attribute: NSLayoutConstraint.Attribute.centerX,
                                         multiplier: 1,
                                         constant: 0);
        self.view.addConstraint(centerX)
        let centerY = NSLayoutConstraint(item: pickerView,
                                         attribute: NSLayoutConstraint.Attribute.centerY,
                                         relatedBy: NSLayoutConstraint.Relation.equal,
                                         toItem: broadcastButton,
                                         attribute: NSLayoutConstraint.Attribute.centerY,
                                         multiplier: 1,
                                         constant: -10);
        self.view.addConstraint(centerY)
        let width = NSLayoutConstraint(item: pickerView,
                                       attribute: NSLayoutConstraint.Attribute.width,
                                       relatedBy: NSLayoutConstraint.Relation.equal,
                                       toItem: self.broadcastButton,
                                       attribute: NSLayoutConstraint.Attribute.width,
                                       multiplier: 1,
                                       constant: 0);
        self.view.addConstraint(width)
        let height = NSLayoutConstraint(item: pickerView,
                                        attribute: NSLayoutConstraint.Attribute.height,
                                        relatedBy: NSLayoutConstraint.Relation.equal,
                                        toItem: self.broadcastButton,
                                        attribute: NSLayoutConstraint.Attribute.height,
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

    // MARK:- Private
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
                    self.navigationItem.leftBarButtonItem = nil
                    self.conferenceButton?.isEnabled = true
                    self.infoLabel?.isHidden = false
                    if let picker = self.broadcastPickerView {
                        picker.isHidden = false
                        self.broadcastButton.isHidden = false
                    } else {
                        self.broadcastButton.isEnabled = true
                    }
                    self.spinner.stopAnimating()
                    self.broadcastButton.setTitle(ViewController.kStartBroadcastButtonTitle, for: UIControl.State.normal)
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
            room.state == .connected {
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
        videoSource = ReplayKitVideoSource(isScreencast: !ViewController.kDownscaleBuffers, inverseTelecine: false)

        screenTrack = LocalVideoTrack(source: videoSource!,
                                      enabled: true,
                                      name: "Screen")

        let videoCodec = Settings.shared.videoCodec ?? Vp8Codec()!
        let (encodingParams, outputFormat) = ReplayKitVideoSource.getParametersForUseCase(codec: videoCodec,
                                                                                          isScreencast: !ViewController.kDownscaleBuffers)
        videoSource?.requestOutputFormat(outputFormat)

        recorder.startCapture(handler: { (sampleBuffer, type, error) in
            if error != nil {
                print("Capture error: ", error as Any)
                return
            }

            switch type {
            case RPSampleBufferType.video:
                self.videoSource?.processFrame(sampleBuffer: sampleBuffer)
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
                    self.broadcastButton.setTitle(ViewController.kStartBroadcastButtonTitle, for: UIControl.State.normal)
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
                    self.connectToRoom(name: "conference", encodingParameters: encodingParams)

                    self.navigationItem.leftBarButtonItem =
                        UIBarButtonItem(title: "Play Video", style: .plain, target: self, action: #selector(self.pickDocument(_:)))
                }
            }
        }
    }

    func connectToRoom(name: String, encodingParameters: EncodingParameters) {
        // Configure access token either from server or manually.
        // If the default wasn't changed, try fetching from server.
        if (accessToken == "TWILIO_ACCESS_TOKEN" || accessToken.isEmpty) {
            do {
                accessToken = try TokenUtils.fetchToken(url: tokenUrl)
            } catch {
                stopConference(error: error)
                return
            }
        }

        // Preparing the connect options with the access token that we fetched (or hardcoded).
        let connectOptions = ConnectOptions(token: accessToken) { (builder) in

            builder.audioTracks = [LocalAudioTrack()!]

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
            builder.encodingParameters = encodingParameters

            // Use the preferred signaling region
            if let signalingRegion = Settings.shared.signalingRegion {
                builder.region = signalingRegion
            }

            if (!name.isEmpty) {
                builder.roomName = name
            }
        }

        // Connect to the Room using the options we provided.
        conferenceRoom = TwilioVideoSDK.connect(options: connectOptions, delegate: self)
    }
}

// MARK:- RPBroadcastActivityViewControllerDelegate
extension ViewController: RPBroadcastActivityViewControllerDelegate {
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
}

// MARK:- RPBroadcastControllerDelegate
extension ViewController: RPBroadcastControllerDelegate {
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
}

// MARK:- RPScreenRecorderDelegate
extension ViewController: RPScreenRecorderDelegate {
    func screenRecorderDidChangeAvailability(_ screenRecorder: RPScreenRecorder) {
        // Assume we will get an error raised if we are actively broadcasting / capturing and access is "stolen".
        if (self.broadcastController == nil && screenTrack == nil) {
            checkRecordingAvailability()
        }
    }
}

// MARK:- RoomDelegate
extension ViewController: RoomDelegate {
    func roomDidConnect(room: Room) {
        print("Connected to Room: ", room)
    }

    func roomDidFailToConnect(room: Room, error: Error) {
        stopConference(error: error)
        print("Failed to connect with error: ", error)
    }

    func roomDidDisconnect(room: Room, error: Error?) {
        if let error = error {
            print("Disconnected with error: ", error)
        } else {
            print("Disconnected from: \(room.name)")
        }

        if self.screenTrack != nil {
            stopConference(error: error)
        } else {
            conferenceRoom = nil
        }
    }

    func roomIsReconnecting(room: Room, error: Error) {
        print("Reconnecting to room \(room.name), error = \(String(describing: error))")
    }

    func roomDidReconnect(room: Room) {
        print("Reconnected to room \(room.name)")
    }
}

// MARK:- UIDocumentPickerDelegate
extension ViewController : UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            print("Ready to play: \(url)")
            let moviePlayer = AVPlayerViewController()
            moviePlayer.player = AVPlayer(url: url)
            moviePlayer.player?.play()
            moviePlayer.allowsPictureInPicturePlayback = false
            moviePlayer.entersFullScreenWhenPlaybackBegins = true
            moviePlayer.exitsFullScreenWhenPlaybackEnds = true
            self.navigationController?.pushViewController(moviePlayer, animated: true)
            self.navigationController?.setNavigationBarHidden(true, animated: true)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print("Document picker was cancelled.")
    }
}
