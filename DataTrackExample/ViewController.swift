//
//  ViewController.swift
//  DataTrackExample
//
//  Copyright © 2017-2019 Twilio. All rights reserved.
//

import UIKit
import TwilioVideo

class Drawer : NSObject {
    var startingPoint: CGPoint!
    var shapeLayer: CAShapeLayer!
    var color: CGColor!
    
    convenience init(_ penColor: CGColor) {
        self.init()
        
        color = penColor
        startingPoint = CGPoint(x: 0, y: 0)
        shapeLayer = CAShapeLayer()
    }
}

class ViewController: UIViewController {
    
    // MARK:- View Controller Members
    
    // Configure access token manually for testing, if desired! Create one manually in the console
    // at https://www.twilio.com/console/video/runtime/testing-tools
    var accessToken = "TWILIO_ACCESS_TOKEN"
    
    // Configure remote URL to fetch token from
    let tokenUrl = "http://localhost:8000/token.php"
    
    // The web app sends messages prefixed with mouse so the message is serialized and
    // deserialized using this convention.
    let kTouchBegan = "mouseDown";
    let kTouchPoint = "mouseCoordinates";
    let kXCoordinate = "x";
    let kYCoordinate = "y";
    
    // Video SDK components
    var room: Room?
    var localDataTrack: LocalDataTrack!
    var localParticipant: LocalParticipant?
    
    // Private members
    var drawers = Dictionary<DataTrack, Drawer>()
    
    // By default app sends `Data`. Flip this flag to send json String instead.
    let useSendStringAPI = false
    
