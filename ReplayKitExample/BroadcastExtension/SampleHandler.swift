//
//  SampleHandler.swift
//  BroadcastExtension
//
//  Created by Piyush Tank on 7/1/18.
//  Copyright © 2018 Twilio. All rights reserved.
//

import Accelerate
import TwilioVideo
import ReplayKit

class SampleHandler: RPBroadcastSampleHandler, TVIRoomDelegate, TVIVideoCapturer {

    public var isScreencast: Bool = true

    // Video SDK components
    public var room: TVIRoom?
    weak var captureConsumer: TVIVideoCaptureConsumer?

    static let kDesiredFrameRate = 30
    static let kDownScaledMaxWidthOrHeight = 640

    let audioDevice = ExampleCoreAudioDevice()

    public var supportedFormats: [TVIVideoFormat] {
        get {
            /*
             * Describe the supported format.
             * For this example we cheat and assume that we will be capturing the entire screen.
             */
            let screenSize = UIScreen.main.bounds.size
            let format = TVIVideoFormat()
            format.pixelFormat = TVIPixelFormat.formatYUV420BiPlanarFullRange
            format.frameRate = UInt(SampleHandler.kDesiredFrameRate)
            format.dimensions = CMVideoDimensions(width: Int32(screenSize.width), height: Int32(screenSize.height))
            return [format]
        }
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {

        TwilioVideo.audioDevice = ExampleCoreAudioDevice(audioCapturer: self)

        // User has requested to start the broadcast. Setup info from the UI extension can be supplied but optional.
        let accessToken = "TWILIO-ACCESS-TOKEN";

        let localScreenTrack = TVILocalVideoTrack(capturer: self)
        let h264VideoCodec = TVIH264Codec()
        let localAudioTrack = TVILocalAudioTrack()
        let connectOptions = TVIConnectOptions.init(token: accessToken) { (builder) in

            // Use the local media that we prepared earlier.
            builder.audioTracks = [localAudioTrack!]
            builder.videoTracks = [localScreenTrack!]

            // Use the preferred video codec
            builder.preferredVideoCodecs = [h264VideoCodec] as! [TVIVideoCodec]

            // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty
            // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
            if #available(iOS 12.0, *) {
                builder.roomName = "test"
            } else {
                builder.roomName = setupInfo?["RoomName"] as? String
            }
        }

        // Connect to the Room using the options we provided.
        room = TwilioVideo.connect(with: connectOptions, delegate: self)

        // User has requested to start the broadcast. Setup info from the UI extension can be supplied but optional.
        print("broadcastStarted")
    }

    override func broadcastPaused() {
        // User has requested to pause the broadcast. Samples will stop being delivered.
    }

    override func broadcastResumed() {
        // User has requested to resume the broadcast. Samples delivery will resume.
    }

    override func broadcastFinished() {
        // User has requested to finish the broadcast.
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        RPScreenRecorder.shared().isMicrophoneEnabled = true
        switch sampleBufferType {
        case RPSampleBufferType.video:
            if (captureConsumer != nil) {
                processVideoSampleBuffer(sampleBuffer)
            }
            break

        case RPSampleBufferType.audioApp:
            // TODO: Mix app's audio and microphone audio at audioDevice's capturing sample rate and supply it.

            /*
             * TODO: For now, since we are providing app's audio to the audio device here, add an assertion if the
             * sample rate does not match with audioDevice's audio captureing sample rate.
             */
            ExampleCoreAudioDeviceRecordCallback(sampleBuffer)
            break

        case RPSampleBufferType.audioMic:
            ExampleCoreAudioDeviceRecordCallback(sampleBuffer)
            break
        }
    }

    func startCapture(_ format: TVIVideoFormat, consumer: TVIVideoCaptureConsumer) {
        captureConsumer = consumer
        captureConsumer!.captureDidStart(true)

        print("Start capturing.")
    }

    func stopCapture() {
        print("Stop capturing.")
    }

    // MARK:- Private
    func processVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        var outPixelBuffer : CVPixelBuffer? = nil

        CVPixelBufferLockBaseAddress(pixelBuffer, []);

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);

        if (pixelFormat != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            assertionFailure("Extension assumes the incoming frames are of type NV12")
        }

        let srcWidth = CVPixelBufferGetWidth(pixelBuffer)
        let srcHeight = CVPixelBufferGetHeight(pixelBuffer)

        var height = 0
        var width = 0
        if srcWidth > srcHeight {
            width = SampleHandler.kDownScaledMaxWidthOrHeight
            height = SampleHandler.kDownScaledMaxWidthOrHeight * srcHeight / srcWidth
        } else {
            height = SampleHandler.kDownScaledMaxWidthOrHeight
            width = SampleHandler.kDownScaledMaxWidthOrHeight * srcWidth / srcHeight
        }

        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         pixelFormat,
                                         nil,
                                         &outPixelBuffer);
        if (status != kCVReturnSuccess) {
            print("Failed to create pixel buffer");
        }

        CVPixelBufferLockBaseAddress(outPixelBuffer!, []);

        // Prepare source pointers.
        var sourceImageY = vImage_Buffer(data: CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
                                         height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)),
                                         width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)),
                                         rowBytes: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0))

        var sourceImageUV = vImage_Buffer(data: CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1),
                                          height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)),
                                          width:vImagePixelCount(CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)),
                                          rowBytes: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1))

        // Prepare out pointers.
        var outImageY = vImage_Buffer(data: CVPixelBufferGetBaseAddressOfPlane(outPixelBuffer!, 0),
                                      height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(outPixelBuffer!, 0)),
                                      width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(outPixelBuffer!, 0)),
                                      rowBytes: CVPixelBufferGetBytesPerRowOfPlane(outPixelBuffer!, 0))

        var outImageUV = vImage_Buffer(data: CVPixelBufferGetBaseAddressOfPlane(outPixelBuffer!, 1),
                                       height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(outPixelBuffer!, 1)),
                                       width:vImagePixelCount( CVPixelBufferGetWidthOfPlane(outPixelBuffer!, 1)),
                                       rowBytes: CVPixelBufferGetBytesPerRowOfPlane(outPixelBuffer!, 1))


        var error = vImageScale_Planar8(&sourceImageY, &outImageY, nil, vImage_Flags(0));
        if (error != kvImageNoError) {
            print("Failed to down scale luma plane ")
            return;
        }

        error = vImageScale_CbCr8(&sourceImageUV, &outImageUV, nil, vImage_Flags(0));
        if (error != kvImageNoError) {
            print("Failed to down scale chroma plane")
            return;
        }

        CVPixelBufferUnlockBaseAddress(outPixelBuffer!, []);
        CVPixelBufferUnlockBaseAddress(pixelBuffer, []);

        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        let frame = TVIVideoFrame(timestamp: time,
                                  buffer: outPixelBuffer!,
                                  orientation: TVIVideoOrientation.up)

        captureConsumer?.consumeCapturedFrame(frame!)
    }

    // MARK:- TVIRoomDelegate

    func didConnect(to room: TVIRoom) {
        print("didConnectToRoom")
    }

    func room(_ room: TVIRoom, didFailToConnectWithError error: Error) {
        print("didFailToConnectWithError")
    }

    func room(_ room: TVIRoom, didDisconnectWithError error: Error?) {
        print("didDisconnectWithError")
    }

    func room(_ room: TVIRoom, participantDidConnect participant: TVIRemoteParticipant) {
        print("participantDidConnect")
    }

    func room(_ room: TVIRoom, participantDidDisconnect participant: TVIRemoteParticipant) {
        print("participantDidDisconnect")
    }
}
