//
//  BrowserBridgeTests.swift
//  BeardieTests
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import XCTest

@testable import Beardie

final class BrowserBridgeTests: XCTestCase {

    func testParsesHello() throws {
        let data = Data(
            """
            {"type":"hello","protocolVersion":1,"instanceId":"inst","browser":"org.chromium.Chromium","bundleId":"org.chromium.Chromium","processIdentifier":123}
            """.utf8
        )
        guard case .hello(let hello) = BrowserBridgeIncomingMessage.parse(data) else {
            return XCTFail("Expected hello")
        }
        XCTAssertEqual(hello.protocolVersion, 1)
        XCTAssertEqual(hello.instanceId, "inst")
        XCTAssertEqual(hello.browser, "org.chromium.Chromium")
        XCTAssertEqual(hello.processIdentifier, 123)
    }

    func testParsesStateWithMediaFields() throws {
        let data = Data(
            """
            {
              "type":"state",
              "instanceId":"inst",
              "tabs":[{
                "tabId":1,
                "windowId":2,
                "active":true,
                "title":"Tab",
                "url":"https://example.com/page",
                "mediaTitle":"Track",
                "artist":"Artist",
                "album":"Album",
                "playbackState":"playing",
                "position":10.5,
                "duration":200,
                "artworkURLs":["https://example.com/a.jpg"],
                "updatedAt":1800000000000
              }]
            }
            """.utf8
        )
        guard case .state(let state) = BrowserBridgeIncomingMessage.parse(data) else {
            return XCTFail("Expected state")
        }
        XCTAssertEqual(state.instanceId, "inst")
        XCTAssertEqual(state.tabs.count, 1)
        let tab = try XCTUnwrap(state.tabs.first)
        XCTAssertEqual(tab.tabId, 1)
        XCTAssertEqual(tab.windowId, 2)
        XCTAssertTrue(tab.active)
        XCTAssertEqual(tab.mediaTitle, "Track")
        XCTAssertEqual(tab.artist, "Artist")
        XCTAssertEqual(tab.playbackState, "playing")
        XCTAssertEqual(tab.position, 10.5)
        XCTAssertEqual(tab.artworkURLs, ["https://example.com/a.jpg"])
    }

    func testParsesAck() {
        let data = Data(#"{"type":"ack","requestId":"req","success":false,"error":"no-tab"}"#.utf8)
        guard case .ack(let ack) = BrowserBridgeIncomingMessage.parse(data) else {
            return XCTFail("Expected ack")
        }
        XCTAssertEqual(ack.requestId, "req")
        XCTAssertFalse(ack.success)
        XCTAssertEqual(ack.error, "no-tab")
    }

    func testUnknownMessagesAreIgnored() {
        if case .unknown = BrowserBridgeIncomingMessage.parse(Data("not json".utf8)) {
            // Expected.
        } else {
            XCTFail("Expected unknown for invalid JSON")
        }

        if case .unknown = BrowserBridgeIncomingMessage.parse(Data(#"{"type":"other"}"#.utf8)) {
            // Expected.
        } else {
            XCTFail("Expected unknown for an unsupported type")
        }
    }

    func testGetStateMessageEncoding() throws {
        let data = try XCTUnwrap(BrowserBridgeOutgoingMessage.getState(requestId: "req"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "getState")
        XCTAssertEqual(object["requestId"] as? String, "req")
    }

    func testActivateAndRestoreMessageEncoding() throws {
        let activate = try XCTUnwrap(
            BrowserBridgeOutgoingMessage.activateTab(requestId: "req", tabId: 5, windowId: 2)
        )
        let activateObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: activate) as? [String: Any]
        )
        XCTAssertEqual(activateObject["type"] as? String, "activateTab")
        XCTAssertEqual(activateObject["requestId"] as? String, "req")
        XCTAssertEqual(activateObject["tabId"] as? Int, 5)
        XCTAssertEqual(activateObject["windowId"] as? Int, 2)

        let restore = try XCTUnwrap(
            BrowserBridgeOutgoingMessage.restoreTab(requestId: "req2", tabId: 5, windowId: 2)
        )
        let restoreObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: restore) as? [String: Any]
        )
        XCTAssertEqual(restoreObject["type"] as? String, "restoreTab")
        XCTAssertEqual(restoreObject["requestId"] as? String, "req2")
    }

    func testCommandMessageEncoding() throws {
        let data = try XCTUnwrap(
            BrowserBridgeOutgoingMessage.command(requestId: "req", tabId: 5, command: "next")
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "command")
        XCTAssertEqual(object["requestId"] as? String, "req")
        XCTAssertEqual(object["tabId"] as? Int, 5)
        XCTAssertEqual(object["command"] as? String, "next")

        let seek = try XCTUnwrap(
            BrowserBridgeOutgoingMessage.command(requestId: "req2", tabId: 5, command: "seek", position: 42)
        )
        let seekObject = try XCTUnwrap(JSONSerialization.jsonObject(with: seek) as? [String: Any])
        XCTAssertEqual(seekObject["position"] as? Double, 42)
    }
}

