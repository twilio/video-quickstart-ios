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
        // Override point for customization after application launch.

        return true
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard let viewController = window?.rootViewController as? ViewController, let interaction = userActivity.interaction else {
            return false
        }

        var personHandle: INPersonHandle?

        if let startVideoCallIntent = interaction.intent as? INStartVideoCallIntent {
            personHandle = startVideoCallIntent.contacts?[0].personHandle
        } else if let startAudioCallIntent = interaction.intent as? INStartAudioCallIntent {
            personHandle = startAudioCallIntent.contacts?[0].personHandle
        }

        if let personHandle = personHandle {
            viewController.performStartCallAction(uuid: UUID(), roomName: personHandle.value)
        }

        return true
    }
}
