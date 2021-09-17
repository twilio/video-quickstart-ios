//
//  Utils.swift
//
//  Copyright © 2016-2019 Twilio, Inc. All rights reserved.
//

import Foundation

// Helper to determine if we're running on simulator or device
struct PlatformUtils {
    static let isSimulator: Bool = {
        var isSim = false
        #if arch(i386) || arch(x86_64)
            isSim = true
        #endif
        return isSim
    }()
}

struct TokenUtils {    
    static func fetchToken(from url : String, completionHandler: @escaping (String, Error?) -> Void) {
      var token: String = "TWILIO_ACCESS_TOKEN"
      let requestURL: URL = URL(string: url)!
      let task = URLSession.shared.dataTask(with: requestURL) {
        (data, response, error) in
        if let error = error {
          completionHandler(token, error)
          return
        }
            
        if let data = data, let tokenReponse = String(data: data, encoding: .utf8) {
            token = tokenReponse
            completionHandler(token, nil)
        }
      }
      task.resume()
    }
}
