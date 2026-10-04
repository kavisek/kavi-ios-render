//
//  PlayerView.swift
//  render
//

import SwiftUI
import AVKit

/// The video surface with AVKit's native playback controls.
///
/// Wraps AppKit's `AVPlayerView` rather than SwiftUI's `VideoPlayer`: on
/// macOS 27.0.1, `VideoPlayer` aborts inside `_AVKit_SwiftUI` (Swift runtime
/// `getSuperclassMetadata` fatal error) the first time it's shown, which
/// crashed the app as soon as a video was picked.
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
