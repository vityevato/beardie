//
//  ArtworkCache.swift
//  Beardie
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import Foundation

/// A small in-memory cache for artwork decoded from MediaRemote snapshots.
///
/// MediaRemote may return artwork in one read and omit it in the next, so the
/// last successful image is kept by fingerprint.
final class ArtworkCache {

    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private var order: [String] = []

    let capacity: Int

    init(capacity: Int = 8) {
        self.capacity = max(1, capacity)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    func store(_ data: Data, fingerprint: String) {
        lock.lock()
        defer { lock.unlock() }

        if storage[fingerprint] != nil {
            order.removeAll { $0 == fingerprint }
        }
        storage[fingerprint] = data
        order.append(fingerprint)

        while order.count > capacity {
            let oldest = order.removeFirst()
            storage.removeValue(forKey: oldest)
        }
    }

    func data(for fingerprint: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[fingerprint]
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
        order.removeAll()
    }
}
