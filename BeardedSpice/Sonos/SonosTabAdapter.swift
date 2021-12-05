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

extension UserDefaultsKeys {
    static let SonosSeekOnPodcast = "SonosSeekOnPodcast" //Bool
    static let SonosSeekOnLongTrack = "SonosSeekOnLongTrack" //Bool
}

final class SonosTabAdapter: TabAdapter, BSVolumeControlProtocol {

    // MARK: Constants
    static let bundleId = "com.sonos.macController2"
    static let seekOffset: Int = 30 //seconrds
    static let offsetFromStartWhenWorkPrevious: Int = 2 //seconrds
    static let seekDebounceTime: RxTimeInterval = 0.5 // seconds
    static let sonosMaxVolume = 100
    static let sonosVolumeStep = 2

    // MARK: Init
    
    init(_ group: Group) {
        self.group = group
        
        super.init()
        
        
        DDLogDebug("Init tab for group: \(group.name)")
    }
    
    // MARK: Public
    @objc var displayName: String {"\(self.group.name) Sonos"}
    
    // MARK: Overrides
    
    override var application: runningSBApplication! {
        return runningSBApplication.sharedApplication(forBundleIdentifier: Self.bundleId)
    }
    
    override func activateApp(withHoldFrontmost hold: Bool) -> Bool {
        if self.application == nil {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleId),
                  let _ = try? NSWorkspace.shared.launchApplication(at: url, options: [.withoutActivation], configuration: [:]) else {
                return false
            }
        }
        return super.activateApp(withHoldFrontmost: hold)
    }
    
    override func title() -> String! {
        let sync = DispatchGroup()
        var title: String?
        sync.enter()
        let subsrc = SonosInteractor.singleTrack(self.group)
            .subscribe { event in
                if case .success(let track) = event {
                    if track?.contentType == .lineInHomeTheater {
                        title = BSLocalizedString("sonos-adapter-track-title-tv", nil)
                    }
                    else {
                        title = track?.title
                    }
                }
                sync.leave()
            }
        
        sync.wait()
        subsrc.dispose()
        
        if let title = title {
            return "\(self.displayName) | \(title)"
        }
        return "\(self.displayName)"
    }
    
    override func url() -> String! {
        return self.group.master.ip.absoluteString
    }
    override func key() -> String! {
        return self.group.slaves.reduce(self.group.master.uuid) { $0 + $1.uuid }
    }
    
    override func autoSelected() -> Bool {
        let sync = DispatchGroup()
        var result = true
        sync.enter()
        let subsrc = SonosInteractor.singleTrack(self.group)
            .subscribe { event in
                if case .success(let track) = event,
                   let track = track {
                    switch track.contentType {
                    case .lineInHomeTheater:
                        result = false
                    default:
                        result = true
                    }
                }
                sync.leave()
            }
        
        sync.wait()
        subsrc.dispose()
        
        return result
    }
    override func activateTab() -> Bool {
        self.wasActivated = true
        return self.wasActivated
    }
    override func deactivateTab() -> Bool {
        defer {
            self.wasActivated = false
        }
        return self.wasActivated && super.deactivateTab()
    }
    override func isActivated() -> Bool {
        return self.wasActivated && super.isActivated()
    }
    override func toggleTab() {
        
        let result = self.deactivateTab()
        if result {
            self.deactivateApp()
        }
        if !result {
            
            _ = self.activateApp(withHoldFrontmost: true)
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
        
        if self.seek(Self.seekOffset, sync) {
            return true
        }
        
        sync.enter()
        SonosInteractor.setNextTrack(self.group)
            .subscribe { event in
                if case .completed = event { result = true }
                sync.leave()
            }
            .disposed(by: bag)
        
        sync.wait()
        
        self.needNoti = result && !self.isPlaying()
        
        return result
    }
    
    override func previous() -> Bool {
        
        var result = false
        let sync = DispatchGroup()
        let bag = DisposeBag()
        
        if self.seek(-(Self.seekOffset), sync) {
            return true
        }
        
        sync.enter()
        SonosInteractor.setPreviousTrack(self.group)
            .observeOn(self.queue)
            .subscribe { event in
                if case .completed = event { result = true }
                sync.leave()
            }
            .disposed(by: bag)
        
        sync.wait()

        self.needNoti = result && !self.isPlaying()

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
                    result = val == .playing || val == .transitioning
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
    
    override func showNotifications() -> Bool {
        defer {
            self.needNoti = true
        }
        return self.application == nil || self.needNoti
    }
    
    override func trackInfo() -> BSTrack! {
        var result: BSTrack! = BSTrack()
        let localBag = DisposeBag()
        let sync = DispatchGroup()
        sync.enter()
        SonosInteractor.singleTrack(self.group)
            .observeOn(self.queue)
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
                    switch track.contentType {
                    
                    case .audioBroadcast:
                        result.track = track.information
                        if result.track?.isEmpty ?? true {
                            result.track = track.title
                            result.artist = track.artist
                        }
                        else {
                            result.artist = track.title
                        }
                        result.album = track.album
                    case .lineIn:
                        result.track = "\(self.displayName) | \(track.title ?? BSLocalizedString("sonos-adapter-track-title-line-in", nil))"
                    case .lineInHomeTheater:
                        result.track = "\(self.displayName) | \(BSLocalizedString("sonos-adapter-track-title-tv", nil))"
                    case .podcast, .longMusicTrack:
                        // here don't define album, this leads to we display `progress` for long track
                        result.track = track.title
                        result.artist = track.artist
                        
                    default:
                        result.track = track.title
                        result.artist = track.artist
                        result.album = track.album
                        // for default tracks remove progress value if its no need for showing
                        if UserDefaults.standard.bool(forKey: BeardedSpiceShowProgress) == false {
                            result.progress = nil
                        }
                    }
                    sync.enter()
                    SonosInteractor.singleImage(track)
                        .observeOn(self.queue)
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
        return self.volumeAction(.up)
    }
    
    func volumeDown() -> BSVolumeControlResult {
        return self.volumeAction(.down)
    }
    func volumeMute() -> BSVolumeControlResult {

        let bag = DisposeBag()
        var result = BSVolumeControlResult.unavailable
        let sync = DispatchGroup()
        sync.enter()
        SonosInteractor.singleMute(self.group)
            .observeOn(self.queue)
            .subscribe { event in
                defer {
                    sync.leave()
                }
                switch event {
                case .success(let val):
                    sync.enter()
                    Observable<Group>.just(self.group)
                        .observeOn(self.queue)
                        .set(mute: !val)
                        .subscribe { event in
                            switch event {
                            case .completed:
                                result = val ? .unmute : .mute
                            default:
                                result = .unavailable
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
        return result
    }
    

    // MARK: Private Helper
    
    private enum Error: Swift.Error {
        case seek
    }
    
    private let queue = SerialDispatchQueueScheduler(internalSerialQueueName: "SonosTabAdapterQueue")
    private let group: Group
    private var wasActivated = false
    private var needNoti = true
    private var seekSubject: BehaviorSubject<(pos: UInt, duration: UInt)>?
    private var seekBag: DisposeBag!
    
    private func switchState(onlyPause: Bool = false) -> Bool {
        var result = false
        let sync = DispatchGroup()
        let bag = DisposeBag()
        sync.enter()
        SonosInteractor.getTransportState(self.group)
            .first()
            .catchErrorJustReturn(nil)
            .map { (state) -> TransportState? in
                return (state ?? .stopped) == .playing ? .paused : state?.reverseState()
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
                                
                                self.needNoti = result && state == .paused

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
        var action: (Int) -> Int = { $0 }
        var complated: (Int) -> BSVolumeControlResult = { _ in .unavailable }
        switch direction {
        case .up:
            action = { min($0 +  Self.sonosVolumeStep, Self.sonosMaxVolume) }
            complated = { $0 == Self.sonosMaxVolume ? .unavailable : .up}
        case .down:
            action = { max($0 -  Self.sonosVolumeStep, 0) }
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
                    guard val < Self.sonosMaxVolume else {
                        return
                    }
                    sync.enter()
                    let newVal = action(val)
                    Observable<Group>.just(self.group)
                        .observeOn(self.queue)
                        .set(mute: false)
                        .andThen(SonosInteractor.change(volume: newVal,
                                                        for: self.group))
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
        DDLogDebug("Volume action result: \(result)")
        return result
    }
    
    private func secondsToTimeString(_ seconds: Int) -> String {
        let sec = abs(seconds)
        return String(format: "%@%02d:%02d:%02d", seconds < 0 ? "-" : "", sec / 3600, (sec % 3600) / 60, (sec % 3600) % 60)
    }
    
    private func seek(_ seek: Int, _ sync: DispatchGroup) -> Bool {
        
        guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.SonosSeekOnLongTrack)
                || UserDefaults.standard.bool(forKey: UserDefaultsKeys.SonosSeekOnPodcast) else {
            return false
        }
        
        if let seekSubject = self.seekSubject, let val = try? seekSubject.value() {
            var newPos = Int(val.pos) + seek
            if newPos < 0 {
                if val.pos <= Self.offsetFromStartWhenWorkPrevious {
                    seekSubject.onError(Error.seek)
                    return false
                }
                newPos = 0
            }
            if newPos > val.duration {
                newPos = Int(val.duration)
            }

            seekSubject.onNext((UInt(newPos), val.duration))
            return true
        }
        
        sync.enter()
        var result = false
        let bag = DisposeBag()
        // getting track type
        SonosInteractor.singleTrack(self.group)
            .observeOn(self.queue)
            .subscribe(onSuccess: { track in
                guard let track = track,
                      (track.contentType == .podcast && UserDefaults.standard.bool(forKey: UserDefaultsKeys.SonosSeekOnPodcast))
                        || (track.contentType == .longMusicTrack && UserDefaults.standard.bool(forKey: UserDefaultsKeys.SonosSeekOnLongTrack)) else {
                    // We don't accumulate commands
                    result = false
                    sync.leave()
                    return
                }
                if let pos = track.progress?.time,
                   let duration = track.progress?.duration {
                    self.seekSubject = BehaviorSubject(value: (pos: pos, duration: duration))
                    self.seekBag = DisposeBag()
                    self.seekSubject?
                        .debounce(Self.seekDebounceTime, scheduler: self.queue)
                        .flatMap({ (pos, _)  -> Completable in
                            self.seekSubject = nil
                            self.needNoti = true
                            return SonosInteractor.seekTrack(time: self.secondsToTimeString(Int(pos)), for: self.group)
                        })
                        .subscribe()
                        .disposed(by: self.seekBag)
                    result = self.seek(seek, sync) // emmits new value
                }
                sync.leave()
            }, onError: { error in
                DDLogError("Error occurs: \(error)")
                sync.leave()
            })
            .disposed(by: bag)
            
        sync.wait()
        return result
    }

}
