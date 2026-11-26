//
//  BSShortcutEventTap.swift
//  BeardieControllers
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import CocoaLumberjackSwift
import CoreGraphics
import Foundation

/// Global shortcut handling for the XPC service.
///
/// `KeyboardShortcuts` registers Carbon hot keys successfully in the XPC
/// process, but Carbon events are delivered through an AppKit event loop that
/// an XPC service does not have. The service therefore uses a CGEventTap, as
/// the previous `BSCShortcutMonitor` did.
@objcMembers
public final class BSShortcutEventTap: NSObject {

    private enum CarbonModifier {
        static let command = 1 << 8
        static let shift = 1 << 9
        static let option = 1 << 11
        static let control = 1 << 12
    }

    private let lock = NSLock()
    private var shortcuts: [BSShortcutKey: BSShortcutAction] = [:]
    private var pressedActions: [Int: BSShortcutAction] = [:]
    private var isEnabled = true
    private var isTapActive = false
    private var eventPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThreadRunLoop: CFRunLoop?

    private var storedActionHandler: ((BSShortcutAction) -> Void)?

    /// Called on the event-tap thread when a shortcut is released.
    public var actionHandler: ((BSShortcutAction) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedActionHandler
        }
        set {
            lock.lock()
            storedActionHandler = newValue
            lock.unlock()
        }
    }

    public override init() {
        super.init()
        startIfNeeded()
    }

    deinit {
        if let tapThreadRunLoop {
            CFRunLoopStop(tapThreadRunLoop)
        }
        if let eventPort {
            CFMachPortInvalidate(eventPort)
        }
    }

    /// Whether the CGEventTap was created successfully.
    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isTapActive
    }

    /// Replaces the shortcut table and starts the tap if it was not available.
    public func updateShortcuts(_ shortcuts: [String: [String: NSNumber]]) {
        var table: [BSShortcutKey: BSShortcutAction] = [:]

        for action in BSShortcutAction.allCases {
            guard
                let dictionary = shortcuts[action.identifier],
                let key = BSShortcutKey(dictionary: dictionary)
            else {
                continue
            }

            table[key] = action
        }

        lock.lock()
        self.shortcuts = table
        pressedActions.removeAll()
        lock.unlock()

        startIfNeeded()
        DDLogInfo("Shortcut event tap updated: \(table.count) actions, active: \(isActive)")
    }

    /// When disabled, the tap passes all key events through, so a recorder in
    /// the app can receive the combination being recorded.
    public func setEnabled(_ enabled: Bool) {
        lock.lock()
        isEnabled = enabled
        pressedActions.removeAll()
        lock.unlock()

        DDLogInfo("Shortcut event tap enabled: \(enabled)")
    }

    private func startIfNeeded() {
        lock.lock()
        let alreadyStarted = eventPort != nil
        lock.unlock()
        guard !alreadyStarted else {
            return
        }

        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: shortcutEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            DDLogError("Can't create shortcut event tap; check Accessibility/Input Monitoring permission")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            DDLogError("Can't create run-loop source for shortcut event tap")
            CFMachPortInvalidate(port)
            return
        }

        lock.lock()
        eventPort = port
        runLoopSource = source
        lock.unlock()

        let thread = Thread { [weak self] in
            guard let self else {
                return
            }

            self.tapThreadRunLoop = CFRunLoopGetCurrent()
            if let source = self.runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            CFRunLoopRun()
        }
        thread.name = "BSShortcutEventTap"
        thread.start()

        lock.lock()
        isTapActive = true
        lock.unlock()

        DDLogInfo("Shortcut event tap started")
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            lock.lock()
            let port = eventPort
            lock.unlock()

            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            DDLogInfo("Shortcut event tap re-enabled after timeout")
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let key = BSShortcutKey(
            keyCode: keyCode,
            carbonModifiers: carbonModifiers(from: event.flags)
        )

        lock.lock()
        let enabled = isEnabled
        var releasedAction: BSShortcutAction?
        var shouldConsume = false

        if enabled {
            if type == .keyDown {
                if let action = shortcuts[key] {
                    pressedActions[keyCode] = action
                    shouldConsume = true
                }
            } else if let action = pressedActions.removeValue(forKey: keyCode) {
                releasedAction = action
                shouldConsume = true
            }
        }

        let handler = storedActionHandler
        lock.unlock()

        if let releasedAction, let handler {
            handler(releasedAction)
        }

        return shouldConsume ? nil : Unmanaged.passUnretained(event)
    }

    private func carbonModifiers(from flags: CGEventFlags) -> Int {
        var modifiers = 0

        if flags.contains(.maskCommand) {
            modifiers |= CarbonModifier.command
        }
        if flags.contains(.maskShift) {
            modifiers |= CarbonModifier.shift
        }
        if flags.contains(.maskAlternate) {
            modifiers |= CarbonModifier.option
        }
        if flags.contains(.maskControl) {
            modifiers |= CarbonModifier.control
        }

        return modifiers
    }
}

private func shortcutEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }

    let eventTap = Unmanaged<BSShortcutEventTap>
        .fromOpaque(refcon)
        .takeUnretainedValue()

    return eventTap.handle(type: type, event: event)
}
