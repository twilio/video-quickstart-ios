//
//  ViewController.swift
//  ReplayKitExample
//
//  Copyright © 2018 Twilio. All rights reserved.
//

import UIKit
import ReplayKit

class ViewController: UIViewController, RPBroadcastActivityViewControllerDelegate, RPBroadcastControllerDelegate {

    @IBOutlet weak var spinner: UIActivityIndicatorView!
    @IBOutlet weak var broadcastButton: UIButton!

    static let kStartBroadcastButtonTitle = "Start Broadcast"
    static let kStopBroadcastButtonTitle = "Stop Broadcast"

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
        RPScreenRecorder.shared().isMicrophoneEnabled = true
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
