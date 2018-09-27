# Twilio Video ScreenCapturer Example

> NOTE: `TVIScreenCapturer` is deprecated on iOS 12.0 and above due to performance issues on wide-color devices. If you wish to share the contents of the screen we recommend that you use [ReplayKit](https://developer.apple.com/documentation/replaykit) instead. We are currently working on a ReplayKit example [app](https://github.com/twilio/video-quickstart-swift/pull/287).

This project demonstrates how to use `TVIScreenCapturer`, or a custom class (`ExampleScreenCapturer`) to capture the contents of a `UIView`. In this case, we are targeting a `WKWebView`, but the approach is suitably generic to work with any `UIView`.

### Setup

See the master [README](https://github.com/twilio/video-quickstart-swift/blob/master/README.md) for instructions on how to generate access tokens and connect to a Room.

This example requires a device running iOS 9.0 or above.