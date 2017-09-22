//
//  Settings.swift
//  VideoQuickStart
//
//  Copyright © 2017 Twilio, Inc. All rights reserved.
//

import TwilioVideo

class Settings: NSObject {

    static let defaultCodecStr: String = "Default"
    
    var supportedAudioCodecs = [String]()
    var supportedVideoCodecs = [String]()
    
    // MARK: Local variables
    private var audioCodec = defaultCodecStr
    private var videoCodec = defaultCodecStr
    
    // Can't initialize a singleton
    private override init() {
        supportedAudioCodecs = [Settings.defaultCodecStr,
                                TVIAudioCodec.ISAC.rawValue,
                                TVIAudioCodec.opus.rawValue,
                                TVIAudioCodec.PCMA.rawValue,
                                TVIAudioCodec.PCMU.rawValue,
                                TVIAudioCodec.G722.rawValue]
        
        supportedVideoCodecs = [Settings.defaultCodecStr,
                                TVIVideoCodec.VP8.rawValue,
                                TVIVideoCodec.H264.rawValue,
                                TVIVideoCodec.VP9.rawValue]
        
        // Initializing the audio and video codec selection with the default string.
        audioCodec = Settings.defaultCodecStr
        videoCodec = Settings.defaultCodecStr
    }
    
    // MARK: Shared Instance
    static let shared = Settings()
    
    func setAudioCodec(codec: String) {
        audioCodec = codec
    }
    
    func getAudioCodec() -> String {
        return audioCodec
    }
    
    func setVideoCodec(codec: String) {
        videoCodec = codec
    }
    
    func getVideoCodec() -> String {
        return videoCodec
    }
}
