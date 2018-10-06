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
    var videoSource: ReplayKitVideoSource?
    var screenTrack: TVILocalVideoTrack?
    let audioDevice = ExampleReplayKitAudioCapturer()

    var accessToken: String = "TWILIO_ACCESS_TOKEN"
    let accessTokenUrl = "http://127.0.0.1:5000/"

    static let kBroadcastSetupInfoRoomNameKey = "roomName"

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {

        TwilioVideo.audioDevice = ExampleReplayKitAudioCapturer(audioCapturer: self)

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
        videoSource = ReplayKitVideoSource(isScreencast: false)
        let constraints = TVIVideoConstraints.init { (builder) in
            builder.maxSize = CMVideoDimensions(width: Int32(ReplayKitVideoSource.kDownScaledMaxWidthOrHeight),
                                                height: Int32(ReplayKitVideoSource.kDownScaledMaxWidthOrHeight))
        }
        screenTrack = TVILocalVideoTrack(capturer: videoSource!,
                                         enabled: true,
                                         constraints: constraints,
                                         name: "Screen")

        let localAudioTrack = TVILocalAudioTrack()
        let connectOptions = TVIConnectOptions(token: accessToken) { (builder) in

            // Use the local media that we prepared earlier.
            builder.audioTracks = [localAudioTrack!]
            builder.videoTracks = [self.screenTrack!]

            // We have observed that downscaling the input and using H.264 results in the lowest memory usage.
            builder.preferredVideoCodecs = [TVIH264Codec()]

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
        // TODO: Signal audio as well.
        self.screenTrack?.isEnabled = false
    }

    override func broadcastResumed() {
        // User has requested to resume the broadcast. Samples delivery will resume.
        // TODO: Signal audio as well
        self.screenTrack?.isEnabled = true
    }

    override func broadcastFinished() {
        // User has requested to finish the broadcast.
        self.room?.disconnect()
        self.videoSource = nil
        self.screenTrack = nil
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case RPSampleBufferType.video:
            videoSource?.processVideoSampleBuffer(sampleBuffer)
            break
        case RPSampleBufferType.audioApp:
            /*
             * TODO: We do not capture app audio at the moment. For some broadcast use cases it may make sense to capture both the
             * application and microphone audio. Doing this requires down-mixing the resulting streams.
             */
            break
        case RPSampleBufferType.audioMic:
            ExampleCoreAudioDeviceRecordCallback(sampleBuffer)
            break
        }
    }

    // MARK:- TVIRoomDelegate
    func didConnect(to room: TVIRoom) {
        print("didConnectToRoom: ", room)
    }

    func room(_ room: TVIRoom, didFailToConnectWithError error: Error) {
        print("room: ", room, " didFailToConnectWithError: ", error)
        finishBroadcastWithError(error)
    }

    func room(_ room: TVIRoom, didDisconnectWithError error: Error?) {
        if let theError = error {
            print("room: ", room, "didDisconnectWithError: ", theError)
            finishBroadcastWithError(theError)
        }
    }

    func room(_ room: TVIRoom, participantDidConnect participant: TVIRemoteParticipant) {
        print("participant: ", participant.identity, " didConnect")
    }

    func room(_ room: TVIRoom, participantDidDisconnect participant: TVIRemoteParticipant) {
        print("participant: ", participant.identity, " didDisconnect")
    }
}
