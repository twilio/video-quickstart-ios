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

    var broadcastController: RPBroadcastController?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        if #available(iOS 11.0, *) {
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
        } else {
            // Fallback on earlier versions
            RPBroadcastActivityViewController.load { broadcastActivityViewController, error in
                if let broadcastActivityViewController = broadcastActivityViewController {
                    broadcastActivityViewController.delegate = self

                    broadcastActivityViewController.modalPresentationStyle = .popover
                    self.present(broadcastActivityViewController, animated: true)
                }
            }
        }
    }


    //MARK: RPBroadcastActivityViewControllerDelegate {
    func broadcastActivityViewController(_ broadcastActivityViewController: RPBroadcastActivityViewController, didFinishWith broadcastController: RPBroadcastController?, error: Error?) {
        self.broadcastController = broadcastController
        self.broadcastController?.delegate = self
        broadcastActivityViewController.dismiss(animated: true) {
            self.broadcastController?.startBroadcast { [unowned self] error in
                // broadcast started
                print("broadcast started with error: \(String(describing: error))")
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
