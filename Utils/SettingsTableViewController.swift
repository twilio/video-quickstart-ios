//
//  SettingsTableViewController.swift
//  VideoQuickStart
//
//  Copyright © 2017 Twilio, Inc. All rights reserved.
//

import UIKit
import TwilioVideo

class SettingsTableViewController: UITableViewController {
    
    static let audioCodecLabel = "Audio Codec"
    static let videoCodecLabel = "Video Codec"
    static let maxAudioBitrate = "Max Audio Bitrate (bps)"
    static let maxVideoBitrate = "Max Video Bitrate (bps)"
    static let defaultStr = "Default"
    static let codecDisclaimerText = "Set your preferred audio and video codec. Not all codecs are supported in Group Rooms. The media server will fallback to OPUS or VP8 if a preferred codec is not supported. VP8 Simulcast should only be enabled in a Group Room."
    static let encodingParamsDisclaimerText = "Set sender bandwidth constraints. Zero represents the WebRTC default which varies by codec."
    
    let disclaimers = [codecDisclaimerText, encodingParamsDisclaimerText]
    let settings = Settings.shared
    let disclaimerFont = UIFont.preferredFont(forTextStyle: UIFontTextStyle.footnote)
    var labels: [[String]] = [[SettingsTableViewController.audioCodecLabel, SettingsTableViewController.videoCodecLabel],
                             [SettingsTableViewController.maxAudioBitrate, SettingsTableViewController.maxVideoBitrate]]

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Settings"
    }
    
    func getDisclaimerSizeForString(string: String!) -> CGSize {
        let disclaimerString: NSString = string as NSString
        
        return disclaimerString.boundingRect(with: CGSize(width: self.tableView.frame.width-20,
                                                          height: CGFloat.greatestFiniteMagnitude),
                                             options: NSStringDrawingOptions.usesLineFragmentOrigin,
                                             attributes: [NSFontAttributeName: disclaimerFont],
                                             context: nil).size
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return (labels.count)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return (labels[section].count)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SETTINGS-REUSE-IDENTIFIER", for: indexPath)
        
        // Configure the cell...
        let label = self.labels[indexPath.section][indexPath.row]
        cell.textLabel?.text = label
        var detailText = SettingsTableViewController.defaultStr
        
        switch (label) {
            case SettingsTableViewController.audioCodecLabel:
                if let codec = settings.audioCodec {
                    detailText = codec.name
                }
                break;
            
            case SettingsTableViewController.videoCodecLabel:
                if let codec = settings.videoCodec {
                    detailText = self.getDisplayStrForVideoCodec(codec: codec)
                }
                break;
            
            case SettingsTableViewController.maxAudioBitrate:
                detailText = String(settings.maxAudioBitrate)
                break;
            
            case SettingsTableViewController.maxVideoBitrate:
                detailText = String(settings.maxVideoBitrate)
                break;

            default:
                break;
        }
        cell.detailTextLabel?.text = detailText
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let tappedLabel = self.labels[indexPath.section][indexPath.row]
        
        switch (tappedLabel) {
            case SettingsTableViewController.audioCodecLabel:
                didSelectAudioCodecRow(indexPath: indexPath)
                break;

            case SettingsTableViewController.videoCodecLabel:
                didSelectVideoCodecRow(indexPath: indexPath)
                break;

            case SettingsTableViewController.maxAudioBitrate:
                didSelectMaxAudioBitRateRow(indexPath: indexPath)
                break
            
            case SettingsTableViewController.maxVideoBitrate:
                didSelectMaxVideoBitRateRow(indexPath: indexPath)
                break
            
            default:
                break;
        }
    }
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let view = UIView()
        
        let disclcaimer = UILabel(frame: CGRect(x:10, y:5,
                                                width:tableView.frame.width - 20,
                                                height:getDisclaimerSizeForString(string: disclaimers[section]).height))
        disclcaimer.font = disclaimerFont
        disclcaimer.text = disclaimers[section]
        disclcaimer.textColor = UIColor.darkGray
        disclcaimer.numberOfLines = 0
        
        view.addSubview(disclcaimer)
        
        return view;
    }
    
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return getDisclaimerSizeForString(string: disclaimers[section]).height + 10
    }
    
    func didSelectAudioCodecRow(indexPath: IndexPath) {
        var selectedButton : UIAlertAction!
        var defaultButton: UIAlertAction!
        
        let alertController = UIAlertController(title: self.labels[indexPath.section][indexPath.row], message: nil, preferredStyle: .actionSheet)
        let selectionArray = settings.supportedAudioCodecs
        
        for codec in selectionArray {
            let selectionButton = UIAlertAction(title: codec.name, style: .default, handler: { (action) -> Void in
                self.settings.audioCodec = codec
                self.tableView.reloadData()
            })
            
            if (settings.audioCodec == codec) {
                selectedButton = selectionButton;
            }
            
            alertController.addAction(selectionButton)
        }
        
        // The default action
        defaultButton = UIAlertAction(title: "Default", style: .default, handler: { (action) -> Void in
            self.settings.audioCodec = nil
            self.tableView.reloadData()
        })
        
        if selectedButton == nil {
            selectedButton = defaultButton;
        }
        
        alertController.addAction(defaultButton!)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            alertController.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            alertController.popoverPresentationController?.sourceRect = (tableView.cellForRow(at: indexPath)?.bounds)!
        } else {
            selectedButton?.setValue("true", forKey: "checked")
            
            // Adding the cancel action
            let cancelButton = UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) -> Void in })
            alertController.addAction(cancelButton)
        }
        self.navigationController!.present(alertController, animated: true, completion: nil)
    }
    
    func didSelectVideoCodecRow(indexPath: IndexPath) {
        var selectedButton : UIAlertAction!
        
        let defaultButton = UIAlertAction(title: "Default", style: .default, handler: { (action) -> Void in
            self.settings.videoCodec = nil
            self.tableView.reloadData()
        })
        
        let alertController = UIAlertController(title: self.labels[indexPath.section][indexPath.row], message: nil, preferredStyle: .actionSheet)
        let selectionArray = settings.supportedVideoCodecs
        
        for codec in selectionArray {
            let selectionButton = UIAlertAction(title: self.getDisplayStrForVideoCodec(codec: codec),
                                                style: .default,
                                                handler: { (action) -> Void in
                self.settings.videoCodec = codec
                self.tableView.reloadData()
            })
            
            if (settings.videoCodec == codec) {

                // Workaround for https://github.com/twilio/twilio-video-ios/issues/12
                if settings.videoCodec!.isKind(of: TVIVp8Codec.self) {
                    if codec.isKind(of: TVIVp8Codec.self) {
                        if ((codec as! TVIVp8Codec).isSimulcast == (settings.videoCodec as! TVIVp8Codec).isSimulcast) {
                            selectedButton = selectionButton;
                        }
                    }
                } else {
                    selectedButton = selectionButton;
                }
            }
            
            alertController.addAction(selectionButton)
        }
        
        if selectedButton == nil {
            selectedButton = defaultButton;
        }
        
        alertController.addAction(defaultButton)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            alertController.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            alertController.popoverPresentationController?.sourceRect = (tableView.cellForRow(at: indexPath)?.bounds)!
        } else {
            selectedButton?.setValue("true", forKey: "checked")
            
            // Adding the cancel action
            let cancelButton = UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) -> Void in })
            alertController.addAction(cancelButton)
        }
        self.navigationController!.present(alertController, animated: true, completion: nil)
    }
    
    func didSelectMaxAudioBitRateRow(indexPath: IndexPath) {
        let alertController = UIAlertController(title: self.labels[indexPath.section][indexPath.row], message: nil, preferredStyle: .alert)
        
        alertController.addTextField  { (textField : UITextField!) -> Void in
            textField.text = String(self.settings.maxAudioBitrate)
            textField.placeholder = "Max audio bitrate"
            textField.keyboardType = .numberPad
        }
        
        let okAction = UIAlertAction(title: "OK", style: .default, handler: { alert -> Void in
            let maxAudioBitrate = alertController.textFields![0] as UITextField
            if maxAudioBitrate.text! != "" {
                self.settings.maxAudioBitrate = UInt(maxAudioBitrate.text!)!
                self.tableView.reloadData()
            }
        })
        alertController.addAction(okAction)
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) -> Void in })
        alertController.addAction(cancelAction)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            alertController.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            alertController.popoverPresentationController?.sourceRect = (tableView.cellForRow(at: indexPath)?.bounds)!
        }
        self.navigationController!.present(alertController, animated: true, completion: nil)
    }
    
    func didSelectMaxVideoBitRateRow(indexPath: IndexPath) {
        let alertController = UIAlertController(title: self.labels[indexPath.section][indexPath.row], message: nil, preferredStyle: .alert)
        
        alertController.addTextField  { (textField : UITextField!) -> Void in
            textField.text = String(self.settings.maxVideoBitrate)
            textField.placeholder = "Max video bitrate"
            textField.keyboardType = .numberPad
        }
        
        let okAction = UIAlertAction(title: "OK", style: .default, handler: { alert -> Void in
            let maxVideoBitrate = alertController.textFields![0] as UITextField
            if maxVideoBitrate.text! != "" {
                self.settings.maxVideoBitrate = UInt(maxVideoBitrate.text!)!
                self.tableView.reloadData()
            }
        })
        alertController.addAction(okAction)
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) -> Void in })
        alertController.addAction(cancelAction)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            alertController.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            alertController.popoverPresentationController?.sourceRect = (tableView.cellForRow(at: indexPath)?.bounds)!
        }
        self.navigationController!.present(alertController, animated: true, completion: nil)
    }

    func getDisplayStrForVideoCodec(codec: TVIVideoCodec) -> String {
        var str = codec.name
        if codec.isKind(of: TVIVp8Codec.self) {
            let vp8Codec = codec as! TVIVp8Codec
            str += vp8Codec.isSimulcast ? " Simulcast" : ""
        }
        return str;
    }
}
