//
//  VideoPlayerModel.swift
//  render
//

import AVFoundation
import Observation

/// Owns the player and the security-scoped access for the currently loaded
/// video. Kept separate from the view so loading logic can be unit tested.
@Observable
final class VideoPlayerModel {
    private(set) var player: AVPlayer?
    private(set) var currentFileName: String?
    private(set) var errorMessage: String?

    @ObservationIgnored private var accessedURL: URL?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            load(url: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func load(url: URL) {
        unload()

        // Only URLs handed over by the file importer are security scoped; a
        // false return here just means the URL needs no extra access.
        if url.startAccessingSecurityScopedResource() {
            accessedURL = url
        }

        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "Couldn't play \(url.lastPathComponent)."
            Task { @MainActor in self?.errorMessage = message }
        }

        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        currentFileName = url.lastPathComponent
        newPlayer.play()
    }

    func unload() {
        statusObservation = nil
        player?.pause()
        player = nil
        currentFileName = nil
        errorMessage = nil
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }
}
