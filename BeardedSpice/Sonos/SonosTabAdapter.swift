//
//  SonosTabAdapter.swift
//  Beardie
//
//  Created by Roman Sokolov on 02.07.2021.
//  Copyright © 2021 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import Cocoa
import RxSwift
import RxSonosLib

final class SonosTabAdapter: TabAdapter, BSVolumeControlProtocol {

    // MARK: Init
    
    init(_ group: Group) {
        self.group = group
        
        super.init()
        
        
        DDLogDebug("Init tab for group: \(group.name)")
    }
    
    // MARK: Public
    @objc var displayName: String {"\(self.group.name) (Sonos)"}
    
    // MARK: Overrides
    
    override var application: runningSBApplication! {
        runningSBApplication.sharedApplication(forBundleIdentifier: "com.sonos.macController2")
    }
    
    override func title() -> String! {
        let sync = DispatchGroup()
        var title: String?
        sync.enter()
        let subsrc = SonosInteractor.singleTrack(self.group)
            .debug()
            .subscribe { event in
                if case .success(let track) = event {
                    title = track?.title
                }
                sync.leave()
            }
        
        sync.wait()
        subsrc.dispose()
        
        if let title = title {
            return "\(title) (\(self.group.name) Sonos)"
        }
        return self.displayName
    }
    
    override func url() -> String! {
        return self.group.master.ip.absoluteString
    }
    override func key() -> String! {
        return self.group.master.uuid
    }
    override func activateTab() -> Bool {
        self.wasActivated = super.activateTab()
        return self.wasActivated
    }
    override func deactivateTab() -> Bool {
        self.wasActivated = super.deactivateTab()
        return self.wasActivated
    }
    override func toggleTab() {
        
        let result = self.deactivateTab()
        if result {
            self.deactivateApp()
        }
        if !result {
            
            _ = self.activateApp()
            _ = self.activateTab()
        }
        
    }
    override func frontmost() -> Bool {
        super.frontmost() && wasActivated
    }
    
    override func toggle() -> Bool {
        self.switchState()
    }
    override func pause() -> Bool {
        self.switchState(onlyPause: true)
    }
    
    override func next() -> Bool {
        var result = false
        let sync = DispatchGroup()
        let bag = DisposeBag()
        sync.enter()
        SonosInteractor.setNextTrack(self.group)
            .observeOn(self.queue)
            .subscribe { event in
                if case .completed = event { result = true }
                sync.leave()
            }
            .disposed(by: bag)
        
        sync.wait()
        
        return result
    }
    
    override func previous() -> Bool {
        
        var result = false
        let sync = DispatchGroup()
        let bag = DisposeBag()
        sync.enter()
        SonosInteractor.setPreviousTrack(self.group)
            .observeOn(self.queue)
            .subscribe { event in
                if case .completed = event { result = true }
                sync.leave()
            }
            .disposed(by: bag)
        
        sync.wait()
        
        return result
    }
    
    override func isPlaying() -> Bool {
        var result = false
        let sync = DispatchGroup()
        sync.enter()
        let subscr = SonosInteractor.singleTransportState(self.group)
            .observeOn(self.queue)
            .subscribe {  event in
                switch event {
                case .success(let val):
                    result = val == .playing
                default:
                    result = false
                }
                sync.leave()
            }

        sync.wait()
        subscr.dispose()
        DDLogDebug("isPlaying result: \(result)")
        return result
    }
    
