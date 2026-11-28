//
//  BrowserBridgeModels.swift
//  Beardie
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import Foundation

enum BrowserBridgeProtocol {
    static let version = 1
    static let host = "127.0.0.1"
    static let path = "/nowplaying"

    static let portDefaultsKey = "BrowserBridgePort"
    static let tokenDefaultsKey = "BrowserBridgeToken"
    static let protocolVersionDefaultsKey = "BrowserBridgeProtocolVersion"
}

struct BrowserBridgeTab: Codable, Equatable {
    let tabId: Int
    let windowId: Int
    let active: Bool
    let title: String?
    let url: String?
    let mediaTitle: String?
    let artist: String?
    let album: String?
    let playbackState: String?
    let position: Double?
    let duration: Double?
    let artworkURLs: [String]
    let updatedAt: Date
}

struct BrowserBridgeInstance: Codable, Equatable {
    let instanceId: String
    let browser: String
    let bundleIdentifier: String?
    let processIdentifier: Int32?
    let protocolVersion: Int
    var tabs: [BrowserBridgeTab]
    var lastUpdatedAt: Date
}

struct BrowserBridgeHello: Decodable {
    let protocolVersion: Int
    let instanceId: String
    let browser: String
    let bundleId: String?
    let processIdentifier: Int32?
}

struct BrowserBridgeStateMessage: Decodable {
    let instanceId: String
    let tabs: [BrowserBridgeTab]
}

struct BrowserBridgeAck: Decodable {
    let requestId: String
    let success: Bool
    let error: String?
}

enum BrowserBridgeIncomingMessage {
    case hello(BrowserBridgeHello)
    case state(BrowserBridgeStateMessage)
    case ack(BrowserBridgeAck)
    case unknown

    static func parse(_ data: Data) -> BrowserBridgeIncomingMessage {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String
        else {
            return .unknown
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        switch type {
        case "hello":
            return (try? decoder.decode(BrowserBridgeHello.self, from: data)).map(BrowserBridgeIncomingMessage.hello) ?? .unknown
        case "state":
            return (try? decoder.decode(BrowserBridgeStateMessage.self, from: data)).map(BrowserBridgeIncomingMessage.state) ?? .unknown
        case "ack":
            return (try? decoder.decode(BrowserBridgeAck.self, from: data)).map(BrowserBridgeIncomingMessage.ack) ?? .unknown
        default:
            return .unknown
        }
    }
}

enum BrowserBridgeOutgoingMessage {
    static func helloAck(instanceId: String) -> Data? {
        encode(["type": "helloAck", "instanceId": instanceId, "protocolVersion": BrowserBridgeProtocol.version])
    }

    static func getState(requestId: String) -> Data? {
        encode(["type": "getState", "requestId": requestId])
    }

    static func activateTab(requestId: String, tabId: Int, windowId: Int) -> Data? {
        encode([
            "type": "activateTab",
            "requestId": requestId,
            "tabId": tabId,
            "windowId": windowId
        ])
    }

    static func restoreTab(requestId: String, tabId: Int, windowId: Int) -> Data? {
        encode([
            "type": "restoreTab",
            "requestId": requestId,
            "tabId": tabId,
            "windowId": windowId
        ])
    }

    static func command(requestId: String, tabId: Int, command: String, position: Double? = nil) -> Data? {
        var object: [String: Any] = [
            "type": "command",
            "requestId": requestId,
            "tabId": tabId,
            "command": command
        ]
        if let position {
            object["position"] = position
        }
        return encode(object)
    }

    private static func encode(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object)
    }
}
