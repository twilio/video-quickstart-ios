//
//  SceneDelegate.swift
//  VideoQuickStart
//
//  Created by Chris Eagleston on 9/11/19.
//  Copyright © 2019 Twilio, Inc. All rights reserved.
//

import UIKit
import TwilioVideo

@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    // UIWindowScene delegate

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        print(#function)

        // The example does not support user activities & state restoration at this time.
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

    func windowScene(_ windowScene: UIWindowScene,
                     didUpdate previousCoordinateSpace: UICoordinateSpace,
                     interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
                     traitCollection previousTraitCollection: UITraitCollection) {
        // Forward WindowScene changes to Twilio
        UserInterfaceTracker.sceneInterfaceOrientationDidChange(windowScene)
    }
    
}
