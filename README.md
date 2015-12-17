# Video iOS Quickstart for Swift

Looking for Objective-C instead? [Check out this application](https://github.com/twilio/video-quickstart-objc).

This application should give you a ready-made starting point for writing your
own video chatting apps with Twilio Video. Before we begin, we need to collect
all the credentials we need to run the application:

Credential | Description
---------- | -----------
Twilio Account SID | Your main Twilio account identifier - [find it on your dashboard](https://www.twilio.com/user/account/video).
Twilio Video Configuration SID | Adds video capability to the access token - [generate one here](https://www.twilio.com/user/account/video/profiles)
API Key | Used to authenticate - [generate one here](https://www.twilio.com/user/account/messaging/dev-tools/api-keys).
API Secret | Used to authenticate - [just like the above, you'll get one here](https://www.twilio.com/user/account/messaging/dev-tools/api-keys).

## Setting Up The PHP Application

A Video application has two pieces - a client (our iOS app) and a server.
You can learn more about what the server app does [by going through this guide](https://www.twilio.com/docs/api/video/guides/identity).
For now, let's just get a simple server running so we can use it to power our
iOS application.

<a href="https://github.com/TwilioDevEd/video-quickstart-php/archive/master.zip" target="_blank">
    Download server app for PHP
</a>

Create a configuration file for your application:

```bash
cp config.example.php config.php
```

Edit `config.php` with the four configuration parameters we gathered from above.

Now we should be all set! Run the application using the `php -S` command.

```bash
php -S localhost:8000
```

Alternately, you could simple place the contents of this project directly in the
webroot of your server and visit `index.html`.

Your application should now be running at [http://localhost:8000](http://localhost:8000). 
Send an invite to another user in another browser tab/window and start video chatting!

Now that our server is set up, let's get the starter iOS app up and running.

## PLEASE NOTE

The source code in this application is set up to communicate with a server
running at `http://localhost:8000`, as if you had set up the PHP server in this
README. If you run this project on a device, it will not be able to access your
token server on `localhost`.

To test on device, your server will need to be on the public Internet. For this,
you might consider using a solution like [ngrok](https://ngrok.com/). You would
then update the `localhost` URL in the `ViewController` with your new public
URL.

## Configure and Run the Mobile App

Our mobile application manages dependencies via [Cocoapods](https://cocoapods.org/).
Once you have Cocoapods installed, download or clone this application project to
your machine.  To install all the necessary dependencies from Cocoapods, run:

```
pod install
```

Open up the project from the Terminal with:

```
open VideoQuickStart.xcworkspace
```

Note that you are opening the `.xcworkspace` file rather than the `xcodeproj`
file, like all Cocoapods applications. You will need to open your project this
way every time. You should now be able to press play and run the project in the 
simulator. Assuming your PHP backend app is running on `http://localhost:8000`, 
there should be no further configuration necessary.

You're all set! From here, you can start building your own application. For guidance
on integrating the iOS SDK into your existing project, [head over to our install guide](https://www.twilio.com/docs/api/video/sdks).
If you'd like to learn more about how Video works, you might want to dive
into our [user identity guide](https://www.twilio.com/docs/api/video/guides/identity), 
which talks about the relationship between the mobile app and the server.

Good luck and have fun!

## License

MIT
