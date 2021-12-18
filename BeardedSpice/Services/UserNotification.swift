//
//  UserNotification.swift
//  Beardie
//
//  Created by Roman Sokolov on 12.12.2021.
//  Copyright © 2021 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import Cocoa

// MARK: UserNotification Interface

/// UserNotification public interface
protocol IUserNotification {
    var category: UserNotifications.Category {get set}
    var title: String {get set}
    var subtitle: String?  {get set}
    var body: String?  {get set}
    var image: AnyObject?  {get set}
}

// MARK: - UserNotification Implementation

/// UserNotification representation object
@objcMembers final class UserNotification: NSObject, IUserNotification {
    
    //MARK: Public
    
    var category: UserNotifications.Category = .trackInfo
    var title: String = ""
    var subtitle: String?
    var body: String?
    var image: AnyObject?

}
