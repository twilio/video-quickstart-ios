//
//  ViewController+CallKit.swift
//  VideoCallKitQuickStart
//
//  Copyright © 2016 Twilio. All rights reserved.
//

import UIKit

import TwilioVideo
import CallKit

extension ViewController : CXProviderDelegate {

    func providerDidReset(_ provider: CXProvider) {
        logMessage(messageText: "providerDidReset:")

        localMedia?.audioController.stopAudio()
    }

    func providerDidBegin(_ provider: CXProvider) {
        logMessage(messageText: "providerDidBegin")
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        logMessage(messageText: "provider:didActivateAudioSession:")

        localMedia?.audioController.startAudio()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        logMessage(messageText: "provider:didDeactivateAudioSession:")
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        logMessage(messageText: "provider:timedOutPerformingAction:")
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        logMessage(messageText: "provider:performStartCallAction:")

        localMedia?.audioController.configureAudioSession(.videoChatSpeaker)

        callKitProvider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)

        performRoomConnect(uuid: action.callUUID, roomName: action.handle.value)

        // Hang on to the action, as we will either fulfill it after we succesfully connect to the room, or fail
        // it if there is an error connecting.
        pendingAction = action
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        logMessage(messageText: "provider:performAnswerCallAction:")

        // NOTE: When using CallKit with VoIP pushes, the workaround from https://forums.developer.apple.com/message/169511 
        //       suggests configuring audio in the completion block of the `reportNewIncomingCallWithUUID:update:completion:` 
        //       method instead of in `provider:performAnswerCallAction:` per the Speakerbox example.
        // localMedia?.audioController.configureAudioSession()

        performRoomConnect(uuid: action.callUUID, roomName: self.roomTextField.text)

        // Hang on to the action, as we will either fulfill it after we succesfully connect to the room, or fail
        // it if there is an error connecting.
        pendingAction = action
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        NSLog("provider:performEndCallAction:")

        localMedia?.audioController.stopAudio()
        room?.disconnect()

        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        NSLog("provier:performSetMutedCallAction:")
        toggleMic(sender: self)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        NSLog("provier:performSetHeldCallAction:")

        let cxObserver = callKitCallController.callObserver
        let calls = cxObserver.calls

        guard let call = calls.first(where:{$0.uuid == action.callUUID}) else {
            action.fail()
            return
        }

        if call.isOnHold {
            holdCall(onHold: false)
        } else {
            holdCall(onHold: true)
        }

        action.fulfill()
    }
}

// MARK: Call Kit Actions
extension ViewController {

    func performStartCallAction(uuid: UUID, roomName: String?) {
        let callHandle = CXHandle(type: .generic, value: roomName ?? "")
        let startCallAction = CXStartCallAction(call: uuid, handle: callHandle)
        let transaction = CXTransaction(action: startCallAction)

        callKitCallController.request(transaction)  { error in
            if let error = error {
                NSLog("StartCallAction transaction request failed: \(error.localizedDescription)")
                return
            }

            NSLog("StartCallAction transaction request successful")

            let callUpdate = CXCallUpdate()
            callUpdate.remoteHandle = callHandle
            callUpdate.supportsDTMF = false
            callUpdate.supportsHolding = true
            callUpdate.supportsGrouping = false
            callUpdate.supportsUngrouping = false
            callUpdate.hasVideo = true

            self.callKitProvider.reportCall(with: uuid, updated: callUpdate)
        }
    }

    func reportIncomingCall(uuid: UUID, roomName: String?, completion: ((NSError?) -> Void)? = nil) {
        let callHandle = CXHandle(type: .generic, value: roomName ?? "")

        let callUpdate = CXCallUpdate()
        callUpdate.remoteHandle = callHandle
        callUpdate.supportsDTMF = false
        callUpdate.supportsHolding = true
        callUpdate.supportsGrouping = false
        callUpdate.supportsUngrouping = false
        callUpdate.hasVideo = true

        callKitProvider.reportNewIncomingCall(with: uuid, update: callUpdate) { error in
            if error == nil {
                NSLog("Incoming call successfully reported.")

                // NOTE: CallKit with VoIP push workaround per https://forums.developer.apple.com/message/169511
                self.localMedia?.audioController.configureAudioSession(.videoChatSpeaker)
            } else {
                NSLog("Failed to report incoming call successfully: \(error?.localizedDescription).")
            }

            completion?(error as? NSError)
        }
    }

    func performEndCallAction(uuid: UUID) {
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)

        callKitCallController.request(transaction) { error in
            if let error = error {
                NSLog("EndCallAction transaction request failed: \(error.localizedDescription).")
                return
            }

            NSLog("EndCallAction transaction request successful")
        }
    }

    func performRoomConnect(uuid: UUID, roomName: String?) {
        // Configure access token either from server or manually.
        // If the default wasn't changed, try fetching from server.
        if (accessToken == "TWILIO_ACCESS_TOKEN") {
            do {
                accessToken = try TokenUtils.fetchToken(url: tokenUrl)
            } catch {
                let message = "Failed to fetch access token"
                logMessage(messageText: message)
                return
            }
        }

        // Create a Client with the access token that we fetched (or hardcoded).
        if (client == nil) {
            client = TVIVideoClient(token: accessToken)
            if (client == nil) {
                logMessage(messageText: "Failed to create video client")
                return
            }
        }

        // Prepare local media which we will share with Room Participants.
        self.prepareLocalMedia()

        // Preparing the connect options
        let connectOptions = TVIConnectOptions { (builder) in

            // Use the local media that we prepared earlier.
            builder.localMedia = self.localMedia

            // The name of the Room where the Client will attempt to connect to. Please note that if you pass an empty
            // Room `name`, the Client will create one for you. You can get the name or sid from any connected Room.
            builder.name = roomName

            // The CallKit UUID to assoicate with this Room.
            builder.uuid = uuid
        }
        
        // Connect to the Room using the options we provided.
        room = client?.connect(with: connectOptions, delegate: self)
        
        logMessage(messageText: "Attempting to connect to room \(roomName)")
        
        self.showRoomUI(inRoom: true)
    }
}
