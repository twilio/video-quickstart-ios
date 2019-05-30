//
//  Settings.swift
//  VideoQuickStart
//
//  Copyright © 2017-2019 Twilio, Inc. All rights reserved.
//

import TwilioVideo

class Settings: NSObject {

    let supportedAudioCodecs: [AudioCodec] = [IsacCodec(),
                                              OpusCodec(),
                                              PcmaCodec(),
                                              PcmuCodec(),
                                              G722Codec()]
    
    let supportedVideoCodecs: [VideoCodec] = [Vp8Codec(),
                                              Vp8Codec(simulcast: true),
                                              H264Codec(),
                                              Vp9Codec()]
    
    var audioCodec: AudioCodec?
    var videoCodec: VideoCodec?

    var maxAudioBitrate = UInt()
    var maxVideoBitrate = UInt()

    func getEncodingParameters() -> EncodingParameters?  {
        if maxAudioBitrate == 0 && maxVideoBitrate == 0 {
            return nil;
        } else {
            return EncodingParameters(audioBitrate: maxAudioBitrate,
                                      videoBitrate: maxVideoBitrate)
        }
    }
    
    private override init() {
        // Can't initialize a singleton
    }
    
    // MARK:- Shared Instance
    static let shared = Settings()
}
