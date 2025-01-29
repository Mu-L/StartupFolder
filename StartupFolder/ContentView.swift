//
//  ContentView.swift
//  Startup Folder
//
//  Created by Alin Panaitiu on 16.01.2025.
//

import Combine
import Defaults
import Lowtech
import SwiftUI

struct FooterView: View {
    @State var startupManager = SM

    var body: some View {
        HStack {
            Button {
                NSWorkspace.shared.open(startupManager.startupFolderPath)
            } label: {
                Label("Open Startup Folder", systemImage: "folder.fill")
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .help("Opens the startup folder in Finder (Cmd+Shift+O)")

            Spacer()

            Button {
                let dialog = NSOpenPanel()
                dialog.title = "Choose an application"
                dialog.allowedContentTypes = [.application]
                dialog.allowsMultipleSelection = true
                guard dialog.runModal() == .OK else {
                    return
                }
                for url in dialog.urls {
                    let destinationURL = startupManager.startupFolderPath.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.createSymbolicLink(at: destinationURL, withDestinationURL: url)
                }
                startupManager.loadStartupItems()
            } label: {
                Label("Add App", systemImage: "app.badge.fill")
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .help("Opens an app picker to add to the startup folder (Cmd+Shift+A)")

            Button {
                if let clipboardURL = NSPasteboard.general.string(forType: .string)?.url {
                    url = clipboardURL.absoluteString
                }
                showAddURL = true
            } label: {
                Label("Add URL", systemImage: "link")
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .help("Adds a URL to the startup folder (Cmd+Shift+U)")

            Button {
                showAddScript = true
            } label: {
                Label("Add Script", systemImage: "apple.terminal")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .help("Creates a script in the startup folder (Cmd+Shift+S)")

            Button {
                showAddShortcut = true
            } label: {
                Label("Add Shortcut", systemImage: "bolt.fill")
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .help("Opens a Shortcut picker to add to the startup folder (Cmd+Shift+K)")
        }
        .padding(.horizontal)
        .sheet(isPresented: $showAddURL, onDismiss: addURL) {
            AddURLView(url: $url, name: $name)
        }
        .sheet(isPresented: $showAddScript, onDismiss: addScript) {
            AddScriptView(name: $name, selectedRunner: $selectedRunner)
        }
        .sheet(isPresented: $showAddShortcut, onDismiss: addShortcut) {
            AddShortcutView(selectedShortcut: $selectedShortcut)
        }
    }

    func addScript() {
        guard name.isNotEmpty else {
            return
        }

        let scriptURL = startupManager.startupFolderPath.appendingPathComponent(name.safeFilename)
        let shebang = selectedRunner == nil ? "" : "#!\(selectedRunner!.path)\n"
        FileManager.default.createFile(
            atPath: scriptURL.path,
            contents: shebang.data(using: .utf8),
            attributes: [.posixPermissions: selectedRunner == nil ? 0o644 : 0o755]
        )
        NSWorkspace.shared.open(
            [scriptURL],
            withApplicationAt: Defaults[.editorApp],
            configuration: NSWorkspace.OpenConfiguration()
        )
        startupManager.loadStartupItems()
    }

    func addURL() {
        guard url.isNotEmpty, let url = URL(string: url) else {
            return
        }
        if url.scheme?.starts(with: "http") ?? false {
            let weblocContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0">
            <dict>
                <key>URL</key>
                <string>\(url)</string>
            </dict>
            </plist>
            """
            let weblocURL = startupManager.startupFolderPath.appendingPathComponent((name.safeFilename ?! url.absoluteString.safeFilename) + ".webloc")
            try? weblocContent.write(to: weblocURL, atomically: true, encoding: .utf8)
        } else {
            let urlContent = url.absoluteString
            let urlFile = startupManager.startupFolderPath.appendingPathComponent((name.safeFilename ?! url.absoluteString.safeFilename) + ".link")
            try? urlContent.write(to: urlFile, atomically: true, encoding: .utf8)
        }
        startupManager.loadStartupItems()
    }

    func addShortcut() {
        guard let shortcut = selectedShortcut else {
            return
        }
        let shortcutURL = startupManager.startupFolderPath.appendingPathComponent(shortcut.name.safeFilename + ".shortcut")
        let content = "\(shortcut.identifier)"
        try? content.write(to: shortcutURL, atomically: true, encoding: .utf8)
        startupManager.loadStartupItems()
    }

    @State private var showAddShortcut = false
    @State private var selectedShortcut: Shortcut?

    @State private var showAddURL = false
    @State private var showAddScript = false
    @State private var url = ""
    @State private var name = ""
    @State private var selectedRunner: ScriptRunner? = .sh

}

struct ContentView: View {
    @Default(.labelStyle) private var labelStyle
    @Default(.firstWindowCloseNoticeShown) private var firstWindowCloseNoticeShown
    @State var startupManager = SM

    var itemList: some View {
        List {
            if !startupManager.appItems.isEmpty {
                Section(header: Text("Apps")) {
                    ForEach(startupManager.appItems) { item in
                        StartupItemView(item: item)

                    }
                }
            }
            if !startupManager.scriptItems.isEmpty {
                Section(header: Text("Scripts")) {
                    ForEach(startupManager.scriptItems) { item in
                        StartupItemView(item: item)
                    }
                }
            }
            if !startupManager.binaryItems.isEmpty {
                Section(header: Text("Binaries")) {
                    ForEach(startupManager.binaryItems) { item in
                        StartupItemView(item: item)
                    }
                }
            }
            if !startupManager.linkItems.isEmpty {
                Section(header: Text("Links")) {
                    ForEach(startupManager.linkItems) { item in
                        StartupItemView(item: item)
                    }
                }
            }
            if !startupManager.shortcutItems.isEmpty {
                Section(header: Text("Shortcuts")) {
                    ForEach(startupManager.shortcutItems) { item in
                        StartupItemView(item: item)
                    }
                }
            }
            if !startupManager.otherItems.isEmpty {
                Section(header: Text("Other")) {
                    ForEach(startupManager.otherItems) { item in
                        StartupItemView(item: item)
                    }
                }
            }
            if !startupManager.recentlyDeletedStartupItems.isEmpty {
                Section(header: Text("Recently Deleted")) {
                    ForEach(startupManager.recentlyDeletedStartupItems) { item in
                        StartupItemView(item: item)
                    }
                }
            }
        }.listStyle(.inset)
    }

    var body: some View {
        if startupManager.windowClosed {
            EmptyView()
        } else {
            content
        }
    }

    var content: some View {
        NavigationSplitView {
            SidebarView()
                .labelStyle(.iconOnly)
        }
        detail: {
            VStack(alignment: .leading) {
                if (startupManager.filteredStartupItems ?? startupManager.startupItems).isEmpty {
                    Text("No startup items").fill()
                } else {
                    itemList.labelStyle(labelStyle)
                }
                Spacer()

                FooterView().padding(.bottom, 5).labelStyle(labelStyle)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Labels", selection: $labelStyle) {
                        ForEach(LabelStyleSetting.allCases) { style in
                            Text(style.text).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .help("Choose the style for the buttons")
                }
                ToolbarItem(placement: .primaryAction) {
                    let operationInProgress = startupManager.launchInProgress || startupManager.stopInProgress
                    Button {
                        if operationInProgress {
                            startupManager.cancelOperations()
                        } else if startupManager.allLaunched {
                            startupManager.stopStartupItems()
                        } else {
                            startupManager.launchStartupItems(delay: 0)
                        }
                    } label: {
                        if operationInProgress, hoveringStartStop {
                            Label("Cancel", systemImage: "xmark.circle.fill")
                        } else if operationInProgress, !hoveringStartStop {
                            ProgressView().controlSize(.small)
                        } else if startupManager.allLaunched {
                            Label("Stop all", systemImage: "stop.fill")
                        } else {
                            Label("Start all", systemImage: "play.fill")
                        }
                    }
                    .help(operationInProgress ? "Cancel the \(startupManager.launchInProgress ? "launch" : "stop") operation" : "\(startupManager.allLaunched ? "Stops" : "Launches") all the startup items right now")
                    .onHover { hovering in
                        hoveringStartStop = hovering
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        startupManager.loadStartupItems()
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                    .help("Reloads the startup items from the folder")
                }
                ToolbarItem(placement: .primaryAction) {
                    SettingsLink().labelStyle(.iconOnly)
                }
            }
            .onDisappear {
                if let delegate = AppDelegate.shared, delegate.isSystemShuttingDown {
                    return
                }
                if let delegate = AppDelegate.shared, delegate.isLaunchedAtLogin {
                    delegate.isLaunchedAtLogin = false
                    return
                }
                if !firstWindowCloseNoticeShown {
                    firstWindowCloseNoticeShown = true
                    showAlert()
                }
            }
        }
    }

    @State private var hoveringStartStop = false

    private func showAlert() {
        let alert = NSAlert()
        alert.messageText = "App will continue to run in the background"
        alert.informativeText = "The runtime of the apps and processes will keep being tracked. You can show the window again by running the app again."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

#Preview {
    ContentView()
        .frame(width: 800, height: 750)
}
