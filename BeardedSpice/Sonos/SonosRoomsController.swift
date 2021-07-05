//
//  SonosRoomsController.swift
//  Beardie
//
//  Created by Roman Sokolov on 29.06.2021.
//  Copyright © 2021 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import Cocoa
import RxSwift
import RxSonosLib

final class SonosRoomsController: NSObject {
    
    static let timeout: TimeInterval = 2
    
    // MARK: Public
    @objc static let singleton = SonosRoomsController()
    
    @objc var tabs = [SonosTabAdapter]()
    
    override init() {
        
        super.init()
        self.startMonitoringGroups()
    }
    
    // MARK: Private
    private let disposedBag = DisposeBag()
    
    private func startMonitoringGroups() {
        
        SonosSettings.shared.requestTimeout = Self.timeout
        
        SonosInteractor.getAllGroups()
            .distinctUntilChanged()
            .subscribe(self.onGroups)
            .disposed(by: self.disposedBag)

    }
    
    private lazy var onGroups: (Event<[Group]>) -> Void = { [weak self] event in
        guard let self = self else {
            return
        }
        switch event {
        case .next(let groups):
            self.tabs = groups.map { SonosTabAdapter($0) }
        default:
            self.tabs = []
            self.startMonitoringGroups()
        }
    }
}
