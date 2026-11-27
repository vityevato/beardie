//
//  NowPlayingModels.swift
//  Beardie
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import Foundation

/// A command reported by MediaRemote for a now playing client.
struct NowPlayingCommand: Codable, Equatable {
    let identifier: Int
    let name: String?
    let enabled: Bool
}

/// A single MediaRemote client, normalized for use by the app and the XPC service.
struct NowPlayingClient: Codable, Equatable {
    /// Stable key for caching: normalized bundle plus PID when available.
    let sourceIdentifier: String

    let bundleIdentifier: String?
    let parentBundleIdentifier: String?
    let processIdentifier: Int32?
    let displayName: String?

    let title: String?
    let artist: String?
    let album: String?

    let isPlaying: Bool
    let playbackRate: Double?
    let duration: Double?
    let elapsedTime: Double?
    let timestamp: String?

    let supportedCommands: [NowPlayingCommand]

    let artworkMimeType: String?
    let artworkFingerprint: String?

    /// The application bundle to use for matching. WebKit-based browsers report
    /// `com.apple.WebKit.GPU` as their own bundle and the browser as the parent.
    var effectiveBundleIdentifier: String? {
        parentBundleIdentifier ?? bundleIdentifier
    }

    var hasArtwork: Bool {
        artworkFingerprint != nil
    }
}

/// A point-in-time list of all registered MediaRemote clients.
struct NowPlayingSnapshot: Codable, Equatable {
    let clients: [NowPlayingClient]
    let refreshedAt: Date
    let adapterAvailable: Bool
    let error: String?
}

/// Diagnostic state exposed over XPC without requiring a full MediaRemote read.
struct NowPlayingHealth: Codable, Equatable {
    let adapterAvailable: Bool
    let lastRefreshAt: Date?
    let lastError: String?
    let clientCount: Int
    let resetSupported: Bool
}
