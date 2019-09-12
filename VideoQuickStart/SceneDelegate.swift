//
//  SceneDelegate.swift
//  VideoQuickStart
//
//  Created by Chris Eagleston on 9/11/19.
//  Copyright © 2019 Twilio, Inc. All rights reserved.
//

import UIKit

@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    // UIWindowScene delegate

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let userActivity = connectionOptions.userActivities.first ?? session.stateRestorationActivity {
            if !configure(window: window, with: userActivity) {
                print("Failed to restore from \(userActivity)")
            }
        }

        // If there were no user activities, we don't have to do anything.
        // The `window` property will automatically be loaded with the storyboard's initial view controller.
    }

    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        return scene.userActivity
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        print(#function)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        print(#function)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        print(#function)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        print(#function)
    }

    // Utilities

    func configure(window: UIWindow?, with activity: NSUserActivity) -> Bool {
        if activity.title == "Room" {
            if let roomName = activity.userInfo?["RoomName"] as? String {
//                if let photoDetailViewController = PhotoDetailViewController.loadFromStoryboard() {
//                    photoDetailViewController.photo = Photo(name: photoID)
//
//                    if let navigationController = window?.rootViewController as? UINavigationController {
//                        navigationController.pushViewController(photoDetailViewController, animated: false)
//                        return true
//                    }
//                }
            }
        }
        return false
    }

}
