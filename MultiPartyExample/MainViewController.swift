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
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var roomTextField: UITextField!
    @IBOutlet weak var roomLine: UIView!
    @IBOutlet weak var roomLabel: UILabel!
    @IBOutlet weak var messageLabel: UILabel!

    // MARK: UIViewController
    override func viewDidLoad() {
        super.viewDidLoad()

        messageLabel.adjustsFontSizeToFitWidth = true;
        messageLabel.minimumScaleFactor = 0.75;

        let tap = UITapGestureRecognizer(target: self, action: #selector(MainViewController.dismissKeyboard))
        view.addGestureRecognizer(tap)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        logMessage(messageText: "TwilioVideo v(\(TwilioVideo.version()))")
        roomTextField.text = ""
        roomTextField.becomeFirstResponder()
    }

    @objc func dismissKeyboard() {
        if roomTextField.isFirstResponder {
            roomTextField.resignFirstResponder()
        }
    }

    func logMessage(messageText: String) {
        NSLog(messageText)
        messageLabel.text = messageText
    }

    @IBAction func connect(_ sender: Any) {
        guard let roomName = roomTextField.text, !roomName.isEmpty else {
            roomTextField.becomeFirstResponder()
            return
        }

        dismissKeyboard()

        // Configure access token either from server or manually.
        // If the default wasn't changed, try fetching from server.
        if accessToken == "TWILIO_ACCESS_TOKEN" {
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
                navigationItem.backBarButtonItem?.title = "Disconnect"
                destinationVC.accessToken = accessToken
                destinationVC.roomName = roomTextField.text
            }
        } else {
            navigationItem.backBarButtonItem?.title = "Back"
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
