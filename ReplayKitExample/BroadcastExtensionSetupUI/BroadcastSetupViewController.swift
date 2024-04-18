//
//  BroadcastSetupViewController.swift
//  BroadcastExtensionSetupUI
//
//  Copyright © 2018-2019 Twilio. All rights reserved.
//

import ReplayKit

class BroadcastSetupViewController: UIViewController {

    @IBOutlet weak var broadcastButton: UIButton!
    @IBOutlet weak var roomTextField: UITextField!

    @IBAction func broadcast(_ sender: Any) {
        userDidFinishSetup()
    }

    // Call this method when the user has finished interacting with the view controller and a broadcast stream can start
    func userDidFinishSetup() {
        // URL of the resource where broadcast can be viewed that will be returned to the application
        let broadcastURL = Bundle.main.url(forResource: "twilio_clound_com", withExtension: "mov")
        // Dictionary with setup information that will be provided to broadcast extension when broadcast is started

        let setupInfo: [String : NSCoding & NSObjectProtocol] = ["roomName": roomTextField.text! as NSCoding & NSObjectProtocol]
        
        // Tell ReplayKit that the extension is finished setting up and can begin broadcasting
        self.extensionContext?.completeRequest(withBroadcast: broadcastURL!, setupInfo: setupInfo)
    }
    
    func userDidCancelSetup() {
        let error = NSError(domain: "YouAppDomain", code: -1, userInfo: nil)
        // Tell ReplayKit that the extension was cancelled by the user
        self.extensionContext?.cancelRequest(withError: error)
    }
}
