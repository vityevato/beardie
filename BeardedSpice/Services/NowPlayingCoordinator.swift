//
//  NowPlayingCoordinator.swift
//  Beardie
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import CocoaLumberjackSwift
import Foundation

/// App-side facade for the Now Playing service in the XPC controller.
///
/// The coordinator owns the current XPC client, the last health payload and
/// the last snapshot. CommandRouter uses the synchronous helpers below; they
/// must be called off the main queue (the app's working queue is the intended
/// caller).
@objc(NowPlayingCoordinator)
final class NowPlayingCoordinator: NSObject {

    private static let shared = NowPlayingCoordinator()

    private let lock = NSLock()
    private var client: NowPlayingXPCClient?
    private var health: NowPlayingHealth?
    private var healthDate: Date?
    private var snapshot: NowPlayingSnapshot?
    private var snapshotDate: Date?

    private static let healthTTL: TimeInterval = 2
    private static let snapshotTTL: TimeInterval = 2

    // MARK: - Lifecycle

    /// Rebinds the coordinator to a new XPC connection. Called at launch and
    /// after the app reconnects to a restarted controller service.
    @objc(startWithConnection:)
    static func start(connection: NSXPCConnection) {
        guard UserDefaults.standard.bool(forKey: "UseSystemNowPlaying") else {
            DDLogDebug("UseSystemNowPlaying is disabled")
            return
        }

        let client = NowPlayingXPCClient(connection: connection)
        shared.lock.lock()
        shared.client = client
        shared.health = nil
        shared.healthDate = nil
        shared.snapshot = nil
        shared.snapshotDate = nil
        shared.lock.unlock()

        // A reconnect can leave a stale election override behind. The reset
        // also refreshes the adapter capabilities in the service.
        client.reset { success in
            DDLogInfo("NowPlaying reset after connection: \(success ? "OK" : "failed")")
            shared.refresh()
        }
    }

    /// Writes the current sources and health to the log (debug command).
    @objc(logCurrentState)
    static func logCurrentState() {
        guard let snapshot = snapshotSync(force: true) else {
            DDLogError("NowPlaying snapshot is unavailable")
            return
        }

        DDLogInfo("NowPlaying snapshot: \(snapshot.clients.count) clients")
        for nowPlayingClient in snapshot.clients {
            DDLogDebug(
                "NowPlaying source: \(nowPlayingClient.displayName ?? "unknown") "
                    + "bundle=\(nowPlayingClient.effectiveBundleIdentifier ?? "unknown") "
                    + "pid=\(nowPlayingClient.processIdentifier ?? 0) "
                    + "playing=\(nowPlayingClient.isPlaying) "
                    + "title=\(nowPlayingClient.title ?? "none")"
            )
        }

        if let health = healthSync(force: true) {
            DDLogInfo(
                "NowPlaying health: adapter=\(health.adapterAvailable), "
                    + "targeted=\(health.targetedCommandsAvailable), "
                    + "clients=\(health.clientCount), error=\(health.lastError ?? "none")"
            )
        }
    }

    /// Debug-only helper for local E2E runs. Never called from product code.
    @objc(debugSendCommandToBundle:command:hold:)
    static func debugSendCommand(to bundleIdentifier: String, command: Int, hold: Double) -> Bool {
        guard let result = sendCommand(
            command,
            to: bundleIdentifier,
            hold: hold,
            timeout: max(6, hold + 3)
        ) else {
            return false
        }
        return result.sent && result.elected
    }

    // MARK: - Asynchronous refresh

