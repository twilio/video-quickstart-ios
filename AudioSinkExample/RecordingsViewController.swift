//
//  RecordingsViewController.swift
//  AudioSinkExample
//
//  Copyright © 2017 Twilio Inc. All rights reserved.
//

import Foundation

class RecordingsViewController: UITableViewController {

    let kReuseIdentifier = "ReuseId"
    var recordings = Array<URL>()
    var audioPlayer: AVPlayer?

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Recordings"
        tableView.register(UITableViewCell.classForCoder(), forCellReuseIdentifier: kReuseIdentifier)

        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).last else {
            return
        }

        var directoryContents : [String]?
        do {
            try directoryContents = fileManager.contentsOfDirectory(atPath: documentsDirectory.path)
        } catch {
            print("Couldn't fetch directory contents. \(error)")
            return
        }

        for path in directoryContents! {
            if (path.hasSuffix("wav") || path.hasSuffix("WAV")) {
                recordings.append(URL(fileURLWithPath: path, relativeTo: documentsDirectory))
            }
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return recordings.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return self.recordings.count > 0 ? "Tap to playback audio recordings." : "Enter a Room to record audio Tracks."
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = recordings[indexPath.row]

        if let currentPlayer = audioPlayer {
            currentPlayer.pause()
            audioPlayer = nil
        }

        // TODO: Use KVO!
        let nextPlayer = AVPlayer.init(url: item as URL)
        nextPlayer.playImmediately(atRate: 1)
        audioPlayer = nextPlayer

        tableView.deselectRow(at: indexPath, animated: true)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kReuseIdentifier, for: indexPath)
        let recordingItem = recordings[indexPath.row]
        cell.textLabel?.text = recordingItem.lastPathComponent

        return cell
    }
}
