//
//  BSShortcutRecorderView.swift
//  Beardie
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import AppKit
import KeyboardShortcuts

/// Thin Objective-C compatible wrapper around `KeyboardShortcuts.RecorderCocoa`.
///
/// `RecorderCocoa` is `final`, so it cannot be used as a custom class in the
/// Shortcuts preferences XIB directly. This view owns the recorder and
/// forwards its changes and recording state to the preferences controller.
@MainActor
@objc(BSShortcutRecorderView)
public final class BSShortcutRecorderView: NSView {

    private static weak var activeRecorderView: BSShortcutRecorderView?
    // Internal notification posted by RecorderCocoa. The package version is
    // pinned, so the name and the "isActive" user-info key stay stable.
    private static let recorderActivityNotification =
        Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange")

    private var recorder: KeyboardShortcuts.RecorderCocoa!
    private var activityObserver: NSObjectProtocol?
    private var tabMonitor: Any?
    private var mouseUpMonitor: Any?

    /// The action recorded by this view.
    @objc public var action: BSShortcutAction = .playPause {
        didSet {
            recorder.shortcutName = BSShortcuts.name(for: action)
        }
    }

    /// Called after the user records or clears a shortcut.
    @objc public var onChange: (() -> Void)?

    /// Called when this recorder starts or stops recording.
    @objc public var recordingDidChange: ((Bool) -> Void)?

    /// The wrapper that should receive focus on Tab.
    @objc public weak var nextRecorderView: BSShortcutRecorderView?

    /// The wrapper that should receive focus on Shift-Tab.
    @objc public weak var previousRecorderView: BSShortcutRecorderView?

    /// First recorder, used as the forward wrap target when keyboard
    /// navigation is disabled (toolbar buttons are not in the Tab loop).
    @objc public weak var firstRecorderView: BSShortcutRecorderView?

    /// Last recorder, used as the backward wrap target when keyboard
    /// navigation is disabled.
    @objc public weak var lastRecorderView: BSShortcutRecorderView?

    /// First toolbar control to focus when Tab leaves the recorder loop while
    /// keyboard navigation is enabled.
    @objc public weak var forwardExitView: NSView?

