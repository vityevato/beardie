//
//  CommandRouter.swift
//  Beardie
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import CocoaLumberjackSwift
import Foundation

/// The Now Playing operations the router needs. The live implementation talks
/// to the XPC controller; unit tests inject a stub.
protocol NowPlayingRouting {
    var targetedCommandsAvailable: Bool { get }
    func client(matching bundleIdentifier: String) -> NowPlayingClient?
    func sendCommand(
        _ command: Int,
        to bundleIdentifier: String,
        hold: TimeInterval
    ) -> NowPlayingCommandResult?
    func pauseOthers(exceptBundleIdentifier: String?) -> NowPlayingPauseOthersResult?
}

struct LiveNowPlayingRouting: NowPlayingRouting {

    var targetedCommandsAvailable: Bool {
        NowPlayingCoordinator.targetedCommandsAvailable
    }

    func client(matching bundleIdentifier: String) -> NowPlayingClient? {
        if let client = NowPlayingCoordinator.client(matching: bundleIdentifier) {
            return client
        }
        _ = NowPlayingCoordinator.snapshotSync(force: true)
        return NowPlayingCoordinator.client(matching: bundleIdentifier)
    }

    func sendCommand(
        _ command: Int,
        to bundleIdentifier: String,
        hold: TimeInterval = 0.25
    ) -> NowPlayingCommandResult? {
        NowPlayingCoordinator.sendCommand(command, to: bundleIdentifier, hold: hold)
    }

    func pauseOthers(exceptBundleIdentifier: String?) -> NowPlayingPauseOthersResult? {
        NowPlayingCoordinator.pauseOthers(exceptBundleIdentifier: exceptBundleIdentifier)
    }
}

/// Routes media commands for the player that the existing selection
/// (`autoSelectTabWithForceFocused:` / `BSActiveTab`) already chose.
///
/// The router never changes `activeApp.activeTab`. Each method returns `true`
/// only when a new transport delivered the command:
///
/// - bridge tabs: the BrowserBridge `command` message;
/// - native applications: a targeted MediaRemote transaction through XPC;
/// - a `false` result means the caller must run the legacy adapter path.
///
/// Command methods block while they wait for the bridge ack or the XPC
/// transaction. Call them off the main queue; the app's working queue is the
/// intended caller.
@objc(CommandRouter)
final class CommandRouter: NSObject {

    @objc static let shared = CommandRouter()

    /// MediaRemote command numbers. They are the stable core of `MRCommand`;
    /// the router still prefers the command names reported by the client when
    /// they are available (favorite/like changed numbers between releases).
    private enum MediaCommand {
        static let play = 0
        static let pause = 1
        static let nextTrack = 4
        static let previousTrack = 5
        static let skipForward = 17
        static let skipBackward = 18
        static let goBackFifteenSeconds = 12
        static let skipFifteenSeconds = 13
    }

    private enum RoutedCommand {
        case toggle
        case next
        case previous
        case favorite
    }

    private let routing: NowPlayingRouting

    init(routing: NowPlayingRouting = LiveNowPlayingRouting()) {
        self.routing = routing
        super.init()
    }

    // MARK: - Commands

    @objc(performToggleWithSelection:)
    func performToggle(with selection: BSActiveTab) -> Bool {
        guard let tab = selection.activeTab else {
            return false
        }
        let performed = route(tab: tab, command: .toggle)
        if performed {
            notifyToggle(tab: tab, selection: selection)
        }
        return performed
    }

    @objc(performNextWithSelection:)
    func performNext(with selection: BSActiveTab) -> Bool {
        guard let tab = selection.activeTab else {
            return false
        }
        let performed = route(tab: tab, command: .next)
        if performed {
            notifyTrackChange(tab: tab, selection: selection)
        }
        return performed
    }

    @objc(performPreviousWithSelection:)
    func performPrevious(with selection: BSActiveTab) -> Bool {
        guard let tab = selection.activeTab else {
            return false
        }
        let performed = route(tab: tab, command: .previous)
        if performed {
            notifyTrackChange(tab: tab, selection: selection)
        }
        return performed
    }

    @objc(performFavoriteWithSelection:)
    func performFavorite(with selection: BSActiveTab) -> Bool {
        guard let tab = selection.activeTab else {
            return false
        }
        let performed = route(tab: tab, command: .favorite)
        if performed {
            notifyFavorite(tab: tab, selection: selection)
        }
        return performed
    }

