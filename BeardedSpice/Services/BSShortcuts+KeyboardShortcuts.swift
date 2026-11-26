//
//  BSShortcuts+KeyboardShortcuts.swift
//  Beardie
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import Foundation
import KeyboardShortcuts

/// App-side helpers for converting between `KeyboardShortcuts.Shortcut` and
/// the property-list payload understood by the XPC service.
@objcMembers
final class BSShortcuts: NSObject {

    static func name(for action: BSShortcutAction) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name(action.identifier)
    }

    /// Serializes all configured shortcuts for the XPC service.
    @MainActor
    @objc static func shortcutDictionary() -> [String: [String: NSNumber]] {
        var result: [String: [String: NSNumber]] = [:]

        for action in BSShortcutAction.allCases {
            guard let shortcut = KeyboardShortcuts.getShortcut(for: name(for: action)) else {
                continue
            }

            let key = BSShortcutKey(
                keyCode: shortcut.carbonKeyCode,
                carbonModifiers: shortcut.carbonModifiers
            )
            result[action.identifier] = key.dictionaryValue
        }

        return result
    }
}
