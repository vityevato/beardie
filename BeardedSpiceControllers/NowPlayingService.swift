//
//  NowPlayingService.swift
//  BeardedSpiceControllers
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import CocoaLumberjackSwift
import Foundation

/// Read-only Now Playing service that lives in the XPC controller.
///
/// It owns the adapter runner, the client snapshot cache and the artwork
/// cache. Commands are not sent from this service yet; Stage 4 adds the
/// election and transaction layer.
final class NowPlayingService {

    private let queue = DispatchQueue(label: "com.calm-apps.mac.beardie.nowplaying")
    private let runner: MediaRemoteAdapterRunning?
    private let snapshotCache = NowPlayingSnapshotCache(ttl: 1.0)
    private let artworkCache = ArtworkCache()
    private let electionController: ElectionController

    private var lastError: String?
    private var lastRefreshAt: Date?
    private var lastSnapshot: NowPlayingSnapshot?

    init(runner: MediaRemoteAdapterRunning? = MediaRemoteAdapterRunner()) {
        self.runner = runner
        self.electionController = ElectionController(runner: runner)
        if runner == nil {
            lastError = MediaRemoteAdapterError.resourcesMissing.localizedDescription
        }
    }

    /// Clears a stale MediaRemote election override before the first read.
    func start() {
        guard let runner else {
            DDLogError("NowPlayingService started without MediaRemoteAdapter")
            return
        }

        runner.run(arguments: ["reset"], timeout: 5) { result in
            self.queue.async {
                switch result {
                case .success:
                    DDLogInfo("NowPlaying startup reset completed")
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    DDLogError("NowPlaying startup reset failed: \(error.localizedDescription)")
                }
                self.electionController.refreshCapabilities()
            }
        }
    }

    func snapshot(force: Bool = false, completion: @escaping (Result<NowPlayingSnapshot, Error>) -> Void) {
        queue.async {
            if !force, let cached = self.snapshotCache.value() {
                completion(.success(cached))
                return
            }

            guard let runner = self.runner else {
                let error = MediaRemoteAdapterError.resourcesMissing
                self.lastError = error.localizedDescription
                completion(.failure(error))
                return
            }

            runner.run(arguments: ["clients", "--no-artwork", "--now"], timeout: 5) { result in
                self.queue.async {
                    switch result {
                    case .success(let data):
                        do {
                            let clients = try NowPlayingParser.parseClients(
                                from: data,
                                artworkCache: self.artworkCache
                            )
                            let snapshot = NowPlayingSnapshot(
                                clients: clients,
                                refreshedAt: Date(),
                                adapterAvailable: true,
                                error: nil
                            )
                            self.snapshotCache.store(snapshot)
                            self.lastSnapshot = snapshot
                            self.lastRefreshAt = snapshot.refreshedAt
                            self.lastError = nil
                            completion(.success(snapshot))
                        } catch {
                            self.lastError = error.localizedDescription
                            completion(.failure(error))
                        }
                    case .failure(let error):
                        self.lastError = error.localizedDescription
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    func health(completion: @escaping (NowPlayingHealth) -> Void) {
        queue.async {
            let capabilities = self.electionController.capabilities
            let health = NowPlayingHealth(
                adapterAvailable: self.runner != nil,
                lastRefreshAt: self.lastRefreshAt,
                lastError: self.lastError ?? self.electionController.lastError,
                clientCount: self.lastSnapshot?.clients.count ?? 0,
                resetSupported: self.runner != nil,
                targetedCommandsAvailable: capabilities.targetedCommands
            )
            completion(health)
        }
    }

    // MARK: - Targeted commands

    func sendCommand(
        _ command: Int,
        to bundleIdentifier: String,
        hold: TimeInterval,
        completion: @escaping (Result<NowPlayingCommandResult, Error>) -> Void
    ) {
        electionController.send(command: command, to: bundleIdentifier, hold: hold, completion: completion)
    }

    /// Pauses every playing MediaRemote client except the given bundle through
    /// separate transactions.
    func pauseOthers(
        exceptBundleIdentifier excludedBundleIdentifier: String?,
        completion: @escaping (NowPlayingPauseOthersResult) -> Void
    ) {
        snapshot(force: true) { result in
            switch result {
            case .success(let snapshot):
                let excluded = excludedBundleIdentifier?.lowercased()
                var targets: [String] = []
                var seen = Set<String>()

                for client in snapshot.clients where client.isPlaying {
                    guard let bundleIdentifier = client.effectiveBundleIdentifier else {
                        continue
                    }
                    let key = bundleIdentifier.lowercased()
                    if key == excluded {
                        continue
                    }
                    guard seen.insert(key).inserted else {
                        continue
                    }
                    targets.append(bundleIdentifier)
                }

                if targets.isEmpty {
                    completion(NowPlayingPauseOthersResult(paused: [], failed: []))
                    return
                }
                self.electionController.pauseOthers(targets: targets, completion: completion)
            case .failure(let error):
                DDLogError("NowPlaying pauseOthers snapshot failed: \(error.localizedDescription)")
                completion(NowPlayingPauseOthersResult(paused: [], failed: []))
            }
        }
    }

    /// Cancels a running transaction and clears a possible election override.
    /// Called when the last host connection goes away.
    func cancelActiveTransaction(completion: (() -> Void)? = nil) {
        electionController.cancelActiveTransaction(completion: completion)
    }

    func reset(completion: @escaping (Bool) -> Void) {
        guard let runner else {
            completion(false)
            return
        }

        queue.async {
            runner.run(arguments: ["reset"], timeout: 5) { result in
                self.queue.async {
                    switch result {
                    case .success:
                        self.snapshotCache.invalidate()
                        self.lastError = nil
                        self.electionController.refreshCapabilities {
                            completion(true)
                        }
                    case .failure(let error):
                        self.lastError = error.localizedDescription
                        DDLogError("NowPlaying reset failed: \(error.localizedDescription)")
                        completion(false)
                    }
                }
            }
        }
    }
}
