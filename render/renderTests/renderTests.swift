//
//  renderTests.swift
//  renderTests
//
//  Created by Kavi Sekhon on 2026-09-04.
//

import AppKit
import AVFoundation
import AVKit
import SwiftUI
import Testing
@testable import render

/// Polls `condition` on the main actor until it holds or `timeout` passes.
@MainActor
private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

@MainActor
struct VideoPlayerModelTests {

    @Test func startsEmpty() {
        let model = VideoPlayerModel()
        #expect(model.player == nil)
        #expect(model.currentFileName == nil)
        #expect(model.errorMessage == nil)
    }

    @Test func loadingValidVideoBecomesReadyAndPlays() async throws {
        let url = try await VideoFixture.makeMP4()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = VideoPlayerModel()
        model.load(url: url)

        let player = try #require(model.player)
        #expect(model.currentFileName == url.lastPathComponent)
        #expect(model.errorMessage == nil)
        #expect(player.rate == 1)

        let ready = await waitUntil { player.currentItem?.status == .readyToPlay }
        #expect(ready, "item status: \(String(describing: player.currentItem?.status.rawValue)), error: \(String(describing: player.currentItem?.error))")

        let advanced = await waitUntil { player.currentTime().seconds > 0.1 }
        #expect(advanced, "playback never advanced past \(player.currentTime().seconds)s")
        #expect(model.errorMessage == nil)
    }

    @Test func loadingCorruptFileSurfacesError() async throws {
        let url = try VideoFixture.makeCorruptMP4()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = VideoPlayerModel()
        model.load(url: url)

        let failed = await waitUntil { model.errorMessage != nil }
        #expect(failed, "a corrupt file should report an error")
        #expect(model.player?.currentItem?.status == .failed)
    }

    @Test func loadingAnotherVideoReplacesThePreviousPlayer() async throws {
        let first = try await VideoFixture.makeMP4()
        let second = try await VideoFixture.makeMP4()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let model = VideoPlayerModel()
        model.load(url: first)
        let firstPlayer = try #require(model.player)

        model.load(url: second)
        let secondPlayer = try #require(model.player)

        #expect(firstPlayer !== secondPlayer)
        #expect(firstPlayer.rate == 0, "the replaced player should stop")
        #expect(model.currentFileName == second.lastPathComponent)
    }

    @Test func importFailureSurfacesError() {
        let model = VideoPlayerModel()
        model.handleImportResult(.failure(CocoaError(.fileReadNoPermission)))
        #expect(model.player == nil)
        #expect(model.errorMessage != nil)
    }

    @Test func importWithNoURLsIsIgnored() {
        let model = VideoPlayerModel()
        model.handleImportResult(.success([]))
        #expect(model.player == nil)
        #expect(model.errorMessage == nil)
    }

    @Test func unloadClearsState() async throws {
        let url = try await VideoFixture.makeMP4()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = VideoPlayerModel()
        model.load(url: url)
        let player = try #require(model.player)

        model.unload()
        #expect(model.player == nil)
        #expect(model.currentFileName == nil)
        #expect(player.rate == 0)
    }
}

/// Renders the real views in a window. The app used to abort the moment a
/// video was picked because the player view crashed on first render, which
/// no model-level test can catch.
@MainActor
struct PlayerRenderingTests {

    private func render<V: View>(_ view: V) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return window
    }

    private func findSubview<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = findSubview(type, in: subview) { return match }
        }
        return nil
    }

    @Test func playerViewRendersWithAPlayer() async throws {
        let url = try await VideoFixture.makeMP4()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = AVPlayer(url: url)

        let window = render(PlayerView(player: player))
        defer { window.close() }

        let playerView = try #require(findSubview(AVPlayerView.self, in: window.contentView!))
        #expect(playerView.player === player)
    }

    @Test func contentViewRendersALoadedVideo() async throws {
        let url = try await VideoFixture.makeMP4()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = VideoPlayerModel()
        model.load(url: url)

        let window = render(ContentView(model: model))
        defer { window.close() }

        let playerView = try #require(findSubview(AVPlayerView.self, in: window.contentView!))
        #expect(playerView.player === model.player)
    }

    /// Mirrors the real flow: the window is up showing the empty state, then
    /// the user picks a file and the player view is swapped in.
    @Test func contentViewSwapsInPlayerAfterLoading() async throws {
        let url = try await VideoFixture.makeMP4()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = VideoPlayerModel()
        let window = render(ContentView(model: model))
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        #expect(findSubview(AVPlayerView.self, in: window.contentView!) == nil)

        model.load(url: url)

        let swapped = await waitUntil {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            return findSubview(AVPlayerView.self, in: window.contentView!) != nil
        }
        #expect(swapped, "the player view never appeared after loading")
        let playerView = try #require(findSubview(AVPlayerView.self, in: window.contentView!))
        #expect(playerView.player === model.player)
    }

    @Test func contentViewRendersEmptyState() throws {
        let window = render(ContentView())
        defer { window.close() }
        #expect(findSubview(AVPlayerView.self, in: window.contentView!) == nil)
    }
}
