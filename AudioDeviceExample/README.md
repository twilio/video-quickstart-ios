# Twilio Video TVIAudioDevice Example

The project demonstrates how to use Twilio's Programmable Video SDK with audio playback and recording functionality provided by a custom `TVIAudioDevice`.

The example demonstrates the following custom audio device(s):

**ExampleCoreAudioDevice**

Uses a RemoteIO audio unit to playback stereo audio at up to 48 kHz. In contrast to `TVIDefaultAudioDevice`, this class does not record audio and is intended for high quality playback. Since recording is not needed this device does not use the built in echo cancellation provided by CoreAudio's VoiceProcessingIO audio unit nor does it require microphone permissions from the user.

**ExampleAudioEngineDevice**

Coming soon.

Use AVAudioEngine to play and record Room audio, while mixing in sound effects.

### Setup

See the master [README](https://github.com/twilio/video-quickstart-swift/blob/master/README.md) for instructions on how to generate access tokens and connect to a Room.

This example requires Xcode 9.0 and the iOS 11.0 SDK, as well as a device running iOS 9.0 or above.

### Running

Once you have configured your access token, build and run the example. You will be presented with the following screen:

<kbd><img width="400px" src="../images/quickstart/audio-sink-launched.jpg"/></kbd>

Tap the "Connect" button to join a Room. Once you've joined you will be sharing video but not audio. In order to playback audio from a remote Participant you will need a Client which supports audio recording. The easiest way to do this is to build and run the normal QuickStart [example](https://github.com/twilio/video-quickstart-swift/tree/2.0.0-preview/VideoQuickStart) and join the same Room.

After the remote Participant has joined you should be able to hear their audio. Watch out if both devices are in the same physical space, because `ExampleCoreAudioDevice` does not use echo cancellation.

### Known Issues

The AVAudioSession is configured and activated at playback initialization time. Ideally, it would be better to activate the AVAudioSession only when audio playback is needed. 

You will also notice that backgrounding the application causes the signaling connection to die. 

Both issues are limitations with custom `TVIAudioDevice`s in `2.0.0-beta1` and we expect to rectify them in future releases.