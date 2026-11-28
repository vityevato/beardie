//
//  MediaRemoteAdapterRunner.swift
//  BeardedSpiceControllers
//
//  Copyright © 2026 GPL v3 http://www.gnu.org/licenses/gpl.html
//

import CocoaLumberjackSwift
import Foundation

enum MediaRemoteAdapterError: LocalizedError {
    case resourcesMissing
    case launchFailed(String)
    case timedOut
    case cancelled
    case failed(status: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .resourcesMissing:
            return "MediaRemoteAdapter resources are missing from the XPC bundle"
        case .launchFailed(let message):
            return "Failed to launch MediaRemoteAdapter: \(message)"
        case .timedOut:
            return "MediaRemoteAdapter timed out"
        case .cancelled:
            return "MediaRemoteAdapter was cancelled"
        case .failed(let status, let message):
            return "MediaRemoteAdapter exited with status \(status): \(message)"
        }
    }
}

protocol MediaRemoteAdapterRunning {
    func run(
        arguments: [String],
        timeout: TimeInterval,
        completion: @escaping (Result<Data, Error>) -> Void
    )

    /// Terminates the adapter process that is running right now, if any.
    func cancelCurrent()
}

/// Runs the vendored MediaRemote adapter through `/usr/bin/perl`.
///
/// The helper framework is loaded only by the Perl process; Beardie and the
/// XPC service never link against MediaRemote.
final class MediaRemoteAdapterRunner: MediaRemoteAdapterRunning {

    private let scriptURL: URL
    private let frameworkURL: URL
    private let launchQueue = DispatchQueue(label: "com.calm-apps.mac.beardie.mediaremote-adapter")
    private let stateLock = NSLock()
    private var currentProcess: Process?
    private var currentRunCancelled = false

    init?() {
        guard
            let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworksURL = Bundle.main.privateFrameworksURL
        else {
            return nil
        }

        let frameworkURL = frameworksURL.appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: frameworkURL.path) else {
            return nil
        }

        self.scriptURL = scriptURL
        self.frameworkURL = frameworkURL
    }

    /// Terminates the adapter process that is running right now, if any.
    ///
    /// Queued runs are not affected. The service uses this when the app
    /// connection disappears in the middle of a targeted transaction, then
    /// queues a reset to clear a possible election override.
    func cancelCurrent() {
        stateLock.lock()
        currentRunCancelled = true
        let process = currentProcess
        stateLock.unlock()

        if let process, process.isRunning {
            process.terminate()
        }
    }

    func run(
        arguments: [String],
        timeout: TimeInterval = 5,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        // The launch queue is serial, so adapter processes never overlap. This
        // guarantees that the startup reset completes before the first read.
        launchQueue.async {
            self.stateLock.lock()
            self.currentRunCancelled = false
            self.stateLock.unlock()

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [self.scriptURL.path, self.frameworkURL.path] + arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let finished = DispatchSemaphore(value: 0)
            var output = Data()
            var errorMessage = ""
            var terminationStatus: Int32 = -1

            process.terminationHandler = { process in
                output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                errorMessage = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                terminationStatus = process.terminationStatus
                finished.signal()
            }

            do {
                try process.run()
            } catch {
                completion(.failure(MediaRemoteAdapterError.launchFailed(error.localizedDescription)))
                return
            }

            self.stateLock.lock()
            self.currentProcess = process
            self.stateLock.unlock()

            defer {
                self.stateLock.lock()
                if self.currentProcess === process {
                    self.currentProcess = nil
                }
                self.stateLock.unlock()
            }

            if finished.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                if finished.wait(timeout: .now() + 1) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    finished.wait()
                }
                self.stateLock.lock()
                let cancelled = self.currentRunCancelled
                self.stateLock.unlock()
                completion(.failure(cancelled ? MediaRemoteAdapterError.cancelled : MediaRemoteAdapterError.timedOut))
                return
            }

            self.stateLock.lock()
            let cancelled = self.currentRunCancelled
            self.stateLock.unlock()
            if cancelled {
                completion(.failure(MediaRemoteAdapterError.cancelled))
                return
            }

            if terminationStatus == 0 {
                completion(.success(output))
            } else {
                completion(.failure(MediaRemoteAdapterError.failed(
                    status: terminationStatus,
                    message: errorMessage
                )))
            }
        }
    }
}
