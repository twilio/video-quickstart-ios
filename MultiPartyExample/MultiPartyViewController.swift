//
//  MultiPartyViewController.swift
//  MultiPartyExample
//
//  Copyright © 2019 Twilio, Inc. All rights reserved.
//

import UIKit
import TwilioVideo

class MultiPartyViewController: UIViewController {

    // MARK: View Controller Members

    var roomName: String?
    var accessToken: String?

    // Video SDK components
    var room: TVIRoom?
    var camera: TVICameraSource?
    var localVideoTrack: TVILocalVideoTrack?
    var localAudioTrack: TVILocalAudioTrack?

    // MARK: UI Element Outlets and handles


    // MARK: UIViewController
    override func viewDidLoad() {
        super.viewDidLoad()


    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
