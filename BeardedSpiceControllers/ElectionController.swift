//
//  ElectionController.swift
//  BeardedSpiceControllers
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import CocoaLumberjackSwift
import Foundation

enum ElectionError: LocalizedError {
    case notAvailable
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Targeted MediaRemote commands are not available"
        case .invalidPayload:
            return "The MediaRemote adapter returned an invalid transaction payload"
        }
    }
}

/// Owns targeted MediaRemote command transactions.
///
/// A transaction points the system-wide now playing election override at one
/// application, waits until MediaRemote elected it, sends exactly one command,
/// keeps the override for a short hold time and clears it. The whole sequence
/// runs inside one adapter process, so the XPC service never leaves an
/// override behind on its own.
///
/// Transactions are serialized: MediaRemote has one system-wide election, and
/// concurrent overrides would fight each other. `pauseOthers` therefore issues
/// separate transactions one after another.
final class ElectionController {

    private let queue = DispatchQueue(label: "com.calm-apps.mac.beardie.nowplaying.election")
    private let runner: MediaRemoteAdapterRunning?
    private let stateLock = NSLock()

    private var _capabilities = NowPlayingCapabilities(
        readClients: false,
        targetedCommands: false,
        supportedCommands: false,
        electionOverride: false
    )
    private var _lastError: String?

    init(runner: MediaRemoteAdapterRunning?) {
        self.runner = runner
    }

    var capabilities: NowPlayingCapabilities {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _capabilities
    }

    var targetedCommandsAvailable: Bool {
        capabilities.targetedCommands
    }

