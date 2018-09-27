# Twilio Video ScreenCapturer Example

> NOTE: `TVIScreenCapturer` is deprecated on iOS 12.0 and above due to performance issues on wide-color devices. If you wish to share the contents of the screen we recommend that you use [ReplayKit](https://developer.apple.com/documentation/replaykit) instead. We are currently working on a ReplayKit example [app](https://github.com/twilio/video-quickstart-swift/pull/287).

This project demonstrates how to use `TVIScreenCapturer`, or a custom class (`ExampleScreenCapturer`) to capture the contents of a `UIView`. In this case, we are targeting a `WKWebView`, but the approach is suitably generic to work with any `UIView`.

### Setup

This example does not connect to a Room, and thus does not require any access tokens or other configuration. Internet connectivity is required to load the contents of the `WKWebView`. Any device or simulator with iOS 9.0 or later may be used.
