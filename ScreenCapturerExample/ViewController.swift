//
//  ViewController.swift
//  ScreenCapturerExample
//
//  Copyright © 2016-2017 Twilio, Inc. All rights reserved.
//

import TwilioVideo
import UIKit
import WebKit
import AVFoundation

class ViewController : UIViewController {

    var localVideoTrack: TVILocalVideoTrack?
    var remoteView: TVIVideoView?
    var screenCapturer: TVIVideoCapturer?
    var webView: WKWebView?
    var webNavigation: WKNavigation?

    // Set this value to 'true' to use ExampleScreenCapturer instead of TVIScreenCapturer.
    let useExampleCapturer = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup a WKWebView, and request Twilio's website
        webView = WKWebView.init(frame: view.frame)
        webView?.navigationDelegate = self
        webView?.translatesAutoresizingMaskIntoConstraints = false
        webView?.allowsBackForwardNavigationGestures = true
        self.view.addSubview(webView!)

        let requestURL: URL = URL(string: "https://twilio.com")!
        let request = URLRequest.init(url: requestURL)
        webNavigation = webView?.load(request)

        setupLocalMedia()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        webView?.frame = self.view.bounds

        // Layout the remote video using frame based techniques. It's also possible to do this using autolayout
        if ((remoteView?.hasVideoData)!) {
            let dimensions = remoteView?.videoDimensions
            let remoteRect = remoteViewSize()
            let aspect = CGSize(width: CGFloat((dimensions?.width)!), height: CGFloat((dimensions?.height)!))
            let padding : CGFloat = 10.0
            let boundedRect = AVMakeRect(aspectRatio: aspect, insideRect: remoteRect).integral
            remoteView?.frame = CGRect(x: self.view.bounds.width - boundedRect.width - padding,
                                       y: self.view.bounds.height - boundedRect.height - padding,
                                       width: boundedRect.width,
                                       height: boundedRect.height)
        } else {
            remoteView?.frame = CGRect.zero
        }
    }

    func setupLocalMedia() {
        // Setup screen capturer
        let capturer: TVIVideoCapturer
        if (useExampleCapturer) {
            capturer = ExampleScreenCapturer.init(aView: self.webView!)
        } else {
            capturer = TVIScreenCapturer.init(view: self.webView!)
        }

        localVideoTrack = TVILocalVideoTrack.init(capturer: capturer, enabled: true, constraints: nil, name: "Screen")

        if (localVideoTrack == nil) {
            presentError(message: "Failed to add screen capturer track!")
            return;
        }

        screenCapturer = capturer;

        // Setup rendering
        remoteView = TVIVideoView.init(frame: CGRect.zero, delegate: self)
        localVideoTrack?.addRenderer(remoteView!)

        remoteView!.isHidden = true
        self.view.addSubview(self.remoteView!)
        self.view.setNeedsLayout()
    }

    func presentError( message: String) {
        print(message)
    }

    func remoteViewSize() -> CGRect {
        let traits = self.traitCollection
        let width = traits.horizontalSizeClass == UIUserInterfaceSizeClass.regular ? 188 : 160;
        let height = traits.horizontalSizeClass == UIUserInterfaceSizeClass.regular ? 188 : 120;
        return CGRect(x: 0, y: 0, width: width, height: height)
    }
}

// MARK: WKNavigationDelegate
extension ViewController : WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("WebView:", webView, "finished navigation:", navigation)

        self.navigationItem.title = webView.title
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let message = String(format: "WebView:", webView, "did fail navigation:", navigation, error as CVarArg)
        presentError(message: message)
    }
}

// MARK: TVIVideoViewDelegate
extension ViewController : TVIVideoViewDelegate {
    func videoViewDidReceiveData(_ view: TVIVideoView) {
        if (view == remoteView) {
            remoteView?.isHidden = false
            self.view.setNeedsLayout()
        }
    }

    func videoView(_ view: TVIVideoView, videoDimensionsDidChange dimensions: CMVideoDimensions) {
        self.view.setNeedsLayout()
    }
}
