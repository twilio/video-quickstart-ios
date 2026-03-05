# Virtual Background Processor Example

This is an example of using the Twilio Virtual Background plug-in to blur the background or replace the background with an image.

## TwilioVirtualBackgrounds framework

The example requires the `TwilioVirtualBackgroundProcessors.xcframework`. Add the [twilio-virtual-background-processors-ios repository](https://github.com/twilio/twilio-virtual-background-processors-ios) via SwiftPM.

## Using the plug-in

Create the `TVICameraSource` with the virtual background plug-in then use the camera source to initialize the local video track. Example:

```
    if let blurFilterRadius = Settings.shared.backgroundBlurRadius, blurFilterRadius.floatValue > 0 {
        backgroundProcessor = DefaultBackgroundProcessor(blurFilterRadius: blurFilterRadius)
        camera = CameraSource(options: options, delegate: self, backgroundProcessorDelegate: backgroundProcessor!)
    } else if let image = Settings.shared.backgroundImage {
        backgroundProcessor = DefaultBackgroundProcessor(backgroundImage: image)
        camera = CameraSource(options: options, delegate: self, backgroundProcessorDelegate: backgroundProcessor!)
    } else {
        camera = CameraSource(options: options, delegate: self)
    }

    localVideoTrack = LocalVideoTrack(source: camera!, enabled: true, name: "camera")

    camera!.startCapture(device: frontCamera != nil ? frontCamera! : backCamera!) { (captureDevice, videoFormat, error) in
        // ...
    }
```

The background processor supports changing blur radius or background image on the flight without having to create a new background processor or camera source. Note that the plug-in will bypass the video frames if the blur radius is set to `0`. 

The plug-in also supports pause and resume processing by toggling the `pauseProcessing` property:
```
   background.pauseProcessing = true
```
