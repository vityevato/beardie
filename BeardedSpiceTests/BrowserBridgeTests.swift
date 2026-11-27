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
}
