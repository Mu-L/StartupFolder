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
    init(url: URL, folder: FilePath.ComponentView? = nil) {
        self.url = url
        self.folder = folder
        name = url.lastPathComponent
        type = StartupItem.determineType(of: url)
        if type == .shortcut {
            shortcut = extractShortcut(from: url)
        }
    }

    enum StartupItemType: CaseIterable {
        case app
        case script
        case binary
        case other
        case link
        case shortcut

        var text: String {
            switch self {
            case .app:
                "App"
            case .script:
                "Script"
            case .binary:
                "Binary"
            case .other:
                "Other"
            case .link:
                "Link"
            case .shortcut:
                "Shortcut"
            }
        }
    }

    enum ExecutionStatus: CaseIterable {
        case notStarted
        case running
        case succeeded
        case terminated
        case failed

        var text: String {
            switch self {
            case .notStarted:
                "Not started"
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

    var folder: FilePath.ComponentView?

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
    var shortcut: Shortcut?

    var isTerminating = false

    var process: Process? {
        didSet {
            stdoutFilePath = process?.stdoutFilePath?.existingFilePath
            stderrFilePath = process?.stderrFilePath?.existingFilePath
        }
    }

    var shouldShowExtension: Bool {
        switch type {
        case .app, .link, .shortcut:
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
        } else if url.isExecutable(), !url.isBinary() {
            .script
        } else if url.isExecutable() {
            .binary
        } else if url.pathExtension == "webloc" {
            .link
        } else if url.pathExtension == "shortcut" {
            .shortcut
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
            try FileManager.default.moveItem(at: url, to: SM.startupFolderPath.appendingPathComponent(name))
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
        case .script, .binary, .shortcut:
            launchExecutable()
        case .link, .other:
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
                    log.error("Failed to open app \(self.url): \(error)")
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
        if type == .shortcut {
            guard let shortcut else {
                log.error("Failed to extract shortcut from \(url)")
                return
            }
            process = shellProc("/usr/bin/shortcuts", args: ["run", shortcut.identifier])
        } else {
            process = shellProc(url.path, args: [])
        }
        guard let process else {
            status = .failed
            log.error("Failed to launch process for \(url)")
            return
        }

        status = .running
        startTime = Date()

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

    private func extractShortcut(from url: URL) -> Shortcut? {
        guard let identifier = try? String(contentsOf: url).trimmed else {
            return nil
        }
        return SHM.shortcutsMap?.values.joined().first { $0.identifier == identifier }
            ?? Shortcut(name: url.deletingPathExtension().lastPathComponent, identifier: identifier)
    }

}
