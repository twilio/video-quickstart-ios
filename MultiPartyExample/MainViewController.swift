//
//  MainViewController.swift
//  MultiPartyExample
//
//  Copyright © 2019 Twilio, Inc. All rights reserved.
//

import UIKit
import TwilioVideo

class MainViewController: UIViewController {

    // MARK: View Controller Members

    // Configure access token manually for testing, if desired! Create one manually in the console
    // at https://www.twilio.com/console/video/runtime/testing-tools
    var accessToken = "TWILIO_ACCESS_TOKEN"

    // Configure remote URL to fetch token from
    var tokenUrl = "http://localhost:8000/token.php"

    // MARK: UI Element Outlets and handles
    @IBOutlet weak var connectButton: UIButton?
    @IBOutlet weak var roomTextField: UITextField?
    @IBOutlet weak var roomLine: UIView?
    @IBOutlet weak var roomLabel: UILabel?
    @IBOutlet weak var messageLabel: UILabel?

    // MARK: UIViewController
    override func viewDidLoad() {
        super.viewDidLoad()

        messageLabel?.adjustsFontSizeToFitWidth = true
        messageLabel?.minimumScaleFactor = 0.75
        connectButton?.layer.cornerRadius = 4

        let tap = UITapGestureRecognizer(target: self, action: #selector(MainViewController.dismissKeyboard))
        view.addGestureRecognizer(tap)

        logMessage(messageText: "Twilio Video v\(TwilioVideo.version())")
        roomTextField?.becomeFirstResponder()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        roomTextField?.text = ""
        logMessage(messageText: "Twilio Video v\(TwilioVideo.version())")
    }

    @objc func dismissKeyboard() {
        if let textField = self.roomTextField,
            textField.isFirstResponder {
            textField.resignFirstResponder()
        }
    }

    func logMessage(messageText: String) {
        NSLog(messageText)
        messageLabel?.text = messageText
    }

    @IBAction func connect(_ sender: Any) {
        // An empty name is allowed, to support tokens which are scoped to a single Room.
        guard let roomName = roomTextField?.text else {
            roomTextField?.becomeFirstResponder()
            return
        }

        dismissKeyboard()

        // Configure access token either from server or manually.
        // If the default wasn't changed, try fetching from server.
        if accessToken == "TWILIO_ACCESS_TOKEN" {
            logMessage(messageText: "Authorizing ...")
            do {
                accessToken = try TokenUtils.fetchToken(url: tokenUrl)
            } catch {
                let message = "Failed to fetch access token"
                logMessage(messageText: message)
                return
            }
        }

        logMessage(messageText: "Connecting to room \(roomName)")
        performSegue(withIdentifier: "multiPartyViewSegue", sender: sender)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "multiPartyViewSegue" {
            if let destinationVC = segue.destination as? MultiPartyViewController {
                destinationVC.accessToken = accessToken
                destinationVC.roomName = roomTextField?.text
            }
        }
    }
}

// MARK: UITextFieldDelegate
extension MainViewController : UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        connect(textField)
        return true
    }
}
