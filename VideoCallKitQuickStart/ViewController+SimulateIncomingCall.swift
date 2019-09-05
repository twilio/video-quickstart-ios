//
//  ViewController+SimulateIncomingCall.swift
//  VideoCallKitQuickStart
//
//  Copyright © 2016-2019 Twilio, Inc. All rights reserved.
//

import UIKit
import UserNotifications

// MARK:- Simulate Incoming Call
extension ViewController {

    func registerForLocalNotifications() {
        // Define the custom actions.
        let acceptAction = UNNotificationAction(identifier: "ACCEPT_ACTION",
              title: "Accept",
              options: UNNotificationActionOptions(rawValue: 0))
        let declineAction = UNNotificationAction(identifier: "DECLINE_ACTION",
              title: "Decline",
              options: .destructive)
        let notificationCenter = UNUserNotificationCenter.current()

        // Define the notification type
        if #available(iOS 11.0, *) {
            let meetingInviteCategory =
                UNNotificationCategory(identifier: "ROOM_INVITATION",
                                       actions: [acceptAction, declineAction],
                                       intentIdentifiers: [],
                                       hiddenPreviewsBodyPlaceholder: "",
                                       options: .customDismissAction)
            notificationCenter.setNotificationCategories([meetingInviteCategory])
        }

        // Register the notification type.
        notificationCenter.delegate = self

        // Request permission to display alerts and play sounds.
        notificationCenter.requestAuthorization(options: [.alert])
           { (granted, error) in
              // Enable or disable features based on authorization.
           }
    }

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

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let content = UNMutableNotificationContent()
            content.title = "Room Invitation"
            content.body = "Tap to connect to the Room."
            content.categoryIdentifier = "ROOM_INVITATION"
            let identifier = NSUUID.init().uuidString
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { (error) in
                if let theError = error {
                    print("Error posting local notification \(theError)")
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

extension ViewController : UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        print("Will present notification \(notification)")

        self.reportIncomingCall(uuid: UUID(), roomName: self.roomTextField.text) { _ in
            // Always call the completion handler when done.
            completionHandler(UNNotificationPresentationOptions())
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {

        print("Received notification response in \(UIApplication.shared.applicationState.rawValue) \(response)")

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            self.reportIncomingCall(uuid: UUID(), roomName: self.roomTextField.text) { _ in
                // Always call the completion handler when done.
                completionHandler()
            }
            break
        case "ACCEPT_ACTION":
            self.reportIncomingCall(uuid: UUID(), roomName: self.roomTextField.text) { _ in
                // Always call the completion handler when done.
                completionHandler()
            }
            break
        case "DECLINE_ACTION":
            completionHandler()
            break
        case UNNotificationDismissActionIdentifier:
            completionHandler()
            break
        // Handle other actions…
        default:
            break
        }
    }
}
