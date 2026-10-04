//
//  renderUITests.swift
//  renderUITests
//
//  Created by Kavi Sekhon on 2026-09-04.
//

import XCTest

final class renderUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsEmptyState() throws {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["No Video Selected"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Video…"].exists)
    }

    /// End-to-end: pick an .mp4 through the real open panel and check the
    /// app is still running with the file loaded. Picking a file used to
    /// crash the app the moment the player view appeared.
    @MainActor
    func testOpeningVideoPlaysWithoutCrashing() async throws {
        let app = launchApp()
        let video = try await openVideo(in: app)
        defer { try? FileManager.default.removeItem(at: video) }

        XCTAssertFalse(app.staticTexts["No Video Selected"].exists)

        // Give playback a moment, then confirm the app survived it.
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(app.state, .runningForeground, "app crashed during playback")
    }

    /// End-to-end: turn on the CRT filter over a playing video, switch
    /// presets and drag a parameter slider.
    @MainActor
    func testCRTFilterCanBeEnabledAndTuned() async throws {
        let app = launchApp()
        let video = try await openVideo(in: app)
        defer { try? FileManager.default.removeItem(at: video) }

        let filtersButton = app.descendants(matching: .any)["filtersButton"]
        XCTAssertTrue(filtersButton.waitForExistence(timeout: 5))
        filtersButton.click()

        let toggle = app.descendants(matching: .any)["crtFilterToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "filter panel never opened")
        let slider = app.descendants(matching: .any)["crt.curvature"].sliders.firstMatch
        XCTAssertTrue(slider.exists)
        XCTAssertFalse(slider.isEnabled, "parameters should be locked while the filter is off")

        toggle.click()
        XCTAssertTrue(slider.isEnabled, "parameters should unlock once the filter is on")

        let picker = app.descendants(matching: .any)["crtPresetPicker"]
        picker.click()
        app.menuItems["Worn VHS"].click()
        XCTAssertTrue(app.staticTexts["3.5 px"].waitForExistence(timeout: 2), "Worn VHS colour bleed not applied")

        slider.adjust(toNormalizedSliderPosition: 0.9)
        XCTAssertTrue(app.buttons["Reset to Worn VHS"].isEnabled, "tweaking a slider should allow a reset")
        app.buttons["Reset to Worn VHS"].click()
        XCTAssertFalse(app.buttons["Reset to Worn VHS"].isEnabled)

        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(app.state, .runningForeground, "app crashed while filtering")
    }

    /// Launches the app. macOS only lets it become active, which SwiftUI
    /// waits for before showing the first window, while nobody is using
    /// another app, so keep hands off the Mac while UI tests run.
    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    /// Picks a generated .mp4 through the open panel and waits until the app
    /// shows it as loaded. Returns the file so the caller can delete it.
    @MainActor
    private func openVideo(in app: XCUIApplication) async throws -> URL {
        let video = try await VideoFixture.makeMP4(seconds: 10)

        app.buttons["Open Video…"].click()
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "open panel never appeared")

        // Go-to-folder accepts a full file path and selects that file.
        panel.typeKey("g", modifierFlags: [.command, .shift])
        panel.typeText(video.path)
        panel.typeKey(.return, modifierFlags: [])
        let openButton = panel.buttons["Open"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 5))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: openButton)
        await fulfillment(of: [enabled], timeout: 5)
        openButton.click()

        XCTAssertTrue(
            app.staticTexts[video.lastPathComponent].waitForExistence(timeout: 10),
            "loaded file name never appeared (app state: \(app.state.rawValue))"
        )
        XCTAssertEqual(app.state, .runningForeground, "app crashed after opening the video")
        return video
    }
}
