//
//  MainViewController.swift
//  ARKitFullExample
//
//  Created by Ahmed Bekhit on 11/18/17.
//  Copyright © 2017 Ahmed Fathi Bekhit. All rights reserved.
//

import UIKit

class MainViewController: UIViewController {
    @IBOutlet var toSKBtn: UIButton!
    @IBOutlet var toSCNBtn: UIButton!
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        toSKBtn.layer.cornerRadius = toSKBtn.bounds.height/2
        toSCNBtn.layer.cornerRadius = toSCNBtn.bounds.height/2
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}