    var lastError: String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastError
    }

    // MARK: - Capabilities

    /// Runs the adapter self-test once and records whether targeted
    /// transactions are supported on this system. The result gates every
    /// command path.
    func refreshCapabilities(completion: (() -> Void)? = nil) {
        guard let runner else {
            setCapabilities(unavailableCapabilities, error: MediaRemoteAdapterError.resourcesMissing.localizedDescription)
            DispatchQueue.main.async { completion?() }
            return
        }

        queue.async {
            runner.run(arguments: ["capabilities"], timeout: 5) { result in
                self.queue.async {
                    switch result {
                    case .success(let data):
                        do {
                            let capabilities = try self.parseCapabilities(data)
                            self.setCapabilities(capabilities, error: nil)
                            DDLogInfo(
                                "NowPlaying capabilities: targeted=\(capabilities.targetedCommands), "
                                    + "readClients=\(capabilities.readClients), "
                                    + "supportedCommands=\(capabilities.supportedCommands)"
                            )
                        } catch {
                            self.setCapabilities(self.unavailableCapabilities, error: error.localizedDescription)
                            DDLogError("NowPlaying capabilities failed: \(error.localizedDescription)")
                        }
                    case .failure(let error):
                        self.setCapabilities(self.unavailableCapabilities, error: error.localizedDescription)
                        DDLogError("NowPlaying capabilities failed: \(error.localizedDescription)")
                    }
                    completion?()
                }
            }
        }
    }

    // MARK: - Commands

    func send(
        command: Int,
        to bundleIdentifier: String,
        hold: TimeInterval,
        completion: @escaping (Result<NowPlayingCommandResult, Error>) -> Void
    ) {
        queue.async {
            guard self.targetedCommandsAvailable else {
                completion(.failure(ElectionError.notAvailable))
                return
            }
            self.performTransaction(command: command, to: bundleIdentifier, hold: hold, completion: completion)
        }
    }

    /// Pauses each target through its own transaction. Failures do not stop
    /// the remaining targets; the result reports both groups.
    func pauseOthers(targets: [String], completion: @escaping (NowPlayingPauseOthersResult) -> Void) {
        queue.async {
            guard self.targetedCommandsAvailable else {
                completion(NowPlayingPauseOthersResult(paused: [], failed: targets))
                return
            }
            self.pauseTargets(targets, index: 0, paused: [], failed: [], completion: completion)
        }
    }

    /// Cancels the transaction that is running now and clears a possible
    /// election override. Called when the host app disappears.
    func cancelActiveTransaction(completion: (() -> Void)? = nil) {
        runner?.cancelCurrent()

        guard let runner else {
            DispatchQueue.main.async { completion?() }
            return
        }

        queue.async {
            runner.run(arguments: ["reset"], timeout: 5) { result in
                if case .failure(let error) = result {
                    DDLogError("NowPlaying transaction reset failed: \(error.localizedDescription)")
                    self.setLastError(error.localizedDescription)
                }
                self.queue.async {
                    completion?()
                }
            }
        }
    }

    // MARK: - Private

    private var unavailableCapabilities: NowPlayingCapabilities {
        NowPlayingCapabilities(
            readClients: false,
            targetedCommands: false,
            supportedCommands: false,
            electionOverride: false
        )
    }

    private func performTransaction(
        command: Int,
        to bundleIdentifier: String,
        hold: TimeInterval,
        completion: @escaping (Result<NowPlayingCommandResult, Error>) -> Void
    ) {
        guard let runner else {
            completion(.failure(MediaRemoteAdapterError.resourcesMissing))
            return
        }

        let holdMilliseconds = max(0, Int((hold * 1000).rounded()))
        let arguments = [
            "transaction",
            "--bundle-id=\(bundleIdentifier)",
            "--command=\(command)",
            "--hold=\(holdMilliseconds)"
        ]

        runner.run(arguments: arguments, timeout: 6) { result in
            switch result {
            case .success(let data):
                do {
                    let commandResult = try JSONDecoder().decode(NowPlayingCommandResult.self, from: data)
                    self.setLastError(nil)
                    completion(.success(commandResult))
                } catch {
                    self.setLastError(error.localizedDescription)
                    DDLogError(
                        "NowPlaying transaction for \(bundleIdentifier) returned an invalid payload: "
                            + "\(error.localizedDescription)"
                    )
                    completion(.failure(ElectionError.invalidPayload))
                }
            case .failure(let error):
                self.setLastError(error.localizedDescription)
                DDLogError(
                    "NowPlaying transaction for \(bundleIdentifier) failed: \(error.localizedDescription)"
                )
                // A killed helper may have left the election override behind.
                // Clear it before the next transaction uses a new process.
                self.resetAfterFailedTransaction()
                completion(.failure(error))
            }
        }
    }

    private func resetAfterFailedTransaction() {
        guard let runner else {
            return
        }
        queue.async {
            runner.run(arguments: ["reset"], timeout: 5) { result in
                if case .failure(let error) = result {
                    DDLogError("NowPlaying recovery reset failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func pauseTargets(
        _ targets: [String],
        index: Int,
        paused: [String],
        failed: [String],
        completion: @escaping (NowPlayingPauseOthersResult) -> Void
    ) {
        guard index < targets.count else {
            completion(NowPlayingPauseOthersResult(paused: paused, failed: failed))
            return
        }

        let target = targets[index]
        // kMRPause = 1.
        performTransaction(command: 1, to: target, hold: 0.25) { result in
            self.queue.async {
                var paused = paused
                var failed = failed
                switch result {
                case .success:
                    paused.append(target)
                case .failure:
                    failed.append(target)
                }
                self.pauseTargets(targets, index: index + 1, paused: paused, failed: failed, completion: completion)
            }
        }
    }

    private func parseCapabilities(_ data: Data) throws -> NowPlayingCapabilities {
        try JSONDecoder().decode(NowPlayingCapabilities.self, from: data)
    }

    private func setCapabilities(_ capabilities: NowPlayingCapabilities, error: String?) {
        stateLock.lock()
        _capabilities = capabilities
        if let error {
            _lastError = error
        }
        stateLock.unlock()
    }

    private func setLastError(_ error: String?) {
        stateLock.lock()
        _lastError = error
        stateLock.unlock()
    }
}
