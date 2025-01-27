//
//  StartupItem.swift
//  StartupFolder
//
//  Created by Alin Panaitiu on 25.01.2025.
//

import Defaults
import FaviconFinder
import Foundation
import Lowtech
import SwiftUI
import System
import UniformTypeIdentifiers

extension URL {
    var resolvingAliasOrSymlink: URL {
        (try? URL(resolvingAliasFileAt: self)) ?? resolvingSymlinksInPath()
    }
}

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

        icon = switch type {
        case .app:
            NSWorkspace.shared.icon(forFile: url.resolvingAliasOrSymlink.path)
        case .binary:
            NSWorkspace.shared.icon(forFile: url.resolvingAliasOrSymlink.path)
        case .link:
            getFavicon(for: siteURL) ?? NSImage(named: NSImage.networkName)!
        case .script:
            getLanguageIcon(for: url) ?? NSImage(named: NSImage.actionTemplateName)!
        case .shortcut:
            SHORTCUT_ICON
        default:
            NSImage(named: NSImage.actionTemplateName)!
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
                if #available(macOS 15.0, *) {
                    .green.mix(with: .primary, by: 0.2)
                } else {
                    .green
                }
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

    var icon: NSImage? = nil

    @ObservationIgnored lazy var utType: UTType? = {
        if type == .script, url.pathExtension.isEmpty {
            guard let fileHandle = try? FileHandle(forReadingFrom: url),
                  let firstLine = String(data: fileHandle.readData(ofLength: 1024), encoding: .utf8)?.components(separatedBy: .newlines).first,
                  firstLine.hasPrefix("#!")
            else {
                return nil
            }
            return ScriptRunner(fromShebang: firstLine)?.utType ?? .executable
        }
        guard let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
              let utType = resourceValues.contentType
        else {
            return nil
        }
        return utType
    }()

    @ObservationIgnored lazy var siteURL: URL? = {
        guard type == .link else {
            return nil
        }
        if url.pathExtension == "webloc" {
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let siteURLString = plist["URL"] as? String,
                  let siteURL = URL(string: siteURLString)
            else {
                return nil
            }
            return siteURL
        } else if ["link", "txt", "url"].contains(url.pathExtension) {
            guard let content = try? String(contentsOf: url).trimmed,
                  let siteURL = URL(string: content)
            else {
                return nil
            }
            return siteURL
        }
        return nil
    }()

    var isNetLink: Bool {
        type == .link && (siteURL?.scheme?.starts(with: "http") ?? false)
    }

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
        if url.pathExtension == "app" || (url.resolvingAliasOrSymlink).pathExtension == "app" {
            .app
        } else if ["webloc", "link", "txt", "url"].contains(url.pathExtension) {
            if let _ = try? String(contentsOf: url).url {
                .link
            } else {
                .other
            }
        } else if url.pathExtension == "shortcut" {
            .shortcut
        } else if url.isExecutable(), !url.isBinary() {
            .script
        } else if url.isExecutable() {
            .binary
        } else if let scriptRunner = ScriptRunner(fromExtension: url.pathExtension) {
            .script
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
        case .link:
            launchURL()
        case .other:
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
            process = shellProc("/usr/bin/shortcuts", args: ["run", shortcut.identifier ?! shortcut.name])
        } else if type == .script, !url.isExecutable(), let scriptRunner = ScriptRunner(fromExtension: url.pathExtension) {
            process = shellProc(scriptRunner.path, args: [url.path])
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

    private func launchURL() {
        status = NSWorkspace.shared.open(siteURL ?? url) ? .succeeded : .failed
    }

    private func launchWithWorkspace() {
        status = NSWorkspace.shared.open(url) ? .succeeded : .failed
    }

    private func extractShortcut(from url: URL) -> Shortcut? {
        let identifier: String?
        if let fileHandle = try? FileHandle(forReadingFrom: url) {
            let data = fileHandle.readData(ofLength: 36) // UUID length
            identifier = String(data: data, encoding: .utf8)?.trimmed
        } else {
            identifier = nil
        }

        if let identifier, !identifier.isEmpty {
            return SHM.shortcutsMap?.values.joined().first { $0.identifier == identifier }
                ?? Shortcut(name: url.deletingPathExtension().lastPathComponent, identifier: identifier)
        } else {
            return SHM.shortcutsMap?.values.joined().first { $0.name == url.deletingPathExtension().lastPathComponent }
                ?? Shortcut(name: url.deletingPathExtension().lastPathComponent, identifier: "")
        }
    }

    private func getLanguageIcon(for url: URL) -> NSImage? {
        NSWorkspace.shared.icon(for: utType ?? .executable)
    }

    private func getFavicon(for url: URL?) -> NSImage? {
        guard let url else {
            return nil
        }
        if let image = FAVICON_CACHE.object(forKey: url as NSURL) {
            return image
        }

        guard url.scheme?.starts(with: "http") ?? false else {
            if let appURL = LSCopyDefaultApplicationURLForURL(url as CFURL, .all, nil)?.takeRetainedValue() as URL? {
                let appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
                FAVICON_CACHE.setObject(appIcon, forKey: url as NSURL)
                return appIcon
            }
            return nil
        }

        Task.init { [weak self] in
            if let image = await downloadFavicon(for: url) {
                mainAsync {
                    FAVICON_CACHE.setObject(image, forKey: url as NSURL)
                    self?.icon = image
                }
            }

        }
        return nil
    }

}

let SHORTCUT_ICON = NSWorkspace.shared.icon(forFile: "/System/Applications/Shortcuts.app")
let FAVICON_CACHE_DIR = FilePath.dir(
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("startup-folder-favicons")
        .filePath ?? "/tmp/startup-folder-favicons".filePath!
)
let FAVICON_CACHE = NSCache<NSURL, NSImage>()

func downloadFavicon(for url: URL) async -> NSImage? {
    guard let domain = url.host else {
        return nil
    }

    let cacheFilePath = FAVICON_CACHE_DIR / "\(domain.safeFilename).png"
    if cacheFilePath.exists, let image = NSImage(contentsOf: cacheFilePath.url) {
        return image
    }

    do {
        let favicon = try await FaviconFinder(url: url)
            .fetchFaviconURLs()
            .download()
            .smallest()

        guard let image = favicon.image?.image else {
            log.error("Failed to retrieve favicon for \(url)")
            return nil
        }

        if let tiff = image.tiffRepresentation, let tiffData = NSBitmapImageRep(data: tiff),
           let imageData = tiffData.representation(using: .png, properties: [:])
        {
            try imageData.write(to: cacheFilePath.url)
        } else {
            log.error("Failed to save favicon for \(url)")
        }

        return image
    } catch {
        log.error("Failed to retrieve or save favicon with error: \(String(describing: error))")
        return nil
    }
}
