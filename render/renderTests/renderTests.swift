//
//  renderTests.swift
//  renderTests
//
//  Created by Kavi Sekhon on 2026-09-04.
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif
import AVFoundation
import AVKit
import SwiftUI
import Testing
@testable import render

/// Polls `condition` on the main actor until it holds or `timeout` passes.
@MainActor
func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
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

    @Test func playerViewRendersWithAPlayer() async throws {
        let url = try await VideoFixture.makeMP4()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = AVPlayer(url: url)

        let window = TestWindow(PlayerView(player: player))
        defer { window.close() }

        let surface = try #require(window.playerSurface())
        #expect(surface.player === player)
    }

    @Test func contentViewRendersALoadedVideo() async throws {
        let url = try await VideoFixture.makeMP4()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = VideoPlayerModel()
        model.load(url: url)

        let window = TestWindow(ContentView(model: model))
        defer { window.close() }

        let surface = try #require(window.playerSurface())
        #expect(surface.player === model.player)
    }

    /// Mirrors the real flow: the window is up showing the empty state, then
    /// the user picks a file and the player view is swapped in.
    @Test func contentViewSwapsInPlayerAfterLoading() async throws {
        let url = try await VideoFixture.makeMP4()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = VideoPlayerModel()
        let window = TestWindow(ContentView(model: model))
        defer { window.close() }
        #expect(window.playerSurface() == nil)

        model.load(url: url)

        let swapped = await waitUntil {
            window.refresh()
            return window.playerSurface() != nil
        }
        #expect(swapped, "the player view never appeared after loading")
        let surface = try #require(window.playerSurface())
        #expect(surface.player === model.player)
    }

    @Test func contentViewRendersEmptyState() {
        let window = TestWindow(ContentView())
        defer { window.close() }
        #expect(window.playerSurface() == nil)
    }
}

/// Hosts a SwiftUI view in a real, on-screen window on either platform and
/// finds the native AVKit player it created: `AVPlayerView` on macOS,
/// `AVPlayerViewController` on iOS and iPadOS.
@MainActor
private final class TestWindow {
    /// The AVKit player surface found in the window, and the player it shows.
    struct PlayerSurface {
        let player: AVPlayer?
    }

    #if os(macOS)
    private let window: NSWindow

    init<V: View>(_ view: V) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        refresh()
    }

    func refresh() {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    func playerSurface() -> PlayerSurface? {
        find(AVPlayerView.self, in: window.contentView!).map { PlayerSurface(player: $0.player) }
    }

    func close() {
        window.close()
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.find(type, in: $0) }.first
    }
    #else
    private let window: UIWindow

    init<V: View>(_ view: V) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        refresh()
    }

    func refresh() {
        window.rootViewController?.view.setNeedsLayout()
        window.layoutIfNeeded()
    }

    func playerSurface() -> PlayerSurface? {
        find(in: window.rootViewController!).map { PlayerSurface(player: $0.player) }
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }

    private func find(in controller: UIViewController) -> AVPlayerViewController? {
        if let match = controller as? AVPlayerViewController { return match }
        return controller.children.lazy.compactMap { self.find(in: $0) }.first
    }
    #endif
}
