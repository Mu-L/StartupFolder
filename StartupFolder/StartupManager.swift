//
//  StartupManager.swift
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
class StartupManager {
    var recentlyDeletedStartupItems: [StartupItem] = []
    var appItems: [StartupItem] = []
    var scriptItems: [StartupItem] = []
    var binaryItems: [StartupItem] = []
    var linkItems: [StartupItem] = []
    var otherItems: [StartupItem] = []
    var shortcutItems: [StartupItem] = []

    @ObservationIgnored @Default(.startupFolderPath) var startupFolderPath

    var startupItems: [StartupItem] = [] {
        didSet {
            categorize()
        }
    }

    func categorize() {
        appItems = startupItems.filter { $0.type == .app }.sorted { $0.name < $1.name }
        scriptItems = startupItems.filter { $0.type == .executable && !$0.isBinary }.sorted { $0.name < $1.name }
        binaryItems = startupItems.filter { $0.type == .executable && $0.isBinary }.sorted { $0.name < $1.name }
        linkItems = startupItems.filter { $0.type == .webloc }.sorted { $0.name < $1.name }
        otherItems = startupItems.filter { $0.type == .other }.sorted { $0.name < $1.name }
        shortcutItems = startupItems.filter { $0.type == .shortcut }.sorted { $0.name < $1.name }
    }

    func cleanup() {
        let onCleanup = Defaults[.onCleanup]

        if onCleanup.contains(.quitApps) {
            for item in startupItems where item.app != nil {
                item.app?.terminate()
            }
        }

        if onCleanup.contains(.terminateProcesses) {
            for item in startupItems where item.process != nil && item.type == .executable {
                item.process?.terminate()
            }
        }

        if onCleanup.contains(.stopShortcuts) {
            for item in startupItems where item.type == .shortcut {
                item.process?.terminate()
            }
        }

    }
    func watchStartupFolder() {
        do {
            try LowtechFSEvents.startWatching(paths: [startupFolderPath.path], for: ObjectIdentifier(self), latency: 3) { event in
                guard let flags = event.flag, flags.hasElements(from: [.itemCreated, .itemRemoved, .itemRenamed, .itemModified]) else {
                    return
                }
                log.debug("Event: \(event)")
                SM.loadStartupItems()
            }
        } catch {
            log.error("Failed to watch Startup folder: \(error)")
        }
    }

    func setupStartupFolder() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: startupFolderPath.path) {
            do {
                try fileManager.createDirectory(at: startupFolderPath, withIntermediateDirectories: true, attributes: nil)
                log.info("Created Startup folder at \(startupFolderPath)")
            } catch {
                log.error("Failed to create Startup folder: \(error)")
            }
        }
    }

    func loadStartupItems() {
        let enumerator = FileManager.default.enumerator(at: startupFolderPath, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            url, error in
            log.warning("Failed to enumerate Startup folder at \(url): \(error)")
            return true
        }
        let startupPathComponents = startupFolderPath.filePath?.components

        var newItems: [StartupItem] = []
        while let file = (enumerator?.nextObject() as? URL) {
            if file.pathExtension == "app" {
                enumerator?.skipDescendants()
            }
            guard let resourceValues = try? file.resourceValues(forKeys: [.isDirectoryKey]),
                  let isDirectory = resourceValues.isDirectory, !isDirectory
            else {
                continue
            }

            var folder: FilePath.ComponentView?
            if let startupPathComponents, let path = file.filePath {
                let subfolder = path.removingLastComponent().components.trimmingPrefix(startupPathComponents)
                if !subfolder.isEmpty {
                    folder = FilePath.ComponentView(subfolder)
                }
            }
            newItems.append(StartupItem(url: file, folder: folder))
        }

        var mergedItems: [StartupItem] = []
        for newItem in newItems {
            if let existingItem = startupItems.first(where: { $0.url == newItem.url }) {
                existingItem.name = newItem.name
                existingItem.type = newItem.type
                existingItem.folder = newItem.folder
                mergedItems.append(existingItem)
            } else {
                mergedItems.append(newItem)
            }
        }
        startupItems = mergedItems
    }

    func launchStartupItems() {
        for item in startupItems {
            item.launch()
        }
    }

}

let SM = StartupManager()
