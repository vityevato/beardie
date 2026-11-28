//
//  BSCService.swift
//  BeardedSpice
//
//  Created by Roman Sokolov on 05.03.16.
//  Copyright © 2016  GPL v3 http://www.gnu.org/licenses/gpl.html
//

import CocoaLumberjackSwift
import Foundation

private enum HostCommand {
    case playPauseToggle
    case nextTrack
    case previousTrack
    case activeTab
    case favorite
    case notification
    case activatePlayingTab
    case playerNext
    case playerPrevious
    case volumeUp(BS_XPCEvent?)
    case volumeDown(BS_XPCEvent?)
    case volumeMute(BS_XPCEvent?)
    case headphoneUnplug
}

@objc(BSCService)
final class BSCService: NSObject, BSHeadphoneStatusListenerProtocol {

    static let shared = BSCService()

    private static let miKeyRepeatTimeout: TimeInterval = 0.6
    private static let rcdServicePlist = "/System/Library/LaunchAgents/com.apple.rcd.plist"

    private let workingQueue = DispatchQueue(label: "BeardedSpiceControllerService")

    private var keyTap: SPMediaKeyTap!
    private var mikeys: [DDHidAppleMikey]?
    private var headphoneStatusListener: BSHeadphoneStatusListener?

    let nowPlayingService = NowPlayingService()

    private var shortcuts: [String: [String: NSNumber]] = [:]
    private var shortcutEventTap: BSShortcutEventTap!

    private var remoteControlDaemonEnabled = false

    private var connections: [NSXPCConnection] = []

    private var enabled = false
    private var shortcutsRegistrationEnabled = true

    private lazy var miKeyCommandBlock: EHExecuteBlockDelayed = {
        EHExecuteBlockDelayed(
            timeout: Self.miKeyRepeatTimeout,
            leeway: Self.miKeyRepeatTimeout,
            queue: workingQueue,
            block: { [weak self] in
                guard let self else { return }

                switch self.miKeyCommandCounter {
                case 1:
                    self.send(.playPauseToggle)
                case 2:
                    self.send(.nextTrack)
                case 3:
                    self.send(.previousTrack)
                default:
                    break
                }
                DDLogDebug("\(#function) - Comman Block Running (\(self.miKeyCommandCounter))")
                self.miKeyCommandCounter = 0
            }
        )
    }()
    private var miKeyCommandCounter = 0

    private override init() {

        super.init()

        UserDefaults.standard.register(defaults: [
            kMediaKeyUsingBundleIdentifiersDefaultsKey: SPMediaKeyTap.defaultMediaKeyUserBundleIdentifiers() ?? []
        ])

        shortcutEventTap = BSShortcutEventTap()
        shortcutEventTap.actionHandler = { [weak self] action in
            DispatchQueue.main.async {
                self?.handleShortcutAction(action)
            }
        }

        headphoneStatusListener = BSHeadphoneStatusListener(delegate: self, listenerQueue: workingQueue)
        keyTap = SPMediaKeyTap(delegate: self)

        // System notifications
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(refreshAllControllers(_:)),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        let center = DistributedNotificationCenter.default()
        center.addObserver(
            self,
            selector: #selector(refreshAllControllers(_:)),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(refreshAllControllers(_:)),
            name: NSNotification.Name("com.apple.screensaver.didstop"),
            object: nil
        )

        nowPlayingService.start()
    }

    // MARK: - Public Methods

