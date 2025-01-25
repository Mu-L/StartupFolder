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
                Text("Code editor")
                    + Text("\nUsed for opening scripts and other editable files")
                    .round(11, weight: .regular).foregroundColor(.secondary)
                Spacer()
                Button(editorApp.lastPathComponent) {
                    selectEditorApp()
                }
            }
            .padding()
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 400, minHeight: 200)
    }

    @Default(.editorApp) private var editorApp

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
}

#Preview {
    SettingsView()
}
