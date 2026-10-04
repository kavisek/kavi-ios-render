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
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["No Video Selected"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Video…"].exists)
    }

    /// End-to-end: pick an .mp4 through the real open panel and check the
    /// app is still running with the file loaded. Picking a file used to
    /// crash the app the moment the player view appeared.
    @MainActor
    func testOpeningVideoPlaysWithoutCrashing() async throws {
        let video = try await VideoFixture.makeMP4()
        defer { try? FileManager.default.removeItem(at: video) }

        let app = XCUIApplication()
        app.launch()

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
        XCTAssertFalse(app.staticTexts["No Video Selected"].exists)

        // Give playback a moment, then confirm the app survived it.
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(app.state, .runningForeground, "app crashed during playback")
    }
}
