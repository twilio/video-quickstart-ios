//
//  ViewController.swift
//  ReplayKitExample
//
//  Created by Piyush Tank on 7/1/18.
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
            let broadcastPickerView = RPBroadcastPickerView(frame: broadcastButton.frame)
            broadcastPickerView.preferredExtension = "com.twilio.ReplayKitExample.BroadcastVideoExtension"
            view.addSubview(broadcastPickerView)
            broadcastPickerView.backgroundColor = UIColor.red
            broadcastButton.isHidden = true
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

        self.broadcastController = broadcastController
        self.broadcastController?.delegate = self

        broadcastActivityViewController.dismiss(animated: true) {
            self.broadcastController?.startBroadcast { [unowned self] error in
                // broadcast started
                print("broadcast started with error: \(String(describing: error))")
                self.broadcasting = true
                DispatchQueue.main.async {
                    self.spinner.startAnimating()
                    self.broadcastButton.setTitle(ViewController.kStopBroadcastButtonTitle, for: .normal)
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
