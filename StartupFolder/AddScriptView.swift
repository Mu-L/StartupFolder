import SwiftUI
import UniformTypeIdentifiers

struct AddScriptView: View {
    @Binding var name: String
    @Binding var selectedRunner: ScriptRunner?

    var body: some View {
        VStack {
            VStack {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        dismiss()
                    }
                Picker("Script runner", selection: $selectedRunner) {
                    ForEach(ScriptRunner.allCases, id: \.self) { runner in
                        Text("\(runner.name) (\(runner.path))").tag(runner as ScriptRunner?)
                    }
                    Divider()
                    Text("Custom").tag(nil as ScriptRunner?)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .padding()
            HStack {
                Button {
                    cancel()
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
            cancel()
        }
        .padding()
    }

    func cancel() {
        name = ""
        selectedRunner = nil
        dismiss()
    }

    @Environment(\.dismiss) private var dismiss
}

enum ScriptRunner: String, CaseIterable {
    case sh
    case zsh
    case fish
    case python3
    case ruby
    case perl
    case swift
    case osascript
    case node

    init?(fromShebang shebang: String) {
        let path = shebang.replacingOccurrences(of: "#!", with: "").replacingOccurrences(of: "/usr/bin/env ", with: "").trimmingCharacters(in: .whitespaces)
        guard let runner = ScriptRunner.allCases.first(where: { $0.path == path }) ?? ScriptRunner.allCases.first(where: { $0.path.contains(path) }) else {
            return nil
        }
        self = runner
    }

    init?(fromExtension ext: String) {
        guard let runner = ScriptRunner.allCases.first(where: { $0.fileExtension == ext }) else {
            return nil
        }
        self = runner
    }

    var fileExtension: String {
        switch self {
        case .sh: "sh"
        case .zsh: "zsh"
        case .fish: "fish"
        case .python3: "py"
        case .ruby: "rb"
        case .perl: "pl"
        case .swift: "swift"
        case .osascript: "scpt"
        case .node: "js"
        }
    }

    var shebang: String {
        "#!\(path)"
    }

    var utType: UTType? {
        if let utType = UTType(filenameExtension: fileExtension) {
            return utType
        }

        switch self {
        case .sh: return .shellScript
        case .zsh: return .shellScript
        case .fish: return .shellScript
        case .python3: return .pythonScript
        case .ruby: return .rubyScript
        case .perl: return .perlScript
        case .swift: return .swiftSource
        case .osascript: return .appleScript
        case .node: return .javaScript
        }
    }

    var name: String {
        switch self {
        case .sh: "Bash"
        case .zsh: "Zsh"
        case .fish: "Fish"
        case .python3: "Python 3"
        case .ruby: "Ruby"
        case .perl: "Perl"
        case .swift: "Swift"
        case .osascript: "AppleScript"
        case .node: "Node.js"
        }
    }

    var path: String {
        switch self {
        case .sh: "/bin/sh"
        case .zsh: "/bin/zsh"
        case .fish: "/usr/local/bin/fish"
        case .python3: "/usr/bin/python3"
        case .ruby: "/usr/bin/ruby"
        case .perl: "/usr/bin/perl"
        case .swift: "/usr/bin/swift"
        case .osascript: "/usr/bin/osascript"
        case .node: "/usr/local/bin/node"
        }
    }
}
