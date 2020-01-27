//
//  ClippingView.swift
//  MultiPartyExample
//
//  Copyright © 2020 Twilio, Inc. All rights reserved.
//

import UIKit

class ClippingView: UIView {

    @IBOutlet var clipView: UIView!

    override func layoutSubviews() {
        super.layoutSubviews()

        let path = UIBezierPath(rect: self.convert(clipView.frame, from: self.superview))
        let maskLayer = CAShapeLayer()

        path.append(UIBezierPath(rect: self.bounds))
        maskLayer.fillRule = .evenOdd
        maskLayer.path = path.cgPath

        self.layer.mask = maskLayer
    }

}
