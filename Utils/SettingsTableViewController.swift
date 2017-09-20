//
//  SettingsTableViewController.swift
//  VideoQuickStart
//
//  Copyright © 2017 Twilio, Inc. All rights reserved.
//

import UIKit

class SettingsTableViewController: UITableViewController {
    
    let audioCodecLabel: String = "Audio Codec"
    let videoCodecLabel: String = "Video Codec"
    var labels: [String]?
    
    let settings = Settings.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Settings"
        self.labels = [audioCodecLabel, videoCodecLabel]
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return (labels?.count)!
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SETTINGS-REUSE-IDENTIFIER", for: indexPath)
        
        // Configure the cell...
        let label = self.labels?[indexPath.row]
        cell.textLabel?.text = label
        switch (label) {
            case audioCodecLabel?:
                cell.detailTextLabel?.text = settings.getAudioCodec()
            case videoCodecLabel?:
                cell.detailTextLabel?.text = settings.getVideoCodec()
                break;
            default:
                break;
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let tappedLabel = self.labels?[indexPath.row]
        
        let alertController = UIAlertController(title: self.labels?[indexPath.row], message: nil, preferredStyle: .actionSheet)

        switch (tappedLabel) {
            case audioCodecLabel?:
                let selectionArray = settings.supportedAudioCodecs
                
                for codec in selectionArray {
                    let selectionButton = UIAlertAction(title: codec, style: .default, handler: { (action) -> Void in
                        self.settings.setAudioCodec(codec: codec)
                        self.tableView.reloadData()
                    })
                    
                    if (settings.getAudioCodec() == codec) {
                        selectionButton.setValue("true", forKey: "checked")
                    }
                    
                    alertController.addAction(selectionButton)
                }
                break;

            case videoCodecLabel?:
                let selectionArray = settings.supportedVideoCodecs
                
                for codec in selectionArray {
                    let selectionButton = UIAlertAction(title: codec, style: .default, handler: { (action) -> Void in
                        self.settings.setVideoCodec(codec: codec)
                        self.tableView.reloadData()
                    })
                    
                    if (settings.getVideoCodec() == codec) {
                        selectionButton.setValue("true", forKey: "checked")
                    }
                    
                    alertController.addAction(selectionButton)
                }
                break;
            
            default:
                break;
        }
        
        let cancelButton = UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) -> Void in })
        alertController.addAction(cancelButton)
        
        self.navigationController!.present(alertController, animated: true, completion: nil)
    }
}
