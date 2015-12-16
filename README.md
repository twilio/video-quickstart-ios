# video-quickstart-objc
Twilio Video starter iOS application in ObjC

## Configuring the App

This application should give you a ready-made starting point for writing your
own video apps with Twilio Video. Before we begin, we need to get the access token. 

You can retrieve the access token from [here](https://www.twilio.com/user/account/video/getting-started).
Just select iOS as your platform and you'll be able to generate an access token. Under the **listenForInvites** method in **CreateConversationViewController.m** replace this line

        NSString *accessToken = @"access_token";

with the access token you copied. 

## Installing Dependencies

After downloading or cloning the app, in a terminal window enter the following

        pod install --verbose

This will install the necessary dependencies, TwilioCommon and TwilioConversationsClient. The download may take a few minutes so grab some coffee while you wait. Once they are installed you
can go ahead and open QuickStart.xcworkspace. 


##Running the app

You should now be ready to rock! Type in a username to invite in the first view and hit
the invite button. If you typed in a valid name, you'll see their screen pop up in the view. Begin your video chatting
adventure!

![screenshot of chat app](http://i.imgur.com/sqPwNTw.jpg)

## License

MIT
