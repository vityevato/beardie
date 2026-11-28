//
//  NowPlayingSafariHandler.swift
//  Now Playing Safari Extension
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import Foundation
import SafariServices

/// Native message handler for the Safari Web Extension.
///
/// Safari Web Extensions do not use the Chrome native messaging manifest.
/// This handler returns the loopback bridge endpoint and the Safari PID to the
/// extension background page.
final class NowPlayingSafariHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message = request?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let messageName = message?["msg"] as? String
        let response = responsePayload(for: messageName)

        let responseItem = NSExtensionItem()
        responseItem.userInfo = [SFExtensionMessageKey: ["body": response]]
        context.completeRequest(returningItems: [responseItem], completionHandler: nil)
    }

    private func responsePayload(for messageName: String?) -> [String: Any] {
        guard messageName == "bridge" else {
            return ["error": "unsupported-message"]
        }

        let defaults = UserDefaults(suiteName: BS_GROUP)
        let port = defaults?.integer(forKey: "BrowserBridgePort") ?? 0
        let token = defaults?.string(forKey: "BrowserBridgeToken") ?? ""
        let protocolVersion = defaults?.integer(forKey: "BrowserBridgeProtocolVersion") ?? 0

        // The app extension runs in its own process, so NSRunningApplication.current
        // is not Safari. Resolve the browser application explicitly.
        let safari = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.SafariTechnologyPreview").first

        return [
            "port": port,
            "token": token,
            "protocolVersion": protocolVersion,
            "browser": "safari",
            "bundleId": safari?.bundleIdentifier ?? "com.apple.Safari",
            "pid": safari?.processIdentifier ?? -1
        ]
    }
}
