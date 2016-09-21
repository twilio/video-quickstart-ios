# Twilio Video Quick Start for Swift

Looking for Objective-C instead? [Check out this application](https://github.com/twilio/video-quickstart-objc).

## Up and Running

1) Create a Twilio Video [Configuration Profile](https://www.twilio.com/user/account/video/profiles). If you haven't used Twilio before, welcome! You'll need to [Sign up for a Twilio account](https://www.twilio.com/try-twilio).

2) Download this project and run `pod install` to install TwilioVideo.framework. Open VideoQuickstart.xcworkspace in Xcode

3) Generate an [Access Token](https://www.twilio.com/user/account/video/dev-tools/testing-tools). Pick your identity (such as Bob). Leave this web page open, because you'll use it as the other side of the video chat.

4) Paste the access token into ViewController.swift.

5) Run your app (preferably on an iOS device, but could be on the iOS simulator)

6) On the same web page where you generated the token, scroll down the bottom, put in the username that you generated the access token for, and click Create Conversation. Your video conversation should start immediately! 

## What is this project?

This quick start will help you get video chat integrated directly into your iOS applications using Twilio's Video SDK. This quick start is for Swift developers - if your app uses Objective-C, check out the [Twilio Video Quick Start for Objective-C](https://github.com/twilio/video-quickstart-objc). 

This sample app is written in Swift 3.0. You will need at least Xcode 8.0 in order to run the application.

You'll see how how to set up key classes like TVIVideoClient, TVIRoom, TVIParticipant, TVILocalMedia, and TVICameraCapturer. The ViewController implements the TVIRoomDelegate, and TVIParticipantDelegate protocols in order to display remote Participant video on screen. If you are using an iOS device then video from the local camera will be displayed as well.

## Prerequisites

This project uses Apple's Swift programming language 3.0 for iOS, and the only supported way to develop iOS apps is on an Apple computer running OS X and Xcode. We have tested this application with the latest versions of iOS (10.0) and Xcode (8.0) at the time of this writing.

You do not need to have an Apple iPhone, iPod Touch, or iPad for testing. You can use the iOS Simulator that comes with Xcode to do your testing, but local video will not be shared. If you have an iOS device, you can now run apps from Xcode on your device without a paid developer account.

## Twilio Library Setup for the Project

You will need to add the Twilio Video library to the project to compile and run. There are two different options for doing this:

1) Using the [Cocoapods](https://cocoapods.org/) dependency management system. 

2) Installing the Twilio Video framework yourself, using the directions on the [Twilio Video SDK Download Page](https://www.twilio.com/docs/api/video/sdks)

You only need to do one or the other, not both!

### Using Cocoapods

First, you will need to have Cocoapods 1.0.0+ installed on your Mac, so go ahead and do that if you haven't already - the directions are here: [Getting Started with Cocoapods](https://guides.cocoapods.org/using/getting-started.html). If you're not sure, type `pod --version` into a command line.

Next, just run `pod install` from the command line in the top level directory of this project. Cocoapods will install the Twilio library and then set up a .xcworkspace file that you will use to run your project from now on. 

### Manual Installation

Download the latest version of Twilio Video from the [SDK Download Page](https://www.twilio.com/docs/api/video/sdks). After uncompressing the downloaded files, drag and drop the framework (TwilioVideo.framework) into your project > Target > Embedded Binaries in Xcode. Make sure that the checkbox next to the VideoQuickStart target is checked. You may want to select the "Copy items if needed" option so you aren't referencing frameworks in your Downloads folder.

## Access Tokens and Servers

Using Twilio's Video client within your applications requires an access token. These access tokens can come from one of two places:

1) You can create a one-time use access token for testing on Twilio.com. This access token can be hard-coded directly into your mobile app, and you won't need to run your own server.

2) You can run your own server that provides access tokens, based on your Twilio credentials. This server can either run locally on your development machine, or it can be installed on a server. If you run the server on your local machine, you can use the ngrok utility to give the server an externally accessible web address. That way, you can run the quick start app on an actual device, instead of the iOS Simulator.

### Generating an Access Token

The first step is to [Generate an Access Token](https://www.twilio.com/user/account/video/dev-tools/testing-tools) from the Twilio developer console. Use whatever clever username you would like for the identity. You will get an access token that you can copy and paste into ViewController.swift.

Once you have that access token in place, scroll down to the bottom of the page and you will get a web-based video chat window in the Twilio developer console that you can use to communicate with your iPhone app! Just invite that identity you just named above!

### Setting up a Video Chat Web Server

If you want to be a little closer to a real environment, you can download one of the video quickstart applications - for instance, [Video Quickstart: PHP](https://github.com/TwilioDevEd/video-quickstart-php) and either run it locally, or install it on a server.

 You'll need to gather a couple of configuration options from your Twilio developer console before running it, so read the directions on the quickstart. You'll copy the config.example.php file to a config.php file, and then add in these credentials:
 
 Credential | Description
---------- | -----------
Twilio Account SID | Your main Twilio account identifier - [find it on your dashboard](https://www.twilio.com/user/account/video).
Twilio Video Configuration SID | Adds video capability to the access token - [generate one here](https://www.twilio.com/user/account/video/profiles)
API Key | Used to authenticate - [generate one here](https://www.twilio.com/user/account/messaging/dev-tools/api-keys).
API Secret | Used to authenticate - [just like the above, you'll get one here](https://www.twilio.com/user/account/messaging/dev-tools/api-keys).

#### A Note on API Keys

When you generate an API key pair at the URLs above, your API Secret will only
be shown once - make sure to save this in a secure location.

#### Running the Video Quickstart with ngrok

Because we suggest that you run your video chat application on actual iOS device so that you can use the camera on the device, you'll need to provide an externally accessible URL for the app (the iOS simulator will be fine with localhost). The [ngrok](https://ngrok.com/) tool creates a publicly accessible URL that you can use to send HTTP/HTTPS traffic to a server running on your localhost. Use HTTPS to make web connections that retrieve a Twilio access token.

When you get a URL from ngrok, go ahead and update ViewController.swift with the new URL.  If you go down this path, be sure to follow the directions in the comments in the viewDidLoad() method at the top of the source file - you will need to uncomment one line, and comment out another. You will also need to update the code if your ngrok URL changes.

For this quick start, the Application transport security settings are set to allow arbitrary HTTP loads for testing your app. For production applications, you'll definitely want to retrieve access tokens over HTTPS/SSL.

## Have fun!

This is an introduction to Twilio's Video SDK on iOS. From here, you can start building applications that use video chat across the web, iOS, and Android platforms.

## License

MIT
