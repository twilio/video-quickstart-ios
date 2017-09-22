//
//  SettingsTableViewController.swift
//  VideoQuickStart
//
//  Copyright © 2017 Twilio, Inc. All rights reserved.
//

import UIKit
import TwilioVideo

class SettingsTableViewController: UITableViewController {
    
    static let audioCodecLabel: String = "Audio Codec"
    static let videoCodecLabel: String = "Video Codec"
    
    var labels: [String] = [SettingsTableViewController.audioCodecLabel, SettingsTableViewController.videoCodecLabel]
    
    let settings = Settings.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Settings"
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return (labels.count)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SETTINGS-REUSE-IDENTIFIER", for: indexPath)
        
        // Configure the cell...
        let label = self.labels[indexPath.row]
        cell.textLabel?.text = label
        switch (label) {
            case SettingsTableViewController.audioCodecLabel:
                var codecStr = Settings.defaultCodecStr
                if ((settings.getAudioCodec()) != nil) {
                    codecStr = (settings.getAudioCodec()?.rawValue)!
                }
                cell.detailTextLabel?.text = codecStr
                break;
            
            case SettingsTableViewController.videoCodecLabel:
                var codecStr = Settings.defaultCodecStr
                if ((settings.getVideoCodec()) != nil) {
                    codecStr = (settings.getVideoCodec()?.rawValue)!
                }
                cell.detailTextLabel?.text = codecStr
                break;

            default:
                break;
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let tappedLabel = self.labels[indexPath.row]
        
        let alertController = UIAlertController(title: self.labels[indexPath.row], message: nil, preferredStyle: .actionSheet)

        switch (tappedLabel) {
            case SettingsTableViewController.audioCodecLabel:
                let selectionArray = settings.supportedAudioCodecs
                
                for codec in selectionArray {
                    let selectionButton = UIAlertAction(title: codec, style: .default, handler: { (action) -> Void in
                        self.settings.setAudioCodec(codec: TVIAudioCodec(rawValue: codec))
                        self.tableView.reloadData()
                    })
                    
                    if UIDevice.current.userInterfaceIdiom != .pad {
                        if (settings.getAudioCodec()?.rawValue == codec ||
                            (codec == Settings.defaultCodecStr && settings.getAudioCodec() == nil)) {
                            selectionButton.setValue("true", forKey: "checked")
                        }
                    }
                    
                    alertController.addAction(selectionButton)
                }
                break;

            case SettingsTableViewController.videoCodecLabel:
                let selectionArray = settings.supportedVideoCodecs
                
                for codec in selectionArray {
                    let selectionButton = UIAlertAction(title: codec, style: .default, handler: { (action) -> Void in
                        self.settings.setVideoCodec(codec: TVIVideoCodec(rawValue: codec))
                        self.tableView.reloadData()
                    })
                    
                    if UIDevice.current.userInterfaceIdiom != .pad {
                        if (settings.getVideoCodec()?.rawValue == codec ||
                            (codec == Settings.defaultCodecStr && settings.getVideoCodec() == nil)) {
                            selectionButton.setValue("true", forKey: "checked")
                         }
                    }
                    
                    alertController.addAction(selectionButton)
                }
                break;
            
            default:
                break;
        }
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            alertController.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            alertController.popoverPresentationController?.sourceRect = (tableView.cellForRow(at: indexPath)?.bounds)!
        } else {
            let cancelButton = UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) -> Void in })
            alertController.addAction(cancelButton)
        }

        self.navigationController!.present(alertController, animated: true, completion: nil)
    }
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let view = UIView()
        
        let desclcaimer = UILabel(frame: CGRect(x:10, y:10, width:tableView.frame.width - 10, height:80))
        desclcaimer.font = desclcaimer.font.withSize(14)
        desclcaimer.text = "Set your preferred audio and video codec. Not all codecs are supported with Group rooms. The media server will fallback to OPUS or VP8 if a preferred codec is not supported."
        desclcaimer.textColor = UIColor.darkGray
        desclcaimer.numberOfLines = 0
        
        view.addSubview(desclcaimer)
        
        return view;
    }
    
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 80
    }
}
