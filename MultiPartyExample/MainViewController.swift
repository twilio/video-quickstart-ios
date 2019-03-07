//
//  MainViewController.swift
//  MultiPartyExample
//
//  Copyright © 2019 Twilio, Inc. All rights reserved.
//

import UIKit

class MainViewController: UIViewController {

    // MARK: View Controller Members
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var roomTextField: UITextField!
    @IBOutlet weak var roomLine: UIView!
    @IBOutlet weak var roomLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "MultiPartyExample"

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
    
    @IBAction func connect(_ sender: Any) {
        guard let roomName = roomTextField.text, !roomName.isEmpty else {
            self.roomTextField.becomeFirstResponder()
            return
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
