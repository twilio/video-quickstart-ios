//
//  Settings.swift
//  VideoQuickStart
//
//  Copyright © 2017 Twilio, Inc. All rights reserved.
//

import TwilioVideo

class Settings: NSObject {

    var supportedAudioCodecs = [TVIAudioCodec]()
    var supportedVideoCodecs = [TVIVideoCodec]()
    
    var audioCodec: TVIAudioCodec?
    var videoCodec: TVIVideoCodec?
    
    // Can't initialize a singleton
    private override init() {
        supportedAudioCodecs = [TVIAudioCodec.ISAC,
                                TVIAudioCodec.opus,
                                TVIAudioCodec.PCMA,
                                TVIAudioCodec.PCMU,
                                TVIAudioCodec.G722]
        
        supportedVideoCodecs = [TVIVideoCodec.VP8,
                                TVIVideoCodec.H264,
                                TVIVideoCodec.VP9]
    }
    
    // MARK: Shared Instance
    static let shared = Settings()
}
