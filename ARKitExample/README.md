# Twilio Video ARKit Example

The project demonstrates how to use Twilio's Programmable Video SDK to stream an augmented reality scene created with ARKit and SceneKit. This example was originally written by [Lizzie Siegle](https://github.com/elizabethsiegle/) for her blog post about [ARKit](https://www.twilio.com/blog/2017/10/ios-arkit-swift-twilio-programmable-video.html).

### Setup

See the master [README](https://github.com/twilio/video-quickstart-ios/blob/master/README.md) for instructions on how to generate access tokens and connect to a Room.

This example requires Xcode 12.0, and the iOS 14.0 SDK. An iOS device with an A9 CPU or greater is needed for ARKit to function properly.

### Usage

At launch the example immediately begins capturing AR content with an `ARSession`. An `ARSCNView` is used to render the SceneKit virtual scene on top of the camera feed.

At the same time the Client will attempt to connect to a Room named `arkit`. To view the AR content being shared join the same Room using the regular QuickStart example. For this to work properly **you need to generate a new access token with a different identity** otherwise you will kick out the existing ARKit Participant.

Please note that this project does not demonstrate rendering remote video, but you will be able to hear the audio from other Participants and they will be able to see and hear you.

### Known Issues

The technique used to capture AR content rendered by SceneKit is somewhat un-optimized, and does not use the native sizes produced by `ARSession`. It may be possible to have SceneKit render into developer provided buffers (shared between the CPU and GPU), but we were unable to accomplish this while still using an `ARSCNView` for rendering.
