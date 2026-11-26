//
//  BSShortcuts.swift
//  Beardie
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import Foundation

/// Actions that can be bound to a global keyboard shortcut.
///
/// The identifiers are stable: they are used as `KeyboardShortcuts.Name`
/// values and as keys in the app-to-XPC payload.
@objc public enum BSShortcutAction: Int, CaseIterable {
    case playPause
    case nextTrack
    case previousTrack
    case activeTab
    case favorite
    case notification
    case activatePlayingTab
    case playerNext
    case playerPrevious

    public var identifier: String {
        switch self {
        case .playPause:
            return "playPause"
        case .nextTrack:
            return "nextTrack"
        case .previousTrack:
            return "previousTrack"
        case .activeTab:
            return "activeTab"
        case .favorite:
            return "favorite"
        case .notification:
            return "notification"
        case .activatePlayingTab:
            return "activatePlayingTab"
        case .playerNext:
            return "playerNext"
        case .playerPrevious:
            return "playerPrevious"
        }
    }
}

/// Serializable shortcut value shared by the app and the XPC service.
///
/// Carbon modifiers are used because they are stable and already stored by
/// `KeyboardShortcuts.Shortcut`.
struct BSShortcutKey: Hashable {
    let keyCode: Int
    let carbonModifiers: Int

    init(keyCode: Int, carbonModifiers: Int) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init?(dictionary: [String: NSNumber]) {
        guard
            let keyCode = dictionary["keyCode"]?.intValue,
            let carbonModifiers = dictionary["carbonModifiers"]?.intValue,
            keyCode >= 0,
            carbonModifiers >= 0
        else {
            return nil
        }

        self.init(keyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    var dictionaryValue: [String: NSNumber] {
        [
            "keyCode": NSNumber(value: keyCode),
            "carbonModifiers": NSNumber(value: carbonModifiers)
        ]
    }
}
