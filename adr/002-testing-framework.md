# 002: Testing framework for the macOS app

- **Date:** 2026-10-04
- **Status:** Accepted
- **Author:** Kavi (via Claude Code)

## Context

Investigating [001](001-videoplayer-crash-on-open.md), where the app crashed
on opening a video, showed the project had no real tests. The test targets
were still Xcode's templates. We needed tests that could:

- check the video-loading logic on its own,
- reproduce a crash that only happens in the running app, and
- run from the terminal (`make`) on a developer Mac, with no manual clicking.

Environment: macOS 27.0.1 on Apple silicon, Xcode 27.0, app deployment target
macOS 26.5. Everything below uses Apple's built-in tooling, with no
third-party dependencies.

## Decision

Use three layers, each with the framework that fits it.

### 1. Unit tests: Swift Testing (`renderTests` target)

Apple's [Swift Testing](https://developer.apple.com/documentation/testing)
(`import Testing`, `@Test`, `#expect`, `#require`) is used for everything that
runs inside the app process.

- **Hosted tests.** `renderTests` runs inside `render.app` (`TEST_HOST` /
  `BUNDLE_LOADER`), so tests use `@testable import render` and real AppKit /
  AVFoundation.
- **`@MainActor` suites.** The app target sets
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Test suites are marked
  `@MainActor` to match.
- **Parameterized tests** (`@Test(arguments:)`) cover every CLI alias and
  launch flag without repeating test code.
- **Async polling.** Playback is asynchronous, so a small `waitUntil` helper
  polls a condition until a timeout instead of sleeping for a fixed time.

Suites:

| Suite | File | Covers |
| --- | --- | --- |
| `VideoPlayerModelTests` | `renderTests/renderTests.swift` | Loading a valid video (becomes ready, playback advances), corrupt file shows an error, replacing a video stops the previous player, import failure, empty import, unload |
| `PlayerRenderingTests` | `renderTests/renderTests.swift` | Hosts `PlayerView` / `ContentView` in a real `NSWindow` via `NSHostingView` and checks an `AVPlayerView` is present and bound to the player, including the empty → player swap |
| `CLITests` | `renderTests/CLITests.swift` | Every command and alias, unknown command exit code, and system launch flags (`-NS…`, `-Apple…`, `-psn_…`) falling through to the GUI |

### 2. End-to-end UI tests: XCTest / XCUITest (`renderUITests` target)

Swift Testing can't drive UI, so end-to-end tests use XCUITest
(`XCUIApplication`). The test runner launches `render.app` as a separate
process and controls it through the accessibility layer, like a user would:

1. Launch the app and check the "No Video Selected" empty state.
2. Click **Open Video…**, and in the system open panel press Cmd+Shift+G,
   type the fixture's path, press Return, and click **Open**.
3. Check the file name appears, the empty state is gone, and the app is
   still in `.runningForeground` after a couple of seconds of playback.

If the app crashes, XCUITest reports `kavi.render crashed` and fails the
test. That is how the 001 regression is caught.

### 3. Shared test fixtures (`render/TestSupport/`)

`VideoFixture.swift` generates media at test time with `AVAssetWriter`:

- `makeMP4()` writes a 2-second 320×240 H.264 `.mp4` to the temporary
  directory.
- `makeCorruptMP4()` writes non-video bytes with an `.mp4` extension.

`TestSupport` is a file-system-synchronized group that is a member of
**both** test targets. The unit and UI tests share one fixture source and
the app target never sees it. The repo has no binary media checked in
(`.gitignore` excludes `*.mp4`), and the tests don't depend on any local
file.

### Running

```sh
make test   # xcodebuild test -scheme render -destination 'platform=macOS'
```

Run one target or test while iterating:

```sh
xcodebuild test -project render/render.xcodeproj -scheme render \
  -destination 'platform=macOS,arch=arm64' -only-testing:renderTests
xcodebuild test -project render/render.xcodeproj -scheme render \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:renderUITests/renderUITests/testOpeningVideoPlaysWithoutCrashing
```

Results and logs go to an `.xcresult` bundle under DerivedData
(`Logs/Test/`). Crashes of the app under test also leave a report in
`~/Library/Logs/DiagnosticReports/render-*.ips`, which is where the 001
stack trace came from.

At the time of writing, 28 test cases pass: 26 unit test cases (16 test
functions, with the CLI tests parameterized; about 0.6 s) and 2 UI tests
(about 22 s, mostly app launch and the open panel).

## Alternatives considered

- **XCTest for unit tests too.** It works, but Swift Testing is the current
  default in Xcode, gives clearer failure messages from `#expect`, and has
  built-in parameterized tests. XCTest stays only where it is required, for
  XCUITest.
- **AppleScript / System Events to click through the real app.** Tried first.
  It timed out (`AppleEvent timed out (-1712)`) waiting for Accessibility
  permission for the terminal. It also needs per-machine permission setup and
  makes no assertions. XCUITest handles automation permission through Xcode
  and reports results.
- **Only hosted rendering tests.** Not enough: rendering SwiftUI's
  `VideoPlayer` in a window inside the test host, including the empty →
  player transition, did **not** reproduce the 001 crash. Only the real app
  launch path, covered by XCUITest, did.
- **Checking in a sample video.** Large, potentially copyrighted, and ignored
  by `.gitignore`. Generating fixtures keeps the repo small and tests
  deterministic.
- **Standalone `swift` scripts against `AVPlayer`.** Useful for a quick
  one-off check that a file decodes, and used early in the 001 investigation.
  They test AVFoundation, not our app, so they aren't kept as tests.

## Consequences

- Logic can be unit tested because it lives outside the views
  (`VideoPlayerModel`, `CLI`). New features should follow that split.
- UI-facing fixes should come with an XCUITest. Hosted tests can miss bugs
  that only appear in the real launch path.
- The test host is a real app launch, so `RenderMain` must keep tolerating
  system launch arguments. `CLITests` guards this.
- UI tests are slower and need a logged-in GUI session. They can't run on a
  headless machine, and the first run may prompt to allow Xcode automation.
  A future CI setup needs a macOS runner with a GUI session, or should run
  only `renderTests`.
- `renderUITestsLaunchTests` (Xcode's launch-screenshot template) is still
  in the target and runs under `make test`. Remove it or make it a real test
  if it adds no value.
- UI tests need the Mac left idle while they run. macOS won't let the
  XCUITest-launched app become active while someone is using another app,
  and SwiftUI then never shows its first window, so every UI test fails with
  "no matches found". See [003](003-crt-filter.md#ui-tests-need-an-idle-mac).
