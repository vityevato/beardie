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
    case failed(status: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .resourcesMissing:
            return "MediaRemoteAdapter resources are missing from the XPC bundle"
        case .launchFailed(let message):
            return "Failed to launch MediaRemoteAdapter: \(message)"
        case .timedOut:
            return "MediaRemoteAdapter timed out"
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
}

/// Runs the vendored MediaRemote adapter through `/usr/bin/perl`.
///
/// The helper framework is loaded only by the Perl process; Beardie and the
/// XPC service never link against MediaRemote.
final class MediaRemoteAdapterRunner: MediaRemoteAdapterRunning {

    private let scriptURL: URL
    private let frameworkURL: URL
    private let launchQueue = DispatchQueue(label: "com.calm-apps.mac.beardie.mediaremote-adapter")

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

    func run(
        arguments: [String],
        timeout: TimeInterval = 5,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        // The launch queue is serial, so adapter processes never overlap. This
        // guarantees that the startup reset completes before the first read.
        launchQueue.async {
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

            if finished.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                if finished.wait(timeout: .now() + 1) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    finished.wait()
                }
                completion(.failure(MediaRemoteAdapterError.timedOut))
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
