# Twilio Video TVIAudioSink Example

The project demonstrates how to use Twilio's Programmable Video SDK to access raw audio samples using the `TVIAudioSink` API on `TVIAudioTrack`. Local and remote audio is recorded using `AVFoundation.framework` and speech is recognized using `Speech.framework`.

### Setup

See the master [README](https://github.com/twilio/video-quickstart-swift/blob/master/README.md) for instructions on how to generate access tokens and connect to a Room.

This example requires Xcode 9.0, and a device running iOS 10.0 or above.

### Usage

TODO. Add screenshots and instructions on how to use.

### Known Issues

Local audio samples are not raised until at least one underlying WebRTC PeerConnection is negotiated. In a Peer-to-Peer Room it is not possible to record or recognize audio until at least one other Participant joins. The same limitation does not apply to Group Rooms where there is a persistent PeerConnection with Twilio's media servers.
