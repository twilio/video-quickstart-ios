//
//  SceneDelegate.swift
//  VideoCallKitQuickStart
//
//  Created by Andrejs Semivragovs on 15/06/2026.
//  Copyright © 2026 Twilio, Inc. All rights reserved.
//

import UIKit

@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let userActivity = connectionOptions.userActivities.first,
           let roomName = userActivity.roomNameFromCallIntent,
           let viewController = window?.rootViewController as? ViewController {
            viewController.performStartCallAction(uuid: UUID(), roomName: roomName)
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let viewController = window?.rootViewController as? ViewController,
              let roomName = userActivity.roomNameFromCallIntent else {
            return
        }
        viewController.performStartCallAction(uuid: UUID(), roomName: roomName)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        print(#function)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        print(#function)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        print(#function)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        print(#function)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        print(#function)
    }

}
