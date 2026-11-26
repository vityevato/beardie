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

    func testRecordsAndClearsPlayPauseShortcut() {
        XCTAssertTrue(openPreferences())
        XCTAssertTrue(selectShortcutsTab())

        let window = app.windows["Preferences"]
        let recorder = window.descendants(matching: .any)
            .matching(identifier: "shortcut.playPause")
            .firstMatch
        XCTAssertTrue(recorder.waitForExistence(timeout: TestTimeouts.element))

        recorder.click()
        recorder.typeKey("\u{F716}", modifierFlags: [])

        XCTAssertTrue(waitForRecorderValue(recorder, toBeEmpty: false),
                      "The recorder did not store the shortcut")

        // Give the XPC service a moment to receive the updated shortcuts.
        Thread.sleep(forTimeInterval: 0.5)

        recorder.click()
        recorder.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])

        XCTAssertTrue(waitForRecorderValue(recorder, toBeEmpty: true),
                      "The recorder did not clear the shortcut")
    }

    func testTabNavigation() {
        // Keyboard navigation is disabled: Tab stays inside the recorder
        // text fields and wraps at both ends; the toolbar must not be reached.
        relaunch(extraArguments: ["-BSForceFullKeyboardAccess", "NO"])

        XCTAssertTrue(openPreferences())
        XCTAssertTrue(selectShortcutsTab())

        let window = app.windows["Preferences"]
        let first = window.descendants(matching: .any)
            .matching(identifier: "shortcut.playPause")
            .firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: TestTimeouts.element))

        first.click()
        XCTAssertTrue(waitForFocus("shortcut.playPause"),
                      "Play/Pause recorder did not receive focus")

        let forwardOrder = [
            "shortcut.nextTrack",
            "shortcut.previousTrack",
            "shortcut.playerNext",
            "shortcut.playerPrevious",
            "shortcut.setActiveTab",
            "shortcut.activatePlayingTab",
            "shortcut.favorite",
            "shortcut.notification",
        ]

        for identifier in forwardOrder {
            app.typeKey(XCUIKeyboardKey.tab.rawValue, modifierFlags: [])
            XCTAssertTrue(waitForFocus(identifier),
                          "Expected focus on \(identifier), got \(focusedRecorderIdentifier() ?? "nil")")
        }

        // Wraps back to the first recorder; no toolbar jump.
        app.typeKey(XCUIKeyboardKey.tab.rawValue, modifierFlags: [])
        XCTAssertTrue(waitForFocus("shortcut.playPause"),
                      "Tab from the last recorder did not wrap to the first recorder")

        // Shift-Tab traverses the order backwards and wraps to the last
        // recorder; no toolbar jump.
        let last = window.descendants(matching: .any)
            .matching(identifier: "shortcut.notification")
            .firstMatch
        last.click()
        XCTAssertTrue(waitForFocus("shortcut.notification"),
                      "The last recorder did not receive focus")
        Thread.sleep(forTimeInterval: 0.15)

        let backwardOrder = [
            "shortcut.favorite",
            "shortcut.activatePlayingTab",
            "shortcut.setActiveTab",
            "shortcut.playerPrevious",
            "shortcut.playerNext",
            "shortcut.previousTrack",
            "shortcut.nextTrack",
            "shortcut.playPause",
        ]

        for identifier in backwardOrder {
            app.typeKey(XCUIKeyboardKey.tab.rawValue, modifierFlags: [.shift])
            XCTAssertTrue(waitForFocus(identifier),
                          "Expected Shift-Tab focus on \(identifier), got \(focusedRecorderIdentifier() ?? "nil")")
            Thread.sleep(forTimeInterval: 0.1)
        }

        app.typeKey(XCUIKeyboardKey.tab.rawValue, modifierFlags: [.shift])
        XCTAssertTrue(waitForFocus("shortcut.notification"),
                      "Shift-Tab from the first recorder did not wrap to the last recorder")
    }

    func testTabNavigationWithFullKeyboardAccess() {
        // Keyboard navigation is enabled: Tab leaves the recorder loop for
        // the first toolbar button, Shift-Tab for the last one.
        relaunch(extraArguments: ["-BSForceFullKeyboardAccess", "YES"])

        XCTAssertTrue(openPreferences())
        XCTAssertTrue(selectShortcutsTab())

        let window = app.windows["Preferences"]
        let last = window.descendants(matching: .any)
            .matching(identifier: "shortcut.notification")
            .firstMatch
        XCTAssertTrue(last.waitForExistence(timeout: TestTimeouts.element))

        last.click()
        XCTAssertTrue(waitForFocus("shortcut.notification"))
        Thread.sleep(forTimeInterval: 0.15)

        app.typeKey(XCUIKeyboardKey.tab.rawValue, modifierFlags: [])
        XCTAssertTrue(waitForToolbarFocus(expected: "General"),
                      "Tab from the last recorder did not reach the first toolbar button; focused=\(focusedToolbarButtonTitle() ?? "nil")")

        let first = window.descendants(matching: .any)
            .matching(identifier: "shortcut.playPause")
            .firstMatch
        first.click()
        XCTAssertTrue(waitForFocus("shortcut.playPause"))

        app.typeKey(XCUIKeyboardKey.tab.rawValue, modifierFlags: [.shift])
        XCTAssertTrue(waitForToolbarFocus(expected: "Controllers"),
                      "Shift-Tab from the first recorder did not reach the last toolbar button; focused=\(focusedToolbarButtonTitle() ?? "nil")")
    }

    private func focusedRecorderIdentifier() -> String? {
        var result: String?

        for line in app.debugDescription.split(separator: "\n") where line.contains("Keyboard Focused") {
            if let start = line.range(of: "identifier: '"),
               let end = line[start.upperBound...].firstIndex(of: "'") {
                let identifier = String(line[start.upperBound..<end])
                if identifier.hasPrefix("shortcut.") {
                    result = identifier
                }
            }
        }

        return result
    }

    private func focusedToolbarButtonTitle() -> String? {
        var result: String?

        for line in app.debugDescription.split(separator: "\n") where line.contains("Keyboard Focused") {
            for title in ["General", "Shortcuts", "Controllers"] {
                if line.contains("title: '\(title)'") {
                    result = title
                }
            }
        }

        return result
    }

    private func waitForToolbarFocus(expected: String,
                                     timeout: TimeInterval = TestTimeouts.element) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if focusedToolbarButtonTitle() == expected {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return false
    }

    private func waitForFocus(_ identifier: String,
                              timeout: TimeInterval = TestTimeouts.element) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if focusedRecorderIdentifier() == identifier {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return false
    }

    private func waitForRecorderValue(_ recorder: XCUIElement,
                                      toBeEmpty: Bool,
                                      timeout: TimeInterval = TestTimeouts.element) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let value = recorder.value as? String ?? ""
            if value.isEmpty == toBeEmpty {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return false
    }
}