    // MARK:- UI Element Outlets and handles
    
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var roomTextField: UITextField!
    @IBOutlet weak var roomLine: UIView!
    @IBOutlet weak var roomLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.disconnectButton.isHidden = true
        self.roomTextField.autocapitalizationType = .none
        self.roomTextField.delegate = self
        self.connectButton.adjustsImageWhenDisabled = true
    }
    
    func connectToARoom() {
        self.connectButton.isEnabled = true
        
        let dataTrackOptions = DataTrackOptions() { (builder) in
            builder.isOrdered = true
            builder.name = "Draw"
        }
        
        self.localDataTrack = LocalDataTrack(options: dataTrackOptions)
        
        // Preparing the connect options with the access token that we fetched (or hardcoded).
        let connectOptions = ConnectOptions(token: accessToken) { (builder) in
            
            builder.dataTracks = [self.localDataTrack]

            // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty
            // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
            builder.roomName = self.roomTextField.text
        }

        // Connect to the Room using the options we provided.
        room = TwilioVideoSDK.connect(options: connectOptions, delegate: self)

        logMessage(messageText: "Attempting to connect to room \(String(describing: self.roomTextField.text))")

        self.showRoomUI(inRoom: true)
        self.dismissKeyboard()
    }

    // MARK:- IBActions
    @IBAction func connect(sender: AnyObject) {
        self.connectButton.isEnabled = false
        // Configure access token either from server or manually.
        // If the default wasn't changed, try fetching from server.
        if (accessToken == "TWILIO_ACCESS_TOKEN") {
            TokenUtils.fetchToken(from: tokenUrl) { [weak self]
                (token, error) in
                DispatchQueue.main.async {
                    if let error = error {
                        let message = "Failed to fetch access token:" + error.localizedDescription
                        self?.logMessage(messageText: message)
                        self?.connectButton.isEnabled = true
                        return
                    }
                    self?.accessToken = token;
                    self?.connectToARoom()
                }
            }
        } else {
            self.connectToARoom()
        }
    }
    
    @IBAction func disconnect(sender: AnyObject) {
        if let room = self.room {
            room.disconnect()
            logMessage(messageText: "Attempting to disconnect from room \(room.name)")
        }
    }
    
    // Update our UI based upon if we are in a Room or not
    func showRoomUI(inRoom: Bool) {
        self.connectButton.isHidden = inRoom
        self.roomTextField.isHidden = inRoom
        self.roomLine.isHidden = inRoom
        self.roomLabel.isHidden = inRoom
        self.disconnectButton.isHidden = !inRoom
        UIApplication.shared.isIdleTimerDisabled = inRoom
    }
    
    func dismissKeyboard() {
        if (self.roomTextField.isFirstResponder) {
            self.roomTextField.resignFirstResponder()
        }
    }
    
    func logMessage(messageText: String) {
        NSLog(messageText)
        messageLabel.text = messageText
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        if self.localParticipant == nil {
            return
        }
        
        // We don't support multi-touch and assume the first touch that began is the same one that moved later.
        
        if let location = touches.first?.location(in: self.view) {
            let drawer = drawers[localDataTrack!]
            drawer?.startingPoint = location
            
            let relativeTouchPoint = CGPoint(x: location.x / self.view.bounds.width,
                                             y: location.y / self.view.bounds.height)
            
            let dictionary = [self.kTouchBegan : true,
                              self.kTouchPoint : [ self.kXCoordinate : Float(relativeTouchPoint.x),
                                                   self.kYCoordinate : Float(relativeTouchPoint.y) ]] as [String : Any]
            send(dictionary)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        
        if self.localParticipant == nil {
            return
        }
        
        var touchPoint: CGPoint!
        if let location = touches.first?.location(in: self.view) {
            touchPoint = location
            let drawer = drawers[localDataTrack!]
            
            draw(touchPoint, drawer: drawers[localDataTrack!]!);
            drawer?.startingPoint = touchPoint
            
            let relativeTouchPoint = CGPoint(x: touchPoint.x / self.view.bounds.width,
                                             y: touchPoint.y / self.view.bounds.height)
            
            let dictionary = [self.kTouchBegan : false,
                              self.kTouchPoint : [ self.kXCoordinate : Float(relativeTouchPoint.x),
                                                   self.kYCoordinate : Float(relativeTouchPoint.y) ]] as [String : Any]
            send(dictionary)
        }
    }
    
    func send(_ dictionary: Dictionary<String, Any>) {
        if (self.useSendStringAPI) {
            let tmp = dictionary.description.replacingOccurrences(of: "[", with: "{")
            let jsonString = tmp.replacingOccurrences(of: "]", with: "}")
            
            NSLog("Sending json string \(jsonString)")
            self.localDataTrack?.send(jsonString)
        } else {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: dictionary, options: .prettyPrinted)
                NSLog ("Sending data \(dictionary)")
                self.localDataTrack?.send(jsonData)
            } catch {
                print(error.localizedDescription)
            }
        }
    }
    
    func draw(_ touchPoint: CGPoint, drawer: Drawer) {
        let path = UIBezierPath()
        path.move(to: touchPoint)
        path.addLine(to: drawer.startingPoint)
        
        if let combinedPath = drawer.shapeLayer.path?.mutableCopy() {
            combinedPath.addPath(path.cgPath)
            drawer.shapeLayer.path = combinedPath
        } else {
            drawer.shapeLayer.path = path.cgPath
        }
        
        if (self.view.layer.sublayers?.contains(drawer.shapeLayer!) == false) {
            drawer.shapeLayer.strokeColor = drawer.color
            self.view.layer.addSublayer(drawer.shapeLayer!)
            self.view.bringSubviewToFront(disconnectButton)
        }
    }
    
    func addDrawer(_ key: DataTrack, color: CGColor) {
        let drawer = Drawer(color)
        drawers[key] = drawer
    }
    
    func removeDrawer(_ key: DataTrack) {
        if let drawer = drawers[key] {
            drawer.shapeLayer.removeFromSuperlayer()
            drawers.removeValue(forKey: key)
        }
    }
}

// MARK:- UITextFieldDelegate
extension ViewController : UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.connect(sender: textField)
        return true
    }
}

// MARK:- RoomDelegate
extension ViewController : RoomDelegate {
    func roomDidConnect(room: Room) {
        self.localParticipant = room.localParticipant!
        self.addDrawer(self.localDataTrack, color: UIColor.black.cgColor)
        
        for remoteParticipant in room.remoteParticipants {
            remoteParticipant.delegate = self
        }

        logMessage(messageText: "Connected to room \(room.name) as \(String(describing: room.localParticipant?.identity))")
    }
    
    func roomDidDisconnect(room: Room, error: Error?) {
        logMessage(messageText: "Disconnected from room \(room.name), error = \(String(describing: error))")
        
        for (_, drawer) in self.drawers {
            drawer.shapeLayer!.removeFromSuperlayer()
        }
        self.drawers.removeAll(keepingCapacity: true)
        self.localParticipant = nil;
        self.room = nil
        
        self.showRoomUI(inRoom: false)
    }
    
    func roomDidFailToConnect(room: Room, error: Error) {
        logMessage(messageText: "Failed to connect to room with error: \(error.localizedDescription)")
        self.room = nil
        
        self.showRoomUI(inRoom: false)
    }

    func roomIsReconnecting(room: Room, error: Error) {
        logMessage(messageText: "Reconnecting to room \(room.name), error = \(String(describing: error))")
    }

