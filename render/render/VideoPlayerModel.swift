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
    }

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
