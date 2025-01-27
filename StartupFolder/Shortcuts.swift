import Defaults
import Foundation
import Lowtech
import SwiftUI
import System

struct Shortcut: Codable, Hashable, Defaults.Serializable, Identifiable {
    var name: String
    var identifier: String

    var id: String { identifier }
    var url: URL {
        if let url = identifier.url {
            return url
        }
        guard let id = identifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return "shortcuts://".url!
        }
        return "shortcuts://open-shortcut?id=\(id)".url!
    }
}

struct ShortcutsPicker: View {
    @State var shortcutsManager = SHM
    @Binding var shortcut: Shortcut?

    var body: some View {
        HStack {
            Picker(
                selection: $shortcut,
                content: {
                    ShortcutChoiceMenu()
                },
                label: {
                    Text("Shortcut")
                }
            )
            Button("\(Image(systemName: shortcut == nil ? "hammer" : "hammer.fill"))") {
                if let url = shortcut?.url {
                    NSWorkspace.shared.open(url)
                }
            }
            .help("Opens the shortcut in the Shortcuts app for editing")
            .buttonStyle(FlatButton())
            .disabled(shortcut == nil)
        }
        .onChange(of: shortcutsManager.cacheIsValid) {
            if !shortcutsManager.cacheIsValid {
                log.debug("Re-fetching Shortcuts from AutomationSettingsView.onChange")
                shortcutsManager.fetch()
            }
        }
        .onAppear {
            if !shortcutsManager.cacheIsValid {
                log.debug("Re-fetching Shortcuts from AutomationSettingsView.onAppear")
                shortcutsManager.fetch()
            }
        }

    }
}

struct ShortcutChoiceMenu: View {
    @State var shortcutsManager = SHM

    var onShortcutChosen: ((Shortcut) -> Void)? = nil

    var body: some View {
        if let shortcutsMap = shortcutsManager.shortcutsMap {
            if shortcutsMap.isEmpty {
                Text("Create a shortcut in the Shortcuts app to have it appear here").disabled(true)
            } else {
                let shorts = shortcutsMap.sorted { $0.key < $1.key }

                ForEach(shorts, id: \.key) { folder, shortcuts in
                    Section(folder) { shortcutList(shortcuts) }
                }
            }
        } else {
            Text("Loading...")
                .disabled(true)
                .onAppear {
                    shortcutsManager.fetch()
                }
        }
    }

