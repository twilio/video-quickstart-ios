//
//  ExampleVideoRecorder.swift
//  VideoRendererExample
//
//  Copyright © 2017 Twilio Inc. All rights reserved.
//

import AVFoundation
import Foundation
import TwilioVideo

class ExampleVideoRecorder : NSObject, TVIVideoRenderer {
    let identifier : String
    let videoTrack : TVIVideoTrack

    var recorderTimestamp = kCMTimeInvalid
    var videoFormatDescription: CMFormatDescription?
    var videoRecorder : AVAssetWriter?
    var videoRecorderInput : AVAssetWriterInput?

    // Register pixel formats that are known to work with AVAssetWriterInput.
    var optionalPixelFormats: [NSNumber] = [NSNumber.init(value: TVIPixelFormat.formatYUV420BiPlanarFullRange.rawValue),
                                            NSNumber.init(value: TVIPixelFormat.formatYUV420BiPlanarVideoRange.rawValue),
                                            NSNumber.init(value: TVIPixelFormat.format32BGRA.rawValue)]

    init(videoTrack: TVIVideoTrack, identifier: String) {
        self.videoTrack = videoTrack
        self.identifier = identifier

        super.init()

        startRecording()
    }

    func startRecording() {
        do {
            self.videoRecorder = try AVAssetWriter.init(url:ExampleVideoRecorder.recordingURL(identifier: identifier) , fileType: AVFileTypeMPEG4)
        } catch {
            print("Could not create AVAssetWriter with error: \(error)")
            return
        }

        // TODO: Determine width and height dynamically.
        let outputSettings = [
//            AVVideoCodecKey : AVVideoCodecType.h264,
            AVVideoWidthKey : 640,
            AVVideoHeightKey : 480,
            AVVideoScalingModeKey : AVVideoScalingModeResizeAspect] as [String : Any]

        videoRecorderInput = AVAssetWriterInput.init(mediaType: AVMediaTypeVideo, outputSettings: outputSettings)
        videoRecorderInput?.expectsMediaDataInRealTime = true

        if let videoRecorder = self.videoRecorder,
            let videoRecorderInput = self.videoRecorderInput,
            videoRecorder.canAdd(videoRecorderInput) {
            videoRecorder.add(videoRecorderInput)

            if (videoRecorder.startWriting()) {
                videoTrack.addRenderer(self)
            } else {
                print("Could not start writing!")
            }
        } else {
            print("Could not add AVAssetWriterInput!")
        }

        // This example does not support backgrounding. Now is a good point to consider kicking off a background
        // task, and handling failures.
    }

    func stopRecording() {
        videoTrack.removeRenderer(self)
        videoRecorderInput?.markAsFinished()
        videoRecorder?.finishWriting {
            if (self.videoRecorder?.status == AVAssetWriterStatus.failed) {

            } else if (self.videoRecorder?.status == AVAssetWriterStatus.completed) {
                
            }
            self.videoRecorder = nil
            self.videoRecorderInput = nil
            self.recorderTimestamp = kCMTimeInvalid
        }
    }

    class func recordingURL(identifier: String) -> URL {
        // TODO
        return (URL.init(string: ""))!
    }

//        + (NSURL *)recordingURLWithIdentifier:(NSString *)identifier {
//    NSURL *documentsDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
//
//    // Choose a filename which will be unique if the `identifier` is reused (Append RFC3339 formatted date).
//    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
//    dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
//    dateFormatter.dateFormat = @"HHmmss";
//    dateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
//
//    NSString *dateComponent = [dateFormatter stringFromDate:[NSDate date]];
//    NSString *filename = [NSString stringWithFormat:@"%@-%@.wav", identifier, dateComponent];
//
//    return [documentsDirectory URLByAppendingPathComponent:filename];
//    }

}

extension ExampleVideoRecorder {
    func renderFrame(_ frame: TVIVideoFrame) {
        // Frames are delivered with presentation timestamps. We will make do with this for our recorder.
        let timestamp = frame.timestamp

        if (CMTIME_IS_INVALID(recorderTimestamp)) {
            print("Received first video sample at: \(timestamp). Starting recording session.")
            self.recorderTimestamp = timestamp
            self.videoRecorder?.startSession(atSourceTime: timestamp)
        }

        detectFormatChange(imageBuffer: frame.imageBuffer)

        // Our uncompressed buffers do not need to be decoded.
        var sampleTiming = CMSampleTimingInfo.init(duration: kCMTimeInvalid,
                                                   presentationTimeStamp: timestamp,
                                                   decodeTimeStamp: kCMTimeInvalid)

        // Create a CMSampleBuffer
        // TODO: Support I420 inputs
//        let pixelFormat = CVPixelBufferGetPixelFormatType(frame.imageBuffer)
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
                                                              frame.imageBuffer,
                                                              self.videoFormatDescription!,
                                                              &sampleTiming,
                                                              &sampleBuffer)

        if (status != kCVReturnSuccess) {
            print("Couldn't create a SampleBuffer. Status=\(status)")
        } else if let buffer = sampleBuffer,
            let input = videoRecorderInput,
            input.append(buffer) {
            // Success.
        } else {
            print("Couldn't append a SampleBuffer.")
        }
    }

    func detectFormatChange(imageBuffer: CVPixelBuffer) {
        if (self.videoFormatDescription == nil ||
            CMVideoFormatDescriptionMatchesImageBuffer(self.videoFormatDescription!, imageBuffer) == false) {
            let status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, imageBuffer, &self.videoFormatDescription)

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

    func updateVideoSize(_ videoSize: CMVideoDimensions, orientation: TVIVideoOrientation) {
    }
}