    func roomDidReconnect(room: Room) {
        logMessage(messageText: "Reconnected to room \(room.name)")
    }

    func participantDidConnect(room: Room, participant: RemoteParticipant) {
        participant.delegate = self
        
        logMessage(messageText: "Participant \(participant.identity) connected with \(participant.remoteDataTracks.count) data, \(participant.remoteAudioTracks.count) audio and \(participant.remoteVideoTracks.count) video tracks")
    }
    
    func participantDidDisconnect(room: Room, participant: RemoteParticipant) {
        logMessage(messageText: "Room \(room.name), Participant \(participant.identity) disconnected")
    }
}

// MARK:- RemoteParticipantDelegate
extension ViewController : RemoteParticipantDelegate {
    func remoteParticipantDidPublishDataTrack(participant: RemoteParticipant, publication: RemoteDataTrackPublication) {
        // Remote Participant has offered to share the data Track.
        
        logMessage(messageText: "Participant \(participant.identity) published data track")
    }

    func remoteParticipantDidUnpublishDataTrack(participant: RemoteParticipant, publication: RemoteDataTrackPublication) {
        // Remote Participant has stopped sharing the data Track.
        
        logMessage(messageText: "Participant \(participant.identity) unpublished data track")
    }

    func didSubscribeToDataTrack(dataTrack: RemoteDataTrack, publication: RemoteDataTrackPublication, participant: RemoteParticipant) {
        // We are subscribed to the remote Participant's data Track. We will start receiving the
        // remote Participant's data messages now.
        
        self.addDrawer(dataTrack, color: UIColor.lightGray.cgColor)
        dataTrack.delegate = self
        
        logMessage(messageText: "Subscribed to data track for Participant \(participant.identity)")
    }
    
    func didUnsubscribeFromDataTrack(dataTrack: RemoteDataTrack, publication: RemoteDataTrackPublication, participant: RemoteParticipant) {
        // We are unsubscribed from the remote Participant's data Track. We will no longer receive the
        // remote Participant's data messages.
        
        self.removeDrawer(dataTrack)
        logMessage(messageText: "Unsubscribed from data track for Participant \(participant.identity)")
    }

    func didFailToSubscribeToDataTrack(publication: RemoteDataTrackPublication, error: Error, participant: RemoteParticipant) {
        logMessage(messageText: "FailedToSubscribe \(publication.trackName) data track, error = \(String(describing: error))")
    }
}

// MARK:- RemoteDataTrackDelegate
extension ViewController : RemoteDataTrackDelegate {
    func remoteDataTrackDidReceiveString(remoteDataTrack: RemoteDataTrack, message: String) {
        NSLog("remoteDataTrack:didReceiveString: \(message)" )
        
        if let data = message.data(using: .utf8) {
            processJsonData(remoteDataTrack, message: data)
        }
    }
    
    func remoteDataTrackDidReceiveData(remoteDataTrack: RemoteDataTrack, message: Data) {
        NSLog("remoteDataTrack:didReceiveData: \(message)" )
        processJsonData(remoteDataTrack, message: message)
    }
    
    func processJsonData(_ remoteDataTrack: RemoteDataTrack, message: Data) {
        do {
            var success = false
            if let jsonDictionary = try JSONSerialization.jsonObject(with: message, options: []) as? [String: AnyObject] {
                NSLog("processJsonData: \(jsonDictionary)" )
                
                if let touch = jsonDictionary[self.kTouchPoint] as? [String: AnyObject],
                    let pointX = touch[self.kXCoordinate] as? NSNumber,
                    let pointY = touch[self.kYCoordinate] as? NSNumber {
                    
                    let theTouchPoint = CGPoint(x: CGFloat(pointX.floatValue) * self.view.bounds.width,
                                                y: CGFloat(pointY.floatValue) * self.view.bounds.height)
                    
                    if let touchBegan = jsonDictionary[self.kTouchBegan] {
                        if (touchBegan).boolValue {
                            drawers[remoteDataTrack]!.startingPoint = theTouchPoint
                        } else {
                            draw(theTouchPoint, drawer: drawers[remoteDataTrack]!)
                            drawers[remoteDataTrack]!.startingPoint = theTouchPoint
                        }
                        success = true
                    }
                } else {
                    print("Unable to parse incoming JSON data. \(jsonDictionary)")
                }
            }
            if success == false {
                NSLog("Failed to parse json data")
            }
        } catch {
            NSLog("Error: processJsonData \(error)")
        }
    }
}
