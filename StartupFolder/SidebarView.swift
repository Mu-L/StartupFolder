import Defaults
import Foundation
import Lowtech
import SwiftUI
import System

struct SidebarView: View {
    var filteredItems: [StartupItem] {
        let items = startupManager.startupItems.filter { item in
            (selectedStatuses.isEmpty || selectedStatuses.contains(.none) || selectedStatuses.contains(item.status)) &&
                (selectedFolders.isEmpty || selectedFolders.contains(.none) || selectedFolders.contains(item.folder)) &&
                (selectedTypes.isEmpty || selectedTypes.contains(.none) || selectedTypes.contains(item.type))
        }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: resetFilters) {
                Text("Reset Filters")
            }.disabled(selectedStatuses.isEmpty && selectedFolders.isEmpty && selectedTypes.isEmpty)

            Text("Statuses")
                .font(.headline)
                .padding(.top)
            List(selection: $selectedStatuses) {
                Text("All").tag(StartupItem.ExecutionStatus?.none).bold()
                ForEach(StartupItem.ExecutionStatus.allCases.sorted(using: KeyPathComparator(\.text)), id: \.self) { status in
                    HStack {
                        Image(systemName: status.iconName)
                            .foregroundColor(status.color)
                        Text(status.text)
                    }.tag(status as StartupItem.ExecutionStatus?)
                }
            }
            .frame(maxHeight: 210)
            .listStyle(.sidebar)
            .onChange(of: selectedStatuses) {
                startupManager.filteredStartupItems = (selectedStatuses.isEmpty && selectedFolders.isEmpty && selectedTypes.isEmpty) ? nil : filteredItems
            }

            Text("Types")
                .font(.headline)
                .padding(.top)
            List(selection: $selectedTypes) {
                Text("All").tag(StartupItem.StartupItemType?.none).bold()
                ForEach(StartupItem.StartupItemType.allCases.sorted(using: KeyPathComparator(\.text)), id: \.self) { type in
                    HStack {
                        Image(systemName: type.iconName)
                            .foregroundColor(type.color)
                        Text(type.text)
                    }.tag(type as StartupItem.StartupItemType?)
                }
            }
            .frame(maxHeight: 240)
            .listStyle(.sidebar)
            .onChange(of: selectedTypes) {
                startupManager.filteredStartupItems = (selectedStatuses.isEmpty && selectedFolders.isEmpty && selectedTypes.isEmpty) ? nil : filteredItems
            }

            Text("Folders")
                .font(.headline)
                .padding(.top)
            List(selection: $selectedFolders) {
                Text("All").tag(FilePath.ComponentView?.none).bold()

                ForEach(startupManager.folders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.blue)
                        Text(folder.string)
                            .truncationMode(.middle)
                            .lineLimit(1)
                    }.tag(folder as FilePath.ComponentView?)
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedFolders) {
                startupManager.filteredStartupItems = (selectedStatuses.isEmpty && selectedFolders.isEmpty && selectedTypes.isEmpty) ? nil : filteredItems
            }

        }
        .frame(minWidth: 140)
        .padding(.leading, 10)
    }

    @State private var selectedStatuses: Set<StartupItem.ExecutionStatus?> = []
    @State private var selectedFolders: Set<FilePath.ComponentView?> = []
    @State private var selectedTypes: Set<StartupItem.StartupItemType?> = []
    @State private var startupManager = SM

    private func resetFilters() {
        selectedStatuses.removeAll()
        selectedFolders.removeAll()
        selectedTypes.removeAll()
        startupManager.filteredStartupItems = nil
    }
}

// Extend the enums to include icon names and colors
extension StartupItem.ExecutionStatus {
    var iconName: String {
        switch self {
        case .notStarted: "circle"
        case .running: "play.circle"
        case .succeeded: "checkmark.circle"
        case .terminated: "xmark.circle"
        case .failed: "exclamationmark.circle"
        }
    }
}

extension StartupItem.StartupItemType {
    var iconName: String {
        switch self {
        case .app: "app.dashed"
        case .script: "doc.text"
        case .binary: "apple.terminal.circle"
        case .other: "questionmark.circle"
        case .link: "link"
        case .shortcut: "s.square"
        }
    }

    var color: Color {
        switch self {
        case .app: .purple
        case .script: .orange
        case .binary: .gray
        case .other: .pink
        case .link: .blue
        case .shortcut: .indigo
        }
    }
}

#Preview {
    SidebarView()
}
