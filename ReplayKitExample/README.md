# Twilio Video ReplayKit Example

The project demonstrates how to integrate Twilio's Programmable Video SDK with `ReplayKit.framework`.

Two distinct use cases are covered:

**Conferencing (In-App)**

Use `RPScreenRecorder` to capture the screen and play/record audio using `TVIDefaultAudioDevice`. After joining a Room you will be able to hear other Participants, and they will be able to hear you, and see the contents of your screen.

When using the "in-process" `RPScreenRecorder` APIs, you may only capture content from your own application. Screen capture is suspended upon entering the backround.

**Broadcast (Extension)**

Use an `RPBroadcastSampleHandler` to capture the screen, and microphone audio.

An extension is not limited to capturing the screen of a single application. Instead, it is possible to capture any application including the home screen. While audio capture is possible (using `ExampleCoreAudioDevice`), playback is not allowed.

**ReplayKitVideoSource**

This `TVIVideoCapturer` produces `TVIVideoFrame`s from `CMSampleBuffer`s captured by ReplayKit. In order to reduce memory usage, this class may be configured (via `TVIVideoConstraints`) to downscale the captured content.

### Setup

See the master [README](https://github.com/twilio/video-quickstart-swift/blob/master/README.md) for instructions on how to generate access tokens and connect to a Room.

This example requires Xcode 10.0 and the iOS 12.0 SDK, as well as a device running iOS 11.0 or above.

### Running

Once you have setup your access token, install and run the example. You will be presented with the following screen:

< TODO, update image >

<kbd><img width="400px" src="../images/quickstart/audio-sink-launched.jpg"/></kbd>

### Betterments

1. Use a faster resizing filter than Lancoz3. We spend a lot of CPU resizing buffers from ReplayKit.
2. Pre-allocate resizing filter, and call `vImageVerticalShear_Planar8` etc. directly.
3. Pre-allocate temporary buffers needed for resizing.
4. Use a `CVPixelBufferPool` to constrain memory usage and to improve buffer reuse (fewer `CVPixelBuffer` allocations).
5. Presrve color tags when downscaling `CVPixelBuffer`s.
6. Support capturing both application and microphone audio at the same time, in an extension. Down-mix the resulting audio samples into a single stream.

### Known Issues

**1. Memory Usage**

Memory usage in a ReplayKit Broadcast Extension is limited to 50 MB (as of iOS 12.0). There are cases where Twilio Video can use more than this amount, especially when capturing larger 2x and 3x retina screens. This example uses downscaling to reduce the amount of memory needed by our process.

<kbd><img width="400px" src="../images/quickstart/replaykit-extension-memory.png"/></kbd>

Using the H.264 video codec, and a Group Room incurs the lowest memory cost.

**2. RPScreenRecorder debugging**

It is possible to get ReplayKit into an inconsistent state when setting breakpoints in `RPScreenRecorder` callbacks. If you notice that capture is starting but no audio/video samples are being produced, then you should consider resetting Media Services on your device.

First, end your debugging session and then navigate to: 

**Settings > Developer > Reset Media Services**

<kbd><img width="400px" src="../images/quickstart/replaykit-reset-media-services.png"/></kbd>

**3. Extension Debugging**

It is possible to get ReplayKit into an inconsistent state when debugging `RPBroadcastSampleHandler` callbacks. If this occurs you may notice the following error:

> Broadcast did finish with error: Error Domain=com.apple.ReplayKit.RPRecordingErrorDomain Code=-5808 "Attempted to start an invalid broadcast session" UserInfo={NSLocalizedDescription=Attempted to start an invalid broadcast session}

This problem may be solved by deleting and re-installing the example app.
