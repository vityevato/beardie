//
//  BrowserBridgeService.swift
//  Beardie
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import CocoaLumberjackSwift
import Foundation
import Security

/// Loopback WebSocket bridge for the new Chrome/Safari Now Playing extensions.
///
/// The legacy web-strategy bridge is unchanged. This service is additive and
/// only runs when `UseBrowserBridge` is enabled. Browser extensions discover
/// the loopback port and per-launch token through native messaging.
@objc(BrowserBridgeService)
final class BrowserBridgeService: NSObject {

    private struct Connection {
        let socket: PSWebSocket
        var instanceId: String?
    }

    private struct PendingRequest {
        let instanceId: String
        let completion: (Bool) -> Void
        let timeout: DispatchWorkItem
    }

    private let queue = DispatchQueue(label: "com.calm-apps.mac.beardie.browser-bridge")
    private let requestTimeout: TimeInterval = 3
    private var server: PSWebSocketServer?
    private var port: UInt16 = 0
    private var token = ""
    private var connections: [ObjectIdentifier: Connection] = [:]
    private var instances: [String: BrowserBridgeInstance] = [:]
    private var pendingRequests: [String: PendingRequest] = [:]
    private var stateWaiters: [String: [() -> Void]] = [:]
    private var started = false

    static let shared = BrowserBridgeService()

    @objc(startIfEnabled)
    static func startIfEnabled() {
        guard UserDefaults.standard.bool(forKey: "UseBrowserBridge") else {
            DDLogDebug("UseBrowserBridge is disabled")
            return
        }
        if !ChromeNativeMessaging.updateManifest() {
            DDLogError("BrowserBridgeService: failed to install the native messaging manifest")
        }
        shared.start()
    }

    override private init() {
        super.init()
    }

    @objc(stopIfRunning)
    static func stopIfRunning() {
        shared.clearPublishedEndpoint()
        shared.stop()
    }

    func start() {
        queue.async {
            guard !self.started else {
                return
            }

            guard let freePort = self.findFreePort(), freePort > 0 else {
                DDLogError("BrowserBridgeService: no free loopback port")
                return
            }

            let token = self.randomToken()
            guard let defaults = BSSharedResources.sharedDefaults else {
                DDLogError("BrowserBridgeService: shared defaults are unavailable")
                return
            }
            defaults.set(Int(freePort), forKey: BrowserBridgeProtocol.portDefaultsKey)
            defaults.set(token, forKey: BrowserBridgeProtocol.tokenDefaultsKey)
            defaults.set(BrowserBridgeProtocol.version, forKey: BrowserBridgeProtocol.protocolVersionDefaultsKey)
            defaults.synchronize()

            self.port = freePort
            self.token = token

            guard let server = PSWebSocketServer(host: BrowserBridgeProtocol.host, port: UInt(freePort)) else {
                DDLogError("BrowserBridgeService: failed to create WebSocket server")
                self.clearPublishedEndpoint()
                return
            }

            server.delegateQueue = self.queue
            server.delegate = self
            self.server = server
            server.start()
        }
    }

    func stop() {
        queue.async {
            self.failAllPendingRequests(reason: "service stopped")
            self.server?.stop()
            self.server = nil
            self.started = false
            self.connections.removeAll()
            self.instances.removeAll()
            self.clearPublishedEndpoint()
        }
    }

    var activeInstances: [BrowserBridgeInstance] {
        queue.sync {
            instances.values.sorted { $0.instanceId < $1.instanceId }
        }
    }

    func hasActiveInstance(_ instanceId: String) -> Bool {
        queue.sync {
            instances[instanceId] != nil
        }
    }

    /// True when the current bridge state still reports media for this tab.
    /// Used before player selection to refresh a stale empty snapshot.
    func hasMedia(instanceId: String, tabId: Int) -> Bool {
        queue.sync {
            instances[instanceId]?
                .tabs
                .first { $0.tabId == tabId }?
                .mediaTitle != nil
        }
    }

