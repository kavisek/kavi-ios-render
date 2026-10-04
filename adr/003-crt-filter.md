# 003: CRT video filter

- **Date:** 2026-10-04
- **Status:** Accepted
- **Author:** Kavi (via Claude Code)

## Context

The player should be able to apply a filter to the video while it plays.
The first filter is a 90s CRT look, with good presets and every parameter
adjustable live. Requirements from the project philosophy: extensible (more
filters later), fast (1080p at full frame rate), and simple. AVKit's native
playback controls must stay
([001](001-videoplayer-crash-on-open.md) moved us to `AVPlayerView`).

## Decision

### Rendering: `AVVideoComposition` + Core Image

Each frame goes through Core Image inside AVFoundation's own pipeline:

```
AVPlayerItem ── videoComposition ──▶ CI handler ──▶ VideoFilter.apply ──▶ AVPlayerView
                 (VideoFilterPipeline)    (render queue, GPU)
```

- `VideoFilterPipeline` (`render/render/Filters/VideoFilter.swift`) builds
  one composition per player item with
  `AVVideoComposition.videoComposition(with:applyingCIFiltersWithHandler:)`
  and attaches it once the asset loads.
- The active filter lives behind a `Mutex`. Changing it takes effect on the
  next rendered frame, so the composition is never rebuilt while sliders
  move. `nil` means pass-through.
- `AVPlayerView`, its controls, and full screen are untouched. The same
  composition could later drive `AVAssetExportSession` to export a filtered
  video.

The async composition API is deprecated starting in macOS 27 in favour of
`init(applyingFiltersTo:applier:)`. The deployment target is macOS 26.5, so
it is the correct API for now and produces no warning. Switch when the
target moves to 27.

Alternatives considered:
- **`AVPlayerItemVideoOutput` + a custom Metal view** over the player. Full
  control, but it re-implements presentation and timing, and doesn't help
  with a future export.
- **Built-in Core Image filters only.** There is no curvature, scanline, or
  phosphor mask filter, so a custom kernel is needed.

### Extensibility: the `VideoFilter` protocol

```swift
nonisolated protocol VideoFilter: Sendable {
    func apply(to image: CIImage, time: Double) -> CIImage
}
```

A filter is a value type that turns a frame into a frame. `time` is the
frame's position, for animated effects. `CRTFilter` is the first
implementation. A new filter needs only a struct conforming to this, plus
UI. The pipeline and model don't change.

### The CRT effect (`render/render/Filters/CRTFilter.swift`)

One custom kernel does the per-pixel work, wrapped by built-in filters:

1. **Softness:** `CIGaussianBlur` (optional) for a lower-resolution tube.
2. **CRT kernel**, in this order: barrel **curvature** with black, soft-edged
   borders beyond the glass; **colour bleed** (red/blue convergence error,
   stronger at the edges); **scanlines** (sin² bands); an aperture-grille
   **phosphor mask** (R/G/B stripes, 3 px per triad); **vignette**; **noise**;
   per-frame **flicker**; **brightness** gain.
3. **Glow:** `CIBloom`.
4. **Saturation:** `CIColorControls`.

Pixel-sized values (colour bleed, softness, glow radius) are defined at 1080p
and scaled to the video's height, so a preset looks the same at any
resolution. The kernel's region of interest is padded by the maximum
curvature and colour-bleed reach, so Core Image only fetches what it needs.

**Kernel compiled at runtime.** The kernel is Metal source in a Swift string,
compiled once with `CIKernel.kernels(withMetalString:)` (`[[stitchable]]`).
Xcode 27 ships the Metal toolchain as a separate download. A `.metal` file
would make every build, including Homebrew's `make build-release`, depend on
it. The trade-off is that compile errors show up at runtime, not build time.
`CRTFilterTests.kernelCompiles` catches that. If compilation fails, the
error goes to the `filters` log category and the filter passes frames
through instead of breaking playback. Runtime Metal kernels require a GPU
that supports dynamic libraries, which all Apple silicon Macs do.

### Settings and presets (`render/render/Filters/CRTSettings.swift`)

- `CRTSettings` holds 12 values: curvature, vignette, scanline intensity,
  line count, phosphor mask, glow, colour bleed, softness, noise, flicker,
  saturation, brightness. It is `Hashable`, `Codable` and `Sendable`, so it
  can be compared, saved, or sent to the render queue.
