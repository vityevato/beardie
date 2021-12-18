//
//  UserNotifications.swift
//  Beardie
//
//  Created by Roman Sokolov on 08.12.2021.
//  Copyright © 2021 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import Cocoa
import UserNotifications
import UniformTypeIdentifiers

// MARK: UserNotifications Interface

/// UserNotifications public interface
protocol IUserNotifications {
    
    static var singleton: Self {get}
    
    /// Delivers notification
    /// - Parameters:
    ///   - category: type of the notification
    func notify(category: UserNotifications.Category,
                title: String,
                subtitle: String?,
                body: String?,
                imageUrl: URL?)
    func notify(_ notification: UserNotification)
    /// Setup notifications delegate on this instance, setup notification action handler
    func setUp(handler: @escaping (UserNotifications.Category) -> Void )
}

/// Interface of the additional entities for UserNotifications namespace
extension UserNotifications {
    
    /// Type of a notifications
    @objc(UserNotificationsCategory) enum Category: Int, CustomStringConvertible, CaseIterable {
        case trackInfo,
             playerRotation,
             axFullscreenIssue,
             info
    }
}


// MARK: - UserNotifications Implementation

/// Service class for delivery of a notifications
final class UserNotifications: NSObject, IUserNotifications {
    
    //MARK: Private properties

    private let notifier = Notifier()
    private var handler: ((UserNotifications.Category) -> Void)?
    
    //MARK: Public
    
    @objc static let singleton = UserNotifications()

    @objc func notify(category: Category = .trackInfo,
                title: String,
                subtitle: String? = nil,
                body: String? = nil,
                imageUrl: URL? = nil) {
        Task {
            await notifier.notify(category: category,
                                  title: title,
                                  subtitle: subtitle,
                                  body: body,
                                  imageUrl: imageUrl)
        }
    }

    @objc func notify(_ notification: UserNotification) {
        Task {
            await notifier.notify(notification)
        }
    }
    
    @objc func setUp(handler: @escaping (UserNotifications.Category) -> Void ) {
        UNUserNotificationCenter.current().delegate = self
        self.handler = handler
    }
}

// MARK: UNUserNotificationCenterDelegate implementation

extension UserNotifications: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(macOS 11, *) {
            completionHandler([.banner, .list])
        } else {
            completionHandler([.alert])
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DDLogInfo("userNotificationCenter did receive response \(response)")
        if let category = Category(response.notification.request.content.categoryIdentifier) {
            self.handler?(category)
        }
        completionHandler()
    }
}

// MARK: additional entities implementation

/// UserNotifications.Category implementation
extension UserNotifications.Category {
    
    var description: String {
        switch self {
            case .trackInfo:
                return "trackInfo"
            case .axFullscreenIssue:
                return "axFullscreenIssue"
            case .playerRotation:
                return "playerRotation"
            case .info:
                return "info"
        }
    }
    
    init?(_ string: String) {
        guard let value = Self.allCases.first( where: { ("\($0)" == string) } ) else { return nil}
        self = value
    }
}

extension UserNotifications {
    
