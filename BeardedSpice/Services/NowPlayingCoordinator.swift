//
//  NowPlayingCoordinator.swift
//  Beardie
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import CocoaLumberjackSwift
import Foundation

/// Debug-facing integration for the Stage 1 read-only Now Playing service.
///
/// The feature is gated by `UseSystemNowPlaying`. It does not change UI or
/// commands; it only fetches and logs the sources reported by the XPC service.
@objc(NowPlayingCoordinator)
final class NowPlayingCoordinator: NSObject {

    private static var client: NowPlayingXPCClient?

    @objc(startWithConnection:)
    static func start(connection: NSXPCConnection) {
        guard UserDefaults.standard.bool(forKey: "UseSystemNowPlaying") else {
            DDLogDebug("UseSystemNowPlaying is disabled")
            return
        }

        let client = NowPlayingXPCClient(connection: connection)
        self.client = client

        client.fetchSnapshot { result in
            switch result {
            case .success(let snapshot):
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
            case .failure(let error):
                DDLogError("NowPlaying snapshot failed: \(error.localizedDescription)")
            }

            client.fetchHealth { healthResult in
                switch healthResult {
                case .success(let health):
                    DDLogInfo(
                        "NowPlaying health: adapter=\(health.adapterAvailable), clients=\(health.clientCount), error=\(health.lastError ?? "none")"
                    )
                case .failure(let error):
                    DDLogError("NowPlaying health failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Fetches a fresh snapshot for the Stage 3 target resolver.
    ///
    /// The timeout keeps the Raise/Hide shortcut from hanging when the XPC
    /// service is unresponsive. A late reply is ignored.
    static func fetchSnapshot(
        timeout: TimeInterval = 5,
        completion: @escaping (Result<NowPlayingSnapshot, Error>) -> Void
    ) {
        guard let client else {
            completion(.failure(NowPlayingXPCError.proxyUnavailable))
            return
        }

        let lock = NSLock()
        var finished = false
        func finish(_ result: Result<NowPlayingSnapshot, Error>) {
            lock.lock()
            if finished {
                lock.unlock()
                return
            }
            finished = true
            lock.unlock()
            completion(result)
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            finish(.failure(NowPlayingXPCError.timedOut))
        }
        client.fetchSnapshot { result in
            finish(result)
        }
    }
}