final class BrowserTargetResolverTests: XCTestCase {

    func testResolvesExactBrowserTrack() {
        let now = Date()
        let target = BrowserTargetResolver.resolve(
            client: makeClient(
                title: "Song",
                artist: "Artist",
                bundleIdentifier: "com.google.Chrome.helper",
                parentBundleIdentifier: "com.google.Chrome",
                duration: 200,
                elapsedTime: 30
            ),
            instances: [
                makeInstance(
                    bundleIdentifier: "com.google.Chrome",
                    tabs: [
                        makeTab(
                            tabId: 7,
                            mediaTitle: "Song",
                            artist: "Artist",
                            playbackState: "playing",
                            position: 30,
                            duration: 200,
                            updatedAt: now
                        )
                    ],
                    updatedAt: now
                )
            ],
            now: now
        )

        XCTAssertEqual(target?.tabId, 7)
        XCTAssertEqual(target?.instanceId, "instance")
        XCTAssertEqual(target?.browserBundleIdentifier, "com.google.Chrome")
    }

    func testResolvesPausedPlayer() {
        let now = Date()
        let target = BrowserTargetResolver.resolve(
            client: makeClient(
                title: "Song",
                artist: "Artist",
                bundleIdentifier: "com.google.Chrome",
                isPlaying: false
            ),
            instances: [
                makeInstance(
                    bundleIdentifier: "com.google.Chrome",
                    tabs: [
                        makeTab(
                            mediaTitle: "Song",
                            artist: "Artist",
                            playbackState: "paused",
                            updatedAt: now
                        )
                    ],
                    updatedAt: now
                )
            ],
            now: now
        )

        XCTAssertEqual(target?.tabId, 7)
    }

    func testRejectsDifferentBrowserBundle() {
        let now = Date()
        let target = BrowserTargetResolver.resolve(
            client: makeClient(
                title: "Song",
                artist: "Artist",
                bundleIdentifier: "com.apple.Safari"
            ),
            instances: [
                makeInstance(
                    bundleIdentifier: "com.google.Chrome",
                    tabs: [
                        makeTab(mediaTitle: "Song", artist: "Artist", playbackState: "playing", updatedAt: now)
                    ],
                    updatedAt: now
                )
            ],
            now: now
        )

        XCTAssertNil(target)
    }

    func testMatchesChromeHelperBundle() {
        let now = Date()
        let target = BrowserTargetResolver.resolve(
            client: makeClient(
                title: "Song",
                artist: "Artist",
                bundleIdentifier: "com.google.Chrome.helper"
            ),
            instances: [
                makeInstance(
                    bundleIdentifier: "com.google.Chrome",
                    tabs: [makeTab(mediaTitle: "Song", artist: "Artist", playbackState: "playing", updatedAt: now)],
                    updatedAt: now
                )
            ],
            now: now
        )

        XCTAssertNotNil(target)
    }

