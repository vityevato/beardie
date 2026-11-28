//
//  BrowserBridgeTabAdapter.swift
//  Beardie
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import AppKit
import CocoaLumberjackSwift
import Foundation

/// A bridge tab exposed as a regular `TabAdapter`, so the existing player
/// selection (`autoSelectTabWithForceFocused:` / `BSActiveTab`) can choose it
/// exactly like a native app, Sonos room or legacy web tab.
///
/// The adapter is a player handle: `toggleTab` raises the tab and a second
/// invocation restores the previously active tab. Playing or paused state is
/// not a condition for Raise/Hide; it only contributes to player selection
/// through `isPlaying`.
@objc(BrowserBridgeTabAdapter)
final class BrowserBridgeTabAdapter: TabAdapter {

    private struct Snapshot {
        let instanceId: String
        let browserBundleIdentifier: String
        let browserDisplayName: String
        let processIdentifier: Int32?
        let tab: BrowserBridgeTab
    }

    private static let stateLock = NSLock()
    private static var raisedKeys = Set<String>()
    private static var pendingKeys = Set<String>()
    /// Keyed by browser bundle identifier, matching the old per-application
    /// `_frontmostApp` behavior across tabs of the same browser.
    private static var previousApps: [String: String] = [:]

    private let snapshotLock = NSLock()
    private var snapshot: Snapshot

    init(instance: BrowserBridgeInstance, tab: BrowserBridgeTab) {
        self.snapshot = Self.makeSnapshot(instance: instance, tab: tab)
        super.init()
    }

    func update(instance: BrowserBridgeInstance, tab: BrowserBridgeTab) {
        snapshotLock.lock()
        snapshot = Self.makeSnapshot(instance: instance, tab: tab)
        snapshotLock.unlock()
    }

    // MARK: - TabAdapter overrides

    override func title() -> String! {
        withSnapshot { $0.tab.mediaTitle ?? $0.tab.title ?? "" }
    }

    override func url() -> String! {
        withSnapshot { $0.tab.url }
    }

    override func key() -> String! {
        withSnapshot { "\($0.instanceId)#\($0.tab.tabId)" }
    }

    override func autoSelectable() -> Bool {
        true
    }

    override func isPlaying() -> Bool {
        withSnapshot { $0.tab.playbackState?.lowercased() == "playing" }
    }

    override func frontmost() -> Bool {
        let current = withSnapshot { $0 }
        guard let frontmostBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return frontmostBundle == current.browserBundleIdentifier && current.tab.active
    }

    override func isActivated() -> Bool {
        frontmost()
    }

    override func activateApp(withHoldFrontmost hold: Bool) -> Bool {
        false
    }

    override func deactivateApp() -> Bool {
        false
    }

    override func activateTab() -> Bool {
        false
    }

    override func deactivateTab() -> Bool {
        false
    }

    override func trackInfo() -> BSTrack! {
        withSnapshot {
            BSTrack(info: [
                kBSTrackNameTrack: $0.tab.mediaTitle ?? $0.tab.title ?? "",
                kBSTrackNameArtist: $0.tab.artist ?? "",
                kBSTrackNameAlbum: $0.tab.album ?? ""
            ])
        }
    }

    /// Raise when the tab is not the active frontmost tab. When it is already
    /// raised, restore the target tab/window and the application that was
    /// frontmost before Raise. A failed restore keeps the raised state so the
    /// next invocation can retry.
    override func toggleTab() {
        let current = withSnapshot { $0 }
        let key = "\(current.instanceId)#\(current.tab.tabId)"

        Self.stateLock.lock()
        if Self.pendingKeys.contains(key) {
            Self.stateLock.unlock()
            return
        }
        let isRaised = Self.raisedKeys.contains(key)
        Self.pendingKeys.insert(key)
        Self.stateLock.unlock()

        if isRaised && liveFrontmost(current) {
            restore(current: current, key: key)
        } else {
            raise(current: current, key: key)
        }
    }

