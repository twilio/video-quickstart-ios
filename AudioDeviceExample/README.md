# Twilio Video TVIAudioDevice Example

The project demonstrates how to use Twilio's Programmable Video SDK with audio playback and recording functionality provided by a custom `TVIAudioDevice`.

The example demonstrates the following custom audio device(s):

#### ExampleCoreAudioDevice

Uses a RemoteIO audio unit to playback stereo audio at up to 48 kHz. In contrast to `TVIDefaultAudioDevice`, this class does not record audio and is intended for high quality playback. Since recording is not needed this device does not use the built in echo cancellation provided by CoreAudio's VoiceProcessingIO audio unit nor does it require microphone permissions from the user.

### Setup

See the master [README](https://github.com/twilio/video-quickstart-swift/blob/master/README.md) for instructions on how to generate access tokens and connect to a Room.

This example requires Xcode 9.0 and the iOS 11.0 SDK, as well as a device running iOS 9.0 or above.

### Running

Once you have setup your access token, install and run the example. You will be presented with the following screen:

<kbd><img width="400px" src="../images/quickstart/audio-sink-launched.jpg"/></kbd>

TODO: Describe usage of the example and update screenshots.

### Known Issues

The AVAudioSession is configured and activated at playback initialization time. Ideally, it would be better to activate and deactivate audio playback.