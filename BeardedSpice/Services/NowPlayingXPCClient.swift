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
    case timedOut

    var errorDescription: String? {
        switch self {
        case .proxyUnavailable:
            return "The controllers XPC proxy is unavailable"
        case .invalidPayload:
            return "The controllers XPC service returned an invalid payload"
        case .timedOut:
            return "The controllers XPC service did not answer in time"
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
}
