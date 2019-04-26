//
//  SampleHandler.swift
//  BroadcastExtension
//
//  Copyright © 2018 Twilio. All rights reserved.
//

import Accelerate
import TwilioVideo
import ReplayKit

class SampleHandler: RPBroadcastSampleHandler, TVIRoomDelegate {

    // Video SDK components
    public var room: TVIRoom?
    var audioTrack: TVILocalAudioTrack?
    var videoSource: ReplayKitVideoSource?
    var screenTrack: TVILocalVideoTrack?
    var disconnectSemaphore: DispatchSemaphore?

    var accessToken: String = "TWILIO_ACCESS_TOKEN"
    let accessTokenUrl = "http://127.0.0.1:5000/"

    static let kBroadcastSetupInfoRoomNameKey = "roomName"

    // In order to save memory, we request that our source downscale its output.
    static let kDownScaledMaxWidthOrHeight = 720

    // Maximum bitrate (in kbps) used to send video.
    static let kMaxVideoBitrate = UInt(1400)

    // Which kind of audio samples we will capture. The example does not mix multiple types of samples together.
    static let kAudioSampleType = RPSampleBufferType.audioMic

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {

        TwilioVideo.audioDevice = ExampleReplayKitAudioCapturer(sampleType: SampleHandler.kAudioSampleType)

        // User has requested to start the broadcast. Setup info from the UI extension can be supplied but is optional.
        if (accessToken == "TWILIO_ACCESS_TOKEN" || accessToken.isEmpty) {
            do {
                accessToken = try TokenUtils.fetchToken(url: self.accessTokenUrl)
            } catch {
                let message = "Failed to fetch access token."
                print(message)
            }
        }

        // This source will attempt to produce smaller buffers with fluid motion.
        let outputFormat = TVIVideoFormat()

        var screenSize = UIScreen.main.bounds.size
        screenSize.width *= UIScreen.main.nativeScale
        screenSize.height *= UIScreen.main.nativeScale

        let downscaledTarget = CGSize(width: SampleHandler.kDownScaledMaxWidthOrHeight,
                                      height: SampleHandler.kDownScaledMaxWidthOrHeight)
        let fitRect = AVMakeRect(aspectRatio: screenSize,
                                 insideRect: CGRect(origin: CGPoint.zero, size: downscaledTarget)).integral
        let outputSize = fitRect.size

        outputFormat.dimensions = CMVideoDimensions(width: Int32(outputSize.width), height: Int32(outputSize.height))

        videoSource = ReplayKitVideoSource(isScreencast: false)
        screenTrack = TVILocalVideoTrack(source: videoSource!,
                                         enabled: true,
                                         name: "Screen")

        videoSource!.requestOutputFormat(outputFormat)
        audioTrack = TVILocalAudioTrack()

        let connectOptions = TVIConnectOptions(token: accessToken) { (builder) in

            // Use the local media that we prepared earlier.
            builder.audioTracks = [self.audioTrack!]
            builder.videoTracks = [self.screenTrack!]

            // We have observed that downscaling the input and using H.264 results in the lowest memory usage.
            builder.preferredVideoCodecs = [TVIH264Codec()]

            /*
             * Constrain the bitrate to improve QoS for subscribers when simulcast is not used, and to reduce overall
             * bandwidth usage for the broadcaster.
             */
            builder.encodingParameters = TVIEncodingParameters(audioBitrate: 0,
                                                               videoBitrate: UInt(1024) * SampleHandler.kMaxVideoBitrate)

            /*
             * A broadcast extension has no need to subscribe to Tracks, and connects as a publish-only
             * Participant. In a Group Room, this options saves memory and bandwidth since decoders and receivers are
             * no longer needed. Note that subscription events will not be raised for remote publications.
             */
            builder.isAutomaticSubscriptionEnabled = false

            // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty
            // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
            if #available(iOS 12.0, *) {
                builder.roomName = "Broadcast"
            } else {
                builder.roomName = setupInfo?[SampleHandler.kBroadcastSetupInfoRoomNameKey] as? String
            }
        }

        // Connect to the Room using the options we provided.
        room = TwilioVideo.connect(with: connectOptions, delegate: self)

        // The user has requested to start the broadcast. Setup info from the UI extension can be supplied but is optional.
        print("broadcastStartedWithSetupInfo: ", setupInfo as Any)
    }

    override func broadcastPaused() {
        // User has requested to pause the broadcast. Samples will stop being delivered.
        self.audioTrack?.isEnabled = false
        self.screenTrack?.isEnabled = false
    }

    override func broadcastResumed() {
        // User has requested to resume the broadcast. Samples delivery will resume.
        self.audioTrack?.isEnabled = true
        self.screenTrack?.isEnabled = true
    }

    override func broadcastFinished() {
        // User has requested to finish the broadcast.
        DispatchQueue.main.async {
            self.room?.disconnect()
        }
        self.disconnectSemaphore?.wait()
        DispatchQueue.main.sync {
            self.audioTrack = nil
            self.videoSource = nil
            self.screenTrack = nil
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case RPSampleBufferType.video:
            videoSource?.processVideoSampleBuffer(sampleBuffer)
            break

        case RPSampleBufferType.audioApp:
            if (SampleHandler.kAudioSampleType == RPSampleBufferType.audioApp) {
                ExampleCoreAudioDeviceRecordCallback(sampleBuffer)
            }
            break

        case RPSampleBufferType.audioMic:
            if (SampleHandler.kAudioSampleType == RPSampleBufferType.audioMic) {
                ExampleCoreAudioDeviceRecordCallback(sampleBuffer)
            }
            break
        }
    }

    // MARK:- TVIRoomDelegate
    func didConnect(to room: TVIRoom) {
        print("didConnectToRoom: ", room)

        disconnectSemaphore = DispatchSemaphore(value: 0)
    }

    func room(_ room: TVIRoom, didFailToConnectWithError error: Error) {
        print("room: ", room, " didFailToConnectWithError: ", error)
        finishBroadcastWithError(error)
    }

    func room(_ room: TVIRoom, didDisconnectWithError error: Error?) {
        if let semaphore = self.disconnectSemaphore {
            semaphore.signal()
        }
        if let theError = error {
            print("room: ", room, "didDisconnectWithError: ", theError)
            finishBroadcastWithError(theError)
        }
    }

    func room(_ room: TVIRoom, isReconnectingWithError error: Error) {
        print("Reconnecting to room \(room.name), error = \(String(describing: error))")
    }

    func didReconnect(to room: TVIRoom) {
        print("Reconnected to room \(room.name)")
    }

    func room(_ room: TVIRoom, participantDidConnect participant: TVIRemoteParticipant) {
        print("participant: ", participant.identity, " didConnect")
    }

    func room(_ room: TVIRoom, participantDidDisconnect participant: TVIRemoteParticipant) {
        print("participant: ", participant.identity, " didDisconnect")
    }
}