    override func trackInfo() -> BSTrack! {
        var result: BSTrack! = BSTrack()
        let localBag = DisposeBag()
        let sync = DispatchGroup()
        sync.enter()
        SonosInteractor.singleTrack(self.group)
            .observeOn(self.queue)
            .debug()
            .subscribe { [weak self] event in
                defer {
                    sync.leave()
                }
                guard let self = self else {return}
                DDLogDebug("Progress Event: \(event)")
                switch event {
                case .success(let track):
                    guard let track = track else {
                        result = nil
                        return
                    }
                    if let progress = track.progress, progress.duration > 0 {
                        result.progress = "\(progress.timeString) of \(progress.durationString)"
                    }
                    result.track = track.title
                    result.artist = track.artist
                    result.album = track.album
                    sync.enter()
                    SonosInteractor.singleImage(track)
                        .observeOn(self.queue)
                        .debug()
                        .subscribe { [weak self] event in
                            defer {
                                sync.leave()
                            }
                            guard let self = self else { return }
                            switch event {
                            case .success(let data):
                                result?.image = NSImage(data: data)
                            default:
                                result?.image = nil
                            }
                            DDLogDebug("Group (\(self.group.name)) image track: \(String(describing: result))")
                        }
                        .disposed(by: localBag)
                    
                default:
                    result = nil
                }
                DDLogDebug("Group (\(self.group.name)) track: \(String(describing: result))")
                
            }
            .disposed(by: localBag)
        
        sync.wait()
        
        return result
    }
    
    // MARK: BSVolumeControlProtocol Implementation
    
    func volumeUp() -> BSVolumeControlResult {
        return self.volumeAction( .up)
    }
    
    func volumeDown() -> BSVolumeControlResult {
        return volumeAction(.down)
    }
    func volumeMute() -> BSVolumeControlResult {
        Observable<Group>(self.group)
            .subscribe(ObserverType)
        return BSVolumeControlResult.unavailable
    }
    

    // MARK: Private Helper
    
    private let queue = SerialDispatchQueueScheduler(internalSerialQueueName: "SonosTabAdapterQueue")
    private let group: Group
    private var wasActivated = false
    
    private func switchState(onlyPause: Bool = false) -> Bool {
        var result = false
        let sync = DispatchGroup()
        let bag = DisposeBag()
        sync.enter()
        SonosInteractor.getTransportState(self.group)
            .first()
            .catchErrorJustReturn(nil)
            .map { (state) -> TransportState? in
                return state ?? .stopped == .playing ? .paused : state?.reverseState()
            }
            .asObservable()
            .asSingle()
            .observeOn(self.queue)
            .subscribe { [weak self] event in
                defer {
                    sync.leave()
                }
                guard let self = self else {return}
                if case .success(let state) = event {
                    if let state = state {
                       if state == .paused || !onlyPause {
                        sync.enter()
                        SonosInteractor.setTransport(state: state, for: self.group)
                            .observeOn(self.queue)
                            .subscribe { event in
                                if case .completed = event { result = true }
                                sync.leave()
                            }
                            .disposed(by: bag)
                       }
                       else { result = true }
                    }
                }
            }
            .disposed(by: bag)
        
        sync.wait()
        
        return result
    }
    private func volumeAction(_ direction: BSVolumeControlResult) -> BSVolumeControlResult {
        var action: (Int) -> Int = { min($0 +  SonosRoomsController.sonosVolumeStep, SonosRoomsController.sonosMaxVolume) }
        var complated: (Int) -> BSVolumeControlResult = { $0 == SonosRoomsController.sonosMaxVolume ? .unavailable : .up}
        switch direction {
        case .down:
            action = { max($0 -  SonosRoomsController.sonosVolumeStep, 0) }
            complated = {$0 == 0 ? .mute : .down}
        default:
            return .notSupported
        }
        
        let bag = DisposeBag()
        var result = BSVolumeControlResult.unavailable
        let sync = DispatchGroup()
        sync.enter()
        SonosInteractor.singleVolume(self.group)
            .observeOn(self.queue)
            .subscribe {  event in
                defer {
                    sync.leave()
                }
                switch event {
                case .success(let val):
                    guard val < SonosRoomsController.sonosMaxVolume else {
                        return
                    }
                    sync.enter()
                    let newVal = action(val)
                    SonosInteractor.set(volume: newVal,
                                        for: self.group)
                        .subscribe { event in
                            if case .completed = event {
                                result = complated(newVal)
                            }
                            sync.leave()
                        }
                        .disposed(by: bag)
                default:
                    result = .unavailable
                }
            }
            .disposed(by: bag)
        sync.wait()
        DDLogDebug("isPlaying result: \(result)")
        return result
    }
}
