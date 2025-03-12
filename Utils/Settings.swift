//
//  Settings.swift
//  VideoQuickStart
//
//  Copyright © 2017-2019 Twilio, Inc. All rights reserved.
//

import TwilioVideo

enum VideoCodec: CaseIterable {
    case auto, VP8, VP8Simulcast, H264, VP9

    var codec: TwilioVideo.VideoCodec? {
        switch self {
        case .auto:
            return nil
        case .VP8:
            return Vp8Codec()
        case .VP8Simulcast:
            return Vp8Codec(simulcast: true)
        case .H264:
            return H264Codec()
        case .VP9:
            return Vp9Codec()
        }
    }

    var name: String {
        switch self {
        case .auto:
            return "Auto"
        case .VP8, .H264, .VP9:
            return codec?.name ?? ""
        case .VP8Simulcast:
            return "\(VideoCodec.VP8.name) Simulcast"
        }
    }
}

class Settings: NSObject {
    
    var backgroundImage: UIImage?
    var backgroundBlurRadius: NSNumber?

    // ISDK-2644: Resolving a conflict with AudioToolbox in iOS 13
    let supportedAudioCodecs: [TwilioVideo.AudioCodec] = [OpusCodec(),
                                                          PcmaCodec(),
                                                          PcmuCodec(),
                                                          G722Codec()]

    // Valid signaling Regions are listed here:
    // https://www.twilio.com/docs/video/ip-address-whitelisting#signaling-communication
    let supportedSignalingRegions: [String] = ["gll",
                                               "au1",
                                               "br1",
                                               "de1",
                                               "ie1",
                                               "in1",
                                               "jp1",
                                               "sg1",
                                               "us1",
                                               "us2"]


    let supportedSignalingRegionDisplayString: [String : String] = ["gll": "Global Low Latency",
                                                                    "au1": "Australia",
                                                                    "br1": "Brazil",
                                                                    "de1": "Germany",
                                                                    "ie1": "Ireland",
                                                                    "in1": "India",
                                                                    "jp1": "Japan",
                                                                    "sg1": "Singapore",
                                                                    "us1": "US East Coast (Virginia)",
                                                                    "us2": "US West Coast (Oregon)"]
    
    var audioCodec: TwilioVideo.AudioCodec?
    var videoCodec: VideoCodec = .auto

    var maxAudioBitrate = UInt()
    var maxVideoBitrate = UInt()

    var signalingRegion: String?

    // The videoEncodingMode API is mutually exclusive with existing codec management APIs EncodingParameters.maxVideoBitrate and preferredVideoCodecs, therefore when .auto is used, set maxVideoBitrate to 0 (Zero indicates the WebRTC default value, which is 2000 Kbps)
    func getEncodingParameters() -> EncodingParameters?  {
        if maxAudioBitrate == 0 && maxVideoBitrate == 0 {
            return nil;
        } else if videoCodec == .auto {
            return EncodingParameters(audioBitrate: maxAudioBitrate,
                                      videoBitrate: 0)
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