    /// Last toolbar control to focus when Shift-Tab leaves the recorder loop
    /// while keyboard navigation is enabled.
    @objc public weak var backwardExitView: NSView?

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureRecorder()
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureRecorder()
    }

    deinit {
        if let activityObserver {
            NotificationCenter.default.removeObserver(activityObserver)
        }
        if let tabMonitor {
            NSEvent.removeMonitor(tabMonitor)
        }
        if let mouseUpMonitor {
            NSEvent.removeMonitor(mouseUpMonitor)
        }
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)

        // Closing Preferences while a recorder is active must not leave the
        // XPC service with all hot keys paused.
        if newWindow == nil, Self.activeRecorderView === self {
            Self.activeRecorderView = nil
            AppTabKeyEventTap.shared.setRecorderActive(false)
            recordingDidChange?(false)
        }
    }

    /// Sets the accessibility information on the actual recorder.
    ///
    /// The wrapper itself is only a layout container, so exposing it as a
    /// button would hide the editable search field from VoiceOver.
    @objc public func setShortcutAccessibility(identifier: String, label: String) {
        recorder.setAccessibilityElement(true)
        recorder.setAccessibilityIdentifier(identifier)
        recorder.setAccessibilityLabel(label)
    }

    /// The view that should participate in the key-view loop.
    @objc public var keyView: NSView {
        recorder
    }

    /// Makes the actual RecorderCocoa first responder.
    @discardableResult
    @objc public func focusRecorder() -> Bool {
        window?.makeFirstResponder(recorder) ?? false
    }

    private func configureRecorder() {
        let recorder = KeyboardShortcuts.RecorderCocoa(for: BSShortcuts.name(for: .playPause)) { [weak self] _ in
            self?.onChange?()
        }
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(recorder)

        NSLayoutConstraint.activate([
            recorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            recorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            recorder.topAnchor.constraint(equalTo: topAnchor),
            recorder.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        self.recorder = recorder

        installTabMonitor()

        AppTabKeyEventTap.shared.startIfNeeded()
        AppTabKeyEventTap.shared.setNavigateHandler { backward in
            BSShortcutRecorderView.navigateFocus(backward: backward)
        }

        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self, self.isRecorderFirstResponder else {
                return event
            }

            // A click focus happens before the key event monitor is created
            // by RecorderCocoa. Re-add ours after the click so it is the
            // newest monitor and can intercept Shift-Tab.
            self.installTabMonitor()
            return event
        }

        activityObserver = NotificationCenter.default.addObserver(
            forName: Self.recorderActivityNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let isActive = notification.userInfo?["isActive"] as? Bool
            else {
                return
            }

            self.handleRecordingActivity(isActive)
        }
    }

    @objc public static func navigateFocus(backward: Bool) {
        activeRecorderView?.navigate(backward: backward)
    }

    /// Moves focus to the next/previous recorder, wraps when keyboard
    /// navigation is disabled, or exits to the toolbar when it is enabled.
    private func navigate(backward: Bool) {
        let target = backward ? previousRecorderView : nextRecorderView
        if let target {
            moveFocus(to: target, forward: !backward)
            return
        }

        if fullKeyboardAccessEnabled {
            AppTabKeyEventTap.shared.setRecorderActive(false)
            moveFocus(to: nil, forward: !backward)
            return
        }

        // Keyboard navigation is disabled. AppKit's Tab loop only reaches
        // text fields/lists, so behave as if the toolbar buttons do not exist.
        let wrapTarget = backward ? lastRecorderView : firstRecorderView
        if let wrapTarget {
            moveFocus(to: wrapTarget, forward: !backward)
        }
    }

    private var fullKeyboardAccessEnabled: Bool {
        // UI-test override passed as a launch argument; nil in normal runs.
        if let override = UserDefaults.standard.object(forKey: "BSForceFullKeyboardAccess") {
            return (override as? NSString)?.boolValue ?? false
        }
        return NSApp.isFullKeyboardAccessEnabled
    }

    private func installTabMonitor() {
        if let tabMonitor {
            NSEvent.removeMonitor(tabMonitor)
        }

        tabMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard
                let self,
                Self.activeRecorderView === self || self.isRecorderFirstResponder,
                event.specialKey == .tab || event.specialKey == .backTab
            else {
                return event
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isBackward = event.specialKey == .backTab || modifiers == .shift

            if isBackward {
                self.navigate(backward: true)
                return nil
            }

            if modifiers.isEmpty {
                self.navigate(backward: false)
                return nil
            }

            return event
        }
    }

    private func moveFocus(to target: BSShortcutRecorderView?, forward: Bool) {
        // Blur first and let RecorderCocoa end its recording (and remove its
        // local key monitor) before focusing the next recorder. Otherwise the
        // stale monitor can consume the next Shift-Tab.
        window?.makeFirstResponder(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else {
                return
            }

            if let target {
                if target.focusRecorder() {
                    return
                }

                if forward {
                    self.window?.selectNextKeyView(nil)
                } else {
                    self.window?.selectPreviousKeyView(nil)
                }
                return
            }

            // This path is used when keyboard navigation is enabled. Focus
            // the toolbar buttons explicitly instead of relying on AppKit's
            // standard key-view chain, which does not connect RecorderCocoa
            // to the preferences toolbar.
            let exitView = forward ? self.forwardExitView : self.backwardExitView
            if let exitView, self.window?.makeFirstResponder(exitView) == true {
                return
            }

            if forward {
                self.window?.selectNextKeyView(nil)
            } else {
                self.window?.selectPreviousKeyView(nil)
            }
        }
    }

    private func handleRecordingActivity(_ isActive: Bool) {
        if isActive {
            // The package posts the notification from inside
            // `becomeFirstResponder`, before AppKit has necessarily updated
            // the window's first responder. Check on the next turn.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRecorderFirstResponder else {
                    return
                }

                Self.activeRecorderView = self
                AppTabKeyEventTap.shared.setRecorderActive(true)
                self.recordingDidChange?(true)

                // Add the Tab monitor after RecorderCocoa has installed its
                // own key monitor; local monitors are invoked newest-first.
                self.installTabMonitor()
            }
        } else if Self.activeRecorderView === self {
            Self.activeRecorderView = nil
            AppTabKeyEventTap.shared.setRecorderActive(false)
            recordingDidChange?(false)
        }
    }

    private var isRecorderFirstResponder: Bool {
        guard let window else {
            return false
        }

        return window.firstResponder === recorder
            || window.firstResponder === recorder.currentEditor()
    }
}
