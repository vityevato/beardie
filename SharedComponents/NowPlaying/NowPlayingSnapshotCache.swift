//
//  NowPlayingSnapshotCache.swift
//  Beardie
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import Foundation

/// TTL cache for the latest now playing snapshot.
///
/// The XPC service owns one instance and accesses it from a serial queue.
final class NowPlayingSnapshotCache {

    let ttl: TimeInterval
    private var snapshot: NowPlayingSnapshot?

    init(ttl: TimeInterval = 1.0) {
        self.ttl = ttl
    }

    var latest: NowPlayingSnapshot? {
        snapshot
    }

    func value(now: Date = Date()) -> NowPlayingSnapshot? {
        guard let snapshot else {
            return nil
        }
        guard now.timeIntervalSince(snapshot.refreshedAt) < ttl else {
            return nil
        }
        return snapshot
    }

    func store(_ snapshot: NowPlayingSnapshot) {
        self.snapshot = snapshot
    }

    func invalidate() {
        snapshot = nil
    }
}
