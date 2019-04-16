//
//  Colors.swift
//  VideoQuickStart
//
//  Copyright © 2019 Twilio, Inc. All rights reserved.
//

import UIKit

extension UIColor {
    convenience init(red: Int, green: Int, blue: Int) {
        assert(red >= 0 && red <= 255, "Invalid red component")
        assert(green >= 0 && green <= 255, "Invalid green component")
        assert(blue >= 0 && blue <= 255, "Invalid blue component")
        self.init(red: CGFloat(red) / 255.0, green: CGFloat(green) / 255.0, blue: CGFloat(blue) / 255.0, alpha: 1.0)
    }

    convenience init(hex:Int) {
        self.init(red:(hex >> 16) & 0xff, green:(hex >> 8) & 0xff, blue:hex & 0xff)
    }

    struct Twilio {
        struct Status {
            static let Blue = UIColor(hex: 0x0070CC)
            static let Green = UIColor(hex: 0x29BB4f)
            static let Orange = UIColor(hex: 0xFF9800)
            static let Red = UIColor(hex: 0xC41025)
        }
    }
}