- `CRTSettings.Parameter` is one table with each value's title, section,
  range, step, key path and display format. The UI and the tests are both
  generated from it, so adding a parameter is one table entry plus the
  kernel change. The subscript clamps values to the parameter's range.
- Presets (`CRTPreset.all`): **Living Room TV** (default), **Arcade
  Cabinet**, **PC Monitor (VGA)**, **Worn VHS**, **Subtle**. Brightness in
  each compensates for the darkening from scanlines and the mask.

### State and UI

- `VideoPlayerModel` owns `isFilterEnabled`, `crtSettings` and `basePreset`.
  Any change rebuilds a `CRTFilter` value and hands it to the pipeline.
  `matchingPreset` is computed: when no preset matches the settings, the
  picker shows **Custom**, and "Reset to <preset>" restores the last chosen
  preset.
- The filter starts **off** each launch with Living Room TV selected.
  Settings are not saved between launches yet; `Codable` leaves room for it.
- `FilterPanel` is a SwiftUI `Form` in an `.inspector` on the right of the
  window. It has the on/off toggle, the preset picker, and one slider per
  parameter grouped by section. Sliders are disabled while the filter is
  off. The **Filters** button (Cmd+Shift+F) in the bottom bar toggles it,
  and is tinted while the filter is on.

### Redrawing while paused

A paused `AVPlayer` doesn't re-render, so slider changes wouldn't show until
playback resumed. Measured with a frame counter on a paused player:

| Action | Re-rendered? |
| --- | --- |
| Seek to the current time (zero tolerance) | No |
| Assign `videoComposition.copy()` | No (an immutable copy is the same object) |
| Assign `videoComposition.mutableCopy()` | **Yes** |
| Seek one tick forward | Yes (but moves the playhead) |

`VideoPlayerModel.redrawIfPaused()` assigns a `mutableCopy()` after each
change while paused.

## Testing

All in `render/renderTests/FilterTests.swift`, using the shared fixture from
[002](002-testing-framework.md). The fixture frames are now mid-grey instead
of starting near black, so "corners went black" is a meaningful check.

- **Kernel and effect checks** (`CRTFilterTests`): the kernel compiles;
  neutral settings leave a gradient unchanged; every preset keeps the frame
  size; curvature blacks out the corners but not the centre; scanlines darken
  the gaps between lines; the phosphor mask lets one primary colour through
  per column across a triad; brightness scales linearly.
- **Settings** (`CRTSettingsTests`): presets are inside every parameter's
  range, names are unique, every parameter is in exactly one section, and
  the subscript clamps.
- **Model** (`VideoPlayerModelFilterTests`): off by default; enabling
  activates the current settings; tweaking a value makes it Custom; reset
  restores the preset.
- **End-to-end pixels** (`VideoFilterPipelineTests`): plays a real video,
  reads the frames AVPlayer produces with `AVPlayerItemVideoOutput`, and
  checks the corners are grey with the filter off and black with curvature
  on. A second test checks that a settings change while paused re-renders
  the frame. This test caught the redraw bug above.
- **UI** (`renderUITests.testCRTFilterCanBeEnabledAndTuned`): opens a video,
  opens the panel, checks sliders unlock when the filter turns on, picks
  Worn VHS, drags a slider, and resets.

Results: all 46 unit test cases pass. The UI tests have **not** passed yet
for this change, for an environmental reason (below), not a code failure.
The feature was checked by hand in the running app.

### UI tests need an idle Mac

While working on this, every UI test, including ones that passed earlier
from the previous commit, started failing with an app that launched but had
no window. Cause: XCUITest launches the app without making it active, and
macOS won't let a newly launched app take focus while the user is actively
using another app. SwiftUI holds its first window until the app is active.
The app's menu bar items had zero size, and opening the app with `open`
partway through a test made the window appear and the test pass. Run
`make test` without touching the Mac. Several in-app workarounds were tried
and reverted: disabling state restoration, `.defaultLaunchBehavior`,
activating at launch, sending a reopen event to the app itself. None helped.

## Consequences

- Filters run on the GPU within AVFoundation's pipeline. Playback controls,
  full screen and seeking are unchanged.
- New filters plug in through `VideoFilter`. A filter picker can replace
  today's single CRT toggle when there is more than one.
- The composition path can be reused to export filtered video
  (`render add` is still a placeholder).
- Kernel compile errors are runtime errors, caught by `kernelCompiles`.
- Not done yet: saving settings between launches, user-defined presets,
  and exporting.
