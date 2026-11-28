//
//  NowPlayingTests.swift
//  BeardieTests
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import XCTest

@testable import Beardie

final class NowPlayingTests: XCTestCase {

    private func makePayload(artwork: String? = nil) -> Data {
        let artworkField: String
        if let artwork {
            artworkField = """
            ,"artworkMimeType":"image/jpeg","artworkData":"\(artwork)"
            """
        } else {
            artworkField = ""
        }

        let json = """
        [
          {
            "bundleIdentifier": "com.apple.WebKit.GPU",
            "parentApplicationBundleIdentifier": "com.apple.Safari",
            "processIdentifier": 99999,
            "title": "Browser Track",
            "artist": "Browser Artist",
            "album": "Browser Album",
            "playing": true,
            "playbackRate": 1,
            "duration": 240,
            "elapsedTime": 10,
            "elapsedTimeNow": 42.5,
            "timestamp": "2026-11-28T00:00:00Z",
            "supportedCommands": [
              {"id": 0, "name": "Play", "enabled": true},
              {"id": 2, "name": "NextTrack", "enabled": false}
            ]
            \(artworkField)
          },
          {
            "bundleIdentifier": "test.beardie.playera",
            "processIdentifier": 123,
            "playing": false
          },
          {
            "title": "No identity"
          }
        ]
        """
        return Data(json.utf8)
    }

    func testParsesAndNormalizesSafariClient() throws {
        let clients = try NowPlayingParser.parseClients(from: makePayload())
        XCTAssertEqual(clients.count, 2)

        let safari = try XCTUnwrap(clients.first)
        XCTAssertEqual(safari.bundleIdentifier, "com.apple.WebKit.GPU")
        XCTAssertEqual(safari.parentBundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(safari.effectiveBundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(safari.processIdentifier, 99999)
        XCTAssertEqual(safari.displayName, "com.apple.Safari")
        XCTAssertEqual(safari.sourceIdentifier, "com.apple.Safari#99999")
        XCTAssertEqual(safari.title, "Browser Track")
        XCTAssertTrue(safari.isPlaying)
        XCTAssertEqual(safari.elapsedTime, 42.5)
        XCTAssertEqual(safari.duration, 240)
        XCTAssertEqual(safari.supportedCommands.count, 2)
        XCTAssertEqual(safari.supportedCommands.first?.name, "Play")
        XCTAssertEqual(safari.supportedCommands.last?.enabled, false)
    }

    func testKeepsClientWithoutTitleOrMetadata() throws {
        let clients = try NowPlayingParser.parseClients(from: makePayload())
        let player = try XCTUnwrap(clients.last)
        XCTAssertEqual(player.bundleIdentifier, "test.beardie.playera")
        XCTAssertNil(player.title)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.sourceIdentifier, "test.beardie.playera#123")
    }

    func testArtworkFingerprintAndCache() throws {
        let artwork = Data("artwork-bytes".utf8)
        let encoded = artwork.base64EncodedString()
        let cache = ArtworkCache(capacity: 2)

        let clients = try NowPlayingParser.parseClients(from: makePayload(artwork: encoded), artworkCache: cache)
        let safari = try XCTUnwrap(clients.first)

        XCTAssertEqual(safari.artworkMimeType, "image/jpeg")
        let fingerprint = try XCTUnwrap(safari.artworkFingerprint)
        XCTAssertTrue(safari.hasArtwork)
        XCTAssertEqual(cache.data(for: fingerprint), artwork)
        XCTAssertEqual(cache.count, 1)
    }

    func testSnapshotCacheTTL() {
        let cache = NowPlayingSnapshotCache(ttl: 1)
        let old = NowPlayingSnapshot(
            clients: [],
            refreshedAt: Date(timeIntervalSinceNow: -2),
            adapterAvailable: true,
            error: nil
        )
        cache.store(old)
        XCTAssertNil(cache.value(now: Date()))

        let fresh = NowPlayingSnapshot(
            clients: [],
            refreshedAt: Date(),
            adapterAvailable: true,
            error: nil
        )
        cache.store(fresh)
        XCTAssertNotNil(cache.value(now: Date()))
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try NowPlayingParser.parseClients(from: Data("not json".utf8)))
    }

    func testSnapshotCodableRoundTrip() throws {
        let clients = try NowPlayingParser.parseClients(from: makePayload())
        let snapshot = NowPlayingSnapshot(
            clients: clients,
            refreshedAt: Date(timeIntervalSince1970: 1_800_000_000),
            adapterAvailable: true,
            error: nil
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(NowPlayingSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testCommandLookupUsesReportedIdentifier() throws {
        let client = NowPlayingClient(
            sourceIdentifier: "test.player#1",
            bundleIdentifier: "test.player",
            parentBundleIdentifier: nil,
            processIdentifier: 1,
            displayName: "Player",
            title: "Song",
            artist: "Artist",
            album: nil,
            isPlaying: true,
            playbackRate: 1,
            duration: 200,
            elapsedTime: 10,
            timestamp: nil,
            supportedCommands: [
                NowPlayingCommand(identifier: 21, name: "LikeTrack", enabled: true),
                NowPlayingCommand(identifier: 4, name: "NextTrack", enabled: false)
            ],
            artworkMimeType: nil,
            artworkFingerprint: nil
        )

        XCTAssertEqual(client.commandIdentifier(named: "liketrack"), 21)
        XCTAssertNil(client.commandIdentifier(named: "NextTrack"))
        XCTAssertEqual(client.supportsCommand(identifier: 21), true)
        XCTAssertEqual(client.supportsCommand(identifier: 4), false)
        XCTAssertEqual(client.supportsCommand(identifier: 99), false)
    }

    func testMissingSupportedCommandsMeansUnknown() {
        let client = NowPlayingClient(
            sourceIdentifier: "test.player#1",
            bundleIdentifier: "test.player",
            parentBundleIdentifier: nil,
            processIdentifier: 1,
            displayName: "Player",
            title: "Song",
            artist: nil,
            album: nil,
            isPlaying: true,
            playbackRate: 1,
            duration: nil,
            elapsedTime: nil,
            timestamp: nil,
            supportedCommands: [],
            artworkMimeType: nil,
            artworkFingerprint: nil
        )

        XCTAssertNil(client.supportsCommand(identifier: 4))
    }

    func testCommandResultCodableRoundTrip() throws {
        let result = NowPlayingCommandResult(
            target: "test.player",
            command: 2,
            elected: true,
            sent: true,
            error: nil
        )
        let data = try JSONEncoder().encode(result)
        XCTAssertEqual(try JSONDecoder().decode(NowPlayingCommandResult.self, from: data), result)

        let capabilities = NowPlayingCapabilities(
            readClients: true,
            targetedCommands: true,
            supportedCommands: true,
            electionOverride: true
        )
        let capabilitiesData = Data(
            #"{"readClients":true,"targetedCommands":true,"supportedCommands":true,"electionOverride":true}"#.utf8
        )
        XCTAssertEqual(
            try JSONDecoder().decode(NowPlayingCapabilities.self, from: capabilitiesData),
            capabilities
        )
    }

    func testPauseOthersResultCodableRoundTrip() throws {
        let result = NowPlayingPauseOthersResult(paused: ["a"], failed: ["b"])
        let data = try JSONEncoder().encode(result)
        XCTAssertEqual(try JSONDecoder().decode(NowPlayingPauseOthersResult.self, from: data), result)
    }
}