    func testRejectsAmbiguousTabs() {
        let now = Date()
        let tabs = [
            makeTab(tabId: 1, mediaTitle: "Song", artist: "Artist", playbackState: "playing", updatedAt: now),
            makeTab(tabId: 2, mediaTitle: "Song", artist: "Artist", playbackState: "playing", updatedAt: now)
        ]
        let target = BrowserTargetResolver.resolve(
            client: makeClient(title: "Song", artist: "Artist", bundleIdentifier: "com.google.Chrome"),
            instances: [makeInstance(bundleIdentifier: "com.google.Chrome", tabs: tabs, updatedAt: now)],
            now: now
        )

        XCTAssertNil(target)
    }

    func testPrefersPlayingTab() {
        let now = Date()
        let tabs = [
            makeTab(tabId: 1, active: true, mediaTitle: "Song", artist: "Artist", playbackState: "paused", updatedAt: now),
            makeTab(tabId: 2, mediaTitle: "Song", artist: "Artist", playbackState: "playing", updatedAt: now)
        ]
        let target = BrowserTargetResolver.resolve(
            client: makeClient(title: "Song", artist: "Artist", bundleIdentifier: "com.google.Chrome"),
            instances: [makeInstance(bundleIdentifier: "com.google.Chrome", tabs: tabs, updatedAt: now)],
            now: now
        )

        XCTAssertEqual(target?.tabId, 2)
    }

    func testRejectsStaleInstance() {
        let now = Date()
        let stale = now.addingTimeInterval(-60)
        let target = BrowserTargetResolver.resolve(
            client: makeClient(title: "Song", artist: "Artist", bundleIdentifier: "com.google.Chrome"),
            instances: [
                makeInstance(
                    bundleIdentifier: "com.google.Chrome",
                    tabs: [makeTab(mediaTitle: "Song", artist: "Artist", playbackState: "playing", updatedAt: stale)],
                    updatedAt: stale
                )
            ],
            now: now
        )

        XCTAssertNil(target)
    }

    func testRejectsConflictingArtist() {
        let now = Date()
        let target = BrowserTargetResolver.resolve(
            client: makeClient(
                title: "Song",
                artist: "Artist",
                bundleIdentifier: "com.google.Chrome",
                duration: 200,
                elapsedTime: 30
            ),
            instances: [
                makeInstance(
                    bundleIdentifier: "com.google.Chrome",
                    tabs: [
                        makeTab(
                            mediaTitle: "Song",
                            artist: "Different Artist",
                            playbackState: "playing",
                            position: 30,
                            duration: 200,
                            updatedAt: now
                        )
                    ],
                    updatedAt: now
                )
            ],
            now: now
        )

        XCTAssertNil(target)
    }

    func testPicksTheInstanceWithMatchingTrack() {
        let now = Date()
        let instances = [
            makeInstance(
                instanceId: "first",
                bundleIdentifier: "com.google.Chrome",
                tabs: [makeTab(mediaTitle: "Other Song", artist: "Other Artist", playbackState: "playing", updatedAt: now)],
                updatedAt: now
            ),
            makeInstance(
                instanceId: "second",
                bundleIdentifier: "com.google.Chrome",
                tabs: [makeTab(mediaTitle: "Song", artist: "Artist", playbackState: "playing", updatedAt: now)],
                updatedAt: now
            )
        ]
        let target = BrowserTargetResolver.resolve(
            client: makeClient(title: "Song", artist: "Artist", bundleIdentifier: "com.google.Chrome"),
            instances: instances,
            now: now
        )

        XCTAssertEqual(target?.instanceId, "second")
    }

