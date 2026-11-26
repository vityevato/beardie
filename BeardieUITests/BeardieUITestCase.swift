//
//  BeardieUITestCase.swift
//  BeardieUITests
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import XCTest

enum UITestLaunchArguments {
    static let base: [String] = [
        "-AppleLanguages", "(en)",
        "-AppleLocale", "en_US",
        "-BeardedSpiceFirstRun", "NO",
        "-BeardieBrowserExtensionsFirstRun", "NO",
        "-SUEnableAutomaticChecks", "NO",
        "-SUHasLaunchedBefore", "YES",
        "-BSHideStatusItem", "NO",
        "-BeardedSpiceLaunchAtLogin", "NO",
        // Avoid the system local-network permission prompt while capturing UI.
        "-SonosSupport", "NO",
    ]
}

enum TestTimeouts {
    static let applicationStart: TimeInterval = 30
    static let element: TimeInterval = 5
    static let quick: TimeInterval = 1.5
}

/// Base class for Beardie UI tests.
///
/// Beardie is an accessory application (`LSUIElement`), so Preferences are
/// opened through the status bar item, not through the main menu.
class BeardieUITestCase: XCTestCase {

    private(set) var app: XCUIApplication!
    private var didSaveFailureDiagnostics = false

    var defaultScreenshotElement: XCUIElement? {
        app.windows["Preferences"]
    }

    override func setUpWithError() throws {
        try super.setUpWithError()

        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchArguments = UITestLaunchArguments.base
        app.launch()
        self.app = app
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil

        try super.tearDownWithError()
    }

    /// Relaunches the app with additional launch arguments. Used by tests that
    /// need a deterministic keyboard-navigation mode.
    func relaunch(extraArguments: [String]) {
        app?.terminate()

        let app = XCUIApplication()
        app.launchArguments = UITestLaunchArguments.base + extraArguments
        app.launch()
        self.app = app
    }

    override func record(_ issue: XCTIssue) {
        if issue.type == .assertionFailure, !didSaveFailureDiagnostics, app != nil {
            didSaveFailureDiagnostics = true
            saveFailureDiagnostics()
        }

        super.record(issue)
    }

    private func saveFailureDiagnostics() {
        let name = "failure-\(safeFileName(self.name))"
        saveScreenshot(name, fullScreen: true)

        let directory = screenshotDirectory
        let fileURL = directory.appendingPathComponent("\(name)-ax.txt")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try app.debugDescription.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Accessibility hierarchy saved: \(fileURL.path)")
        } catch {
            print("Could not save accessibility hierarchy: \(error)")
        }
    }

    private var screenshotDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["UI_SCREENSHOT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        return FileManager.default.temporaryDirectory
            .appendingPathComponent("BeardieUITests/latest", isDirectory: true)
    }

    // MARK: - Preferences

    @discardableResult
    func openPreferences() -> Bool {
        let statusItem = app.statusItems.firstMatch
        guard statusItem.waitForExistence(timeout: TestTimeouts.applicationStart) else {
            XCTFail("The Beardie status bar item did not appear")
            return false
        }

        statusItem.click()

        let preferencesItem = app.menuItems
            .matching(NSPredicate(format: "identifier == %@ OR title BEGINSWITH %@",
                                  "menu.preferences", "Preferences"))
            .firstMatch
        guard preferencesItem.waitForExistence(timeout: TestTimeouts.element) else {
            XCTFail("The Preferences menu item did not appear")
            return false
        }

        preferencesItem.click()

        let window = app.windows["Preferences"]
        guard window.waitForExistence(timeout: TestTimeouts.element) else {
            XCTFail("The Preferences window did not appear")
            return false
        }

        return true
    }

    @discardableResult
    func selectShortcutsTab() -> Bool {
        let window = app.windows["Preferences"]

        let candidates = [
            window.toolbars.buttons["Shortcuts"],
            app.toolbars.buttons["Shortcuts"],
            window.buttons["Shortcuts"],
        ]

        for candidate in candidates where candidate.waitForExistence(timeout: TestTimeouts.quick) {
            candidate.click()
            return true
        }

        XCTFail("The Shortcuts toolbar item did not appear")
        return false
    }

    // MARK: - Screenshots

    @discardableResult
    func saveScreenshot(_ name: String,
                        of element: XCUIElement? = nil,
                        fullScreen: Bool = false) -> URL? {
        let screenshot = fullScreen
            ? XCUIScreen.main.screenshot()
            : (element ?? defaultScreenshotElement)?.screenshot() ?? XCUIScreen.main.screenshot()

        let directory = screenshotDirectory
        let fileURL = directory.appendingPathComponent("\(safeFileName(name)).png")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: fileURL)
            print("Screenshot saved: \(fileURL.path)")
            return fileURL
        } catch {
            XCTFail("Could not save screenshot '\(name)': \(error)")
            return nil
        }
    }

    func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let characters = value.unicodeScalars.map {
            allowed.contains($0) ? Character(String($0)) : "-"
        }
        return String(characters)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