    private func raise(current: Snapshot, key: String) {
        let browserBundle = current.browserBundleIdentifier
        let frontmostBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Record the frontmost application at every Raise, including the
        // browser itself. A later Hide restores only a different app; a value
        // equal to the browser means "no app switch".
        Self.stateLock.lock()
        Self.previousApps[browserBundle] = frontmostBundle ?? browserBundle
        Self.stateLock.unlock()

        // Activate the browser before switching tabs. Safari may restore its
        // last active tab/window when it becomes active, which would undo a
        // tab switch performed while it was in the background.
        Self.activateBrowserAndWait(bundleIdentifier: browserBundle)

        DDLogInfo(
            "BrowserBridgeTabAdapter: raise tab \(current.tab.tabId) in \(current.instanceId) "
                + "previousApp=\(frontmostBundle ?? "none")"
        )
        BrowserBridgeService.shared.activateTab(
            instanceId: current.instanceId,
            tabId: current.tab.tabId,
            windowId: current.tab.windowId
        ) { success in
            Self.complete(key: key, action: "raise", current: current, success: success)
        }
    }

    private func restore(current: Snapshot, key: String) {
        DDLogInfo(
            "BrowserBridgeTabAdapter: restore tab \(current.tab.tabId) in \(current.instanceId)"
        )
        BrowserBridgeService.shared.restoreTab(
            instanceId: current.instanceId,
            tabId: current.tab.tabId,
            windowId: current.tab.windowId
        ) { success in
            if success {
                Self.stateLock.lock()
                let previousApp = Self.previousApps.removeValue(
                    forKey: current.browserBundleIdentifier
                )
                Self.stateLock.unlock()
                if let previousApp {
                    DDLogInfo(
                        "BrowserBridgeTabAdapter: restore previous app \(previousApp)"
                    )
                    if previousApp != current.browserBundleIdentifier {
                        Self.activateApplication(bundleIdentifier: previousApp)
                    }
                }
            }
            Self.complete(key: key, action: "restore", current: current, success: success)
        }
    }

    /// Live check: the browser must be frontmost and the tab must be the
    /// active tab of the last focused browser window. The cached `tab.active`
    /// can lag behind an actual window/tab switch.
    private func liveFrontmost(_ current: Snapshot) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            == current.browserBundleIdentifier
        else {
            return false
        }
        if Thread.isMainThread {
            return current.tab.active
        }

