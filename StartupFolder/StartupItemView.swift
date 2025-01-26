import Defaults
import Foundation
import Lowtech
import SwiftUI
import System
import WrappingHStack

struct StartupItemView: View {
    @State var item: StartupItem
    @State var runtime: String?

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    HStack {
                        Text(item.shouldShowExtension ? item.name : item.name.ns.deletingPathExtension).font(.headline)
                        Button(action: {
                            if item.type == .shortcut, let url = item.shortcut?.url {
                                NSWorkspace.shared.open(url)
                            } else {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            }
                        }) {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .buttonStyle(PlainButtonStyle())

                        if let folder = item.folder {
                            Text("(in \(folder.map(\.string).joined(separator: "/")))").mono(9).foregroundStyle(.secondary)
                        }
                    }
                    if !item.isTrashed {
                        HStack {
                            if item.isTerminating {
                                ProgressView()
                                Text("Terminating...").foregroundStyle(.secondary)
                            }
                            if let code = item.exitCode {
                                Text("Exit Code: \(code)").fixedSize().monospacedDigit()
                            }
                            if let duration = runtime {
                                Text("Run time: \(duration)").fixedSize().monospacedDigit()
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !item.isTrashed {
                    Text(item.status.text)
                        .foregroundColor(item.status.color)
                }
            }

            if item.isTrashed {
                trashedActions.fixedSize()
            } else {
                actions.fixedSize()
            }
        }
        .roundbg(radius: 8, verticalPadding: 8, horizontalPadding: 8, color: .translucid, shadowSize: 0, noFG: true)
        .sheet(isPresented: $showStdout) {
            outputView(item.readStdout() ?? "", path: item.stdoutFilePath)
        }
        .sheet(isPresented: $showStderr) {
            outputView(item.readStderr() ?? "", path: item.stderrFilePath)
        }
        .onReceive(timer) { _ in
            runtime = durationText()
        }
    }

    func outputView(_ text: String, path: FilePath?) -> some View {
        VStack {
            ScrollView {
                VStack {
                    Text(text)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .monospaced()
                        .fill(.topLeading)
                }.frame(maxWidth: .infinity)
            }
            .padding()
            if let path {
                Button("Open in editor") {
                    NSWorkspace.shared.open([path.url], withApplicationAt: Defaults[.editorApp], configuration: .init())
                }
                .padding(4)
            }
        }.frame(width: 600, height: 300, alignment: .topLeading)
    }

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var trashedActions: some View {
        HStack {
            Button {
                item.putBack()
            } label: {
                Label("Put back", systemImage: "trash.slash")
            }
            Button(role: .destructive) {
                SM.recentlyDeletedStartupItems.removeAll { $0.id == item.id }
            } label: {
                Label("Delete completely", systemImage: "trash")
            }
            .foregroundStyle(.red)
        }
    }

    var actions: some View {
        WrappingHStack(alignment: .leading, verticalSpacing: 2) {
            if item.canTerminate {
                Button {
                    Task.init { await item.restart() }
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }.disabled(item.isTerminating)
                Button {
                    Task.init { await item.terminate() }
                } label: {
                    Label("Quit", systemImage: "xmark.circle")
                }.disabled(item.isTerminating)
                Button(role: .destructive) {
                    item.forceTerminate()
                } label: {
                    Label("Force Quit", systemImage: "xmark.octagon.fill")
                }
                .foregroundStyle(.red)
            } else {
                Button {
                    item.launch()
                } label: {
                    Label("Start", systemImage: "play.circle")
                }.disabled(item.isTerminating)
            }

            if item.type == .executable {
                Button {
                    NSWorkspace.shared.open([item.url], withApplicationAt: Defaults[.editorApp], configuration: .init())
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            Button(role: .destructive) {
                item.trash()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .foregroundStyle(.red)

            if item.type != .webloc {
                let outSize = item.stdoutFilePath?.fileSize() ?? 0
                let errSize = item.stderrFilePath?.fileSize() ?? 0

                Button {
                    if outSize < 100 * 1024 {
                        showStdout = true
                    } else if let url = item.stdoutFilePath?.url {
                        NSWorkspace.shared.open([url], withApplicationAt: Defaults[.editorApp], configuration: NSWorkspace.OpenConfiguration())
                    }
                } label: {
                    Label(outSize <= 0 ? "No output" : "View output", systemImage: "doc.text")
                }
                .disabled(outSize <= 0)
                Button {
                    if errSize < 100 * 1024 {
                        showStderr = true
                    } else if let url = item.stderrFilePath?.url {
                        NSWorkspace.shared.open([url], withApplicationAt: Defaults[.editorApp], configuration: NSWorkspace.OpenConfiguration())
                    }
                } label: {
                    Label(errSize <= 0 ? "No errors" : "View errors", systemImage: "exclamationmark.triangle")
                }
                .disabled(errSize <= 0)
            }
        }
    }

    func durationText() -> String? {
        guard let start = item.startTime else {
            return nil
        }
        let end = item.endTime ?? Date()
        let duration = end.timeIntervalSince(start)
        return if duration < 1 {
            "\((duration * 1000).intround) ms"
        } else if duration < 60 {
            String(format: "%.2fs", duration)
        } else if duration < 3600 {
            String(format: "%dmin %02ds", Int(duration / 60), Int(duration) % 60)
        } else if duration < 86400 {
            String(
                format: "%dh %02dmin %02ds",
                Int(duration / 3600),
                Int((duration / 60).truncatingRemainder(dividingBy: 60)),
                Int(duration.truncatingRemainder(dividingBy: 60))
            )
        } else {
            String(
                format: "%dd %02dh %02dmin %02ds",
                Int(duration / 86400),
                Int((duration / 3600).truncatingRemainder(dividingBy: 24)),
                Int((duration / 60).truncatingRemainder(dividingBy: 60)),
                Int(duration.truncatingRemainder(dividingBy: 60))
            )
        }
    }

    @State private var showStdout = false
    @State private var showStderr = false

}

let RUNNING_ITEM: StartupItem = {
    let s = StartupItem(url: "~/Startup/test-wait".existingFilePath!.url)
    s.status = .running
    s.startTime = Date().addingTimeInterval(-300)
    return s
}()
#Preview {
    StartupItemView(item: RUNNING_ITEM).frame(width: 600)
}
