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

            Button {
                showAddURL = true
            } label: {
                Label("Add URL", systemImage: "link")
            }

            Button {
                showAddScript = true
            } label: {
                Label("Add Script", systemImage: "apple.terminal")
            }

            Button {
                showAddShortcut = true
            } label: {
                Label("Add Shortcut", systemImage: "bolt.fill")
            }
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
        FileManager.default.createFile(atPath: scriptURL.path, contents: shebang.data(using: .utf8), attributes: [.posixPermissions: 0o755])
        NSWorkspace.shared.open([scriptURL], withApplicationAt: Defaults[.editorApp], configuration: NSWorkspace.OpenConfiguration())
        startupManager.loadStartupItems()
    }

    func addURL() {
        guard url.isNotEmpty, let url = URL(string: url) else {
            return
        }
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
            if !startupManager.shortcutItems.isEmpty {
                Section(header: Text("Shortcuts")) {
                    ForEach(startupManager.shortcutItems) { item in
                        StartupItemView(item: item)
                    }
                }
            }
        }.listStyle(.inset)
    }

    var body: some View {
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
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Labels", selection: $labelStyle) {
                        ForEach(LabelStyleSetting.allCases) { style in
                            Text(style.text).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                }
                ToolbarItem(placement: .primaryAction) {
                    SettingsLink().labelStyle(.iconOnly)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 800, height: 400)
}
