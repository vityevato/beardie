//
//  ShortcutsPreferencesUITests.swift
//  BeardieUITests
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import XCTest

final class ShortcutsPreferencesUITests: BeardieUITestCase {

    private let recorderIdentifiers = [
        "shortcut.playPause",
        "shortcut.nextTrack",
        "shortcut.previousTrack",
        "shortcut.setActiveTab",
        "shortcut.favorite",
        "shortcut.notification",
        "shortcut.activatePlayingTab",
        "shortcut.playerNext",
        "shortcut.playerPrevious",
    ]

    func testShortcutsPaneShowsAllRecorders() {
        XCTAssertTrue(openPreferences())
        XCTAssertTrue(selectShortcutsTab())

        let window = app.windows["Preferences"]
        for identifier in recorderIdentifiers {
            let element = window.descendants(matching: .any)
                .matching(identifier: identifier)
                .firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: TestTimeouts.element),
                          "Missing shortcut recorder '\(identifier)'")
        }
    }

    func testCaptureShortcutsPane() {
        XCTAssertTrue(openPreferences())
        XCTAssertTrue(selectShortcutsTab())

        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertNotNil(saveScreenshot("shortcuts-pane", of: app.windows["Preferences"]))
    }
}
