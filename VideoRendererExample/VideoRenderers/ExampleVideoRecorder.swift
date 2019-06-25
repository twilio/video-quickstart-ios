//
//  ExampleVideoRecorder.swift
//  VideoRendererExample
//
//  Copyright © 2017 Twilio Inc. All rights reserved.
//

import AVFoundation
import Foundation
import TwilioVideo

class ExampleVideoRecorder : NSObject, VideoRenderer {
    let identifier : String
    let videoTrack : VideoTrack

    var recorderTimestamp = CMTime.invalid
    var videoFormatDescription: CMFormatDescription?
    var videoRecorder : AVAssetWriter?
    var videoRecorderInput : AVAssetWriterInput?

    init(videoTrack: VideoTrack, identifier: String) {
        self.videoTrack = videoTrack
        self.identifier = identifier

        super.init()

        initRecording()
    }

    private func initRecording() {
        do {
            self.videoRecorder = try AVAssetWriter.init(url:ExampleVideoRecorder.recordingURL(identifier: identifier),
                                                        fileType: AVFileType.mp4)
        } catch {
            print("Could not create AVAssetWriter with error: \(error)")
            return
        }

        // The recorder will determine the asset's format as frames arrive.
        videoTrack.addRenderer(self)

        // This example does not support backgrounding. Now might be a good point to consider kicking off a background
        // task, and handling failures.
    }

    private func startRecording(frame: VideoFrame) {
        self.recorderTimestamp = frame.timestamp

        // Determine width and height dynamically (based upon the first frame). This works well for local content.
        let outputSettings: [String : Any]
        if #available(iOS 11.0, *) {
            outputSettings = [
                AVVideoCodecKey : AVVideoCodecType.h264,
                AVVideoWidthKey : frame.width,
                AVVideoHeightKey : frame.height,
                AVVideoScalingModeKey : AVVideoScalingModeResizeAspect] as [String : Any]
        } else {
            outputSettings = [
                AVVideoWidthKey : frame.width,
                AVVideoHeightKey : frame.height,
                AVVideoScalingModeKey : AVVideoScalingModeResizeAspect] as [String : Any]
        }

        videoRecorderInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: outputSettings)
        videoRecorderInput?.expectsMediaDataInRealTime = true

        if let videoRecorder = self.videoRecorder,
            let videoRecorderInput = self.videoRecorderInput,
            videoRecorder.canAdd(videoRecorderInput) {
            videoRecorder.add(videoRecorderInput)

            if (videoRecorder.startWriting()) {
                self.videoRecorder?.startSession(atSourceTime: self.recorderTimestamp)
            } else {
                print("Could not start writing!")
            }
        } else {
            print("Could not add AVAssetWriterInput!")
        }
    }

    public func stopRecording() {
        videoTrack.removeRenderer(self)
        videoRecorderInput?.markAsFinished()
        videoRecorder?.finishWriting {
            if (self.videoRecorder?.status == AVAssetWriter.Status.failed) {
                print("Failed to write asset.")
            } else if (self.videoRecorder?.status == AVAssetWriter.Status.completed) {
                print("Completed asset with URL:", self.videoRecorder?.outputURL.absoluteString)
            }
            self.videoRecorder = nil
            self.videoRecorderInput = nil
            self.recorderTimestamp = CMTime.invalid
        }
    }

    class func recordingURL(identifier: String) -> URL {
        guard let documentsDirectory = FileManager.default.urls(for: FileManager.SearchPathDirectory.documentDirectory,
                                                                 in: FileManager.SearchPathDomainMask.userDomainMask).last else {
            return URL(fileURLWithPath: "")
        }

        // Choose a filename which will be unique if the `identifier` is reused (Append RFC3339 formatted date).
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "HHmmss"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        let dateComponent = dateFormatter.string(from: Date())
        let filename = identifier + "-" + dateComponent + ".mp4"

        return documentsDirectory.appendingPathComponent(filename)
    }
}

extension ExampleVideoRecorder {
    func renderFrame(_ frame: VideoFrame) {
        // Frames are delivered with presentation timestamps. We will make do with this for our recorder.
        let timestamp = frame.timestamp

        // Defer creating and configuring the input until a frame has arrived.
        if (CMTIME_IS_INVALID(recorderTimestamp)) {
            print("Received first video sample at: \(timestamp). Starting recording session.")
            startRecording(frame: frame)
        }

        detectFormatChange(imageBuffer: frame.imageBuffer)

        // Our uncompressed buffers do not need to be decoded.
        // TODO: Assuming the duration might not be a good idea.
        var sampleTiming = CMSampleTimingInfo.init(duration: CMTime(value: 1, timescale: 30),
                                                   presentationTimeStamp: timestamp,
                                                   decodeTimeStamp: CMTime.invalid)

        // Append a CMSampleBuffer to the recorder's input.
        // TODO: Support I420 inputs for recording of remote content.
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                              imageBuffer: frame.imageBuffer,
                                                              formatDescription: self.videoFormatDescription!,
                                                              sampleTiming: &sampleTiming,
                                                              sampleBufferOut: &sampleBuffer)

        if (status != kCVReturnSuccess) {
            print("Couldn't create a SampleBuffer. Status=\(status)")
        } else if let buffer = sampleBuffer,
            let input = videoRecorderInput,
            input.isReadyForMoreMediaData,
            input.append(buffer) {
            // Success.
        } else {
            print("Couldn't append a SampleBuffer.")
        }
    }

    func detectFormatChange(imageBuffer: CVPixelBuffer) {
        if (self.videoFormatDescription == nil ||
            CMVideoFormatDescriptionMatchesImageBuffer(self.videoFormatDescription!, imageBuffer: imageBuffer) == false) {
            let status = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: imageBuffer, formatDescriptionOut: &self.videoFormatDescription)

            if let format = self.videoFormatDescription {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format)
                let pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer)
                let utf16 = [
                    UInt16((pixelFormat >> 24) & 0xFF),
                    UInt16((pixelFormat >> 16) & 0xFF),
                    UInt16((pixelFormat >> 8) & 0xFF),
                    UInt16((pixelFormat & 0xFF)) ]
                let pixelFormatString = String(utf16CodeUnits: utf16, count: 4)
                print("Detected format change: \(dimensions.width) x \(dimensions.height) - \(pixelFormatString)")
            } else {
                print("Failed to create output format description with status: \(status)")
            }
        }
    }

    func updateVideoSize(_ videoSize: CMVideoDimensions, orientation: VideoOrientation) {
        // The recorder inspects individual frames (including pixel format). As a result, there is nothing to do here.
    }
}
