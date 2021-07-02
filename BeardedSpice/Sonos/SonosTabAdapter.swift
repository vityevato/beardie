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

class SonosTabAdapter: TabAdapter {

    // MARK: Init
    
    init(_ group: Group) {
        self.group = group
        
        super.init()
        
        SonosInteractor.getTransportState(group).subscribe { [weak self] event in
            switch event {
            case .next(let val):
                self?.playingState = val == .playing
            default:
                self?.playingState = false
            }
        }
        .disposed(by: disposeBag)
        SonosInteractor.getTrack(group).subscribe { [weak self] event in
            guard let self = self else {return}
            switch event {
            case .next(let track):
                guard let track = track else {
                    self.track = nil
                    return
                }
                let bsTrack = BSTrack()
                bsTrack.track = track.title
                bsTrack.artist = track.artist
                bsTrack.album = track.album
                bsTrack.progress = String(track.duration)
            default:
                self.track = nil
            }
            
        }
    }
    
    // MARK: Public
    override func isPlaying() -> Bool {
        return playingState
    }
    
    
    // MARK: Private
    private let group: Group
    private var playingState = false
    private let disposeBag = DisposeBag()
    private var track: BSTrack?
}
