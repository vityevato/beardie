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

class AppUpdater: NSObject, SUUpdaterDelegate {

    override init() {
        if !self.infoChannel.isEmpty {
            self.appCastUrl = self.infoAppCastUrl
        }
        else {
            let appCastUrl = UserDefaults.standard.string(forKey: UserDefaultsKeys.AppCastUrl) ?? ""
            self.appCastUrl = appCastUrl.isEmpty ? self.infoAppCastUrl : appCastUrl
        }
        UserDefaults.standard.set(self.appCastUrl, forKey: UserDefaultsKeys.AppCastUrl)
        
        self.updater = SUUpdater.shared()
        
        super.init()
        
        self.updater.delegate = self
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(receivedFinishedUpdateDriver),
                                               name: Self.SUUpdateDriverFinishedNotification,
                                               object: nil)
        
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
    
    // MARK: SUUpdaterDelegate implementation
    func feedURLString(for updater: SUUpdater) -> String? {
        return self.appCastUrl
    }
    
    // MARK: Private
    private static let SUUpdateDriverFinishedNotification = Notification.Name("SUUpdateDriverFinished")

    private let infoChannel: String = { Bundle.main.object(forInfoDictionaryKey: "BSChannel") as? String ?? ""}()
    private let infoAppCastUrl: String = { Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "" }()
    
    private let appCastUrl: String
    private let updater: SUUpdater
    
    @objc func receivedFinishedUpdateDriver(_ nt: Notification) {
        UIController.removeWindow(self.updater)
    }
}