    @ViewBuilder func shortcutList(_ shortcuts: [Shortcut]) -> some View {
        if let onShortcutChosen {
            ForEach(shortcuts) { shortcut in
                Button(shortcut.name) { onShortcutChosen(shortcut) }
            }
        } else {
            ForEach(shortcuts) { shortcut in
                Text(shortcut.name).tag(shortcut as Shortcut?)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

}

struct CachedShortcuts {
    var shortcuts: [Shortcut] = []
    var lastUpdate = Date()
    var folder: String?
}
struct CachedShortcutsMap {
    var shortcuts: [String: [Shortcut]] = [:]
    var lastUpdate = Date()
}

var shortcutsCacheByFolder: [String?: CachedShortcuts] = [:]
var shortcutsMapCache: CachedShortcutsMap?

func getShortcutsOrCached(folder: String? = nil) -> [Shortcut]? {
    if let cached = mainThread({ shortcutsCacheByFolder[folder] }), cached.lastUpdate.timeIntervalSinceNow > -60 {
        return cached.shortcuts
    }

    guard let shortcuts = getShortcuts(folder: folder) else {
        return nil
    }

    mainAsync {
        shortcutsCacheByFolder[folder] = CachedShortcuts(shortcuts: shortcuts, lastUpdate: Date(), folder: folder)
    }
    return shortcuts
}

func getShortcutsMapOrCached() -> [String: [Shortcut]] {
    if let cached = mainThread({ shortcutsMapCache }), cached.lastUpdate.timeIntervalSinceNow > -60 {
        return cached.shortcuts
    }

    let shortcutsMap = getShortcutsMap()

    mainAsync {
        shortcutsMapCache = CachedShortcutsMap(shortcuts: shortcutsMap, lastUpdate: Date())
    }
    return shortcutsMap
}

func getShortcuts(folder: String? = nil) -> [Shortcut]? {
    guard !SWIFTUI_PREVIEW else { return nil }
    log.debug("Getting shortcuts for folder \(folder ?? "nil")")

    let additionalArgs = folder.map { ["--folder-name", $0] } ?? []
    guard let output = shell("/usr/bin/shortcuts", args: ["list", "--show-identifiers"] + additionalArgs, timeout: 2).o else {
        return nil
    }

    let lines = output.split(separator: "\n")
    var shortcuts: [Shortcut] = []
    for line in lines {
        let parts = line.split(separator: " ")
        guard let identifier = parts.last?.trimmingCharacters(in: CharacterSet(charactersIn: "()")) else {
            continue
        }
        let name = parts.dropLast().joined(separator: " ")
        shortcuts.append(Shortcut(name: name, identifier: identifier))
    }

    guard shortcuts.count > 0 else {
        return nil
    }

    return shortcuts
}

func getShortcutsMap() -> [String: [Shortcut]] {
    guard let folders: [String] = shell("/usr/bin/shortcuts", args: ["list", "--folders"], timeout: 2).o?.split(separator: "\n").map({ s in String(s) })
    else { return [:] }

    if let cached = mainThread({ shortcutsMapCache }), cached.lastUpdate.timeIntervalSinceNow > -60 {
        return cached.shortcuts
    }

    return (folders + ["none"]).compactMap { folder -> (String, [Shortcut])? in
        guard let shortcuts = getShortcutsOrCached(folder: folder) else {
            return nil
        }
        return (folder == "none" ? "Other" : folder, shortcuts)
    }.reduce(into: [:]) { $0[$1.0] = $1.1 }
}

var shortcutCacheResetTask: DispatchWorkItem? {
    didSet {
        oldValue?.cancel()
    }
}

func startShortcutWatcher() {
    guard fm.fileExists(atPath: "\(HOME)/Library/Shortcuts") else {
        return
    }

    do {
        try LowtechFSEvents.startWatching(paths: ["\(HOME)/Library/Shortcuts"], for: ObjectIdentifier(AppDelegate.instance), latency: 0.9) { event in
            guard !SWIFTUI_PREVIEW else { return }

            shortcutCacheResetTask = mainAsyncAfter(ms: 100) {
                SHM.invalidateCache()
            }
        }
    } catch {
        log.error("Failed to start Shortcut watcher: \(error)")
    }
}

@Observable
class ShortcutsManager {
    init() {
        guard !SWIFTUI_PREVIEW else { return }
        DispatchQueue.global().async { [self] in
            let shortcutsMap = getShortcutsMapOrCached()
            mainActor {
                self.shortcutsMap = shortcutsMap
            }
        }
    }

    var shortcutsMap: [String: [Shortcut]]?
    var cacheIsValid = true

    func invalidateCache() {
        guard !SWIFTUI_PREVIEW else { return }
        cacheIsValid = false
        if shortcutsCacheByFolder.isNotEmpty {
            shortcutsCacheByFolder = [:]
        }
        shortcutsMapCache = nil
    }

    func fetch() {
        guard !SWIFTUI_PREVIEW else { return }
        DispatchQueue.global().async { [self] in
            let shortcutsMap = getShortcutsMapOrCached()
            mainActor {
                self.shortcutsMap = shortcutsMap
                self.cacheIsValid = true
            }
        }
    }

    func refetch() {
        guard !SWIFTUI_PREVIEW else { return }
        if shortcutsCacheByFolder.isNotEmpty {
            shortcutsCacheByFolder = [:]
        }
        shortcutsMapCache = nil

        fetch()
    }
}

let SHM = ShortcutsManager()
