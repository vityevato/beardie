//
//  SharedResources.swift
//  Beardie
//
//  Created by Roman Sokolov on 14.06.2020.
//  Copyright © 2020 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import Foundation
import CocoaLumberjack

/// Place for collecting userDefaults keys in Swift sources.
enum UserDefaultsKeys {
}

extension BSSharedResources {
    
    @objc(setSwiftLogLevel:) static func setSwiftLogLevel(debug: Bool) {
        dynamicLogLevel = debug ? verboseLogLevel : defLogLevel
    }
}
