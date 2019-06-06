//
//  ViewController.swift
//  ScreenCapturerExample
//
//  Copyright © 2016-2019 Twilio, Inc. All rights reserved.
//

import TwilioVideo
import UIKit
import WebKit
import AVFoundation

class ViewController : UIViewController {

    var localVideoTrack: LocalVideoTrack?
    weak var localView: VideoView?

    // A source which uses snapshotting APIs to capture the contents of a WKWebView.
    var webViewSource: VideoSource?

    var webView: WKWebView?
    var webNavigation: WKNavigation?

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

        // Setup a renderer to preview what we are capturing.
        if let videoView = VideoView(frame: CGRect.zero, delegate: self) {
            self.localView = videoView

            localVideoTrack?.addRenderer(videoView)
            videoView.isHidden = true
            self.view.addSubview(videoView)
            self.view.setNeedsLayout()
        }
    }

    deinit {
        teardownLocalMedia()
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

        // Layout the remote video using frame based techniques. It's also possible to do this using autolayout.
        if let remoteView = self.localView {
            if remoteView.hasVideoData {
                var bottomRight = CGPoint(x: view.bounds.width, y: view.bounds.height)
                if #available(iOS 11.0, *) {
                    // Ensure the preview fits in the safe area.
                    let safeAreaGuide = self.view.safeAreaLayoutGuide
                    let layoutFrame = safeAreaGuide.layoutFrame
                    bottomRight.x = layoutFrame.origin.x + layoutFrame.width
                    bottomRight.y = layoutFrame.origin.y + layoutFrame.height
                }
                let dimensions = remoteView.videoDimensions
                let remoteRect = remoteViewSize()
                let aspect = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
                let padding : CGFloat = 10.0
                let boundedRect = AVMakeRect(aspectRatio: aspect, insideRect: remoteRect).integral
                remoteView.frame = CGRect(x: bottomRight.x - boundedRect.width - padding,
                                          y: bottomRight.y - boundedRect.height - padding,
                                          width: boundedRect.width,
                                          height: boundedRect.height)
            } else {
                remoteView.frame = CGRect.zero
            }
        }
    }

    func setupLocalMedia() {
        let source = ExampleWebViewSource(aView: self.webView!)

        guard let videoTrack = LocalVideoTrack(source: source, enabled: true, name: "Screen") else {
            presentError(message: "Failed to add ExampleWebViewSource video track!")
            return
        }

        self.localVideoTrack = videoTrack
        webViewSource = source
        source.startCapture()
    }

    func teardownLocalMedia() {
        // ExampleWebViewSource has an explicit API to start and stop capturing. Stop to break the retain cycle.
        if let source = self.webViewSource {
            let webSource = source as! ExampleWebViewSource
            webSource.stopCapture()
        }

        if let renderer = localView {
            localVideoTrack?.removeRenderer(renderer)
        }
        localVideoTrack = nil
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
extension ViewController : VideoViewDelegate {
    func videoViewDidReceiveData(view: VideoView) {
        if (view == localView) {
            localView?.isHidden = false
            self.view.setNeedsLayout()
        }
    }

    func videoViewDimensionsDidChange(view: VideoView, dimensions: CMVideoDimensions) {
        self.view.setNeedsLayout()
    }
}
