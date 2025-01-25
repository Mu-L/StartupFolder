//
//  StartupItem.swift
//  StartupFolder
//
//  Created by Alin Panaitiu on 25.01.2025.
//

import Defaults
import Foundation
import Lowtech
import SwiftUI
import System

@Observable
class StartupItem: Identifiable {
    init(url: URL) {
        self.url = url
        name = url.lastPathComponent
        type = StartupItem.determineType(of: url)
    }

    enum StartupItemType {
        case app
        case executable
        case other
        case webloc
    }

    enum ExecutionStatus {
        case notStarted
        case running
        case succeeded
        case terminated
        case failed

        var text: String {
            switch self {
            case .notStarted:
                "Not Started"
            case .running:
                "Running"
            case .succeeded:
                "Succeeded"
            case .failed:
                "Failed"
            case .terminated:
                "Terminated"
            }
        }

        var color: Color {
            switch self {
            case .notStarted:
                .gray
            case .running:
                .orange
            case .succeeded:
                .green
            case .failed:
                .red
            case .terminated:
                .blue
            }
        }
    }

    var stdoutFilePath: FilePath? = nil
    var stderrFilePath: FilePath? = nil

    var url: URL
    var name: String
    var type: StartupItemType
    var status: ExecutionStatus = .notStarted
    var exitCode: Int32?
    var startTime: Date?
    var endTime: Date?
    var app: NSRunningApplication?
    var isTrashed = false
    @ObservationIgnored
    lazy var canBeEdited: Bool = {
        guard type == .executable || type == .other else {
            return false
        }

        return url.containsByte(0x00)
    }()
    @ObservationIgnored
    lazy var isBinary: Bool = {
        guard type == .executable else {
            return false
        }

        return url.containsByte(0x00)
    }()

    var isTerminating = false

    var process: Process? {
        didSet {
            stdoutFilePath = process?.stdoutFilePath?.existingFilePath
            stderrFilePath = process?.stderrFilePath?.existingFilePath
        }
    }

    var shouldShowExtension: Bool {
        switch type {
        case .app, .webloc:
            false
        default:
            true
        }
    }

    var isRunning: Bool { status == .running }

    var id: String { "\(url.path)-\(type)" }

    var canTerminate: Bool {
        status == .running && (app.map { !$0.isTerminated } ?? process?.isRunning ?? false)
    }

    static func determineType(of url: URL) -> StartupItemType {
        if url.pathExtension == "app" || (url.resolvingSymlinksInPath()).pathExtension == "app" {
            .app
        } else if url.isExecutable() {
            .executable
        } else if url.pathExtension == "webloc" {
            .webloc
        } else {
            .other
        }
    }

    func readStdout() -> String? {
        guard let stdoutFilePath = process?.stdoutFilePath else {
            return nil
        }
        return (try? String(contentsOfFile: stdoutFilePath)) ?? ""
    }

    func readStderr() -> String? {
        guard let stderrFilePath = process?.stderrFilePath else {
            return nil
        }
        return (try? String(contentsOfFile: stderrFilePath)) ?? ""
    }

    func trash() {
        var trashURL: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashURL)
        } catch {
            log.error("Failed to trash \(url): \(error)")
            return
        }

        let id = id
        SM.startupItems.removeAll { $0.id == id }

        guard let trashURL = trashURL as URL? else {
            log.error("Failed to trash \(url)")
            return
        }
        url = trashURL
        isTrashed = true
        SM.recentlyDeletedStartupItems = SM.recentlyDeletedStartupItems.without(id: id) + [self]
    }

    func putBack() {
        guard isTrashed else {
            return
        }

        do {
            try FileManager.default.moveItem(at: url, to: SM.startupFolderURL.appendingPathComponent(name))
        } catch {
            log.error("Failed to put back \(url): \(error)")
            return
        }

        let id = id
        SM.recentlyDeletedStartupItems.removeAll { $0.id == id }
        SM.startupItems = SM.startupItems + [self]
        isTrashed = false
    }

    func launch() {
        guard !isRunning, !isTerminating else {
            return
        }

        endTime = nil

        switch type {
        case .app:
            launchApp()
        case .executable:
            launchExecutable()
        case .webloc, .other:
            launchWithWorkspace()
        }
    }

    func terminate() async -> Bool {
        guard !isTerminating else {
            return false
        }

        isTerminating = true
        defer { isTerminating = false }

        if let app {
            app.terminate()
        } else if let process {
            process.terminate()
        }

        if await (waitUntilTerminated(for: 3)) {
            status = .terminated
            return true
        }
        return false
    }

    func restart() async -> Bool {
        guard !isTerminating else {
            return false
        }

        isTerminating = true
        defer { isTerminating = false }

        if let app {
            app.terminate()
        } else if let process {
            process.terminate()
        }

        if await !waitUntilTerminated(for: 3) {
            forceTerminate()
            if await !waitUntilTerminated(for: 3) {
                return false
            }
        }
        isTerminating = false
        status = .notStarted
        launch()
        return true
    }

    func waitUntilTerminated(for timeout: TimeInterval) async -> Bool {
        let isRunning: () -> Bool = {
            if let process = self.process {
                process.isRunning
            } else if let app = self.app {
                !app.isTerminated
            } else {
                false
            }
        }

        for _ in 0 ..< Int(timeout * 10) {
            if isRunning() {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            } else {
                return true
            }
        }
        return false
    }

    func forceTerminate() {
        if let app {
            app.forceTerminate()
            status = .terminated
        } else if let process {
            let pid = process.processIdentifier
            kill(pid, SIGKILL)
            status = .terminated
        }
        isTerminating = false
    }

    private func launchApp() {
        status = .running
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
            mainAsync {
                if let error {
                    self.status = .failed
                    return
                }
                guard let app else {
                    self.status = .failed
                    return
                }

                self.status = app.isTerminated ? .succeeded : .running
                self.app = app
            }
        }
    }

    private func launchExecutable() {
        status = .running
        startTime = Date()
        process = shellProc(url.path, args: [])
        guard let process else {
            status = .failed
            return
        }

        process.terminationHandler = { [weak self] proc in
            mainAsync {
                guard let self else {
                    return
                }
                self.exitCode = proc.terminationStatus
                self.endTime = Date()
                if self.status != .terminated, !self.isTerminating {
                    self.status = proc.terminationStatus == 0 ? .succeeded : .failed
                }
            }
        }
    }

    private func launchWithWorkspace() {
        status = NSWorkspace.shared.open(url) ? .succeeded : .failed
    }

}
