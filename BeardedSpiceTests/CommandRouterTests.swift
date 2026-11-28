//
//  CommandRouterTests.swift
//  BeardieTests
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import XCTest

@testable import Beardie

final class CommandRouterTests: XCTestCase {

    final class FakeRouting: NowPlayingRouting {
        var targetedCommandsAvailable = true
        var client: NowPlayingClient?
        var commands: [(identifier: Int, bundle: String)] = []
        var pauseRequests: [String?] = []

        func client(matching bundleIdentifier: String) -> NowPlayingClient? {
            client
        }

        func sendCommand(
            _ command: Int,
            to bundleIdentifier: String,
            hold: TimeInterval
        ) -> NowPlayingCommandResult? {
            commands.append((command, bundleIdentifier))
            return NowPlayingCommandResult(
                target: bundleIdentifier,
                command: command,
                elected: true,
                sent: true,
                error: nil
            )
        }

        func pauseOthers(exceptBundleIdentifier: String?) -> NowPlayingPauseOthersResult? {
            pauseRequests.append(exceptBundleIdentifier)
            return NowPlayingPauseOthersResult(paused: [], failed: [])
        }
    }

    final class FakeNativeAdapter: BSNativeAppTabAdapter {
        let fakeApplication: runningSBApplication

        override init() {
            fakeApplication = runningSBApplication(application: nil, bundleIdentifier: "test.player")
            super.init()
        }

        override var application: runningSBApplication! {
            fakeApplication
        }

        override func showNotifications() -> Bool {
            false
        }

        override func frontmost() -> Bool {
            false
        }
    }

    private func makeClient(
        isPlaying: Bool = false,
        supportedCommands: [NowPlayingCommand] = [
            NowPlayingCommand(identifier: 2, name: "TogglePlayPause", enabled: true),
            NowPlayingCommand(identifier: 4, name: "NextTrack", enabled: true),
            NowPlayingCommand(identifier: 5, name: "PreviousTrack", enabled: true),
            NowPlayingCommand(identifier: 21, name: "LikeTrack", enabled: true)
        ]
    ) -> NowPlayingClient {
        NowPlayingClient(
            sourceIdentifier: "test.player#1",
            bundleIdentifier: "test.player",
            parentBundleIdentifier: nil,
            processIdentifier: 1,
            displayName: "Player",
            title: "Song",
            artist: "Artist",
            album: nil,
            isPlaying: isPlaying,
            playbackRate: isPlaying ? 1 : 0,
            duration: 200,
            elapsedTime: 10,
            timestamp: nil,
            supportedCommands: supportedCommands,
            artworkMimeType: nil,
            artworkFingerprint: nil
        )
    }

    private func makeSelection(adapter: TabAdapter = FakeNativeAdapter()) -> BSActiveTab {
        let selection = BSActiveTab()
        selection.activeTab = adapter
        return selection
    }

    func testRoutesNativeNextThroughMediaRemote() {
        let routing = FakeRouting()
        routing.client = makeClient()
        let router = CommandRouter(routing: routing)
        let selection = makeSelection()

        XCTAssertTrue(router.performNext(with: selection))
        XCTAssertEqual(routing.commands.count, 1)
        XCTAssertEqual(routing.commands.first?.identifier, 4)
        XCTAssertEqual(routing.commands.first?.bundle, "test.player")
    }

    func testNextFallsBackToFifteenSecondSkipWhenNextTrackIsUnsupported() {
        let routing = FakeRouting()
        routing.client = makeClient(supportedCommands: [
            NowPlayingCommand(identifier: 13, name: "SkipFifteenSeconds", enabled: true)
        ])
        let router = CommandRouter(routing: routing)
        let selection = makeSelection()

        XCTAssertTrue(router.performNext(with: selection))
        XCTAssertEqual(routing.commands.first?.identifier, 13)
    }

    func testPreviousFallsBackToFifteenSecondRewindWhenPreviousTrackIsUnsupported() {
        let routing = FakeRouting()
        routing.client = makeClient(supportedCommands: [
            NowPlayingCommand(identifier: 12, name: "GoBackFifteenSeconds", enabled: true)
        ])
        let router = CommandRouter(routing: routing)
        let selection = makeSelection()

        XCTAssertTrue(router.performPrevious(with: selection))
        XCTAssertEqual(routing.commands.first?.identifier, 12)
    }

