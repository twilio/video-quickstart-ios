# Twilio Video ARKit Example

The project demonstrates how to use Twilio's Programmable Video SDK to stream an augmented reality scene created with ARKit and SceneKit. This example was originalyl provided as part of a blog post that you can find [here]().

### Setup

See the master [README](https://github.com/twilio/video-quickstart-swift/blob/master/README.md) for instructions on how to generate access tokens and connect to a Room.

This example requires Xcode 9.0, and the iOS 11.0 SDK. An iOS device with an A9 CPU or greater is needed for ARKit to function properly.

### Usage

At launch the example immediately begins capturing AR content with an `ARSession`. An `ARSCNView` is used to render the SceneKit virtual scene on top of the camera feed.

At the same time the Client will attempt to connect to a Room named `arkit`. If you wish to view the content being shared then simply join the same Room using the regular QuickStart example. This project does not demonstrate rendering remote video, but you will be able to hear the audio from other Participants and they will be able to see and hear you.

### Known Issues

The technique used to capture AR content rendered by SceneKit is somewhat un-optimized, and does not use the native sizes produced by `ARSession`. It may be possible to have SceneKit render into developer provided buffers (shared between the CPU and GPU), but we were unable to accomplish this while still using an `ARSCNView` for AR rendering.