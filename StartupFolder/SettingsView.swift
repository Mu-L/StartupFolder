//
//  SettingsView.swift
//  Startup Folder
//
//  Created by Alin Panaitiu on 24.01.2025.
//

import Defaults
import Lowtech
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            HStack {
                (
                    Text("Code editor")
                        + Text("\nUsed for opening scripts and other editable files")
                        .round(11, weight: .regular).foregroundColor(.secondary)
                ).fixedSize()
                Spacer()
                Button(editorApp.lastPathComponent) {
                    selectEditorApp()
                }.truncationMode(.middle)
            }
            .padding()
            HStack {
                (
                    Text("Startup Folder Path")
                        + Text("\nPath where startup items are stored")
                        .round(11, weight: .regular).foregroundColor(.secondary)
                ).fixedSize()
                Spacer()
                Button(startupFolderPath.path.shellString) {
                    selectStartupFolderPath()
                }.truncationMode(.middle)
            }
            .padding()
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 400, minHeight: 200)
        .alert(isPresented: $showErrorAlert) {
            Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
        }
    }

    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    @Default(.editorApp) private var editorApp
    @Default(.startupFolderPath) private var startupFolderPath

    private func selectEditorApp() {
        let panel = NSOpenPanel()
        panel.title = "Select Editor App"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = "/Applications".fileURL

        if panel.runModal() == .OK, let url = panel.url {
            editorApp = url
        }
    }

    private func selectStartupFolderPath() {
        let panel = NSOpenPanel()
        panel.title = "Select Startup Folder Path"
        panel.subtitle = "Choose an empty folder as this will be used to store startup items."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        if panel.runModal() == .OK, let url = panel.url {
            guard url != startupFolderPath else {
                errorMessage = "The selected folder is the same as the current startup folder."
                showErrorAlert = true
                return
            }

            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
                guard contents.isEmpty else {
                    errorMessage = "The selected folder is not empty."
                    showErrorAlert = true
                    return
                }
                moveStartupFolderContents(to: url)
                startupFolderPath = url
            } catch {
                errorMessage = "Failed to read the contents of the selected folder: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }

    private func moveStartupFolderContents(to newURL: URL) {
        let fileManager = FileManager.default
        let oldURL = startupFolderPath

        do {
            let contents = try fileManager.contentsOfDirectory(at: oldURL, includingPropertiesForKeys: nil, options: [])
            for item in contents {
                let destinationURL = newURL.appendingPathComponent(item.lastPathComponent)
                try fileManager.moveItem(at: item, to: destinationURL)
            }
            try fileManager.removeItem(at: oldURL)
        } catch {
            errorMessage = "Failed to move contents of Startup folder: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
}

#Preview {
    SettingsView()
}
