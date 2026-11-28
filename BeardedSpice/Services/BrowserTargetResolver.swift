//
//  BrowserTargetResolver.swift
//  Beardie
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import CocoaLumberjackSwift
import Foundation

/// A browser tab that was matched to a Now Playing client.
struct BrowserResolvedTarget: Equatable {
    let instanceId: String
    let browserBundleIdentifier: String
    let tabId: Int
    let windowId: Int
    let title: String?
    let artist: String?
    let score: Double
}

/// Matches a MediaRemote Now Playing client to a tab reported by the new
/// browser bridge.
///
/// MediaRemote reports browser media through helper processes (for example
/// `com.google.Chrome.helper` or `com.apple.WebKit.GPU`), while the bridge
/// reports the browser bundle and its own tab ids. The resolver therefore:
///
/// - matches the client's effective bundle to a connected bridge instance;
/// - scores every media tab by title, artist, album, playback state, elapsed
///   time, tab activity and data freshness;
/// - returns `nil` when the best candidate is below the confidence floor or
///   when two candidates are too close.
///
/// The resolver does not choose the current player and never overrides
/// `BSActiveTab`. Stage 4 uses it for command routing; Stage 3 Raise/Hide works
/// from the already selected `TabAdapter`.
enum BrowserTargetResolver {

    static let minimumScore: Double = 45
    static let minimumMargin: Double = 8
    static let maximumDataAge: TimeInterval = 15

    /// Resolves a bridge tab for a player that was already selected by the
    /// app-level player selection. `isPlaying` is not a filter here: a paused
    /// player must resolve exactly like a playing one.
    static func resolve(
        client: NowPlayingClient,
        instances: [BrowserBridgeInstance],
        now: Date = Date()
    ) -> BrowserResolvedTarget? {
        guard normalizedText(client.title) != nil else {
            return nil
        }

        var bestByTab: [String: BrowserResolvedTarget] = [:]

        for instance in instances where isFresh(instance.lastUpdatedAt, now: now) {
            guard bundleMatches(client, instance) else {
                continue
            }
            for tab in instance.tabs {
                guard let target = score(client: client, instance: instance, tab: tab, now: now) else {
                    continue
                }
                let key = "\(target.instanceId)#\(target.tabId)"
                if let existing = bestByTab[key], existing.score >= target.score {
                    continue
                }
                bestByTab[key] = target
            }
        }

        let ranked = bestByTab.values.sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            if $0.instanceId != $1.instanceId {
                return $0.instanceId < $1.instanceId
            }
            return $0.tabId < $1.tabId
        }

        guard let best = ranked.first, best.score >= minimumScore else {
            return nil
        }
        if ranked.count > 1, best.score - ranked[1].score < minimumMargin {
            DDLogInfo(
                "BrowserTargetResolver: ambiguous target \(best.title ?? "untitled") "
                    + "score=\(Int(best.score)) next=\(Int(ranked[1].score))"
            )
            return nil
        }
        return best
    }

    // MARK: - Scoring

    private static func score(
        client: NowPlayingClient,
        instance: BrowserBridgeInstance,
        tab: BrowserBridgeTab,
        now: Date
    ) -> BrowserResolvedTarget? {
        guard isFresh(tab.updatedAt, now: now) else {
            return nil
        }
        guard
            let clientTitle = normalizedText(client.title),
            let tabTitle = normalizedText(tab.mediaTitle)
        else {
            return nil
        }

        var score = titleScore(clientTitle, tabTitle)
        guard score > 0 else {
            return nil
        }

        if let clientArtist = normalizedText(client.artist),
           let tabArtist = normalizedText(tab.artist),
           clientArtist != tabArtist {
            return nil
        }

        score += artistScore(client.artist, tab.artist)
        score += albumScore(client.album, tab.album)

        if tab.playbackState?.lowercased() == "playing" {
            score += 10
        }

        let age = max(0, now.timeIntervalSince(tab.updatedAt))
        if age <= 5 {
            score += 4
        } else if age <= maximumDataAge {
            score += 2
        }

        if tab.active {
            score += 2
        }

        if let clientDuration = client.duration, let tabDuration = tab.duration,
           clientDuration > 0, tabDuration > 0 {
            let delta = abs(clientDuration - tabDuration)
            if delta <= 2 {
                score += 4
            } else if delta > 30 {
                score -= 10
            }
        }

        if let elapsed = client.elapsedTime, let position = tab.position {
            let delta = abs(elapsed - position)
            if delta <= 5 {
                score += 6
            } else if delta > 30 {
                score -= 4
            }
        }

        return BrowserResolvedTarget(
            instanceId: instance.instanceId,
            browserBundleIdentifier: instance.bundleIdentifier ?? instance.browser,
            tabId: tab.tabId,
            windowId: tab.windowId,
            title: tab.mediaTitle,
            artist: tab.artist,
            score: score
        )
    }

    private static func titleScore(_ client: String, _ tab: String) -> Double {
        if client == tab {
            return 45
        }
        if client.count >= 4, tab.count >= 4, tab.contains(client) || client.contains(tab) {
            return 35
        }

        let overlap = tokenOverlap(client, tab)
        if overlap >= 0.75 {
            return 30
        }
        if overlap >= 0.5 {
            return 22
        }
        return 0
    }

    private static func artistScore(_ client: String?, _ tab: String?) -> Double {
        guard let clientArtist = normalizedText(client) else {
            return 0
        }
        guard let tabArtist = normalizedText(tab) else {
            return -10
        }
        return clientArtist == tabArtist ? 20 : 0
    }

    private static func albumScore(_ client: String?, _ tab: String?) -> Double {
        guard let clientAlbum = normalizedText(client) else {
            return 0
        }
        guard let tabAlbum = normalizedText(tab) else {
            return 0
        }
        if clientAlbum == tabAlbum {
            return 8
        }
        if tokenOverlap(clientAlbum, tabAlbum) >= 0.5 {
            return 4
        }
        return -5
    }

    // MARK: - Matching helpers

    private static func bundleMatches(_ client: NowPlayingClient, _ instance: BrowserBridgeInstance) -> Bool {
        guard let clientBundle = normalizedBundle(client.effectiveBundleIdentifier ?? client.bundleIdentifier) else {
            return false
        }
        guard let instanceBundle = normalizedBundle(instance.bundleIdentifier ?? instance.browser) else {
            return false
        }
        if clientBundle == instanceBundle {
            return true
        }
        return strippedHelperBundle(clientBundle) == strippedHelperBundle(instanceBundle)
    }

    private static func normalizedBundle(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func strippedHelperBundle(_ bundle: String) -> String {
        for suffix in [".helper", ".renderer", ".gpu", ".plugin"] where bundle.hasSuffix(suffix) {
            return String(bundle.dropLast(suffix.count))
        }
        return bundle
    }

    private static func isFresh(_ date: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(date)
        return age >= -2 && age <= maximumDataAge
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let folded = value
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let characters = folded.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        }
        let normalized = String(characters).split(separator: " ").joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }

    private static func tokenOverlap(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(lhs.split(separator: " ").map(String.init))
        let right = Set(rhs.split(separator: " ").map(String.init))
        guard !left.isEmpty, !right.isEmpty else {
            return 0
        }
        return Double(left.intersection(right).count) / Double(min(left.count, right.count))
    }
}
