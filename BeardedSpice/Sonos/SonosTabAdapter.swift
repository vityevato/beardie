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

final class SonosTabAdapter: TabAdapter {

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
        let localBag = DisposeBag()
        let sync = DispatchGroup()
        var title: String?
        sync.enter()
        SonosInteractor.getTrack(self.group)
            .timeout(SonosRoomsController.requestTimeout, scheduler: ConcurrentDispatchQueueScheduler(qos: .userInteractive))
            .first()
            .observeOn(self.queue)
            .subscribe { event in
                if case .success(let track) = event {
                    title = track??.title
                }
                sync.leave()
            }
            .disposed(by: localBag)
        sync.wait()
        
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
        let subscr = SonosInteractor.getTransportState(self.group)
            .first()
            .observeOn(self.queue)
            .subscribe({  event in
                switch event {
                case .success(let val):
                    result = val == .playing
                default:
                    result = false
                }
                sync.leave()
            })
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
//        SonosInteractor.singleProgress(self.group)
//            .debug()
//            .
        SonosInteractor.getProgress(self.group)
            .withLatestFrom(SonosInteractor.getTrack(self.group))
            { (pr: GroupProgress, tr: Track? ) -> (GroupProgress, Track?) in
                DDLogDebug("Combine - Progress observable: \(pr), Track info: \(String(describing: tr))")
                return (pr, tr)
            }
            .timeout(SonosRoomsController.requestTimeout, scheduler: ConcurrentDispatchQueueScheduler(qos: .userInteractive))
            .first()
            .observeOn(self.queue)
            .subscribe { [weak self] event in
                defer {
                    sync.leave()
                }
                guard let self = self else {return}
                DDLogDebug("Progress Event: \(event)")
                switch event {
                case .success(let data):
                    guard let (progress, track) = data else {
                        result = nil
                        return
                    }
                    if progress.duration > 0 {
                        result.progress = "\(progress.timeString) of \(progress.durationString)"
                    }
                    guard let track = track else {
                        return
                    }
                    result.track = track.title
                    result.artist = track.artist
                    result.album = track.album
                    sync.enter()
                    SonosInteractor.getTrackImage(track)
                        .first()
                        .observeOn(self.queue)
                        .subscribe { [weak self] event in
                            defer {
                                sync.leave()
                            }
                            guard let self = self else { return }
                            switch event {
                            case .success(let data):
                                result?.image = data == nil ? nil : NSImage(data: data!!)
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
    
    // MARK: Private
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

}
