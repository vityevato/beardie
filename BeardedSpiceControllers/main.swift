//
//  main.swift
//  BeardedSpiceControllers
//
//  Created by Roman Sokolov on 05.03.16.
//  Copyright © 2016  GPL v3 http://www.gnu.org/licenses/gpl.html
//

import CocoaLumberjackSwift
import Foundation

private final class ServiceDelegate: NSObject, NSXPCListenerDelegate {

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {

        DDLogDebug("New connection")

        // This method is where the NSXPCListener configures, accepts, and resumes a new incoming NSXPCConnection.

        // Configure the connection.
        // First, set the interface that the exported object implements.
        newConnection.exportedInterface = NSXPCInterface(with: BeardedSpiceControllersProtocol.self)

        // Next, set the object that the connection exports. All messages sent on the connection to this service will be sent to the exported object to handle. The connection retains the exported object.
        let exportedObject = BeardedSpiceControllers()
        exportedObject.connection = newConnection

        newConnection.exportedObject = exportedObject

        newConnection.remoteObjectInterface = NSXPCInterface(with: BeardedSpiceHostAppProtocol.self)

        newConnection.interruptionHandler = { [weak newConnection] in
            guard let newConnection else { return }
            BSCService.shared.removeConnection(newConnection)
        }
        newConnection.invalidationHandler = { [weak newConnection] in
            guard let newConnection else { return }
            BSCService.shared.removeConnection(newConnection)
        }

        if BSCService.shared.addConnection(newConnection) {
            // Resuming the connection allows the system to deliver more incoming messages.
            newConnection.resume()
            // Returning true from this method tells the system that you have accepted this connection. If you want to reject the connection for some reason, call -invalidate on the connection and return false.
            return true
        } else {
            newConnection.invalidate()
            return false
        }
    }
}

BSSharedResources.initLoggerForComponent(withName: BS_CONTROLLER_BUNDLE_ID, changed: nil)

// Create the delegate for the service.
private let delegate = ServiceDelegate()

// Set up the one NSXPCListener for this service. It will handle all incoming connections.
let listener = NSXPCListener.service()
listener.delegate = delegate

ProcessInfo.processInfo.disableAutomaticTermination("Need for keyboard hotkeys")

// Touch to BSCService
_ = BSCService.shared

// Resuming the serviceListener starts this service. This method does not return.
listener.resume()
