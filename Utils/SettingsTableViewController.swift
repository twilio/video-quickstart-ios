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
    static let defaultCodecStr = "Default"
    static let disclaimerText = "Set your preferred audio and video codec. Not all codecs are supported with Group rooms. The media server will fallback to OPUS or VP8 if a preferred codec is not supported."
    
    let labels: [String] = [SettingsTableViewController.audioCodecLabel, SettingsTableViewController.videoCodecLabel]
    let settings = Settings.shared
    let disclaimerFont = UIFont.preferredFont(forTextStyle: UIFontTextStyle.footnote)

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Settings"
    }
    
    func getDisclaimerSize() -> CGSize {
        let disclaimerString: NSString = SettingsTableViewController.disclaimerText as NSString
        
        return disclaimerString.boundingRect(with: CGSize(width: self.tableView.frame.width-20,
                                                          height: CGFloat.greatestFiniteMagnitude),
                                             options: NSStringDrawingOptions.usesLineFragmentOrigin,
                                             attributes: [NSFontAttributeName: disclaimerFont],
                                             context: nil).size
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
        let settings = Settings.shared

        switch (label) {
            case SettingsTableViewController.audioCodecLabel:
                var codecStr = SettingsTableViewController.defaultCodecStr
                if let codec = settings.audioCodec {
                    codecStr = codec.rawValue
                }
                cell.detailTextLabel?.text = codecStr
                break;
            
            case SettingsTableViewController.videoCodecLabel:
                var codecStr = SettingsTableViewController.defaultCodecStr
                if let codec = settings.videoCodec {
                    codecStr = codec.rawValue
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
        var selectedButton : UIAlertAction!
        var defaultButton: UIAlertAction!
        
        switch (tappedLabel) {
            case SettingsTableViewController.audioCodecLabel:
                let selectionArray = settings.supportedAudioCodecs
                
                for codec in selectionArray {
                    let selectionButton = UIAlertAction(title: codec.rawValue, style: .default, handler: { (action) -> Void in
                        self.settings.audioCodec = codec
                        self.tableView.reloadData()
                    })
                    
                    if (settings.audioCodec == codec) {
                        selectedButton = selectionButton;
                    }
                    
                    alertController.addAction(selectionButton)
                }
                
                defaultButton = UIAlertAction(title: "Default", style: .default, handler: { (action) -> Void in
                    self.settings.audioCodec = nil
                    self.tableView.reloadData()
                })
                break;

            case SettingsTableViewController.videoCodecLabel:
                let selectionArray = settings.supportedVideoCodecs
                
                for codec in selectionArray {
                    let selectionButton = UIAlertAction(title: codec.rawValue, style: .default, handler: { (action) -> Void in
                        self.settings.videoCodec = codec
                        self.tableView.reloadData()
                    })
                    
                    if (settings.videoCodec == codec) {
                        selectedButton = selectionButton;
                    }

                    alertController.addAction(selectionButton)
                }
                
                defaultButton = UIAlertAction(title: "Default", style: .default, handler: { (action) -> Void in
                    self.settings.videoCodec = nil
                    self.tableView.reloadData()
                })
                break;
            
            default:
                break;
        }
        
        if selectedButton == nil {
            selectedButton = defaultButton;
        }
        
        alertController.addAction(defaultButton!)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            alertController.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            alertController.popoverPresentationController?.sourceRect = (tableView.cellForRow(at: indexPath)?.bounds)!
        } else {
            let cancelButton = UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) -> Void in })
            alertController.addAction(cancelButton)
            selectedButton!.setValue("true", forKey: "checked")
        }

        self.navigationController!.present(alertController, animated: true, completion: nil)
    }
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let view = UIView()
        
        let disclcaimer = UILabel(frame: CGRect(x:10, y:10, width:tableView.frame.width - 20, height:self.getDisclaimerSize().height))
        disclcaimer.font = disclaimerFont
        disclcaimer.text = SettingsTableViewController.disclaimerText
        disclcaimer.textColor = UIColor.darkGray
        disclcaimer.numberOfLines = 0
        
        view.addSubview(disclcaimer)
        
        return view;
    }
    
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return self.getDisclaimerSize().height
    }
}
