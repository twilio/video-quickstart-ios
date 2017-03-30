//
//  ViewController+SimulateIncomingCall.swift
//  VideoCallKitQuickStart
//
//  Copyright © 2016-2017 Twilio, Inc. All rights reserved.
//

import UIKit

// MARK: Simulate Incoming Call
extension ViewController {

    @IBAction func simulateIncomingCall(sender: AnyObject) {

        let alertController = UIAlertController(title: "Simulate Incoming Call", message: nil, preferredStyle: .alert)

        let okAction = UIAlertAction(title: "OK", style: .default, handler: { alert -> Void in

            let roomNameTextField = alertController.textFields![0] as UITextField
            let delayTextField = alertController.textFields![1] as UITextField

            let roomName = roomNameTextField.text
            self.roomTextField.text = roomName

            var delay = 5.0
            if let delayString = delayTextField.text, let delayFromString = Double(delayString) {
                delay = delayFromString
            }

            self.logMessage(messageText: "Simulating Incoming Call for room: \(String(describing: roomName)) after a \(delay) second delay")

            let backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
            DispatchQueue.main.asyncAfter(wallDeadline: DispatchWallTime.now() + delay) {
                self.reportIncomingCall(uuid: UUID(), roomName: self.roomTextField.text) { _ in
                    UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
                }
            }
        })

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: {
            (action : UIAlertAction!) -> Void in
        })

        alertController.addTextField  { (textField : UITextField!) -> Void in
            textField.placeholder = "Room Name"
        }

        alertController.addTextField  { (textField : UITextField!) -> Void in
            textField.placeholder = "Delay in seconds (defaults is 5)"
        }

        alertController.addAction(okAction)
        alertController.addAction(cancelAction)
        
        self.present(alertController, animated: true, completion: nil)
    }
}