    private actor Notifier {
        
        private typealias ImageCache = (url: URL, cacheUrl: URL)
        
        private static let imageCacheName = "notification_cover_cache"
        private static let notificationImageName = "notification_cover"
        
        private let un = UNUserNotificationCenter.current()
        private var imageCache: ImageCache?
        private let tempFolder: URL! = {
            do {
                var result = try FileManager.default.url(for: .cachesDirectory,
                                                            in: .userDomainMask,
                                                            appropriateFor: nil,
                                                            create: true)
                result = result.appendingPathComponent(BS_BUNDLE_ID)
                try FileManager.default.createDirectory(at: result,
                                                        withIntermediateDirectories: true)
                
                return result
            } catch {
                error.log()
            }
            return nil
        }()
        
        func notify(category: Category = .trackInfo,
                    title: String,
                    subtitle: String? = nil,
                    body: String? = nil,
                    imageUrl: URL? = nil) async {
            
            do {
                if try await self.un.requestAuthorization(options: [.alert]) {
                    let settings = await self.un.notificationSettings()
                    
                    guard settings.authorizationStatus == .authorized else {
                        DDLogError("User disabled permission for show notifications")
                        return
                    }
                    let content = UNMutableNotificationContent()
                    content.threadIdentifier = "thread-\(category)"
                    content.categoryIdentifier = "\(category)"
                    content.title = title
                    if let subtitle = subtitle {
                        content.subtitle = subtitle
                    }
                    if let body = body {
                        content.body = body
                    }
                    if let imageUrl = imageUrl.flatMap( { return (($0.scheme?.count ?? 0 > 0 ? $0 : URL(string: "http:\($0.absoluteString)"))) }) {
                        if self.imageCache?.url != imageUrl {
                            if imageUrl.isFileURL {
                                self.imageCache = (imageUrl, imageUrl)
                            }
                            else {
                                // download image
                                let group = DispatchGroup()
                                group.enter()
                                let task = URLSession.shared.downloadTask(with: imageUrl) {
                                    (fileUrl, response, error) in
                                    var result: ImageCache?
                                    defer {
                                        self.imageCache = result
                                        group.leave()
                                    }
                                    if let error = error {
                                        error.log()
                                        return
                                    }
                                    guard let fileUrl = fileUrl,
                                          let response = response else {
                                              return
                                          }
                                    
                                    do {
                                        var ext = fileUrl.pathExtension
                                        if let mimeType = response.mimeType,
                                           let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType as CFString, nil)?.takeRetainedValue(),
                                           let tags = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassFilenameExtension)?.takeRetainedValue() {
                                            ext = tags as String
                                        }
                                        let savedURL = self.tempFolder.appendingPathComponent("\(Self.imageCacheName).\(ext)")
                                        _ = try? FileManager.default.removeItem(at: savedURL)
                                        try FileManager.default.moveItem(at: fileUrl, to: savedURL)
                                        result = (imageUrl, savedURL)
                                    } catch {
                                        error.log()
                                    }
                                }
                                task.resume()
                                if group.wait(timeout: .now() + 3.0) == .timedOut {
                                    task.cancel()
                                    self.imageCache = nil
                                }
                            }
                        }
                        if let imageCache = self.imageCache {
                            do {
                                let attachmentUrl = self.tempFolder.appendingPathComponent("\(Self.notificationImageName).\(imageCache.cacheUrl.pathExtension)")
                                _ = try? FileManager.default.removeItem(at: attachmentUrl)
                                try FileManager.default.copyItem(at: imageCache.cacheUrl, to: attachmentUrl)
                                content.attachments = [
                                    try UNNotificationAttachment(identifier: imageCache.url.absoluteString,
                                                                 url: attachmentUrl,
                                                                 options: nil)
                                ]
                            } catch {
                                error.log()
                            }
                        }
                    }
                    do{
                        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.05, repeats: false)
                        let request = UNNotificationRequest(identifier: (category == .info ? UUID().uuidString : "\(category)"),
                                                            content: content,
                                                            trigger: trigger)
                        try await self.un.add(request)
                    } catch {
                        error.log()
                    }
                    return
                }
                DDLogError("User did not grant permission for show notifications")
            } catch {
                error.log()
            }
        }
        
        func notify(_ notification: UserNotification) async {
            var imageUrl: URL?
            if let image = notification.image {
                switch image {
                    case let urlString as String:
                        imageUrl = URL(string: urlString)
                    case let url as URL:
                        imageUrl = url
                    case let image as NSImage:
                        if let rep = image.bestRepresentation(for: NSMakeRect(0, 0, 300, 300), context: nil, hints: nil)
                            as? NSBitmapImageRep {
                            do {
                                imageUrl = self.tempFolder.appendingPathComponent("\(Self.imageCacheName).jpeg")
                                guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.3]) else {
                                    return
                                }
                                try data.write(to: imageUrl!)
                            } catch let err {
                                err.log()
                                return
                            }
                        }
                    default:
                        return
                }
            }
            await notify(category: notification.category,
                         title: notification.title,
                         subtitle: notification.subtitle,
                         body: notification.body,
                         imageUrl: imageUrl)
        }
    }
}
