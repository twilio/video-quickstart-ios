//
//  SettingsTableViewController.swift
//  VideoQuickStart
//
//  Copyright © 2017-2019 Twilio, Inc. All rights reserved.
//

import UIKit
import Photos
import PhotosUI
import TwilioVideo

class SettingsTableViewController: UITableViewController {
    
    static let backgroundImage = "Background Image"
    static let backgroundBlurRadius = "Background Blur Radius"
    static let signalingRegionLabel = "Region"
    static let audioCodecLabel = "Audio Codec"
    static let videoCodecLabel = "Video Codec"
    static let maxAudioBitrateLabel = "Max Audio Bitrate (Kbps)"
    static let maxVideoBitrateLabel = "Max Video Bitrate (Kbps)"
    static let defaultStr = "Default"
    static let virtualBackgroundDisclaimerText = "Set your background image or the radius of the Gaussian blur filter. This will be applied to the local camera view."
    static let signalingRegionDisclaimerText = "Set your preferred region. Global Low Latency (gll) is the default value."
    static let codecDisclaimerText = "Set your preferred audio and video codec. Not all codecs are supported in Group Rooms. The media server will fallback to OPUS or VP8 if a preferred codec is not supported. VP8 Simulcast should only be enabled in a Group Room."
    static let encodingParamsDisclaimerText = "Set sender bandwidth constraints. Zero represents the WebRTC default which varies by codec."
    
    let disclaimers = [virtualBackgroundDisclaimerText, signalingRegionDisclaimerText, codecDisclaimerText, encodingParamsDisclaimerText]
    let settings = Settings.shared
    let disclaimerFont = UIFont.preferredFont(forTextStyle: UIFont.TextStyle.footnote)
    var labels: [[String]] = [[backgroundImage, backgroundBlurRadius],
                              [signalingRegionLabel],
                              [SettingsTableViewController.audioCodecLabel, SettingsTableViewController.videoCodecLabel],
                              [SettingsTableViewController.maxAudioBitrateLabel, SettingsTableViewController.maxVideoBitrateLabel]]
    
