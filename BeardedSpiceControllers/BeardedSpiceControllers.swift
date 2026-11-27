//
//  BeardedSpiceControllers.swift
//  BeardedSpiceControllers
//
//  Created by Roman Sokolov on 05.03.16.
//  Copyright © 2016  GPL v3 http://www.gnu.org/licenses/gpl.html
//

import CocoaLumberjackSwift
import Foundation

/// This object implements the protocol which we have defined. It provides the actual behavior for the service. It is 'exported' by the service to make it available to the process hosting the service over an NSXPCConnection.
@objc(BeardedSpiceControllers)
final class BeardedSpiceControllers: NSObject, BeardedSpiceControllersProtocol {

    weak var connection: NSXPCConnection?

    @objc(setShortcuts:)
    func setShortcuts(_ shortcuts: [String: [String: NSNumber]]!) {
        DDLogInfo("setShortcuts: \(shortcuts?.count ?? 0) actions")

        BSCService.shared.setShortcuts(shortcuts)
    }

    @objc(setShortcutsRegistrationEnabled:)
    func setShortcutsRegistrationEnabled(_ enabled: Bool) {
        DDLogInfo("setShortcutsRegistrationEnabled: \(enabled ? "YES" : "NO")")

        BSCService.shared.setShortcutsRegistrationEnabled(enabled)
    }

    @objc(setMediaKeysSupportedApps:)
    func setMediaKeysSupportedApps(_ bundleIds: [String]!) {
        DDLogInfo("setMediaKeysSupportedApps")

        BSCService.shared.setMediaKeysSupportedApps(bundleIds)
    }

    @objc(setPhoneUnplugActionEnabled:)
    func setPhoneUnplugActionEnabled(_ enabled: Bool) {
        DDLogInfo("setPhoneUnplugActionEnabled")

        BSCService.shared.setPhoneUnplugActionEnabled(enabled)
    }

    @objc(getNowPlayingSnapshotWithCompletion:)
    func getNowPlayingSnapshot(completion: @escaping (Data?) -> Void) {
        BSCService.shared.nowPlayingService.snapshot { result in
            switch result {
            case .success(let snapshot):
                completion(try? JSONEncoder().encode(snapshot))
            case .failure(let error):
                DDLogError("NowPlaying snapshot failed: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }

    @objc(getNowPlayingHealthWithCompletion:)
    func getNowPlayingHealth(completion: @escaping (Data) -> Void) {
        BSCService.shared.nowPlayingService.health { health in
            completion((try? JSONEncoder().encode(health)) ?? Data())
        }
    }

    @objc(resetNowPlayingWithCompletion:)
    func resetNowPlaying(completion: @escaping (Bool) -> Void) {
        BSCService.shared.nowPlayingService.reset { success in
            completion(success)
        }
    }

    @objc(prepareForClosingConnectionWithCompletion:)
    func prepareForClosingConnection(completion: @escaping () -> Void) {

        BSCService.shared.removeConnection(connection)

        completion()
    }
}