    func testRejectsStaleTab() {
        let now = Date()
        let stale = now.addingTimeInterval(-60)
        let target = BrowserTargetResolver.resolve(
            client: makeClient(title: "Song", artist: "Artist", bundleIdentifier: "com.google.Chrome"),
            instances: [
                makeInstance(
                    bundleIdentifier: "com.google.Chrome",
                    tabs: [makeTab(mediaTitle: "Song", artist: "Artist", playbackState: "playing", updatedAt: stale)],
                    updatedAt: now
                )
            ],
            now: now
        )

        XCTAssertNil(target)
    }

    func testRejectsUnrelatedTitle() {
        let now = Date()
        let target = BrowserTargetResolver.resolve(
            client: makeClient(title: "Song", artist: "Artist", bundleIdentifier: "com.google.Chrome"),
            instances: [
                makeInstance(
                    bundleIdentifier: "com.google.Chrome",
                    tabs: [makeTab(mediaTitle: "Completely Different", artist: "Artist", playbackState: "playing", updatedAt: now)],
                    updatedAt: now
                )
            ],
            now: now
        )

        XCTAssertNil(target)
    }

    func testBridgeTabAdapterExposesMediaState() {
        let now = Date()
        let adapter = BrowserBridgeTabAdapter(
            instance: makeInstance(
                instanceId: "instance",
                bundleIdentifier: "com.google.Chrome",
                tabs: [],
                updatedAt: now
            ),
            tab: makeTab(
                tabId: 42,
                mediaTitle: "Song",
                artist: "Artist",
                playbackState: "paused",
                updatedAt: now
            )
        )

        XCTAssertEqual(adapter.title(), "Song")
        XCTAssertEqual(adapter.key(), "instance#42")
        XCTAssertFalse(adapter.isPlaying())
        XCTAssertEqual(adapter.browserDisplayName, "com.google.Chrome")
    }

    // MARK: - Fixtures

    private func makeClient(
        title: String?,
        artist: String?,
        album: String? = nil,
        bundleIdentifier: String?,
        parentBundleIdentifier: String? = nil,
        isPlaying: Bool = true,
        duration: Double? = nil,
        elapsedTime: Double? = nil
    ) -> NowPlayingClient {
        NowPlayingClient(
            sourceIdentifier: "\(bundleIdentifier ?? "unknown")-\(title ?? "untitled")",
            bundleIdentifier: bundleIdentifier,
            parentBundleIdentifier: parentBundleIdentifier,
            processIdentifier: 100,
            displayName: "Browser",
            title: title,
            artist: artist,
            album: album,
            isPlaying: isPlaying,
            playbackRate: isPlaying ? 1 : 0,
            duration: duration,
            elapsedTime: elapsedTime,
            timestamp: nil,
            supportedCommands: [],
            artworkMimeType: nil,
            artworkFingerprint: nil
        )
    }

    private func makeInstance(
        instanceId: String = "instance",
        bundleIdentifier: String,
        tabs: [BrowserBridgeTab],
        updatedAt: Date
    ) -> BrowserBridgeInstance {
        BrowserBridgeInstance(
            instanceId: instanceId,
            browser: bundleIdentifier,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: 200,
            protocolVersion: BrowserBridgeProtocol.version,
            tabs: tabs,
            lastUpdatedAt: updatedAt
        )
    }

    private func makeTab(
        tabId: Int = 7,
        windowId: Int = 1,
        active: Bool = false,
        mediaTitle: String?,
        artist: String?,
        album: String? = nil,
        playbackState: String?,
        position: Double? = nil,
        duration: Double? = nil,
        updatedAt: Date
    ) -> BrowserBridgeTab {
        BrowserBridgeTab(
            tabId: tabId,
            windowId: windowId,
            active: active,
            title: mediaTitle,
            url: "https://example.com",
            mediaTitle: mediaTitle,
            artist: artist,
            album: album,
            playbackState: playbackState,
            position: position,
            duration: duration,
            artworkURLs: [],
            updatedAt: updatedAt
        )
    }
}