    var backgroundImageName: String? = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Settings"
    }
    
    func getDisclaimerSizeForString(string: String!) -> CGSize {
        let disclaimerString: NSString = string as NSString
        
        return disclaimerString.boundingRect(with: CGSize(width: self.tableView.frame.width-20,
                                                          height: CGFloat.greatestFiniteMagnitude),
                                             options: NSStringDrawingOptions.usesLineFragmentOrigin,
                                             attributes: [ NSAttributedString.Key.font: disclaimerFont ],
                                             context: nil).size
    }

    @objc func deselectSelectedRow() {
        if let selectedRow = self.tableView.indexPathForSelectedRow {
            self.tableView.deselectRow(at: selectedRow, animated: true)
        }
    }

    @objc func reloadSelectedRowOrTableView() {
        if let selectedRow = self.tableView.indexPathForSelectedRow {
            self.tableView.reloadRows(at: [selectedRow], with: UITableView.RowAnimation.none)
            self.tableView.selectRow(at: selectedRow, animated: false, scrollPosition: UITableView.ScrollPosition.none)
            self.tableView.deselectRow(at: selectedRow, animated: true)
        } else {
            self.tableView.reloadData()
        }
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
            case SettingsTableViewController.backgroundImage:
                if let imageName = backgroundImageName, imageName.count > 0 {
                    detailText = imageName
                } else {
                    detailText = ""
                }
            case SettingsTableViewController.backgroundBlurRadius:
                if let backgroundBlurRadius = settings.backgroundBlurRadius {
                    detailText = backgroundBlurRadius.stringValue
                } else {
                    detailText = ""
                }
            case SettingsTableViewController.signalingRegionLabel:
                if let signalingRegion = settings.signalingRegion {
                    detailText = settings.supportedSignalingRegionDisplayString[signalingRegion]!
                }
            case SettingsTableViewController.audioCodecLabel:
                if let codec = settings.audioCodec {
                    detailText = codec.name
                }
            case SettingsTableViewController.videoCodecLabel:
                detailText = settings.videoCodec.name
            case SettingsTableViewController.maxAudioBitrateLabel:
                detailText = String(settings.maxAudioBitrate)
            case SettingsTableViewController.maxVideoBitrateLabel:
                detailText = String(settings.maxVideoBitrate)
            default:
                break;
        }
        cell.detailTextLabel?.text = detailText
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let tappedLabel = self.labels[indexPath.section][indexPath.row]
        
        switch (tappedLabel) {
            case SettingsTableViewController.backgroundImage:
                didSelectBackgroundImageRow()
            case SettingsTableViewController.backgroundBlurRadius:
                didSelectBackgroundBlurRadiusRow()
            case SettingsTableViewController.signalingRegionLabel:
                didSelectSignalingRegionRow(indexPath: indexPath)
            case SettingsTableViewController.audioCodecLabel:
                didSelectAudioCodecRow(indexPath: indexPath)
            case SettingsTableViewController.videoCodecLabel:
                didSelectVideoCodecRow(indexPath: indexPath)
            case SettingsTableViewController.maxAudioBitrateLabel:
                didSelectMaxAudioBitRateRow(indexPath: indexPath)
            case SettingsTableViewController.maxVideoBitrateLabel:
                didSelectMaxVideoBitRateRow(indexPath: indexPath)
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
    
    func didSelectBackgroundImageRow() {
        let alertController = UIAlertController(title: "Background Image", message: nil, preferredStyle: .actionSheet)
        
        let selectImageButton = UIAlertAction(title: "Select from library", style: .default, handler: { (action) -> Void in
            let status = PHPhotoLibrary.authorizationStatus()
            switch status {
                case .notDetermined:
                    PHPhotoLibrary.requestAuthorization(for: .readWrite) { [unowned self] (authStatus) in
                        DispatchQueue.main.async { [unowned self] in
                            showPhotoLibraryUI(for: authStatus)
                        }
                    }
                    break
                case .authorized:
                    DispatchQueue.main.async { [unowned self] in
                        showPhotoLibraryUI(for: status)
                    }
                case .limited:
                    NSLog("Photo library access restricted")
                    DispatchQueue.main.async { [unowned self] in
                        showPhotoLibraryUI(for: status)
                    }
                case .restricted:
                    NSLog("Photo library access restricted")
                    break
                case .denied:
                    NSLog("Photo library access denied")
                    break
                default:
                    NSLog("Default case")
            }
            
            self.reloadSelectedRowOrTableView()
        })
        alertController.addAction(selectImageButton)
        
        let clearButton = UIAlertAction(title: "Clear", style: .default, handler: { (action) -> Void in
            self.settings.backgroundImage = nil
            self.reloadSelectedRowOrTableView()
        })
        alertController.addAction(clearButton)
        
        let cancelButton = UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) -> Void in
            self.deselectSelectedRow()
        })
        alertController.addAction(cancelButton)
        
        self.navigationController!.present(alertController, animated: true, completion: nil)
    }
    
    func showPhotoLibraryUI(for status: PHAuthorizationStatus) {
        switch status {
        case .authorized:
            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 1
            let viewController = PHPickerViewController(configuration: config)
            viewController.delegate = self
            self.navigationController!.present(viewController, animated: true, completion: nil)
        case .limited:
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self)
        default:
            NSLog("Default auth status.")
        }
        
    }
    
    func didSelectBackgroundBlurRadiusRow() {
        let alertController = UIAlertController(title: "Blur Radius", message: nil, preferredStyle: .alert)
        
        alertController.addTextField { (textField : UITextField!) -> Void in
            textField.text = self.settings.backgroundBlurRadius == nil ? "" : self.settings.backgroundBlurRadius?.stringValue
            textField.placeholder = "Blur radius"
            textField.keyboardType = .numberPad
        }
        
        let okAction = UIAlertAction(title: "OK", style: .default, handler: { alert -> Void in
            let blurRadius = alertController.textFields![0] as UITextField
            if let value = blurRadius.text, value != "" {
                self.settings.backgroundBlurRadius = NSNumber(value: Float(value)!)
                self.reloadSelectedRowOrTableView()
            }
        })
        alertController.addAction(okAction)
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) -> Void in
            self.deselectSelectedRow()
        })
        alertController.addAction(cancelAction)
        
        self.navigationController!.present(alertController, animated: true, completion: nil)
    }

    func didSelectSignalingRegionRow(indexPath: IndexPath) {
        var selectedButton : UIAlertAction!
        var defaultButton: UIAlertAction!

        let alertController = UIAlertController(title: self.labels[indexPath.section][indexPath.row], message: nil, preferredStyle: .actionSheet)
        let selectionArray = settings.supportedSignalingRegions

        for signalingRegion in selectionArray {
            let selectionButton = UIAlertAction(title: settings.supportedSignalingRegionDisplayString[signalingRegion], style: .default, handler: { (action) -> Void in
                self.settings.signalingRegion = signalingRegion
                self.reloadSelectedRowOrTableView()
            })

            if (settings.signalingRegion == signalingRegion) {
                selectedButton = selectionButton;
            }

            alertController.addAction(selectionButton)
        }

        // The default action
        defaultButton = UIAlertAction(title: "Default", style: .default, handler: { (action) -> Void in
            self.settings.signalingRegion = nil
            self.reloadSelectedRowOrTableView()
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
            let cancelButton = UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) -> Void in
                self.deselectSelectedRow()
            })
            alertController.addAction(cancelButton)
        }
        self.navigationController!.present(alertController, animated: true, completion: nil)
    }

    func didSelectAudioCodecRow(indexPath: IndexPath) {
        var selectedButton : UIAlertAction!
        var defaultButton: UIAlertAction!
        
        let alertController = UIAlertController(title: self.labels[indexPath.section][indexPath.row], message: nil, preferredStyle: .actionSheet)
        let selectionArray = settings.supportedAudioCodecs
        
        for codec in selectionArray {
            let selectionButton = UIAlertAction(title: codec.name, style: .default, handler: { (action) -> Void in
                self.settings.audioCodec = codec
                self.reloadSelectedRowOrTableView()
            })
            
            if (settings.audioCodec == codec) {
                selectedButton = selectionButton;
            }
            
            alertController.addAction(selectionButton)
        }
        
        // The default action
        defaultButton = UIAlertAction(title: "Default", style: .default, handler: { (action) -> Void in
            self.settings.audioCodec = nil
            self.reloadSelectedRowOrTableView()
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
            let cancelButton = UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) -> Void in
                self.deselectSelectedRow()
            })
            alertController.addAction(cancelButton)
        }
        self.navigationController!.present(alertController, animated: true, completion: nil)
    }
    
    func didSelectVideoCodecRow(indexPath: IndexPath) {
        var selectedButton : UIAlertAction!
        
        let alertController = UIAlertController(title: self.labels[indexPath.section][indexPath.row], message: nil, preferredStyle: .actionSheet)
        
        for videoCodec in VideoCodec.allCases {
            let selectionButton = UIAlertAction(title: videoCodec.name,
                                                style: .default,
                                                handler: { (action) -> Void in
                self.settings.videoCodec = videoCodec
                self.reloadSelectedRowOrTableView()
            })
            
            if (settings.videoCodec == videoCodec) {
                selectedButton = selectionButton;
            }
            
            alertController.addAction(selectionButton)
        }
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            alertController.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            alertController.popoverPresentationController?.sourceRect = (tableView.cellForRow(at: indexPath)?.bounds)!
        } else {
            selectedButton?.setValue("true", forKey: "checked")
            
            // Adding the cancel action
            let cancelButton = UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) -> Void in
                self.deselectSelectedRow()
            })
            alertController.addAction(cancelButton)
        }
        self.navigationController!.present(alertController, animated: true, completion: nil)
    }
    
    func didSelectMaxAudioBitRateRow(indexPath: IndexPath) {
        let alertController = UIAlertController(title: self.labels[indexPath.section][indexPath.row], message: nil, preferredStyle: .alert)
        
        alertController.addTextField  { (textField : UITextField!) -> Void in
            textField.text = self.settings.maxAudioBitrate == 0 ? "" : String(self.settings.maxAudioBitrate)
            textField.placeholder = "Max audio bitrate"
            textField.keyboardType = .numberPad
        }
        
        let okAction = UIAlertAction(title: "OK", style: .default, handler: { alert -> Void in
            let maxAudioBitrate = alertController.textFields![0] as UITextField
            if maxAudioBitrate.text! != "" {
                self.settings.maxAudioBitrate = UInt(maxAudioBitrate.text!)!
                self.reloadSelectedRowOrTableView()
            }
        })
        alertController.addAction(okAction)
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) -> Void in
            self.deselectSelectedRow()
        })
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
            textField.text = self.settings.maxVideoBitrate == 0 ? "" : String(self.settings.maxVideoBitrate)
            textField.placeholder = "Max video bitrate"
            textField.keyboardType = .numberPad
        }
        
        let okAction = UIAlertAction(title: "OK", style: .default, handler: { alert -> Void in
            let maxVideoBitrate = alertController.textFields![0] as UITextField
            if maxVideoBitrate.text! != "" {
                self.settings.maxVideoBitrate = UInt(maxVideoBitrate.text!)!
                self.reloadSelectedRowOrTableView()
            }
        })
        alertController.addAction(okAction)
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) -> Void in
            self.deselectSelectedRow()
        })
        alertController.addAction(cancelAction)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            alertController.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            alertController.popoverPresentationController?.sourceRect = (tableView.cellForRow(at: indexPath)?.bounds)!
        }
        self.navigationController!.present(alertController, animated: true, completion: nil)
    }
}

extension SettingsTableViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        for item in results {
            item.itemProvider.loadObject(ofClass: UIImage.self) { pickerImage, error in
                if let image = pickerImage as? UIImage {
                    self.settings.backgroundImage = image
                } else {
                    NSLog("Unable to convert picked image as UIImage")
                }
            }
            
            item.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.item") { url, error in
                if error != nil {
                    NSLog("Unable to get the image filename")
                } else {
                    self.backgroundImageName = url?.lastPathComponent
                }
            }
        }
        
        DispatchQueue.main.async { [unowned self] in
            self.reloadSelectedRowOrTableView()
        }
    }
}
    
