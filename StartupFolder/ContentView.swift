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

struct AddURLView: View {
    @Binding var url: String
    @Binding var name: String

    var body: some View {
        VStack {
            TextField("URL", text: $url)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                .onSubmit {
                    dismiss()
                }
            TextField("Name", text: $name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                .onSubmit {
                    dismiss()
                }
            HStack {
                Button {
                    url = ""
                    name = ""
                    dismiss()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                Button {
                    dismiss()
                } label: {
                    Label("Save", systemImage: "checkmark.circle")
                }
            }
        }
        .onExitCommand {
            url = ""
            name = ""
            dismiss()
        }
        .padding()
    }

    @Environment(\.dismiss) private var dismiss

}

struct AddScriptView: View {
    @Binding var name: String

    var body: some View {
        VStack {
            TextField("Name", text: $name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                .onSubmit {
                    dismiss()
                }
            HStack {
                Button {
                    name = ""
                    dismiss()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                Button {
                    dismiss()
                } label: {
                    Label("Save", systemImage: "checkmark.circle")
                }
            }
        }
        .onExitCommand {
            name = ""
            dismiss()
        }
        .padding()
    }

    @Environment(\.dismiss) private var dismiss

}

struct FooterView: View {
    @State var startupManager = SM

    var body: some View {
        HStack {
            Button {
                NSWorkspace.shared.open(startupManager.startupFolderURL)
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
                    let destinationURL = startupManager.startupFolderURL.appendingPathComponent(url.lastPathComponent)
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
        }
        .padding(.horizontal)
        .sheet(isPresented: $showAddURL, onDismiss: addURL) {
            AddURLView(url: $url, name: $name)
        }
        .sheet(isPresented: $showAddScript, onDismiss: addScript) {
            AddScriptView(name: $name)
        }
    }

    func addScript() {
        guard name.isNotEmpty else {
            return
        }

        let scriptURL = startupManager.startupFolderURL.appendingPathComponent(name.safeFilename)
        FileManager.default.createFile(atPath: scriptURL.path, contents: nil, attributes: [.posixPermissions: 0o755])
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
        let weblocURL = startupManager.startupFolderURL.appendingPathComponent((name.safeFilename ?! url.absoluteString.safeFilename) + ".webloc")
        try? weblocContent.write(to: weblocURL, atomically: true, encoding: .utf8)
        startupManager.loadStartupItems()
    }

    @State private var showAddURL = false
    @State private var showAddScript = false
    @State private var url = ""
    @State private var name = ""

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
        }.listStyle(.sidebar)
    }

    var body: some View {
        VStack(alignment: .leading) {
            if startupManager.startupItems.isEmpty {
                Text("No startup items").fill()
            } else {
                itemList
            }
            Spacer()

            FooterView().padding(.bottom, 5)
        }
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Label Style").font(.caption).foregroundColor(.secondary).offset(x: 4)
                    Picker("Label Style", selection: $labelStyle) {
                        ForEach(LabelStyleSetting.allCases) { style in
                            Text(style.text).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .labelStyle(labelStyle)
    }

}

#Preview {
    ContentView()
        .frame(width: 800, height: 400)
}
