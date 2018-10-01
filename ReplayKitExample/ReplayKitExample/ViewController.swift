//
//  ViewController.swift
//  ReplayKitExample
//
//  Copyright © 2018 Twilio. All rights reserved.
//

import UIKit
import ReplayKit
import TwilioVideo

class ViewController: UIViewController, RPBroadcastActivityViewControllerDelegate, RPBroadcastControllerDelegate {

    @IBOutlet weak var spinner: UIActivityIndicatorView!
    @IBOutlet weak var broadcastButton: UIButton!
    @IBOutlet weak var conferenceButton: UIButton?

    // Conference state.
    var screenTrack: TVILocalVideoTrack?
    var videoSource: ReplayKitVideoSource?
    var conferenceRoom: TVIRoom?

    static let kStartBroadcastButtonTitle = "Start Broadcast"
    static let kStopBroadcastButtonTitle = "Stop Broadcast"
    static let kStartConferenceButtonTitle = "Start Conference"
    static let kStopConferenceButtonTitle = "Stop Conference"

    var broadcasting:Bool = false

    var broadcastController: RPBroadcastController?

    override func viewDidLoad() {
        super.viewDidLoad()
        broadcastButton.setTitle(ViewController.kStartBroadcastButtonTitle, for: .normal)
        if #available(iOS 12.0, *) {
            let broadcastPickerView = RPSystemBroadcastPickerView(frame: CGRect(x: view.center.x-40,
                                                                                y: view.center.y-40,
                                                                                width: 80,
                                                                                height: 80))
            broadcastPickerView.preferredExtension = "com.twilio.ReplayKitExample.BroadcastVideoExtension"
            view.addSubview(broadcastPickerView)
            broadcastPickerView.backgroundColor = UIColor.red

            //TODO: get background image for picker view

            let label = UILabel(frame: CGRect(x: 0, y: 0,  width: 400, height: 80))
            label.textAlignment = .center
            label.text = "Click on the red square above to share screen."
            view.addSubview(label)
            label.center = CGPoint(x: broadcastPickerView.center.x, y: broadcastPickerView.center.y+80)

            broadcastButton.isHidden = true
            self.spinner.isHidden = true
        }
    }

    @IBAction func startBroadcast(_ sender: Any) {
        if (broadcasting) {
            broadcastController?.finishBroadcast { [unowned self] error in
                DispatchQueue.main.async {
                    self.spinner.stopAnimating()
                    self.broadcasting = false
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
        let recorder = RPScreenRecorder.shared()
        sender.isEnabled = false
        if self.screenTrack != nil {
            recorder.stopCapture { (error) in
                if let error = error {
                    print("Screen capture stop error: ", error as Any)
                } else {
                    print("Screen capture stopped.")
                    DispatchQueue.main.async {
                        sender.isEnabled = true
                        self.broadcastButton.isEnabled = true
                        self.spinner.stopAnimating()
                        self.conferenceButton?.setTitle(ViewController.kStartConferenceButtonTitle, for:.normal)

                        self.videoSource = nil
                        self.screenTrack = nil
                    }
                }
            }
        } else {
            self.broadcastButton.isEnabled = false

            // Start recording the screen.
            recorder.isMicrophoneEnabled = false
            recorder.isCameraEnabled = false
            videoSource = ReplayKitVideoSource()
            let constraints = TVIVideoConstraints.init { (builder) in
                builder.maxSize = CMVideoDimensions(width: Int32(ReplayKitVideoSource.kDownScaledMaxWidthOrHeight), height: Int32(ReplayKitVideoSource.kDownScaledMaxWidthOrHeight))
            }
            screenTrack = TVILocalVideoTrack(capturer: videoSource!,
                                             enabled: true,
                                             constraints: constraints,
                                             name: "Screen")

            recorder.startCapture(handler: { (sampleBuffer, type, error) in
                print("Process SampleBuffer: ", sampleBuffer)

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
                    sender.isEnabled = true
                    if error != nil {
                        self.broadcastButton.isEnabled = true
                    } else {
                        self.conferenceButton?.setTitle(ViewController.kStopConferenceButtonTitle, for:.normal)
                        self.spinner.startAnimating()
                    }
                }
            }
        }
    }

    //MARK: RPBroadcastActivityViewControllerDelegate
    func broadcastActivityViewController(_ broadcastActivityViewController: RPBroadcastActivityViewController, didFinishWith broadcastController: RPBroadcastController?, error: Error?) {

        DispatchQueue.main.async {
            self.broadcastController = broadcastController
            self.broadcastController?.delegate = self

            broadcastActivityViewController.dismiss(animated: true) {
                self.broadcastController?.startBroadcast { [unowned self] error in
                    // broadcast started
                    print("Broadcast controller started with error: \(String(describing: error))")
                    DispatchQueue.main.async {
                        self.broadcasting = true
                        self.spinner.startAnimating()
                        self.broadcastButton.setTitle(ViewController.kStopBroadcastButtonTitle, for: .normal)
                    }
                }
            }
        }
    }

    //MARK: RPBroadcastControllerDelegate
    func broadcastController(_ broadcastController: RPBroadcastController, didFinishWithError error: Error?) {
        print("broadcast did finish with error: \(String(describing: error))")
    }

    func broadcastController(_ broadcastController: RPBroadcastController, didUpdateServiceInfo serviceInfo: [String : NSCoding & NSObjectProtocol]) {
        print("broadcast did update service info: \(serviceInfo)")
    }

    func broadcastController(_ broadcastController: RPBroadcastController, didUpdateBroadcast broadcastURL: URL) {
        print("broadcast did update URL: \(broadcastURL)")
    }
}