    /// Pauses every other playing MediaRemote client through separate XPC
    /// transactions. Returns `true` when the XPC service accepted the request.
    @objc(pauseOthersExceptSelection:)
    func pauseOthers(except selection: BSActiveTab?) -> Bool {
        let excluded = selection?.activeTab.flatMap { mediaRemoteBundleIdentifier(for: $0) }
        return routing.pauseOthers(exceptBundleIdentifier: excluded) != nil
    }

    // MARK: - Routing

    private func route(tab: TabAdapter, command: RoutedCommand) -> Bool {
        if let bridge = tab as? BrowserBridgeTabAdapter {
            if sendBridgeCommand(bridge: bridge, command: command) {
                return true
            }
            // The page may not expose a media element or a Media Session
            // handler. MediaRemote can still deliver the command to the
            // browser's elected media session.
            DDLogInfo(
                "CommandRouter: bridge \(routedCommandName(for: command)) "
                    + "unavailable, trying MediaRemote"
            )
            return sendMediaRemoteCommand(for: command, bridge: bridge)
        }

        if let native = tab as? BSNativeAppTabAdapter {
            return sendMediaRemoteCommand(for: command, native: native)
        }

        return false
    }

    private func sendBridgeCommand(bridge: BrowserBridgeTabAdapter, command: RoutedCommand) -> Bool {
        guard let name = bridgeCommandName(for: command) else {
            return false
        }
        guard BrowserBridgeService.shared.hasActiveInstance(bridge.bridgeInstanceId) else {
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        BrowserBridgeService.shared.sendCommand(
            instanceId: bridge.bridgeInstanceId,
            tabId: bridge.bridgeTabId,
            command: name
        ) { result in
            success = result
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3.5)

        if success {
            DDLogInfo("CommandRouter: bridge \(name) sent to tab \(bridge.bridgeTabId)")
        }
        return success
    }

    private func bridgeCommandName(for command: RoutedCommand) -> String? {
        switch command {
        case .toggle:
            return "toggle"
        case .next:
            return "next"
        case .previous:
            return "previous"
        case .favorite:
            return nil
        }
    }

    private func routedCommandName(for command: RoutedCommand) -> String {
        switch command {
        case .toggle:
            return "toggle"
        case .next:
            return "next"
        case .previous:
            return "previous"
        case .favorite:
            return "favorite"
        }
    }

    private func sendMediaRemoteCommand(for command: RoutedCommand, bridge: BrowserBridgeTabAdapter) -> Bool {
        guard let bundleIdentifier = mediaRemoteBundleIdentifier(for: bridge) else {
            DDLogInfo("CommandRouter: bridge tab has no browser bundle identifier")
            return false
        }
        guard let client = routing.client(matching: bundleIdentifier) else {
            DDLogInfo("CommandRouter: no MediaRemote client for \(bundleIdentifier)")
            return false
        }
        return sendMediaRemoteCommand(
            for: command,
            client: client,
            bundleIdentifier: bundleIdentifier
        )
    }

    private func sendMediaRemoteCommand(for command: RoutedCommand, native: BSNativeAppTabAdapter) -> Bool {
        guard routing.targetedCommandsAvailable else {
            return false
        }
        guard let bundleIdentifier = native.application?.bundleIdentifier else {
            return false
        }
        guard let client = routing.client(matching: bundleIdentifier) else {
            DDLogInfo("CommandRouter: no MediaRemote client for \(bundleIdentifier)")
            return false
        }
        return sendMediaRemoteCommand(
            for: command,
            client: client,
            bundleIdentifier: bundleIdentifier
        )
    }

    private func sendMediaRemoteCommand(
        for command: RoutedCommand,
        client: NowPlayingClient,
        bundleIdentifier: String
    ) -> Bool {
        guard routing.targetedCommandsAvailable else {
            return false
        }
        guard let commandIdentifier = mediaRemoteCommand(for: command, client: client) else {
            DDLogInfo(
                "CommandRouter: no supported MediaRemote command for "
                    + "\(routedCommandName(for: command)) on \(bundleIdentifier); "
                    + "available: \(availableCommands(client))"
            )
            return false
        }
        let commandName = client.supportedCommands
            .first { $0.identifier == commandIdentifier }?
            .name ?? "unnamed"
        DDLogInfo(
            "CommandRouter: \(routedCommandName(for: command)) -> MediaRemote "
                + "\(commandIdentifier) (\(commandName)) on \(bundleIdentifier)"
        )
        return sendMediaRemoteCommand(commandIdentifier, to: bundleIdentifier)
    }

    private func availableCommands(_ client: NowPlayingClient) -> String {
        let commands = client.supportedCommands
            .filter { $0.enabled }
            .map { "\($0.identifier):\($0.name ?? "unnamed")" }
        return commands.isEmpty ? "none" : commands.joined(separator: ", ")
    }

    private func sendMediaRemoteCommand(
        _ commandIdentifier: Int,
        to bundleIdentifier: String
    ) -> Bool {
        guard routing.targetedCommandsAvailable else {
            return false
        }

        guard let result = routing.sendCommand(
            commandIdentifier,
            to: bundleIdentifier,
            hold: 0.25
        ) else {
            DDLogInfo(
                "CommandRouter: MediaRemote command \(commandIdentifier) to "
                    + "\(bundleIdentifier) failed"
            )
            return false
        }

        DDLogInfo(
            "CommandRouter: MediaRemote command \(commandIdentifier) to "
                + "\(bundleIdentifier) sent=\(result.sent) elected=\(result.elected)"
        )
        return result.sent && result.elected
    }

    private func mediaRemoteCommand(for command: RoutedCommand, client: NowPlayingClient) -> Int? {
        switch command {
        case .toggle:
            if let identifier = client.commandIdentifier(named: "TogglePlayPause"),
               client.supportsCommand(identifier: identifier) != false {
                return identifier
            }
            let fallback = client.isPlaying ? MediaCommand.pause : MediaCommand.play
            if client.supportsCommand(identifier: fallback) != false {
                return fallback
            }
            return nil
        case .next:
            if let identifier = reportedCommand(
                client,
                names: ["NextTrack"],
                fallback: MediaCommand.nextTrack
            ) {
                return identifier
            }
            if let identifier = reportedCommand(
                client,
                names: ["SkipForward", "SkipForward15Seconds"],
                fallback: MediaCommand.skipForward
            ) {
                return identifier
            }
            return reportedCommand(
                client,
                names: ["SkipFifteenSeconds"],
                fallback: MediaCommand.skipFifteenSeconds
            )
        case .previous:
            if let identifier = reportedCommand(
                client,
                names: ["PreviousTrack"],
                fallback: MediaCommand.previousTrack
            ) {
                return identifier
            }
            if let identifier = reportedCommand(
                client,
                names: ["SkipBackward", "SkipBackward15Seconds"],
                fallback: MediaCommand.skipBackward
            ) {
                return identifier
            }
            return reportedCommand(
                client,
                names: ["GoBackFifteenSeconds"],
                fallback: MediaCommand.goBackFifteenSeconds
            )
        case .favorite:
            guard let identifier = client.commandIdentifier(named: "LikeTrack") else {
                return nil
            }
            return client.supportsCommand(identifier: identifier) == false ? nil : identifier
        }
    }

    /// Prefers a command identifier reported by name and falls back to the
    /// stable MediaRemote number when the client does not enumerate commands.
    /// `nil` means the client positively reported that the command is disabled.
    private func reportedCommand(
        _ client: NowPlayingClient,
        names: [String],
        fallback: Int
    ) -> Int? {
        for name in names {
            if let identifier = client.commandIdentifier(named: name),
               client.supportsCommand(identifier: identifier) != false {
                return identifier
            }
        }
        return client.supportsCommand(identifier: fallback) == false ? nil : fallback
    }

    private func mediaRemoteBundleIdentifier(for tab: TabAdapter) -> String? {
        if let bridge = tab as? BrowserBridgeTabAdapter {
            return bridge.bridgeBrowserBundleIdentifier
        }
        if let native = tab as? BSNativeAppTabAdapter {
            return native.application?.bundleIdentifier
        }
        return nil
    }

    // MARK: - Notifications

    private func notifyToggle(tab: TabAdapter, selection: BSActiveTab) {
        var shouldNotify = false
        let exception = tryBlock {
            shouldNotify = tab.showNotifications()
                && alwaysShowNotification()
                && !tab.frontmost()
        }
        if exception == nil && shouldNotify {
            _ = tryBlock { selection.showNotification() }
        }
    }

    private func notifyTrackChange(tab: TabAdapter, selection: BSActiveTab) {
        _ = tryBlock {
            if tab.showNotifications() && alwaysShowNotification() && !tab.frontmost() {
                selection.showNotificationDelayed(usingFallback: false)
            }
        }
    }

    private func notifyFavorite(tab: TabAdapter, selection: BSActiveTab) {
        var shouldNotify = false
        let exception = tryBlock {
            shouldNotify = tab.showNotifications()
                && tab.trackInfo()?.favorited != nil
        }
        if exception == nil && shouldNotify {
            _ = tryBlock { selection.showNotificationDelayed(usingFallback: false) }
        }
    }
}
