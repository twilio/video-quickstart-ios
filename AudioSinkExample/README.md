# Twilio Video TVIAudioSink Example

The project demonstrates how to use Twilio's Programmable Video SDK to access raw audio samples using the `TVIAudioSink` API on `TVIAudioTrack`. Local and remote audio is recorded using `AVFoundation.framework` and speech is recognized using `Speech.framework`.

### Setup

See the master [README](https://github.com/twilio/video-quickstart-ios/blob/3.x/README.md) for instructions on how to generate access tokens and connect to a Room.

This example requires Xcode 11.0 and the iOS 12.0 SDK, as well as a device running iOS 11.0 or above.

### Running

Once you have setup your access token, install and run the example. You will be presented with the following screen:

<kbd><img width="400px" src="../images/quickstart/audio-sink-launched.jpg"/></kbd>

After you connect to a Room tap on your camera preview to begin recognizing local audio. As you speak `ExampleSpeechRecognizer` will attempt to use `Speech.Framework` to transcribe your speech and display the text on screen. Once other Participants join you can select their video to recognize remote speech.

<kbd><img width="400px" src="../images/quickstart/audio-sink-recognizing.jpg"/></kbd>

Audio is automatically recorded when you join a Room. After disconnecting, tap "Recordings" to browse a list of your `TVIAudioTrack`s recorded using `ExampleAudioRecorder`. Select a recording cell to begin playback using `AVPlayerViewController`, or swipe to delete the file.

<kbd><img width="400px" src="../images/quickstart/audio-sink-recordings.png"/></kbd>

### Known Issues

1. Local audio samples are not raised until at least one underlying WebRTC PeerConnection is negotiated. In a Peer-to-Peer Room it is not possible to record or recognize audio until at least one other Participant joins. The same limitation does not apply to Group Rooms where there is a persistent PeerConnection with Twilio's media servers.
2. When a `TVIAudioSink` is added to a `TVIRemoteAudioTrack` and encoded audio has not been received yet, the media engine outputs (1-channel / 16 kHz) silence. In order for `ExampleAudioRecorder` to determine the correct recording format it detects and discards initial silence and waits for the first decoded samples.