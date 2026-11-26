//
//  AppTabKeyEventTap.swift
//  Beardie
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import AppKit
import CocoaLumberjackSwift
import CoreGraphics

/// Intercepts Tab/Shift-Tab while a shortcut recorder is active.
///
/// `RecorderCocoa` installs its own local key monitors and consumes both Tab
/// and Shift-Tab. On macOS 27 those monitors can outlive the recorder and
/// swallow the next navigation key. A CGEventTap runs before local monitors,
/// so the recorder never sees these two keys. Accessibility permission is
/// required, which Beardie already needs for its other system event taps.
@objcMembers
final class AppTabKeyEventTap: NSObject {

    static let shared = AppTabKeyEventTap()

    private let lock = NSLock()
    private var isRecorderActive = false
    private var isStarted = false
    private var eventPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThreadRunLoop: CFRunLoop?
    private var onNavigate: ((Bool) -> Void)?

    private override init() {
        super.init()
    }

    /// Starts the tap if Accessibility permission is available.
    @objc func startIfNeeded() {
        guard !isStarted else {
            return
        }

        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: appTabEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            DDLogError("Can't create Tab event tap; check Accessibility/Input Monitoring permission")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return
        }

        lock.lock()
        eventPort = port
        runLoopSource = source
        isStarted = true
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
        thread.name = "AppTabKeyEventTap"
        thread.start()

        DDLogInfo("Tab event tap started")
    }

    /// Called by the recorder wrapper when it starts/stops recording.
    @objc func setRecorderActive(_ active: Bool) {
        lock.lock()
        isRecorderActive = active
        lock.unlock()

        if active {
            startIfNeeded()
        }
    }

    @objc func setNavigateHandler(_ handler: @escaping (Bool) -> Void) {
        lock.lock()
        onNavigate = handler
        lock.unlock()
    }

    fileprivate nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            lock.lock()
            let port = eventPort
            lock.unlock()

            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == 48 else {
            return Unmanaged.passUnretained(event)
        }

        let relevantModifiers: CGEventFlags = [.maskShift, .maskCommand, .maskControl, .maskAlternate]
        let modifiers = event.flags.intersection(relevantModifiers)
        guard modifiers.isEmpty || modifiers == .maskShift else {
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let active = isRecorderActive
        let handler = onNavigate
        lock.unlock()

        guard active, NSRunningApplication.current.isActive else {
            return Unmanaged.passUnretained(event)
        }

        let backward = modifiers == .maskShift
        DispatchQueue.main.async {
            handler?(backward)
        }

        return nil
    }
}

private func appTabEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }

    let eventTap = Unmanaged<AppTabKeyEventTap>
        .fromOpaque(refcon)
        .takeUnretainedValue()

    return eventTap.handle(type: type, event: event)
}
