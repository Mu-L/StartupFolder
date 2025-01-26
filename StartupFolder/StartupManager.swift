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

    var startupFolderURL: URL {
        startupFolderPath
    }

    var startupItems: [StartupItem] = [] {
        didSet {
            appItems = startupItems.filter { $0.type == .app }
            scriptItems = startupItems.filter { $0.type == .executable && !$0.isBinary }
            binaryItems = startupItems.filter { $0.type == .executable && $0.isBinary }
            linkItems = startupItems.filter { $0.type == .webloc }
            otherItems = startupItems.filter { $0.type == .other }
        }
    }

    func cleanup() {
        for item in startupItems where item.process != nil {
            item.process?.terminate()
        }
    }
    func watchStartupFolder() {
        do {
            try LowtechFSEvents.startWatching(paths: [startupFolderURL.path], for: ObjectIdentifier(self), latency: 3) { event in
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
        if !fileManager.fileExists(atPath: startupFolderURL.path) {
            do {
                try fileManager.createDirectory(at: startupFolderURL, withIntermediateDirectories: true, attributes: nil)
                log.info("Created Startup folder at \(startupFolderURL.path)")
            } catch {
                log.error("Failed to create Startup folder: \(error)")
            }
        }
    }

    func loadStartupItems() {
        let fileManager = FileManager.default
        do {
            let files = try fileManager.contentsOfDirectory(at: startupFolderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            let newItems = files.map { StartupItem(url: $0) }

            var mergedItems: [StartupItem] = []
            for newItem in newItems {
                if let existingItem = startupItems.first(where: { $0.url == newItem.url }) {
                    existingItem.name = newItem.name
                    existingItem.type = newItem.type
                    mergedItems.append(existingItem)
                } else {
                    mergedItems.append(newItem)
                }
            }
            startupItems = mergedItems
        } catch {
            log.error("Failed to read Startup folder: \(error)")
        }
    }

    func launchStartupItems() {
        for item in startupItems {
            item.launch()
        }
    }

    @ObservationIgnored @Default(.startupFolderPath) private var startupFolderPath

}

let SM = StartupManager()
