# Twilio Video Screen Capturer Example

> NOTE: `TVIScreenCapturer` has been removed in `3.x`. If you wish to share the contents of the entire screen we recommend that you use [ReplayKit](https://developer.apple.com/documentation/replaykit) instead. Take a look at our ReplayKit example [app](../ReplayKitExample) to get started.

This project demonstrates how to write your own `TVIVideoSource` to capture the contents of a `WKWebView` using the snasphotting APIs [available in WebKit.framework](https://developer.apple.com/documentation/webkit). Since snapshots include only a subset of the view hierarchy, they do offer some flexibility over screen sharing solutions like ReplayKit.


### Setup

This example does not connect to a Room, and thus does not require any access tokens or other configuration. Internet connectivity is required to load the contents of the `WKWebView`. Any device or simulator with iOS 12.0 or later may be used.

### FAQ

1. When should I use `ReplayKitVideoSource` vs `ExampleWebViewSource`?

Using ReplayKit means that you will require user consent in order to begin recording. Also, video captured by ReplayKit.framework includes your application's entire `UIWindow`, and the status bar.

If you only want to share a portion of the view hierarchy, and can accept some performance penalty consider writing a use-case based `TVIVideoSource` (like `ExampleWebViewSource`) instead.

### Known Issues

1. Snapshots captured on iOS simulators appear to include pre-multiplied alpha, but the alpha channel is always opaque (0xFF). Without proper alpha information it is impossible to un-premultiply the data and the images look too dim. This issue does not occur on a real device.