    func setShortcuts(_ shortcuts: [String: [String: NSNumber]]?) {

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.shortcuts = shortcuts ?? [:]
            self.refreshShortcutMonitor()
        }
    }

    func setShortcutsRegistrationEnabled(_ enabled: Bool) {

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.shortcutsRegistrationEnabled = enabled
            self.refreshShortcutMonitor()
        }
    }

    func setMediaKeysSupportedApps(_ bundleIds: [String]?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.keyTap.blackListBundleIdentifiers = bundleIds
            DDLogDebug("Refresh Key Tab Black List.")
        }
    }

    func setPhoneUnplugActionEnabled(_ enabled: Bool) {

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.headphoneStatusListener?.enabled = enabled
        }
    }

    func addConnection(_ connection: NSXPCConnection?) -> Bool {
        var result = false
        DispatchQueue.main.sync { [weak self] in
            guard let self else { return }

            if let connection {
                if !self.enabled {
                    self.enabled = true
                    // A previous app session may have ended while a recorder was
                    // active. Recording state is per-session, so start enabled.
                    self.shortcutsRegistrationEnabled = true
                    self.rcdControl()
                    self.refreshShortcutMonitor()

                    // Media keys need an event tap and may be unavailable without
                    // Accessibility/Input Monitoring permission. Global shortcuts
                    // use Carbon hot keys and must keep working in that case.
                    if self.refreshAllControllers(nil) == false {
                        DDLogError("Media keys are unavailable; continuing with global shortcuts only")
                    }
                }
                self.connections.append(connection)
            }

            result = self.enabled
        }
        return result
    }

    func removeConnection(_ connection: NSXPCConnection?) {
        DispatchQueue.main.sync { [weak self] in
            guard let self else { return }

            if let connection {
                self.connections.removeAll { $0 === connection }
                if self.connections.isEmpty && self.enabled {
                    self.enabled = false
                    self.shortcutsRegistrationEnabled = true
                    self.rcdControl()
                    self.refreshShortcutMonitor()
                    _ = self.refreshAllControllers(nil)
                    self.nowPlayingService.cancelActiveTransaction()
                }
            }
        }
    }

    // MARK: - Events Handlers

    // Performs Pause method
    func headphoneUnplugAction() {
        DDLogDebug("headphoneUnplugAction")
        send(.headphoneUnplug)
    }

    func headphonePlugAction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }

            DDLogDebug("headphonePlugAction")
            self.refreshMikeys()
        }
    }

    @objc(mediaKeyTap:receivedMediaKeyEvent:)
    override func mediaKeyTap(_ keyTap: SPMediaKeyTap, receivedMediaKeyEvent event: NSEvent) {
        assert(
            event.type == .systemDefined && Int(event.subtype.rawValue) == SPSystemDefinedEventMediaKeys,
            "Unexpected NSEvent in mediaKeyTap:receivedMediaKeyEvent:"
        )
        // here be dragons...
        let keyCode = Int32((event.data1 & 0xFFFF0000) >> 16)
        let keyFlags = Int(event.data1 & 0x0000FFFF)
        let keyIsPressed = ((keyFlags & 0xFF00) >> 8) == 0xA
        let keyRepeat = (keyFlags & 0x1) != 0

        let xpcEvent = BS_XPCEvent(
            modifierFlags: event.modifierFlags,
            data1: event.data1,
            data2: event.data2,
            keyPressed: keyIsPressed
        )

        var debugString = ""
        if keyIsPressed {

            debugString = keyRepeat ? ", repeated." : "."
            switch keyCode {
            case NX_KEYTYPE_PLAY:
                debugString = "Play/pause pressed" + debugString
                send(.playPauseToggle)
            case NX_KEYTYPE_FAST, NX_KEYTYPE_NEXT:
                debugString = "Ffwd pressed" + debugString
                send(.nextTrack)
            case NX_KEYTYPE_REWIND, NX_KEYTYPE_PREVIOUS:
                debugString = "Rewind pressed" + debugString
                send(.previousTrack)
            case NX_KEYTYPE_SOUND_UP:
                debugString = "Sound Up pressed" + debugString
                send(.volumeUp(xpcEvent))
            case NX_KEYTYPE_SOUND_DOWN:
                debugString = "Sound Down pressed" + debugString
                send(.volumeDown(xpcEvent))
            case NX_KEYTYPE_MUTE:
                debugString = "Sound Mute pressed" + debugString
                send(.volumeMute(xpcEvent))
            default:
                debugString = "Key \(keyCode) pressed\(debugString)"
                // More cases defined in hidsystem/ev_keymap.h
            }
        } else {
            switch keyCode {
            case NX_KEYTYPE_SOUND_UP:
                debugString = "Sound Up unpressed"
                send(.volumeUp(xpcEvent))
            case NX_KEYTYPE_SOUND_DOWN:
                debugString = "Sound Down unpressed"
                send(.volumeDown(xpcEvent))
            case NX_KEYTYPE_MUTE:
                debugString = "Sound Mute unpressed"
                send(.volumeMute(xpcEvent))
            default:
                debugString = "Key \(keyCode) unpressed"
                // More cases defined in hidsystem/ev_keymap.h
            }
        }
        DDLogDebug(debugString)
    }

    @objc(ddhidAppleMikey:press:upOrDown:)
    override func ddhidAppleMikey(_ mikey: DDHidAppleMikey, press usageId: UInt32, upOrDown: Bool) {
        #if DEBUG
        DDLogDebug("Apple Mikey keypress detected: x\(String(usageId, radix: 16, uppercase: true))")
        #endif
        if upOrDown {
            switch Int(usageId) {
            case kHIDUsage_GD_SystemMenu:
                send(.playPauseToggle)
            case kHIDUsage_GD_SystemMenuRight:
                send(.nextTrack)
            case kHIDUsage_GD_SystemMenuLeft:
                send(.previousTrack)
            case kHIDUsage_GD_SystemMenuUp, kHIDUsage_Csmr_VolumeIncrement:
                send(.volumeUp(nil))
            case kHIDUsage_GD_SystemMenuDown, kHIDUsage_Csmr_VolumeDecrement:
                send(.volumeDown(nil))
            case kHIDUsage_Csmr_PlayOrPause:
                catchCommandFromMiKeys()
                // The original code fell through to the default branch here.
                fallthrough
            default:
                DDLogDebug("Unknown key press seen x\(String(usageId, radix: 16, uppercase: true))")
            }
        }
    }

    // MARK: - Private Methods

    private func refreshMediaKeys() -> Bool {

        var result = true
        EHSystemUtils.call(onMainQueue: { [weak self] in
            guard let self else { return }

            if self.enabled {
                result = self.keyTap.startWatchingMediaKeys()
            } else {
                self.keyTap.stopWatchingMediaKeys()
            }
        })

        return result
    }

    private func catchCommandFromMiKeys() {
        miKeyCommandCounter += 1
        DDLogDebug("\(#function) - counter: \(miKeyCommandCounter)")
        miKeyCommandBlock.executeOnceAfterCalm()
    }

    private func refreshMikeys() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            DDLogDebug("Reset Mikeys")

            if let mikeys = self.mikeys {
                if let exception = tryBlock({
                    for mikey in mikeys {
                        mikey.stopListening()
                    }
                }) {
                    DDLogError("Error when stopListening on Apple Mic: \(exception)")
                }
            }

            guard self.enabled else { return }

            var discovered: [DDHidAppleMikey] = []
            if let exception = tryBlock({
                discovered = (DDHidAppleMikey.allMikeys() as? [DDHidAppleMikey]) ?? []
            }) {
                DDLogError("Error of the obtaining Apple Mic divices: \(exception.description)")
                return
            }

            var started: [DDHidAppleMikey] = []
            started.reserveCapacity(discovered.count)
            for item in discovered {

                let exception = tryBlock {
                    item.setDelegate(self)
                    item.setListenInExclusiveMode(true)
                    item.startListening()

                    started.append(item)
                }

                if let exception {
                    DDLogError("Error when startListening on Apple Mic: \(item), exception: \(exception)")
                } else {
                    #if DEBUG
                    DDLogDebug("Apple Mic added - \(item)")
                    #endif
                }
            }
            self.mikeys = started
        }
    }

    private func refreshShortcutMonitor() {

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let registrationEnabled = self.enabled && self.shortcutsRegistrationEnabled
            self.shortcutEventTap.setEnabled(registrationEnabled)
            self.shortcutEventTap.updateShortcuts(self.shortcuts)

            DDLogDebug(
                "Shortcut event tap active: \(self.shortcutEventTap.isActive ? "YES" : "NO"), actions: \(self.shortcuts.count)"
            )
        }
    }

    private func handleShortcutAction(_ action: BSShortcutAction) {

        DDLogDebug("Shortcut action: \(action.rawValue)")

        switch action {
        case .playPause:
            send(.playPauseToggle)

        case .nextTrack:
            send(.nextTrack)

        case .previousTrack:
            send(.previousTrack)

        case .activeTab:
            _ = refreshMediaKeys()
            send(.activeTab)

        case .favorite:
            send(.favorite)

        case .notification:
            _ = refreshMediaKeys()
            send(.notification)

        case .activatePlayingTab:
            _ = refreshMediaKeys()
            send(.activatePlayingTab)

        case .playerNext:
            _ = refreshMediaKeys()
            send(.playerNext)

        case .playerPrevious:
            _ = refreshMediaKeys()
            send(.playerPrevious)
        }
    }

    private func send(_ command: HostCommand) {

        workingQueue.async { [weak self] in
            guard let self else { return }

            for connection in self.connections {

                guard let proxy = connection.remoteObjectProxy as? BeardedSpiceHostAppProtocol else {
                    continue
                }

                switch command {
                case .playPauseToggle:
                    proxy.playPauseToggle()
                case .nextTrack:
                    proxy.nextTrack()
                case .previousTrack:
                    proxy.previousTrack()
                case .activeTab:
                    proxy.activeTab()
                case .favorite:
                    proxy.favorite()
                case .notification:
                    proxy.notification()
                case .activatePlayingTab:
                    proxy.activatePlayingTab()
                case .playerNext:
                    proxy.playerNext()
                case .playerPrevious:
                    proxy.playerPrevious()
                case .volumeUp(let event):
                    proxy.volumeUp(event)
                case .volumeDown(let event):
                    proxy.volumeDown(event)
                case .volumeMute(let event):
                    proxy.volumeMute(event)
                case .headphoneUnplug:
                    proxy.headphoneUnplug()
                }
            }
        }
    }

    private func rcdControl() {

        if enabled {
            DDLogDebug("rcdControl enabled")
            // checking that rcd is enabled and disabling it
            var cliOutput: NSString?
            if EHSystemUtils.cliUtil("/bin/launchctl", arguments: ["list"], output: &cliOutput) == 0 {
                remoteControlDaemonEnabled = (cliOutput as String? ?? "").contains("com.apple.rcd")
                if remoteControlDaemonEnabled {
                    let unloadResult = EHSystemUtils.cliUtil(
                        "/bin/launchctl",
                        arguments: ["unload", Self.rcdServicePlist],
                        output: &cliOutput
                    )
                    remoteControlDaemonEnabled = unloadResult == 0 && !(cliOutput as String? ?? "").contains("error")
                    DDLogDebug("rcdControl unload result: \(remoteControlDaemonEnabled ? "YES" : "NO")")
                }
            }
        } else {

            DDLogDebug("rcdControl disable")
            if remoteControlDaemonEnabled {
                DDLogDebug("rcdControl load")
                _ = EHSystemUtils.cliUtil("/bin/launchctl", arguments: ["load", Self.rcdServicePlist], output: nil)
            }
        }
    }

    // MARK: - Notifications

    /// Method reloads: media keys, apple remote, headphones remote.
    @objc private func refreshAllControllers(_ note: Notification?) -> Bool {
        refreshMikeys()
        if refreshMediaKeys() == false {
            return false
        }
        return true
    }
}
