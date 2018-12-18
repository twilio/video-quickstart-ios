# Twilio Video ScreenCapturer Example

> NOTE: `TVIScreenCapturer` is deprecated on iOS 12.0 and above due to performance issues on wide-color devices. If you wish to share the contents of the entire screen we recommend that you use [ReplayKit](https://developer.apple.com/documentation/replaykit) instead. Take a look at our ReplayKit example [app](../ReplayKitExample) to get started.

This project demonstrates how to implement your own `TVIVideoSource` to capture from the contents of a `WKWebView`. The approach is specific to the snasphotting APIs available in WebKit.framework since iOS 11.0.

`TVIScreenCapturer` is used on devices older than iOS 11.0, where the `UIGraphics` APIs do not suffer from the same performance issues as on iOS 12.0.

### Setup

This example does not connect to a Room, and thus does not require any access tokens or other configuration. Internet connectivity is required to load the contents of the `WKWebView`. Any device or simulator with iOS 9.0 or later may be used.

### FAQ

1. When should I use `ReplayKitVideoSource` vs `ExampleWebViewSource`?

Using ReplayKit means that you will require user consent in order to begin recording. Also, video captured by ReplayKit.framework includes your application's entire `UIWindow`, and the status bar.

If you only want a portion of the screen, and can accept some performance penalty consider writing a use-case based `TVIVideoSource` (like `ExampleWebViewSource`) instead.