    /// Asks every active instance for a fresh tab snapshot and waits briefly
    /// for the state messages. State is otherwise event-driven; this is used
    /// when the user opens the status menu and needs a current list.
    @objc static func refreshState() {
        shared.refreshState(timeout: 0.3)
    }

    private func refreshState(timeout: TimeInterval) {
        let active = activeInstances
        guard !active.isEmpty else {
            return
        }

        let semaphores = active.map { _ in DispatchSemaphore(value: 0) }

        queue.async {
            for (index, instance) in active.enumerated() {
                guard
                    self.instances[instance.instanceId] != nil,
                    let socket = self.socket(for: instance.instanceId),
                    let request = BrowserBridgeOutgoingMessage.getState(requestId: UUID().uuidString)
                else {
                    semaphores[index].signal()
                    continue
                }

                self.stateWaiters[instance.instanceId, default: []].append {
                    semaphores[index].signal()
                }
                self.send(request, to: socket)

                self.queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    guard let self else {
                        semaphores[index].signal()
                        return
                    }
                    if let waiters = self.stateWaiters.removeValue(forKey: instance.instanceId) {
                        for waiter in waiters {
                            waiter()
                        }
                    } else {
                        semaphores[index].signal()
                    }
                }
            }
        }

        let deadline = DispatchTime.now() + timeout + 0.1
        for semaphore in semaphores {
            _ = semaphore.wait(timeout: deadline)
        }
    }

    /// Asks an extension instance to activate a tab and focus its window.
    func activateTab(
        instanceId: String,
        tabId: Int,
        windowId: Int,
        completion: @escaping (Bool) -> Void
    ) {
        sendTabCommand(
            instanceId: instanceId,
            builder: { requestId in
                BrowserBridgeOutgoingMessage.activateTab(
                    requestId: requestId,
                    tabId: tabId,
                    windowId: windowId
                )
            },
            completion: completion
        )
    }

    /// Asks an extension instance to return to the tab that was active before
    /// the last `activateTab`.
    func restoreTab(
        instanceId: String,
        tabId: Int,
        windowId: Int,
        completion: @escaping (Bool) -> Void
    ) {
        sendTabCommand(
            instanceId: instanceId,
            builder: { requestId in
                BrowserBridgeOutgoingMessage.restoreTab(
                    requestId: requestId,
                    tabId: tabId,
                    windowId: windowId
                )
            },
            completion: completion
        )
    }

    /// Sends a media command to the content script of one tab. Supported
    /// commands are `play`, `pause`, `toggle`, `next`, `previous` and `seek`.
    func sendCommand(
        instanceId: String,
        tabId: Int,
        command: String,
        position: Double? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        sendTabCommand(
            instanceId: instanceId,
            builder: { requestId in
                BrowserBridgeOutgoingMessage.command(
                    requestId: requestId,
                    tabId: tabId,
                    command: command,
                    position: position
                )
            },
            completion: completion
        )
    }

    // MARK: - Private

    private func clearPublishedEndpoint() {
        let defaults = BSSharedResources.sharedDefaults
        defaults?.removeObject(forKey: BrowserBridgeProtocol.portDefaultsKey)
        defaults?.removeObject(forKey: BrowserBridgeProtocol.tokenDefaultsKey)
        defaults?.removeObject(forKey: BrowserBridgeProtocol.protocolVersionDefaultsKey)
        defaults?.synchronize()
    }

    private func findFreePort() -> UInt16? {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return nil
        }
        defer { close(fd) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            return nil
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard nameResult == 0 else {
            return nil
        }

        return UInt16(bigEndian: address.sin_port)
    }

    private func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func acceptRequest(_ request: URLRequest) -> Bool {
        guard
            let url = request.url,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.path == BrowserBridgeProtocol.path,
            let requestToken = components.queryItems?.first(where: { $0.name == "token" })?.value,
            requestToken == token
        else {
            DDLogError("BrowserBridgeService: rejected a WebSocket request with an invalid token or path")
            return false
        }
        return true
    }

    private func send(_ data: Data, to socket: PSWebSocket) {
        guard let string = String(data: data, encoding: .utf8) else {
            return
        }
        socket.send(string)
    }

    private func instanceId(for socket: PSWebSocket) -> String? {
        connections[ObjectIdentifier(socket)]?.instanceId
    }

    private func socket(for instanceId: String) -> PSWebSocket? {
        connections.first(where: { $0.value.instanceId == instanceId })?.value.socket
    }

    private func sendTabCommand(
        instanceId: String,
        builder: (String) -> Data?,
        completion: @escaping (Bool) -> Void
    ) {
        let requestId = UUID().uuidString
        guard let data = builder(requestId) else {
            DDLogError("BrowserBridgeService: failed to encode a tab command")
            DispatchQueue.main.async { completion(false) }
            return
        }

        queue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            guard self.instances[instanceId] != nil, let socket = self.socket(for: instanceId) else {
                DDLogError("BrowserBridgeService: instance \(instanceId) is not connected")
                DispatchQueue.main.async { completion(false) }
                return
            }

            let timeout = DispatchWorkItem { [weak self] in
                self?.failPendingRequest(requestId, reason: "timeout")
            }
            self.pendingRequests[requestId] = PendingRequest(
                instanceId: instanceId,
                completion: completion,
                timeout: timeout
            )
            self.queue.asyncAfter(deadline: .now() + self.requestTimeout, execute: timeout)
            self.send(data, to: socket)
        }
    }

    private func handleAck(_ ack: BrowserBridgeAck, socket: PSWebSocket) {
        guard let pending = pendingRequests.removeValue(forKey: ack.requestId) else {
            DDLogError("BrowserBridgeService: ack for unknown request \(ack.requestId)")
            return
        }
        pending.timeout.cancel()

        let matched = pending.instanceId == instanceId(for: socket)
        if !matched {
            DDLogError(
                "BrowserBridgeService: ack \(ack.requestId) came from a different instance"
            )
        }
        if !ack.success {
            DDLogError(
                "BrowserBridgeService: request \(ack.requestId) failed: \(ack.error ?? "unknown")"
            )
        }
        DispatchQueue.main.async {
            pending.completion(ack.success && matched)
        }
    }

    private func failPendingRequest(_ requestId: String, reason: String) {
        guard let pending = pendingRequests.removeValue(forKey: requestId) else {
            return
        }
        pending.timeout.cancel()
        DDLogError(
            "BrowserBridgeService: request \(requestId) for \(pending.instanceId) failed: \(reason)"
        )
        DispatchQueue.main.async {
            pending.completion(false)
        }
    }

    private func failPendingRequests(for instanceId: String, reason: String) {
        let requestIds = pendingRequests
            .filter { $0.value.instanceId == instanceId }
            .map(\.key)
        for requestId in requestIds {
            failPendingRequest(requestId, reason: reason)
        }
    }

    private func failAllPendingRequests(reason: String) {
        for requestId in Array(pendingRequests.keys) {
            failPendingRequest(requestId, reason: reason)
        }
    }

    private func handleHello(_ hello: BrowserBridgeHello, socket: PSWebSocket) {
        guard hello.protocolVersion == BrowserBridgeProtocol.version else {
            DDLogError(
                "BrowserBridgeService: unsupported protocol \(hello.protocolVersion) from \(hello.instanceId)"
            )
            socket.close()
            return
        }

        // Deduplicate by instance id and keep the newest connection.
        if let old = connections.first(where: { $0.value.instanceId == hello.instanceId }) {
            connections.removeValue(forKey: old.key)
            old.value.socket.close()
        }

        var connection = connections[ObjectIdentifier(socket)]
        connection?.instanceId = hello.instanceId
        connections[ObjectIdentifier(socket)] = connection

        let instance = BrowserBridgeInstance(
            instanceId: hello.instanceId,
            browser: hello.browser,
            bundleIdentifier: hello.bundleId,
            processIdentifier: hello.processIdentifier,
            protocolVersion: hello.protocolVersion,
            tabs: [],
            lastUpdatedAt: Date()
        )
        instances[hello.instanceId] = instance

        DDLogInfo(
            "BrowserBridgeService: hello \(hello.browser) instance=\(hello.instanceId) pid=\(hello.processIdentifier ?? 0)"
        )

        if let ack = BrowserBridgeOutgoingMessage.helloAck(instanceId: hello.instanceId) {
            send(ack, to: socket)
        }
        if let request = BrowserBridgeOutgoingMessage.getState(requestId: UUID().uuidString) {
            send(request, to: socket)
        }
    }

    private func handleState(_ state: BrowserBridgeStateMessage) {
        guard var instance = instances[state.instanceId] else {
            DDLogError("BrowserBridgeService: state for unknown instance \(state.instanceId)")
            return
        }
        instance.tabs = state.tabs
        instance.lastUpdatedAt = Date()
        instances[state.instanceId] = instance

        if let waiters = stateWaiters.removeValue(forKey: state.instanceId) {
            for waiter in waiters {
                waiter()
            }
        }

        let media = state.tabs
            .filter { $0.mediaTitle != nil }
            .map { "\($0.mediaTitle ?? "untitled") by \($0.artist ?? "unknown")" }
            .joined(separator: " | ")
        DDLogDebug(
            "BrowserBridgeService: state \(state.instanceId) tabs=\(state.tabs.count) media=\(state.tabs.filter { $0.mediaTitle != nil }.count) [\(media)]"
        )
    }
}

