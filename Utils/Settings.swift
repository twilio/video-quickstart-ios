//
//  Settings.swift
//  VideoQuickStart
//
//  Copyright © 2017 Twilio, Inc. All rights reserved.
//

import TwilioVideo

class Settings: NSObject {

    let defaultCodecStr: String = "Default"
    
    var supportedAudioCodecs = [String]()
    var supportedVideoCodecs = [String]()
    
    // MARK: Local Variable
    private var audioCodec:String?
    private var videoCodec:String?
    
    // Can't init is singleton
    private override init() {
        supportedAudioCodecs = [defaultCodecStr,
                                TVIAudioCodec.ISAC.rawValue,
                                TVIAudioCodec.opus.rawValue,
                                TVIAudioCodec.PCMA.rawValue,
                                TVIAudioCodec.PCMU.rawValue,
                                TVIAudioCodec.G722.rawValue]
        
        supportedVideoCodecs = [defaultCodecStr,
                                TVIVideoCodec.VP8.rawValue,
                                TVIVideoCodec.H264.rawValue,
                                TVIVideoCodec.VP9.rawValue]
        
        // Initializing the audio and video codec selection with the default string.
        audioCodec = defaultCodecStr
        videoCodec = defaultCodecStr
    }
    
    // MARK: Shared Instance
    static let shared = Settings()
    
    func setAudioCodec(codec: String) {
        audioCodec = codec
    }
    
    func getAudioCodec() -> String {
        return audioCodec!
    }
    
    func setVideoCodec(codec: String) {
        videoCodec = codec
    }
    
    func getVideoCodec() -> String {
        return videoCodec!
    }
}