        let semaphore = DispatchSemaphore(value: 0)
        var active = false
        BrowserBridgeService.shared.isActive(
            instanceId: current.instanceId,
            tabId: current.tab.tabId,
            windowId: current.tab.windowId
        ) { result in
            active = result
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1.0)
        return active
    }

    private static func complete(
        key: String,
        action: String,
        current: Snapshot,
        success: Bool
    ) {
        DDLogInfo(
            "BrowserBridgeTabAdapter: \(action) result=\(success) "
                + "tab \(current.tab.tabId) in \(current.instanceId)"
        )
        Self.stateLock.lock()
        Self.pendingKeys.remove(key)
        if success {
            if action == "raise" {
                Self.raisedKeys.insert(key)
            } else {
                Self.raisedKeys.remove(key)
            }
        }
        Self.stateLock.unlock()
    }

    private static func activateBrowserAndWait(bundleIdentifier: String) {
        guard let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first
        else {
            DDLogInfo("BrowserBridgeTabAdapter: no running browser for \(bundleIdentifier)")
            return
        }
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier {
            return
        }

        DispatchQueue.main.async {
            _ = application.activate(options: [.activateAllWindows])
        }
        let deadline = Date().addingTimeInterval(0.6)
        while NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundleIdentifier,
              Date() < deadline {
            usleep(15_000)
        }
        DDLogInfo(
            "BrowserBridgeTabAdapter: activate \(bundleIdentifier) "
                + "frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")"
        )
    }

    private static func activateApplication(bundleIdentifier: String) {
        guard let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first
        else {
            DDLogInfo("BrowserBridgeTabAdapter: no running app for \(bundleIdentifier)")
            return
        }
        DispatchQueue.main.async {
            _ = application.activate(options: [.activateAllWindows])
        }
        DDLogInfo("BrowserBridgeTabAdapter: restore previous app \(bundleIdentifier)")
    }

    @objc var browserDisplayName: String {
        withSnapshot { $0.browserDisplayName }
    }

    @objc var bridgeInstanceId: String {
        withSnapshot { $0.instanceId }
    }

    @objc var bridgeTabId: Int {
        withSnapshot { $0.tab.tabId }
    }

    @objc var bridgeWindowId: Int {
        withSnapshot { $0.tab.windowId }
    }

    @objc var bridgeBrowserBundleIdentifier: String {
        withSnapshot { $0.browserBundleIdentifier }
    }

    /// True when the bridge service still has media for this exact tab. The
    /// cached adapter snapshot can be stale after a state gap, so selection
    /// must ask the service, not the adapter.
    @objc var hasCurrentMedia: Bool {
        let current = withSnapshot { $0 }
        return BrowserBridgeService.shared.hasMedia(
            instanceId: current.instanceId,
            tabId: current.tab.tabId
        )
    }

    static func pruneRaisedTabs(keeping keys: Set<String>) {
        stateLock.lock()
        raisedKeys.formIntersection(keys)
        stateLock.unlock()
    }

    // MARK: - Snapshot helpers

    private func withSnapshot<T>(_ body: (Snapshot) -> T) -> T {
        snapshotLock.lock()
        let current = snapshot
        snapshotLock.unlock()
        return body(current)
    }

    private static func makeSnapshot(instance: BrowserBridgeInstance, tab: BrowserBridgeTab) -> Snapshot {
        let bundleIdentifier = instance.bundleIdentifier ?? instance.browser
        let displayName = instance.processIdentifier
            .flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
            ?? instance.browser
        return Snapshot(
            instanceId: instance.instanceId,
            browserBundleIdentifier: bundleIdentifier,
            browserDisplayName: displayName,
            processIdentifier: instance.processIdentifier,
            tab: tab
        )
    }
}

/// Builds and caches `BrowserBridgeTabAdapter` instances from the current
/// bridge state. The cache keeps adapter identity stable for `BSActiveTab` and
/// the Raise/Hide state across menu refreshes.
@objc(NowPlayingBrowserTabs)
final class NowPlayingBrowserTabs: NSObject {

    private static let cacheLock = NSLock()
    private static let maximumInstanceAge: TimeInterval = 120
    private static var cache: [String: BrowserBridgeTabAdapter] = [:]

    @objc static func tabs() -> [BrowserBridgeTabAdapter] {
        let instances = BrowserBridgeService.shared.activeInstances
        let now = Date()
        var current: [String: BrowserBridgeTabAdapter] = [:]

        cacheLock.lock()
        for instance in instances where now.timeIntervalSince(instance.lastUpdatedAt) <= maximumInstanceAge {
            for tab in instance.tabs where tab.mediaTitle != nil {
                let key = "\(instance.instanceId)#\(tab.tabId)"
                let adapter: BrowserBridgeTabAdapter
                if let existing = cache[key] {
                    adapter = existing
                    adapter.update(instance: instance, tab: tab)
                } else {
                    adapter = BrowserBridgeTabAdapter(instance: instance, tab: tab)
                }
                current[key] = adapter
            }
        }
        cache = current
        cacheLock.unlock()

        BrowserBridgeTabAdapter.pruneRaisedTabs(keeping: Set(current.keys))
        return current.values.sorted {
            let left = $0.browserDisplayName
            let right = $1.browserDisplayName
            if left != right {
                return left < right
            }
            let leftTitle = $0.title() ?? ""
            let rightTitle = $1.title() ?? ""
            if leftTitle != rightTitle {
                return leftTitle < rightTitle
            }
            return ($0.key() ?? "") < ($1.key() ?? "")
        }
    }
}