extension BrowserBridgeService: PSWebSocketServerDelegate {

    func serverDidStart(_ server: PSWebSocketServer) {
        started = true
        DDLogInfo("BrowserBridgeService: listening on \(BrowserBridgeProtocol.host):\(port)")
    }

    func server(_ server: PSWebSocketServer, didFailWithError error: Error) {
        DDLogError("BrowserBridgeService: server failed: \(error.localizedDescription)")
        started = false
        clearPublishedEndpoint()
    }

    func serverDidStop(_ server: PSWebSocketServer) {
        started = false
        clearPublishedEndpoint()
        DDLogInfo("BrowserBridgeService: stopped")
    }

    func server(_ server: PSWebSocketServer, acceptWebSocketWith request: URLRequest) -> Bool {
        acceptRequest(request)
    }

    func server(_ server: PSWebSocketServer, webSocketDidOpen webSocket: PSWebSocket) {
        connections[ObjectIdentifier(webSocket)] = Connection(socket: webSocket, instanceId: nil)
        DDLogDebug("BrowserBridgeService: WebSocket opened")
    }

    func server(_ server: PSWebSocketServer, webSocket: PSWebSocket, didReceiveMessage message: Any) {
        let data: Data?
        if let string = message as? String {
            data = string.data(using: .utf8)
        } else if let messageData = message as? Data {
            data = messageData
        } else {
            data = nil
        }

        guard let data else {
            DDLogError("BrowserBridgeService: unsupported WebSocket message")
            return
        }

        switch BrowserBridgeIncomingMessage.parse(data) {
        case .hello(let hello):
            handleHello(hello, socket: webSocket)
        case .state(let state):
            handleState(state)
        case .ack(let ack):
            handleAck(ack, socket: webSocket)
        case .unknown:
            DDLogError("BrowserBridgeService: unknown WebSocket message")
        }
    }

    func server(_ server: PSWebSocketServer, webSocket: PSWebSocket, didFailWithError error: Error) {
        DDLogError("BrowserBridgeService: WebSocket failed: \(error.localizedDescription)")
    }

    func server(_ server: PSWebSocketServer, webSocket: PSWebSocket, didCloseWithCode code: Int, reason: String?, wasClean: Bool) {
        let key = ObjectIdentifier(webSocket)
        if let instanceId = connections[key]?.instanceId {
            connections.removeValue(forKey: key)
            failPendingRequests(for: instanceId, reason: "instance disconnected")
            if !connections.values.contains(where: { $0.instanceId == instanceId }) {
                instances.removeValue(forKey: instanceId)
            }
            DDLogInfo("BrowserBridgeService: instance \(instanceId) disconnected")
        } else {
            connections.removeValue(forKey: key)
        }
    }
}
