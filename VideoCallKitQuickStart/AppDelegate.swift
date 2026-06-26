//
//  AppDelegate.swift
//  VideoCallKitQuickStart
//
//  Copyright © 2016-2019 Twilio, Inc. All rights reserved.
//

import UIKit
import Intents

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    // iOS 12 fallback — on iOS 13+ with scenes, this is not called.
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard let viewController = window?.rootViewController as? ViewController,
              let roomName = userActivity.roomNameFromCallIntent else {
            return false
        }
        viewController.performStartCallAction(uuid: UUID(), roomName: roomName)
        return true
    }
}

extension NSUserActivity {
    var roomNameFromCallIntent: String? {
        guard let interaction = interaction else { return nil }

        var personHandle: INPersonHandle?
        if let intent = interaction.intent as? INStartVideoCallIntent {
            personHandle = intent.contacts?[0].personHandle
        } else if let intent = interaction.intent as? INStartAudioCallIntent {
            personHandle = intent.contacts?[0].personHandle
        }
        return personHandle?.value
    }
}