    func testNextPrefersNextTrackOverFifteenSecondSkip() {
        let routing = FakeRouting()
        routing.client = makeClient(supportedCommands: [
            NowPlayingCommand(identifier: 4, name: "NextTrack", enabled: true),
            NowPlayingCommand(identifier: 13, name: "SkipFifteenSeconds", enabled: true)
        ])
        let router = CommandRouter(routing: routing)
        let selection = makeSelection()

        XCTAssertTrue(router.performNext(with: selection))
        XCTAssertEqual(routing.commands.first?.identifier, 4)
    }

    func testNextUsesReportedSkipForwardIdentifier() {
        let routing = FakeRouting()
        routing.client = makeClient(supportedCommands: [
            NowPlayingCommand(identifier: 113, name: "SkipForward", enabled: true)
        ])
        let router = CommandRouter(routing: routing)
        let selection = makeSelection()

        XCTAssertTrue(router.performNext(with: selection))
        XCTAssertEqual(routing.commands.first?.identifier, 113)
    }

    func testPreviousUsesReportedSkipBackwardIdentifier() {
        let routing = FakeRouting()
        routing.client = makeClient(supportedCommands: [
            NowPlayingCommand(identifier: 112, name: "SkipBackward", enabled: true)
        ])
        let router = CommandRouter(routing: routing)
        let selection = makeSelection()

        XCTAssertTrue(router.performPrevious(with: selection))
        XCTAssertEqual(routing.commands.first?.identifier, 112)
    }

    func testDisabledSkipCommandsFallBackToLegacyPath() {
        let routing = FakeRouting()
        routing.client = makeClient(supportedCommands: [
            NowPlayingCommand(identifier: 4, name: "NextTrack", enabled: false),
            NowPlayingCommand(identifier: 13, name: "SkipFifteenSeconds", enabled: false)
        ])
        let router = CommandRouter(routing: routing)
        let selection = makeSelection()

        XCTAssertFalse(router.performNext(with: selection))
        XCTAssertTrue(routing.commands.isEmpty)
    }

    func testTogglePrefersReportedCommandName() {
        let routing = FakeRouting()
        routing.client = makeClient(supportedCommands: [
            NowPlayingCommand(identifier: 42, name: "TogglePlayPause", enabled: true)
        ])
        let router = CommandRouter(routing: routing)
        let selection = makeSelection()

        XCTAssertTrue(router.performToggle(with: selection))
        XCTAssertEqual(routing.commands.first?.identifier, 42)
    }

    func testToggleFallsBackToPlayWhenToggleIsUnsupported() {
        let routing = FakeRouting()
        routing.client = makeClient(isPlaying: false, supportedCommands: [
            NowPlayingCommand(identifier: 0, name: "Play", enabled: true)
        ])
        let router = CommandRouter(routing: routing)
        let selection = makeSelection()

        XCTAssertTrue(router.performToggle(with: selection))
        XCTAssertEqual(routing.commands.first?.identifier, 0)
    }

    func testFavoriteUsesReportedLikeIdentifier() {
        let routing = FakeRouting()
        routing.client = makeClient()
        let router = CommandRouter(routing: routing)
        let selection = makeSelection()

        XCTAssertTrue(router.performFavorite(with: selection))
        XCTAssertEqual(routing.commands.first?.identifier, 21)
    }

    func testUnsupportedCommandFallsBackToLegacyPath() {
        let routing = FakeRouting()
        routing.client = makeClient(supportedCommands: [
            NowPlayingCommand(identifier: 4, name: "NextTrack", enabled: false)
        ])
        let router = CommandRouter(routing: routing)
        let selection = makeSelection()

        XCTAssertFalse(router.performNext(with: selection))
        XCTAssertTrue(routing.commands.isEmpty)
    }

    func testUnavailableTargetedCommandsFallBackToLegacyPath() {
        let routing = FakeRouting()
        routing.targetedCommandsAvailable = false
        routing.client = makeClient()
        let router = CommandRouter(routing: routing)
        let selection = makeSelection()

        XCTAssertFalse(router.performNext(with: selection))
        XCTAssertTrue(routing.commands.isEmpty)
    }

    func testPlainAdapterIsNotRouted() {
        let routing = FakeRouting()
        routing.client = makeClient()
        let router = CommandRouter(routing: routing)
        let selection = makeSelection(adapter: TabAdapter())

        XCTAssertFalse(router.performToggle(with: selection))
        XCTAssertTrue(routing.commands.isEmpty)
    }

    func testPauseOthersExcludesSelectedBundle() {
        let routing = FakeRouting()
        let router = CommandRouter(routing: routing)
        let selection = makeSelection()

        XCTAssertTrue(router.pauseOthers(except: selection))
        XCTAssertEqual(routing.pauseRequests, ["test.player"])
    }
}
