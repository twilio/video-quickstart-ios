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
        let inviteAction = UNNotificationAction(identifier: "INVITE_ACTION",
              title: "Simulate VoIP Push",
              options: UNNotificationActionOptions(rawValue: 0))
        let declineAction = UNNotificationAction(identifier: "DECLINE_ACTION",
              title: "Decline",
              options: .destructive)
        let notificationCenter = UNUserNotificationCenter.current()

        // Define the notification type
        let meetingInviteCategory = UNNotificationCategory(identifier: "ROOM_INVITATION",
                                                           actions: [inviteAction, declineAction],
                                                           intentIdentifiers: [],
                                                           options: .customDismissAction)
        notificationCenter.setNotificationCategories([meetingInviteCategory])

        // Register for notification callbacks.
        notificationCenter.delegate = self

        // Request permission to display alerts and play sounds.
        notificationCenter.requestAuthorization(options: [.alert])
           { (granted, error) in
              // Enable or disable features based on authorization.
           }
    }

    @IBAction func simulateIncomingCall(sender: AnyObject) {

        let alertController = UIAlertController(title: "Schedule Notification", message: nil, preferredStyle: .alert)

        let okAction = UIAlertAction(title: "OK", style: .default, handler: { alert -> Void in

            let roomNameTextField = alertController.textFields![0] as UITextField
            let delayTextField = alertController.textFields![1] as UITextField

            let roomName = roomNameTextField.text
            self.roomTextField.text = roomName

            var delay = 5.0
            if let delayString = delayTextField.text, let delayFromString = Double(delayString) {
                delay = delayFromString
            }

            self.logMessage(messageText: "Schedule local notification for Room: \(String(describing: roomName)) after a \(delay) second delay")

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let content = UNMutableNotificationContent()
            content.title = "Room Invite"
            content.body = "Tap to connect to \(roomName ?? "a Room")."
            content.categoryIdentifier = "ROOM_INVITATION"
            if let name = roomName {
                content.userInfo = [ "roomName" : name ]
            }
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

        self.reportIncomingCall(uuid: UUID(), roomName: ViewController.parseNotification(notification: notification)) { _ in
            // Always call the completion handler when done.
            completionHandler(UNNotificationPresentationOptions())
        }
    }

    static func parseNotification(notification: UNNotification) -> String {
        var roomName = ""
        if let requestedName = notification.request.content.userInfo["roomName"] as? String {
            roomName = requestedName
        }
        return roomName
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {

        print("Received notification response in \(UIApplication.shared.applicationState.rawValue) \(response)")
        let roomName = ViewController.parseNotification(notification: response.notification)
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            self.performStartCallAction(uuid: UUID(), roomName: roomName)
            completionHandler()
            break
        case "INVITE_ACTION":
            self.reportIncomingCall(uuid: UUID(), roomName: roomName) { _ in
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
