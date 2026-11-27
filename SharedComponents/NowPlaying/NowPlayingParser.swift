//
//  NowPlayingParser.swift
//  Beardie
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import AppKit
import CryptoKit
import Foundation

enum NowPlayingParserError: LocalizedError {
    case invalidJSON
    case unexpectedPayload

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "The MediaRemote adapter returned invalid JSON"
        case .unexpectedPayload:
            return "The MediaRemote adapter returned an unexpected payload"
        }
    }
}

/// Parses the JSON emitted by `mediaremote-adapter.pl clients`.
enum NowPlayingParser {

    static func parseClients(from data: Data, artworkCache: ArtworkCache? = nil) throws -> [NowPlayingClient] {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw NowPlayingParserError.invalidJSON
        }

        guard let payload = json as? [[String: Any]] else {
            throw NowPlayingParserError.unexpectedPayload
        }

        return payload.compactMap { parseClient($0, artworkCache: artworkCache) }
    }

    private static func parseClient(_ payload: [String: Any], artworkCache: ArtworkCache?) -> NowPlayingClient? {
        let bundleIdentifier = normalizedString(payload["bundleIdentifier"])
        let parentBundleIdentifier = normalizedString(payload["parentApplicationBundleIdentifier"])
        let processIdentifier = (payload["processIdentifier"] as? NSNumber)?.int32Value

        guard bundleIdentifier != nil || parentBundleIdentifier != nil || (processIdentifier ?? 0) > 0 else {
            return nil
        }

        let effectiveBundle = parentBundleIdentifier ?? bundleIdentifier
        let displayName = normalizedString(payload["displayName"])
            ?? applicationName(for: processIdentifier)
            ?? effectiveBundle

        let sourceIdentity = effectiveBundle ?? bundleIdentifier ?? "pid:\(processIdentifier ?? 0)"
        let sourceIdentifier: String
        if let processIdentifier, processIdentifier > 0 {
            sourceIdentifier = "\(sourceIdentity)#\(processIdentifier)"
        } else {
            sourceIdentifier = sourceIdentity
        }

        let artworkMimeType = normalizedString(payload["artworkMimeType"])
        let artworkFingerprint = decodeArtwork(payload["artworkData"], cache: artworkCache)

        return NowPlayingClient(
            sourceIdentifier: sourceIdentifier,
            bundleIdentifier: bundleIdentifier,
            parentBundleIdentifier: parentBundleIdentifier,
            processIdentifier: processIdentifier,
            displayName: displayName,
            title: normalizedString(payload["title"]),
            artist: normalizedString(payload["artist"]),
            album: normalizedString(payload["album"]),
            isPlaying: (payload["playing"] as? NSNumber)?.boolValue ?? false,
            playbackRate: number(payload["playbackRate"]),
            duration: number(payload["duration"]),
            elapsedTime: number(payload["elapsedTimeNow"]) ?? number(payload["elapsedTime"]),
            timestamp: normalizedString(payload["timestamp"]),
            supportedCommands: parseCommands(payload["supportedCommands"]),
            artworkMimeType: artworkMimeType,
            artworkFingerprint: artworkFingerprint
        )
    }

    private static func parseCommands(_ value: Any?) -> [NowPlayingCommand] {
        guard let commands = value as? [[String: Any]] else {
            return []
        }

        return commands.compactMap { command in
            guard let identifier = (command["id"] as? NSNumber)?.intValue else {
                return nil
            }
            return NowPlayingCommand(
                identifier: identifier,
                name: normalizedString(command["name"]),
                enabled: (command["enabled"] as? NSNumber)?.boolValue ?? true
            )
        }
    }

    private static func decodeArtwork(_ value: Any?, cache: ArtworkCache?) -> String? {
        guard
            let encoded = value as? String,
            let data = Data(base64Encoded: encoded),
            !data.isEmpty
        else {
            return nil
        }

        let fingerprint = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        cache?.store(data, fingerprint: fingerprint)
        return fingerprint
    }

    private static func applicationName(for processIdentifier: Int32?) -> String? {
        guard let processIdentifier, processIdentifier > 0 else {
            return nil
        }
        return NSRunningApplication(processIdentifier: processIdentifier)?.localizedName
    }

    private static func normalizedString(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else {
            return nil
        }
        return string
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
