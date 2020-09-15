//
//  ExampleAVPlayerAudioTap.swift
//  CoViewingExample
//
//  Copyright © 2018 Twilio Inc. All rights reserved.
//

import Foundation
import MediaToolbox

class ExampleAVPlayerAudioTap {

    static func mediaToolboxAudioProcessingTapCreate(audioTap: ExampleAVPlayerAudioTap) -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(audioTap).toOpaque()),
            init: audioTap.tapInit,
            finalize: audioTap.tapFinalize,
            prepare: audioTap.tapPrepare,
            unprepare: audioTap.tapUnprepare,
            process: audioTap.tapProcess
        )

        var tap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault,
                                                &callbacks,
                                                kMTAudioProcessingTapCreationFlag_PostEffects,
                                                &tap)

        if status == kCVReturnSuccess {
            return tap!.takeUnretainedValue()
        } else {
            return nil
        }
    }

    let tapInit: MTAudioProcessingTapInitCallback = { (tap, clientInfo, tapStorageOut) in
        let nonOptionalSelf = clientInfo!.assumingMemoryBound(to: ExampleAVPlayerAudioTap.self).pointee
        print("init:", tap, clientInfo as Any, tapStorageOut, nonOptionalSelf)
    }

    let tapFinalize: MTAudioProcessingTapFinalizeCallback = {
        (tap) in
        print(#function)
    }

    let tapPrepare: MTAudioProcessingTapPrepareCallback = {(tap, b, c) in
        print("Prepare:", tap, b, c)
    }

    let tapUnprepare: MTAudioProcessingTapUnprepareCallback = {(tap) in
        print("Unprepare:", tap)
    }

    let tapProcess: MTAudioProcessingTapProcessCallback = {
        (tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut) in
        print("Process callback:", tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut)

        let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
        if status != kCVReturnSuccess {
            print("Failed to get source audio: ", status)
        }
    }
}