    private func refresh() {
        guard let client = currentClient() else {
            return
        }

        client.fetchHealth { result in
            switch result {
            case .success(let health):
                self.store(health: health)
                DDLogInfo(
                    "NowPlaying health: adapter=\(health.adapterAvailable), "
                        + "targeted=\(health.targetedCommandsAvailable), "
                        + "clients=\(health.clientCount), error=\(health.lastError ?? "none")"
                )
            case .failure(let error):
                DDLogError("NowPlaying health failed: \(error.localizedDescription)")
            }

            client.fetchSnapshot { snapshotResult in
                switch snapshotResult {
                case .success(let snapshot):
                    self.store(snapshot: snapshot)
                    DDLogInfo("NowPlaying snapshot: \(snapshot.clients.count) clients")
                case .failure(let error):
                    DDLogError("NowPlaying snapshot failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Synchronous helpers

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "UseSystemNowPlaying")
    }

    /// Returns the last known health, refreshing it when it is older than the
    /// short TTL. Blocks the calling queue for at most `timeout`.
    static func healthSync(force: Bool = false, timeout: TimeInterval = 2) -> NowPlayingHealth? {
        let now = Date()
        shared.lock.lock()
        let cached = shared.health
        let cachedDate = shared.healthDate
        let client = shared.client
        shared.lock.unlock()

        if !force, let cached, let cachedDate, now.timeIntervalSince(cachedDate) <= healthTTL {
            return cached
        }
        guard let client else {
            return cached
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: NowPlayingHealth?
        client.fetchHealth { healthResult in
            if case .success(let health) = healthResult {
                result = health
                shared.store(health: health)
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        return result ?? cached
    }

    /// Returns a snapshot, refreshing it when it is older than the short TTL.
    static func snapshotSync(force: Bool = false, timeout: TimeInterval = 3) -> NowPlayingSnapshot? {
        let now = Date()
        shared.lock.lock()
        let cached = shared.snapshot
        let cachedDate = shared.snapshotDate
        let client = shared.client
        shared.lock.unlock()

        if !force, let cached, let cachedDate, now.timeIntervalSince(cachedDate) <= snapshotTTL {
            return cached
        }
        guard let client else {
            return cached
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: NowPlayingSnapshot?
        client.fetchSnapshot { snapshotResult in
            if case .success(let snapshot) = snapshotResult {
                result = snapshot
                shared.store(snapshot: snapshot)
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        return result ?? cached
    }

    /// Finds the MediaRemote client that represents a native application.
    /// Prefers a playing client, then the one with the most metadata.
    static func client(matching bundleIdentifier: String) -> NowPlayingClient? {
        guard isEnabled, let snapshot = snapshotSync() else {
            return nil
        }
        let target = bundleIdentifier.lowercased()
        let matches = snapshot.clients.filter {
            ($0.effectiveBundleIdentifier ?? "").lowercased() == target
        }
        return matches.max { left, right in
            score(left) < score(right)
        }
    }

    /// Sends a targeted command and waits for the XPC transaction. Returns
    /// `nil` when the service is unavailable or the transaction failed.
    static func sendCommand(
        _ command: Int,
        to bundleIdentifier: String,
        hold: TimeInterval = 0.25,
        timeout: TimeInterval = 6
    ) -> NowPlayingCommandResult? {
        guard isEnabled, let client = currentClient() else {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: NowPlayingCommandResult?
        client.sendCommand(command, to: bundleIdentifier, hold: hold) { commandResult in
            if case .success(let value) = commandResult {
                result = value
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        return result
    }

    /// Pauses every other playing MediaRemote client through separate
    /// transactions. Returns `nil` when the service is unavailable.
    static func pauseOthers(
        exceptBundleIdentifier: String?,
        timeout: TimeInterval = 12
    ) -> NowPlayingPauseOthersResult? {
        guard isEnabled, let client = currentClient() else {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: NowPlayingPauseOthersResult?
        client.pauseOthers(exceptBundleIdentifier: exceptBundleIdentifier) { pauseResult in
            if case .success(let value) = pauseResult {
                result = value
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        return result
    }

    static var targetedCommandsAvailable: Bool {
        guard isEnabled else {
            return false
        }
        return healthSync()?.targetedCommandsAvailable ?? false
    }

    // MARK: - Private

    private func currentClient() -> NowPlayingXPCClient? {
        lock.lock()
        defer { lock.unlock() }
        return client
    }

    private func store(health: NowPlayingHealth) {
        lock.lock()
        self.health = health
        self.healthDate = Date()
        lock.unlock()
    }

    private func store(snapshot: NowPlayingSnapshot) {
        lock.lock()
        self.snapshot = snapshot
        self.snapshotDate = Date()
        lock.unlock()
    }

    private static func currentClient() -> NowPlayingXPCClient? {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        return shared.client
    }

    private static func score(_ client: NowPlayingClient) -> Int {
        var score = 0
        if client.isPlaying {
            score += 4
        }
        if client.title != nil {
            score += 2
        }
        if !client.supportedCommands.isEmpty {
            score += 1
        }
        return score
    }
}
