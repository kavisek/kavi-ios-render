//
//  VideoFilter.swift
//  render
//

import AVFoundation
import CoreImage
import Synchronization

/// A per-frame effect applied to the playing video. Implementations must be
/// value-like and thread safe: they run on AVFoundation's render queue.
nonisolated protocol VideoFilter: Sendable {
    /// Returns the filtered frame. `time` is the frame's position in the
    /// video, in seconds, for effects that animate.
    func apply(to image: CIImage, time: Double) -> CIImage
}

/// Runs whichever filter is currently active over every video frame.
///
/// One `AVVideoComposition` is attached per player item and stays attached;
/// swapping `filter` takes effect on the next rendered frame, so sliders can
/// update the picture live without rebuilding the composition.
nonisolated final class VideoFilterPipeline: Sendable {
    private let state = Mutex<State>(State())

    private struct State {
        var filter: (any VideoFilter)?
        var framesRendered = 0
    }

    /// The active filter, or nil to pass frames through untouched.
    var filter: (any VideoFilter)? {
        get { state.withLock { $0.filter } }
        set { state.withLock { $0.filter = newValue } }
    }

    /// Frames that have gone through the pipeline, filtered or not.
    var framesRendered: Int { state.withLock { $0.framesRendered } }

    func makeVideoComposition(for asset: AVAsset) async throws -> AVVideoComposition {
        try await AVVideoComposition.videoComposition(with: asset) { [self] request in
            let source = request.sourceImage
            let filter = state.withLock { state in
                state.framesRendered += 1
                return state.filter
            }
            guard let filter else {
                request.finish(with: source, context: nil)
                return
            }
            let output = filter.apply(to: source, time: request.compositionTime.seconds)
            request.finish(with: output.cropped(to: source.extent), context: nil)
        }
    }
}
