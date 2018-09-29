//
//  SampleHandler.swift
//  BroadcastExtension
//
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
    var screenTrack: TVILocalVideoTrack?

    static let kDesiredFrameRate = 30

    // Our capturer attempts to downscale the source to fit in a smaller square, in order to save memory.
    static let kDownScaledMaxWidthOrHeight = 640

    // ReplayKit provides planar NV12 CVPixelBuffers consisting of luma (Y) and chroma (UV) planes.
    static let kYPlane = 0
    static let kUVPlane = 1

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

        screenTrack = TVILocalVideoTrack(capturer: self)
        let localAudioTrack = TVILocalAudioTrack()
        let connectOptions = TVIConnectOptions.init(token: accessToken) { (builder) in

            // Use the local media that we prepared earlier.
            builder.audioTracks = [localAudioTrack!]
            builder.videoTracks = [self.screenTrack!]

            // Use the preferred video codec
            builder.preferredVideoCodecs = [TVIH264Codec()]

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
        self.screenTrack = nil
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case RPSampleBufferType.video:
            processVideoSampleBuffer(sampleBuffer)
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

    func startCapture(_ format: TVIVideoFormat, consumer: TVIVideoCaptureConsumer) {
        captureConsumer = consumer
        consumer.captureDidStart(true)

        print("Start capturing.")
    }

    func stopCapture() {
        print("Stop capturing.")
    }

    // MARK:- Private
    func processVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let consumer = self.captureConsumer else {
            return
        }
        guard let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            assertionFailure("SampleBuffer did not have an ImageBuffer")
            return
        }

        // We only support NV12 (full-range) buffers.
        let pixelFormat = CVPixelBufferGetPixelFormatType(sourcePixelBuffer);
        if (pixelFormat != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            assertionFailure("Extension assumes the incoming frames are of type NV12")
            return
        }

        // Compute the downscaled rect for our destination buffer (in whole pixels).
        // TODO: Do we want to round to even width/height only?
        let rect = AVMakeRect(aspectRatio: CGSize(width: CVPixelBufferGetWidth(sourcePixelBuffer),
                                                  height: CVPixelBufferGetHeight(sourcePixelBuffer)),
                              insideRect: CGRect(x: 0,
                                                 y: 0,
                                                 width: SampleHandler.kDownScaledMaxWidthOrHeight,
                                                 height: SampleHandler.kDownScaledMaxWidthOrHeight))
        let size = rect.integral.size

        // We will allocate a CVPixelBuffer to hold the downscaled contents.
        // TODO: Consider copying the pixelBufferAttributes to maintain color information. Investigate the color space of the buffers.
        var outPixelBuffer: CVPixelBuffer? = nil
        var status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width),
                                         Int(size.height),
                                         pixelFormat,
                                         nil,
                                         &outPixelBuffer);
        if (status != kCVReturnSuccess) {
            print("Failed to create pixel buffer");
            return
        }

        let destinationPixelBuffer = outPixelBuffer!

        status = CVPixelBufferLockBaseAddress(sourcePixelBuffer, CVPixelBufferLockFlags.readOnly);
        status = CVPixelBufferLockBaseAddress(destinationPixelBuffer, []);

        // Prepare source pointers.
        var sourceImageY = vImage_Buffer(data: CVPixelBufferGetBaseAddressOfPlane(sourcePixelBuffer, SampleHandler.kYPlane),
                                         height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(sourcePixelBuffer, SampleHandler.kYPlane)),
                                         width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(sourcePixelBuffer, SampleHandler.kYPlane)),
                                         rowBytes: CVPixelBufferGetBytesPerRowOfPlane(sourcePixelBuffer, SampleHandler.kYPlane))

        var sourceImageUV = vImage_Buffer(data: CVPixelBufferGetBaseAddressOfPlane(sourcePixelBuffer, SampleHandler.kUVPlane),
                                          height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(sourcePixelBuffer, SampleHandler.kUVPlane)),
                                          width:vImagePixelCount(CVPixelBufferGetWidthOfPlane(sourcePixelBuffer, SampleHandler.kUVPlane)),
                                          rowBytes: CVPixelBufferGetBytesPerRowOfPlane(sourcePixelBuffer, SampleHandler.kUVPlane))

        // Prepare destination pointers.
        var destinationImageY = vImage_Buffer(data: CVPixelBufferGetBaseAddressOfPlane(destinationPixelBuffer, SampleHandler.kYPlane),
                                              height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(destinationPixelBuffer, SampleHandler.kYPlane)),
                                              width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(destinationPixelBuffer, SampleHandler.kYPlane)),
                                              rowBytes: CVPixelBufferGetBytesPerRowOfPlane(destinationPixelBuffer, SampleHandler.kYPlane))

        var destinationImageUV = vImage_Buffer(data: CVPixelBufferGetBaseAddressOfPlane(destinationPixelBuffer, SampleHandler.kUVPlane),
                                               height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(destinationPixelBuffer, SampleHandler.kUVPlane)),
                                               width: vImagePixelCount( CVPixelBufferGetWidthOfPlane(destinationPixelBuffer, SampleHandler.kUVPlane)),
                                               rowBytes: CVPixelBufferGetBytesPerRowOfPlane(destinationPixelBuffer, SampleHandler.kUVPlane))

        // Scale the Y and UV planes into the destination buffer.
        var error = vImageScale_Planar8(&sourceImageY, &destinationImageY, nil, vImage_Flags(0));
        if (error != kvImageNoError) {
            print("Failed to down scale luma plane.")
            return;
        }

        error = vImageScale_CbCr8(&sourceImageUV, &destinationImageUV, nil, vImage_Flags(0));
        if (error != kvImageNoError) {
            print("Failed to down scale chroma plane.")
            return;
        }

        status = CVPixelBufferUnlockBaseAddress(outPixelBuffer!, [])
        status = CVPixelBufferUnlockBaseAddress(sourcePixelBuffer, [])

        guard let frame = TVIVideoFrame(timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                                        buffer: outPixelBuffer!,
                                        orientation: TVIVideoOrientation.up) else {
            assertionFailure("We couldn't create a TVIVideoFrame with a valid CVPixelBuffer.")
            return
        }
        consumer.consumeCapturedFrame(frame)
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
        print("participant: ", participant, " didConnect")
    }

    func room(_ room: TVIRoom, participantDidDisconnect participant: TVIRemoteParticipant) {
        print("participant: ", participant, " didDisconnect")
    }
}
