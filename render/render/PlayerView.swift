//
//  PlayerView.swift
//  render
//

import SwiftUI
import AVKit

/// The video surface with AVKit's native playback controls: `AVPlayerView`
/// on macOS, `AVPlayerViewController` on iOS and iPadOS.
///
/// Wraps AVKit directly rather than SwiftUI's `VideoPlayer`: on macOS
/// 27.0.1, `VideoPlayer` aborts inside `_AVKit_SwiftUI` (Swift runtime
/// `getSuperclassMetadata` fatal error) the first time it's shown, which
/// crashed the app as soon as a video was picked (adr/001).
#if os(macOS)
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player = nil
    }
}
#else
struct PlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player = nil
    }
}
#endif
