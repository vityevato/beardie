//
//  BSHeadphoneStatusListener.swift
//  BeardedSpice
//
//  Created by Roman Sokolov on 08.08.15.
//  Copyright (c) 2015  GPL v3 http://www.gnu.org/licenses/gpl.html
//

import CoreAudio
import Foundation

protocol BSHeadphoneStatusListenerProtocol: AnyObject {

    /// Action is called when headphone is unplugged.
    func headphoneUnplugAction()

    /// Action is called when headphone is plugged in.
    func headphonePlugAction()
}

/// Monitoring mini-jack connection.
/// Attempt to determine unplugging headphone from it.
/// And perform action when raises this event.
final class BSHeadphoneStatusListener: NSObject {

    private static let headphoneSource: UInt32 = 0x6864706E // 'hdpn'

    private weak var delegate: BSHeadphoneStatusListenerProtocol?
    private let listenerQueue: DispatchQueue

    private var defaultDevice: AudioDeviceID = 0
    private var sourceId: UInt32 = 0
    private var sourceAddr: AudioObjectPropertyAddress

    private var changeDefaultListenerBlock: AudioObjectPropertyListenerBlock!
    private var changeSourceListenerBlock: AudioObjectPropertyListenerBlock!

    private let lock = NSLock()
    private var enabledState = false

    // MARK: - Init and class methods

    init?(delegate: BSHeadphoneStatusListenerProtocol?, listenerQueue: DispatchQueue?) {
        guard let delegate, let listenerQueue else {
            return nil
        }

        self.delegate = delegate
        self.listenerQueue = listenerQueue
        self.sourceAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        super.init()

        changeDefaultListenerBlock = { [weak self] _, _ in
            guard let self else { return }

            _ = self.removeCallbackForDevice()
            if self.getDefaultDevice() {
                var address = self.sourceAddr
                self.changeSourceListenerBlock(1, &address)
                _ = self.addCallbackForDevice()
            }
        }

        changeSourceListenerBlock = { [weak self] _, _ in
            guard let self else { return }

            let oldSourceId = self.sourceId
            _ = self.getCurrentSource()

            if self.sourceId != oldSourceId {
                if oldSourceId == Self.headphoneSource {
                    self.listenerQueue.async { [weak self] in
                        self?.delegate?.headphoneUnplugAction()
                    }
                } else if self.sourceId == Self.headphoneSource {
                    self.listenerQueue.async { [weak self] in
                        self?.delegate?.headphonePlugAction()
                    }
                }
            }
        }
    }

    deinit {
        _ = removeCallback()
    }

    // MARK: - Properties and public methods

    var enabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return enabledState
        }
        set {
            lock.lock()
            defer { lock.unlock() }

            if newValue != enabledState {
                if newValue {
                    if addCallback() {
                        enabledState = true
                    }
                } else if removeCallback() {
                    enabledState = false
                }
            }
        }
    }

    // MARK: - Private methods

    private func addCallback() -> Bool {

        _ = getDefaultDevice()
        _ = getCurrentSource()

        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceCallbackAdded = false
        listenerQueue.sync {
            deviceCallbackAdded = addCallbackForDevice()
        }
        guard deviceCallbackAdded else {
            return false
        }

        return AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr,
            listenerQueue,
            changeDefaultListenerBlock
        ) == noErr
    }

    private func removeCallback() -> Bool {

        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var result = AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr,
            listenerQueue,
            changeDefaultListenerBlock
        )

        if result == noErr {
            var deviceCallbackRemoved = false
            listenerQueue.sync {
                deviceCallbackRemoved = removeCallbackForDevice()
            }
            result = deviceCallbackRemoved ? noErr : 1
        }

        defaultDevice = 0
        sourceId = 0

        return result == noErr
    }

    private func addCallbackForDevice() -> Bool {

        guard defaultDevice != 0 else {
            return false
        }

        return AudioObjectAddPropertyListenerBlock(
            defaultDevice,
            &sourceAddr,
            listenerQueue,
            changeSourceListenerBlock
        ) == noErr
    }

    private func removeCallbackForDevice() -> Bool {

        guard defaultDevice != 0 else {
            return false
        }

        return AudioObjectRemovePropertyListenerBlock(
            defaultDevice,
            &sourceAddr,
            listenerQueue,
            changeSourceListenerBlock
        ) == noErr
    }

    private func getCurrentSource() -> Bool {

        sourceId = 0
        var dataSourceIdSize = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(
            defaultDevice,
            &sourceAddr,
            0,
            nil,
            &dataSourceIdSize,
            &sourceId
        ) == noErr
    }

    private func getDefaultDevice() -> Bool {

        defaultDevice = 0
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        return AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr,
            0,
            nil,
            &defaultSize,
            &defaultDevice
        ) == noErr
    }
}
