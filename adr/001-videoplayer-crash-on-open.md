# 001: App crashes when opening a video

- **Date:** 2026-10-04
- **Status:** Accepted
- **Author:** Kavi (via Claude Code)

## Context

`render start` opens a video player. Picking an `.mp4` via Cmd+O / Open Video…
crashed the app immediately ("render quit unexpectedly"). The file itself was
fine: a standalone `AVPlayer` played it (H.264 1920×1080 @ 29.97 fps, AAC,
252 s) and decoded frames normally.

Environment: macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), deployment target
macOS 26.5.

## Issue 1: SwiftUI `VideoPlayer` aborts on first render

The crash reports (`~/Library/Logs/DiagnosticReports/render-*.ips`) all show
the same stack:

```
EXC_CRASH (SIGABRT), abort() called
libswiftCore   swift::fatalError
libswiftCore   getSuperclassMetadata
libswiftCore   _swift_initClassMetadataImpl
_AVKit_SwiftUI <generic metadata instantiation>
...
SwiftUI        NSViewRepresentable._makeView
SwiftUICore    Transition.makeView / DynamicLayoutViewAdaptor.makeItemLayout
```

When a file is picked, `ContentView` swaps its empty state for SwiftUI's
`VideoPlayer`. The Swift runtime then fails to instantiate class metadata
inside Apple's `_AVKit_SwiftUI` framework and aborts. Our loading code is
never at fault. This is a framework/runtime defect on this OS version.

It only reproduces in the real app launch path. Rendering `VideoPlayer` in a
window from a hosted unit test, including the empty → player transition, did
**not** crash. Only an end-to-end UI test that launches the app and picks a
file through the real open panel reproduced it.

## Issue 2: CLI rejected system launch arguments

`RenderMain` passes `CommandLine.arguments` to `CLI.run` before starting the
GUI. AppKit apps are routinely launched with system flags, such as
`-NSTreatUnknownArgumentsAsOpen NO` from the XCTest host and
`-NSDocumentRevisionsDebugMode YES` from Xcode's Run. `CLI.run` treated these
as unknown commands, printed usage, and exited with code 1. This stopped the
unit-test host from bootstrapping ("test runner exited with code 1 before
establishing connection") and would break launching from Xcode too.

## Decision

1. **Use AppKit's `AVPlayerView` instead of SwiftUI's `VideoPlayer`.**
   `render/render/PlayerView.swift` wraps `AVPlayerView` in an
   `NSViewRepresentable` with `controlsStyle = .inline`. It keeps AVKit's
   native playback controls and avoids `_AVKit_SwiftUI` entirely.
2. **Extract the loading logic into `VideoPlayerModel`**
   (`render/render/VideoPlayerModel.swift`) so it can be unit tested apart
   from the view. While doing so:
   - A `false` from `startAccessingSecurityScopedResource()` no longer aborts
     the load. Only importer URLs are security scoped; other URLs need no
     extra access.
   - Playback failures (`AVPlayerItem.status == .failed`, e.g. a corrupt
     file) now show up in the UI. Before, they failed silently.
3. **CLI passes system launch flags through to the GUI.** Arguments that
   start with `-NS`, `-Apple`, or `-psn_` are not treated as commands.
4. **Add tests at every level** (`make test`):
   - `renderTests/renderTests.swift`: model behaviour (valid video becomes
     ready and advances, corrupt file shows an error, replacing a video stops
     the previous player, import failure and empty import, unload) and view
     rendering (`PlayerView` / `ContentView` render an `AVPlayerView`,
     including the empty → player swap).
   - `renderTests/CLITests.swift`: every command, unknown commands, and
     system launch flags.
   - `renderUITests/renderUITests.swift`: an end-to-end test that opens a
     video through the real open panel and checks the app is still running.
     This is the regression test for Issue 1. It failed with
     `kavi.render crashed` before the fix and passes after.
   - `TestSupport/VideoFixture.swift`, shared by both test targets, generates
     a small H.264 `.mp4` (and a corrupt one) at runtime, so tests don't
     depend on a media file in the repo.

## Consequences

- Playback works. All 23 unit and UI tests pass, and no new crash reports
  appear.
- We lose SwiftUI `VideoPlayer` conveniences such as its overlay content
  parameter. Anything similar now needs SwiftUI layered over `PlayerView` or
  configuration on `AVPlayerView`.
- `PlayerView` is macOS-only (`NSViewRepresentable`). The target also lists
  iOS/visionOS as supported platforms. Building for those needs a
  `UIViewRepresentable` wrapping `AVPlayerViewController`.
- **Revisit** when a newer macOS ships: if `VideoPlayer` no longer crashes,
  switching back is an option. The UI test will catch it if not.
- Lesson: hosted unit tests didn't reproduce a crash that only happened in
  the real launch path. UI-facing fixes need an end-to-end UI test.
