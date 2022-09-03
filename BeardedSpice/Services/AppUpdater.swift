//
//  AppUpdater.swift
//  Beardie
//
//  Created by Roman Sokolov on 06.05.2021.
//  Copyright © 2021 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import Foundation

extension UserDefaultsKeys {
    
    static let AppCastUrl = "AppCastUrl"
}

final class AppUpdater: NSObject {

    override init() {
        if !self.infoChannel.isEmpty {
            self.appCastUrl = self.infoAppCastUrl
        }
        else {
            let appCastUrl = UserDefaults.standard.string(forKey: UserDefaultsKeys.AppCastUrl) ?? ""
            self.appCastUrl = appCastUrl.isEmpty ? self.infoAppCastUrl : appCastUrl
        }
        UserDefaults.standard.set(self.appCastUrl, forKey: UserDefaultsKeys.AppCastUrl)
        
        super.init()
        
        self.updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)

    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    // MARK: Public Methods

    @IBAction func checkForUpdates(_ sender: Any)  {
        UIController.windowWillBeVisible(self.updater) {
            self.updater.checkForUpdates(sender)
        }
    }
    
    // MARK: Private
    private let infoChannel: String = { Bundle.main.object(forInfoDictionaryKey: "BSChannel") as? String ?? ""}()
    private let infoAppCastUrl: String = { Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "" }()
    
    private let appCastUrl: String
    private var updater: SPUStandardUpdaterController!
    
    @objc func receivedFinishedUpdateDriver(_ nt: Notification) {
        UIController.removeWindow(self.updater)
    }
}

// MARK: SPUStandardUserDriverDelegate Implementation

extension AppUpdater: SPUStandardUserDriverDelegate {
    
//    func standardUserDriverWillShowModalAlert() {
//        DDLogError("standardUserDriverWillShowModalAlert")
//    }
//    
//    func standardUserDriverAllowsMinimizableStatusWindow() -> Bool {
//        return false
//    }
//    
//    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
//        DDLogError("standardUserDriverWillHandleShowingUpdate")
//
//    }
//    
//    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
//        DDLogError("standardUserDriverDidReceiveUserAttention")
//
//    }
    
    func standardUserDriverWillFinishUpdateSession() {
        UIController.removeWindow(self.updater)
    }

}

// MARK: SPUUpdaterDelegate Implementation

extension AppUpdater: SPUUpdaterDelegate {
    
    func feedURLString(for updater: SPUUpdater) -> String? {
        return self.appCastUrl
    }
}
