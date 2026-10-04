# 004: iOS and iPadOS support

- **Date:** 2026-10-04
- **Status:** Accepted
- **Author:** Kavi (via Claude Code)

## Context

render shipped as a macOS app. It should also run on iPhone and iPad with the
same player and CRT filter ([003](003-crt-filter.md)). The Xcode project was
already a multiplatform target: `SUPPORTED_PLATFORMS` includes `iphoneos`,
`iphonesimulator`, `xros` and `xrsimulator`, `TARGETED_DEVICE_FAMILY` is
`1,2,7`, iOS deployment target 26.5, and the scene manifest, launch screen and
orientations are generated. Building for the iOS Simulator failed in one
place: `PlayerView` wrapped AppKit's `AVPlayerView`.

## Decision

Keep **one target and one codebase**, and branch with `#if os(macOS)` only
where a platform API or convention actually differs. Everything else is
shared unchanged: the model, the filter pipeline, the CRT kernel, presets and
the filter panel.

### Player view

`PlayerView` (`render/render/PlayerView.swift`) has one implementation per
platform, with the same interface (`PlayerView(player:)`):

| Platform | Wraps | Gives |
| --- | --- | --- |
| macOS | `AVPlayerView` (`NSViewRepresentable`) | inline controls, full screen |
| iOS / iPadOS | `AVPlayerViewController` (`UIViewControllerRepresentable`) | system controls, full screen, Picture in Picture |

SwiftUI's `VideoPlayer` stays unused on all platforms ([001](001-videoplayer-crash-on-open.md)).

### Opening videos

- **macOS:** unchanged. One **Open Video…** button (Cmd+O) with the file
  importer.
- **iOS / iPadOS:** two buttons, **Files** (same `.fileImporter`, Cmd+O with
  a keyboard) and **Photos** (`PhotosPicker`, videos only). On iPhone and
  iPad most videos live in the Photos library, which a Files-only app can't
  reach.

Photos hands over a temporary file during the transfer. `PickedMovie`
(a `Transferable` in `VideoPlayerModel.swift`) copies it into its own
temporary directory and keeps the original name, e.g. `IMG_0042.MOV`, for
display. `VideoPlayerModel.load(url:ownsFile:)` records that the app owns the
copy, and `unload()` deletes it when another video is opened. Photos accepts
any movie type (`.movie`); Photos videos are usually QuickTime/HEVC, which
`AVPlayer` plays. The Files importer still only accepts `.mp4`.

`PhotosPickerItem` is declared in the PhotosUI + SwiftUI overlay, so the
model imports both under `#if os(iOS)`.

### Layout

- The window's `minWidth: 640, minHeight: 400` applies to macOS only; it is
  wider than an iPhone screen.
- The filter panel stays a SwiftUI `.inspector`. On iPad (regular width) it
  is a side column, as on the Mac. On iPhone (compact width) SwiftUI presents
  it as a sheet. `.presentationDetents([.medium, .large])` opens it at half
  height so the video stays visible while tuning.
- The bottom bar is shared. The file name truncates in the middle on narrow
  screens.

### Command line is macOS-only

`RenderMain` only runs `CLI.run` on macOS, and `CLI.swift` and `CLITests.swift`
are wrapped in `#if os(macOS)`. The `render` command and its Homebrew
formula are a Mac feature.

### Filter on iOS

The CRT kernel is compiled at runtime with
`CIKernel.kernels(withMetalString:)` (iOS 15+). It requires a GPU that
supports Metal dynamic libraries: all Apple silicon Macs and A13+ devices,
which covers every device that runs iOS 26.5. `CRTFilterTests.kernelCompiles`
and the pixel checks pass on the iOS Simulator. If compilation ever fails,
the filter passes frames through ([003](003-crt-filter.md)).

## Running on simulators

```sh
make start-ios                     # iPhone 17 simulator
make start-ipad                    # iPad Pro 13-inch (M5) simulator
make start-ios IOS_SIM="iPhone 18 Pro"
make add-video VIDEO=~/Movies/clip.mp4 [SIM="iPad Pro 13-inch (M5)"]
```

`start-ios` / `start-ipad` build into `build-sim/` (git-ignored), boot the
device, install and launch. `add-video` puts a video in the simulator's
Photos library (same as dragging a file onto the Simulator window), and the
app's **Photos** button picks it up.

Xcode 27 installs Simulator separately at `/Applications/Simulator.app`, and
`open -a Simulator` doesn't always resolve, so opening the Simulator window
is best-effort. Install and launch work regardless.

## Testing

Shared tests run on both platforms. Platform-specific parts are behind
`#if`:

- **Unit tests:** `PlayerRenderingTests` use a `TestWindow` helper that
  hosts the view in an `NSWindow` (macOS) or a `UIWindow` attached to the
  app's scene (iOS). It finds the `AVPlayerView` or `AVPlayerViewController`
  the view created and checks it shows the right player. `CLITests` are
  macOS-only.
- **UI tests:** the launch test checks for **Open Video…** on macOS and
  **Files** / **Photos** on iOS. The video-opening test drives the macOS open
  panel, so it is macOS-only. The filter-panel test runs on both, over a
  playing video on macOS and on its own on iOS, because the system Files and
  Photos pickers can't be fed a fixture. A small `press()` helper clicks on
  macOS and taps on iOS.

Results at the time of writing:

| | macOS | iPhone 18 Pro simulator (iOS 27) |
| --- | --- | --- |
| Unit test cases | 46 / 46 pass | 29 / 31 pass |
| UI tests | need an idle Mac ([003](003-crt-filter.md#ui-tests-need-an-idle-mac)) | not run |

**Open issue:** the two `VideoFilterPipelineTests` fail on the iOS Simulator.
They read frames back from `AVPlayer` with `AVPlayerItemVideoOutput`, and the
output delivered no frames even with the filter off. They pass on macOS. It
isn't yet known whether this is a simulator or test-harness limitation, or a
real problem with the composition on iOS. Later simulator test runs also hung
before starting tests, while preparing the device; an explicit timeout
stopped them. Next steps: check the filter by hand on a simulator (open a
video from Photos, turn the CRT filter on), then diagnose frame delivery on
the simulator with a booted device and parallel testing off
(`-parallel-testing-enabled NO`).

## Consequences

- One codebase covers Mac, iPhone and iPad. Platform differences are limited
  to the player wrapper, the open buttons, the window minimum size and the
  CLI.
- iOS gains Photos as a source. macOS could get it too (`PhotosPicker` exists
  there); it was left out to keep the Mac UI unchanged.
- visionOS is still listed in the target's platforms and should mostly work
  through the same iOS code paths (`AVPlayerViewController` exists there),
  but it hasn't been built or tested.
- Whether the filter works on iOS isn't confirmed until the open issue above
  is resolved.
