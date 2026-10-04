//
//  VideoPlayerModel.swift
//  render
//

import AVFoundation
import Observation
#if os(iOS)
import CoreTransferable
import PhotosUI
import SwiftUI // PhotosPickerItem lives in the PhotosUI + SwiftUI overlay
#endif

/// Owns the player and the security-scoped access for the currently loaded
/// video. Kept separate from the view so loading logic can be unit tested.
@Observable
final class VideoPlayerModel {
    private(set) var player: AVPlayer?
    private(set) var currentFileName: String?
    private(set) var errorMessage: String?

    // MARK: Filter

    var isFilterEnabled = false {
        didSet { updateFilter() }
    }

    var crtSettings = CRTPreset.default.settings {
        didSet { updateFilter() }
    }

    /// The preset last picked; "Reset" returns to it.
    private(set) var basePreset = CRTPreset.default

    /// The preset matching the current settings, or nil once they've been
    /// tweaked into a custom look.
    var matchingPreset: CRTPreset? {
        CRTPreset.all.first { $0.settings == crtSettings }
    }

    @ObservationIgnored let filterPipeline = VideoFilterPipeline()
    @ObservationIgnored private var accessedURL: URL?
    @ObservationIgnored private var ownedFileURL: URL?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var compositionTask: Task<Void, Never>?

    func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            load(url: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    /// Plays the video at `url`. Pass `ownsFile` for a temporary copy (e.g.
    /// from Photos) that should be deleted once it's no longer playing.
    func load(url: URL, ownsFile: Bool = false) {
        unload()
        if ownsFile {
            ownedFileURL = url
        }

        // Only URLs handed over by the file importer are security scoped; a
        // false return here just means the URL needs no extra access.
        if url.startAccessingSecurityScopedResource() {
            accessedURL = url
        }

        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "Couldn't play \(url.lastPathComponent)."
            Task { @MainActor [weak self] in self?.errorMessage = message }
        }

        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        currentFileName = url.lastPathComponent
        newPlayer.play()

        attachFilterPipeline(to: item)
    }

    func unload() {
        compositionTask?.cancel()
        compositionTask = nil
        statusObservation = nil
        player?.pause()
        player = nil
        currentFileName = nil
        errorMessage = nil
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        if let ownedFileURL {
            try? FileManager.default.removeItem(at: ownedFileURL.deletingLastPathComponent())
            self.ownedFileURL = nil
        }
    }

    #if os(iOS)
    /// Loads a video chosen with the Photos picker. Photos hands over a
    /// temporary file, which is copied so it outlives the transfer.
    func loadMovie(from item: PhotosPickerItem) async {
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                errorMessage = "Couldn't load the selected video."
                return
            }
            load(url: movie.url, ownsFile: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    #endif

    func applyPreset(_ preset: CRTPreset) {
        basePreset = preset
        crtSettings = preset.settings
    }

    func resetToBasePreset() {
        crtSettings = basePreset.settings
    }

    // MARK: Private

    /// Builds the composition in the background (it needs the asset's
    /// tracks) and attaches it if the item is still the one playing.
    private func attachFilterPipeline(to item: AVPlayerItem) {
        updateFilter()
        compositionTask = Task { [filterPipeline] in
            guard let composition = try? await filterPipeline.makeVideoComposition(for: item.asset),
                  !Task.isCancelled, self.player?.currentItem === item
            else { return }
            item.videoComposition = composition
        }
    }

    private func updateFilter() {
        filterPipeline.filter = isFilterEnabled ? CRTFilter(settings: crtSettings) : nil
        redrawIfPaused()
    }

    /// A paused player won't render again on its own. Re-seeking to the same
    /// time and assigning `copy()` (which returns the same immutable object)
    /// are both no-ops; assigning a distinct `mutableCopy()` makes it
    /// re-render the current frame through the filter so changes show.
    private func redrawIfPaused() {
        guard let player, player.rate == 0, let item = player.currentItem,
              let composition = item.videoComposition?.mutableCopy() as? AVVideoComposition
        else { return }
        item.videoComposition = composition
    }
}

#if os(iOS)
/// A movie received from the Photos picker, copied into its own temporary
/// directory (keeping its original name, e.g. IMG_0042.MOV, for display).
nonisolated struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("picked-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let copy = directory.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}
#endif
