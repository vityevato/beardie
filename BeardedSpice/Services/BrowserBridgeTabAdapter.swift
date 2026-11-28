//
//  BrowserBridgeTabAdapter.swift
//  Beardie
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

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

    /// Raise on the first call, restore the previously active tab on the next
    /// call. Commands are best effort: a failed restore still clears the
    /// remembered state.
    override func toggleTab() {
        let current = withSnapshot { $0 }
        let key = "\(current.instanceId)#\(current.tab.tabId)"

        Self.stateLock.lock()
        if Self.pendingKeys.contains(key) {
            Self.stateLock.unlock()
            return
        }
        let isRaised = Self.raisedKeys.contains(key)
        if isRaised {
            Self.raisedKeys.remove(key)
        }
        Self.pendingKeys.insert(key)
        Self.stateLock.unlock()

        let completion: (Bool) -> Void = { success in
            Self.stateLock.lock()
            Self.pendingKeys.remove(key)
            if !isRaised && success {
                Self.raisedKeys.insert(key)
            }
            Self.stateLock.unlock()
        }

        if isRaised {
            DDLogInfo("BrowserBridgeTabAdapter: restore tab \(current.tab.tabId) in \(current.instanceId)")
            BrowserBridgeService.shared.restoreTab(
                instanceId: current.instanceId,
                tabId: current.tab.tabId,
                windowId: current.tab.windowId,
                completion: completion
            )
        } else {
            DDLogInfo("BrowserBridgeTabAdapter: raise tab \(current.tab.tabId) in \(current.instanceId)")
            BrowserBridgeService.shared.activateTab(
                instanceId: current.instanceId,
                tabId: current.tab.tabId,
                windowId: current.tab.windowId,
                completion: completion
            )
        }
    }

    @objc var browserDisplayName: String {
        withSnapshot { $0.browserDisplayName }
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
