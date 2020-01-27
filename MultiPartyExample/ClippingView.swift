//
//  ClippingView.swift
//  MultiPartyExample
//
//  Copyright © 2020 Twilio, Inc. All rights reserved.
//

import UIKit

class ClippingView: UIView {

    var clippingTarget: UIView?

    var shouldClip: Bool = false {
        didSet {
            self.setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard shouldClip == true, let clippingTarget = clippingTarget else {
            return
        }

        let path = UIBezierPath(roundedRect: convert(clippingTarget.frame, from: superview), cornerRadius:1.5)
        let maskLayer = CAShapeLayer()

        path.append(UIBezierPath(rect: bounds))
        maskLayer.fillRule = .evenOdd
        maskLayer.path = path.cgPath

        layer.mask = maskLayer
    }
}
