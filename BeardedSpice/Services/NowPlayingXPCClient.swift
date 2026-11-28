//
//  NowPlayingXPCClient.swift
//  Beardie
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import Foundation

enum NowPlayingXPCError: LocalizedError {
    case proxyUnavailable
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .proxyUnavailable:
            return "The controllers XPC proxy is unavailable"
        case .invalidPayload:
            return "The controllers XPC service returned an invalid payload"
        }
    }
}

/// Thin app-side client for the read-only Now Playing methods in the XPC service.
final class NowPlayingXPCClient {

    private let connection: NSXPCConnection

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    private var proxy: BeardedSpiceControllersProtocol? {
        connection.remoteObjectProxy as? BeardedSpiceControllersProtocol
    }

    func fetchSnapshot(completion: @escaping (Result<NowPlayingSnapshot, Error>) -> Void) {
        guard let proxy else {
            completion(.failure(NowPlayingXPCError.proxyUnavailable))
            return
        }

        proxy.getNowPlayingSnapshot { data in
            guard
                let data,
                let snapshot = try? JSONDecoder().decode(NowPlayingSnapshot.self, from: data)
            else {
                completion(.failure(NowPlayingXPCError.invalidPayload))
                return
            }
            completion(.success(snapshot))
        }
    }

    func fetchHealth(completion: @escaping (Result<NowPlayingHealth, Error>) -> Void) {
        guard let proxy else {
            completion(.failure(NowPlayingXPCError.proxyUnavailable))
            return
        }

        proxy.getNowPlayingHealth { data in
            guard
                !data.isEmpty,
                let health = try? JSONDecoder().decode(NowPlayingHealth.self, from: data)
            else {
                completion(.failure(NowPlayingXPCError.invalidPayload))
                return
            }
            completion(.success(health))
        }
    }

    func reset(completion: @escaping (Bool) -> Void) {
        guard let proxy else {
            completion(false)
            return
        }
        proxy.resetNowPlaying { success in
            completion(success)
        }
    }

    /// Runs a targeted MediaRemote command transaction in the XPC service.
    func sendCommand(
        _ command: Int,
        to bundleIdentifier: String,
        hold: TimeInterval,
        completion: @escaping (Result<NowPlayingCommandResult, Error>) -> Void
    ) {
        guard let proxy else {
            completion(.failure(NowPlayingXPCError.proxyUnavailable))
            return
        }

        proxy.sendNowPlayingCommand(command, toBundle: bundleIdentifier, hold: hold) { data in
            guard
                let data,
                let result = try? JSONDecoder().decode(NowPlayingCommandResult.self, from: data)
            else {
                completion(.failure(NowPlayingXPCError.invalidPayload))
                return
            }
            completion(.success(result))
        }
    }

    /// Pauses every other playing MediaRemote client through separate XPC
    /// transactions.
    func pauseOthers(
        exceptBundleIdentifier: String?,
        completion: @escaping (Result<NowPlayingPauseOthersResult, Error>) -> Void
    ) {
        guard let proxy else {
            completion(.failure(NowPlayingXPCError.proxyUnavailable))
            return
        }

        proxy.pauseOtherNowPlayingClientsExceptBundle(exceptBundleIdentifier) { data in
            guard
                !data.isEmpty,
                let result = try? JSONDecoder().decode(NowPlayingPauseOthersResult.self, from: data)
            else {
                completion(.failure(NowPlayingXPCError.invalidPayload))
                return
            }
            completion(.success(result))
        }
    }
}
