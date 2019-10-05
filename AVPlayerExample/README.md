# AVPlayer example for Objective-C

This example demonstrates how to use `AVPlayer` to stream Audio & Video content while connected to a `TVIRoom`.

### Setup

See the master [README](https://github.com/twilio/video-quickstart-ios/blob/2.x/README.md) for instructions on how to generate access tokens and connect to a Room.

## Usage

This example is very similar to the basic Quickstart. However, if you join a Room with no other Participants the app will stream media using `AVPlayer` while you wait. Once the first Participant joins the media content is paused and the remote video is shown in its place.

In order to use `AVPlayer` along with Twilio Video the `TVIAudioController+CallKit` APIs are used. Unlike normal CallKit operation, the application manually activates and deactivates `AVAudioSession` as needed.

## Known Issues

We are currently experiencing some problems with low output volume when `AVPlayer` content is mixed with remote Participant audio. This occurs when using the built-in device loudspeaker and microphone, but not when using headphones to monitor audio. For more information please refer to issue [#402](https://github.com/twilio/video-quickstart-ios/issues/402).
