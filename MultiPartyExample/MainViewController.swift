//
//  MainViewController.swift
//  MultiPartyExample
//
//  Copyright © 2019 Twilio, Inc. All rights reserved.
//

import UIKit

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

        self.title = "MultiPartyExample"
        self.messageLabel.adjustsFontSizeToFitWidth = true;
        self.messageLabel.minimumScaleFactor = 0.75;

        if let navigationController = self.navigationController {
            navigationController.navigationBar.barTintColor = UIColor.init(red: 226.0/255.0,
                                                                           green: 29.0/255.0,
                                                                           blue: 37.0/255.0,
                                                                           alpha: 1.0)
            navigationController.navigationBar.tintColor = UIColor.white
            navigationController.navigationBar.barStyle = UIBarStyle.black
        }

        self.roomTextField.autocapitalizationType = .none
        self.roomTextField.delegate = self

        let tap = UITapGestureRecognizer(target: self, action: #selector(MainViewController.dismissKeyboard))
        self.view.addGestureRecognizer(tap)
    }

    @objc func dismissKeyboard() {
        if (self.roomTextField.isFirstResponder) {
            self.roomTextField.resignFirstResponder()
        }
    }

    func logMessage(messageText: String) {
        NSLog(messageText)
        messageLabel.text = messageText
    }

    @IBAction func connect(_ sender: Any) {
        guard let roomName = roomTextField.text, !roomName.isEmpty else {
            self.roomTextField.becomeFirstResponder()
            return
        }

        // Configure access token either from server or manually.
        // If the default wasn't changed, try fetching from server.
        if (accessToken == "TWILIO_ACCESS_TOKEN") {
            do {
                accessToken = try TokenUtils.fetchToken(url: tokenUrl)
            } catch {
                let message = "Failed to fetch access token"
                logMessage(messageText: message)
                return
            }
        }

        print("Connecting to room \(roomName)")
    }
}


// MARK: UITextFieldDelegate
extension MainViewController : UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.connect(textField)
        return true
    }
}
