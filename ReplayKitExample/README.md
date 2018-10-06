# Twilio Video ReplayKit Example

The project demonstrates how to integrate Twilio's Programmable Video SDK with `ReplayKit.framework`. Two distinct use cases are covered:

**Conferencing (In-App)**

Use `RPScreenRecorder` to capture the screen and play/record audio using `TVIDefaultAudioDevice`. After joining a Room you will be able to hear other Participants, and they will be able to hear you, and see the contents of your screen.

When using the in-process `RPScreenRecorder` APIs, you may only capture content from your own application. Screen capture is suspended upon entering the backround. Once you being capturing, your application is locked to its current interface orientation.

**Broadcast (Extension)**

Use an `RPBroadcastSampleHandler` to receive audio and video samples. Video samples are routed to `ReplayKitVideoSource`, while `ExampleReplayKitAudioCapturer` handles audio. In order to reduce memory usage, the extension configures the capturer to downscsale the incoming video frames and prefers the use of the H.264 codec.

An iOS 12.0 extension is not limited to capturing the screen of a single application. In fact, it is possible to capture video from any application including the home screen.

**ReplayKitVideoSource**

This `TVIVideoCapturer` produces `TVIVideoFrame`s from `CMSampleBuffer`s captured by ReplayKit. In order to reduce memory usage, this class may be configured (via `TVIVideoConstraints`) to downscale the captured content.

**ExampleReplayKitAudioCapturer**

Audio capture in an extension is handled by `ExampleReplayKitAudioCapturer`, which consumes audio samples delivered by ReplayKit. Unfortunately, since we can't operate an Audio Unit graph in an extension, playback is not allowed.

### Setup

See the master [README](https://github.com/twilio/video-quickstart-swift/blob/master/README.md) for instructions on how to generate access tokens and connect to a Room.

You will need to provide a hardcoded token, or token server URL in [ViewController.swift](ReplayKitExample/ViewController.swift) for conferencing and in [SampleHandler.swift](BroadcastExtension/SampleHandler.swift) for the broadcast extension.

This example requires Xcode 10.0 and the iOS 12.0 SDK, as well as a device running iOS 11.0 or above. While the app launches on an iPhone Simulator, ReplayKit is non-functional.

### Running

Once you have setup your access token, install and run the example. You will be presented with the following screen:

**iOS 12**

<kbd><img width="360px" src="../images/quickstart/replaykit-launch-ios12.png"/></kbd>

**iOS 11**

<kbd><img width="360px" src="../images/quickstart/replaykit-launch-ios11.png"/></kbd>

From here you can tap "Start Broadcast" to begin using the broadcast extension. The extension will automatically join a room called "Broadcast", unless a Room is specified in your access token grants. Other participants can join using the QuickStart example, or any other example app which can display remote video.

<kbd><img width="360px" src="../images/quickstart/replaykit-picker-ios12.png"/></kbd>

Tapping "Start Conference" begins capturing and sharing the screen from within the main application. Please note that backgrounding the app during a conference will cause in-app capture to be suspended.

### Betterments

1. Use a faster resizing filter than Lancoz3. We spend a lot of CPU cycles resizing buffers from ReplayKit.
2. Pre-allocate temporary buffers needed for `vImageScale` methods, or use `vImageVerticalShear` methods directly.
3. Use a `CVPixelBufferPool` to constrain memory usage and to improve buffer reuse (fewer `CVPixelBuffer` allocations).
4. Preserve color tags when downscaling `CVPixelBuffer`s.
5. Support capturing both application and microphone audio at the same time, in an extension. Down-mix the resulting audio samples into a single stream.
6. Share the camera using ReplayKit (extension), or `TVIVideoCapturer` (in-process).

### Known Issues

**1. Memory Usage**

Memory usage in a ReplayKit Broadcast Extension is limited to 50 MB (as of iOS 12.0). There are cases where Twilio Video can use more than this amount, especially when capturing larger 2x and 3x retina screens. This example uses downscaling to reduce the amount of memory needed by our process.

<kbd><img width="400px" src="../images/quickstart/replaykit-extension-memory.png"/></kbd>

We have observed that using the H.264 video codec, and a Group Room incurs the lowest memory cost.

**2. RPScreenRecorder debugging**

It is possible to get ReplayKit into an inconsistent state when setting breakpoints in `RPScreenRecorder` callbacks. If you notice that capture is starting but no audio/video samples are being produced, then you should reset Media Services on your device.

First, end your debugging session and then navigate to: 

**Settings > Developer > Reset Media Services**

<kbd><img width="400px" src="../images/quickstart/replaykit-reset-media-services.png"/></kbd>

**3. Extension Debugging**

It is possible to get ReplayKit into an inconsistent state when debugging `RPBroadcastSampleHandler` callbacks. If this occurs you may notice the following error:

> Broadcast did finish with error: Error Domain=com.apple.ReplayKit.RPRecordingErrorDomain Code=-5808 "Attempted to start an invalid broadcast session" UserInfo={NSLocalizedDescription=Attempted to start an invalid broadcast session}

This problem may be solved by deleting and re-installing the example app.
