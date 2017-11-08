//
//  RecordingsViewController.swift
//  AudioSinkExample
//
//  Copyright © 2017 Twilio Inc. All rights reserved.
//

import Foundation
import AVKit

class RecordingsViewController: UITableViewController {

    let kReuseIdentifier = "RecordingsCellId"
    var recordings = Array<URL>()

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Recordings"
        tableView.register(UITableViewCell.classForCoder(), forCellReuseIdentifier: kReuseIdentifier)

        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).last else {
            return
        }

        do {
            let directoryContents = try fileManager.contentsOfDirectory(atPath: documentsDirectory.path)

            for path in directoryContents {
                if (path.lowercased().hasSuffix("wav")) {
                    recordings.append(URL(fileURLWithPath: path, relativeTo: documentsDirectory))
                }
            }
        } catch {
            print("Couldn't fetch directory contents. \(error)")
        }
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let recordingToDelete = self.recordings[indexPath.row]

            do {
                try FileManager.default.removeItem(at: recordingToDelete)
                self.recordings.remove(at: indexPath.row)
                self.tableView.deleteRows(at: [indexPath], with: .automatic)
            } catch {
                print("Couldn't delete recording: \(recordingToDelete)")
            }
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return recordings.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return self.recordings.count > 0 ? "" : "Enter a Room to record audio Tracks."
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = recordings[indexPath.row]

        // Present a full-screen AVPlayerViewController and begin playback.
        let player = AVPlayer.init(url: item as URL)
        let playerVC = AVPlayerViewController.init()
        playerVC.player = player
        if #available(iOS 11.0, *) {
            playerVC.entersFullScreenWhenPlaybackBegins = true
        }

        self.showDetailViewController(playerVC, sender: self)

        player.play()
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kReuseIdentifier, for: indexPath)
        let recordingItem = recordings[indexPath.row]

        if let textLabel = cell.textLabel {
            textLabel.adjustsFontSizeToFitWidth = true
            textLabel.minimumScaleFactor = 0.75
            textLabel.text = recordingItem.lastPathComponent
        }

        return cell
    }
}
