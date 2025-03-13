//
//  StartupFolderApp.swift
//  Startup Folder
//
//  Created by Alin Panaitiu on 16.01.2025.
//

import AppKit
import Combine
import Defaults
import EonilFSEvents
import Lowtech
import LowtechIndie
import ServiceManagement
import Sparkle
import SwiftUI
import System

class AppDelegate: LowtechIndieAppDelegate {
    static var shared: AppDelegate? { NSApp.delegate as? AppDelegate }

    var window: NSWindow?

    // if env contains login=true
    var isLaunchedAtLogin = ProcessInfo.processInfo.environment["login"] == "true"
    var launchTimestamp = Date()

    var isSystemShuttingDown = false

    var mainWindow: NSWindow? {
        NSApp.windows.first { $0.title == "Startup Folder" }
    }
    var settingsWindow: NSWindow? {
        NSApp.windows.first { $0.title.contains("Settings") }
    }

    override func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.disableRelaunchOnLogin()
        if !SWIFTUI_PREVIEW, let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != NSRunningApplication.current.processIdentifier }) {
            #if DEBUG
                app.forceTerminate()
            #else
                app.activate()
                NSApp.terminate(nil)
                return
            #endif
        }

        super.applicationDidFinishLaunching(notification)
        setupCleanup()
        setupLaunchAtLogin()
        UM.updater = updateController.updater
        SM.setupStartupFolder()
        SM.loadStartupItems()
        SM.watchStartupFolder()
        if isLaunchedAtLogin {
            if Defaults[.showWindowAtStartup] {
                WM.open("main")
            } else {
                NSApp.setActivationPolicy(.accessory)
                mainWindow?.close()
            }
            SM.launchStartupItems()
        } else if !SWIFTUI_PREVIEW {
            NSApp.setActivationPolicy(.regular)
            WM.open("main")
            focus()
        }
        if !SWIFTUI_PREVIEW {
            startShortcutWatcher()
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationDidTerminate(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.addObserver(self, forKeyPath: #keyPath(NSWorkspace.runningApplications), options: [.new, .old, .prior], context: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeMain(_:)), name: NSWindow.didBecomeMainNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willCloseNotification(_:)), name: NSWindow.willCloseNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemWillPowerOff(_:)), name: NSWorkspace.willPowerOffNotification, object: nil)
    }

    override func applicationDidBecomeActive(_ notification: Notification) {
        guard didBecomeActiveAtLeastOnce else {
            didBecomeActiveAtLeastOnce = true
            return
        }
        log.debug("Became active")
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(NSWorkspace.runningApplications) {
            let oldApps = change?[.oldKey] as? [NSRunningApplication] ?? []
            let newApps = change?[.newKey] as? [NSRunningApplication] ?? []

            let terminatedApps = oldApps.filter { !newApps.contains($0) }
            for terminatedApp in terminatedApps {
                guard let item = SM.startupItems.first(where: { $0.app?.processIdentifier == terminatedApp.processIdentifier }) else {
                    continue
                }
                item.setAppTerminated()
            }

            for app in newApps {
                guard let item = SM.startupItems.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) else {
                    continue
                }
                item.app = app
                if app.isTerminated {
                    item.setAppTerminated()
                } else {
                    item.app = app
                    item.startTime = app.launchDate
                    item.status = .running
                }
            }
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !SWIFTUI_PREVIEW else {
            return true
        }

        log.debug("Reopened")

        if let mainWindow {
            focus()
            mainWindow.orderFrontRegardless()
        } else {
            WM.open("main")
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        log.debug("Open URLs: \(urls)")
        NSApp.deactivate()
        Task {
            await handleURLs(application, urls)
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        log.debug("Open files: \(filenames)")
        NSApp.deactivate()
        Task {
            await handleURLs(sender, filenames.compactMap(\.url))
        }
    }

    func handleURLs(_ application: NSApplication, _ urls: [URL]) async {
        for url in urls {
            do {
                if url.pathExtension == "link", let fileURL = try (String(contentsOf: url)).url {
                    NSWorkspace.shared.open(fileURL)
                }
            } catch {
                log.error("Failed to open URL \(url): \(error)")
                await application.reply(toOpenOrPrint: .failure)
                return
            }
        }
        await application.reply(toOpenOrPrint: .success)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        SM.cleanup()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isSystemShuttingDown {
            return .terminateNow
        }
        if Defaults[.stopAskingOnQuit] {
            if !Defaults[.quitDirectly] {
                NSApp.setActivationPolicy(.accessory)
                mainWindow?.close()
                settingsWindow?.close()
            }
            return Defaults[.quitDirectly] ? .terminateNow : .terminateCancel
        }

        let alert = NSAlert()
        alert.messageText = "Quit Application"
        alert
            .informativeText =
            "Quitting the app will stop it from tracking the startup items runtime. Do you want the app to keep running in the background or quit completely?\n\nYou can always bring back the main window by launching the app again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep running in the background")
        alert.addButton(withTitle: "Quit")
        alert.showsSuppressionButton = true

        let response = alert.runModal()
        Defaults[.stopAskingOnQuit] = alert.suppressionButton?.state == .on
        Defaults[.quitDirectly] = response == .alertSecondButtonReturn
        if response == .alertFirstButtonReturn {
            NSApp.setActivationPolicy(.accessory)
            mainWindow?.close()
            settingsWindow?.close()
            return .terminateCancel
        } else {
            return .terminateNow
        }
    }

    func setupCleanup() {
        signal(SIGINT) { _ in
            SM.cleanup()
            exit(0)
        }
        signal(SIGTERM) { _ in
            SM.cleanup()
            exit(0)
        }
        signal(SIGKILL) { _ in
            SM.cleanup()
            exit(0)
        }
    }

    @objc func windowDidBecomeMain(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window.title == "Startup Folder" {
            NSApp.setActivationPolicy(.regular)
            SM.windowClosed = false
        }
    }

    @objc func willCloseNotification(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window.title == "Startup Folder", window.contentView != nil {
            NSApp.setActivationPolicy(.accessory)
            SM.windowClosed = true
        }
    }

    @objc func applicationDidTerminate(_ notification: Notification) {
        guard let terminatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        for item in SM.startupItems {
            if item.app?.processIdentifier == terminatedApp.processIdentifier {
                item.setAppTerminated()
            }
        }
    }

    @objc func systemWillPowerOff(_ notification: Notification) {
        isSystemShuttingDown = true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        isSystemShuttingDown = true
    }
}

func setupLaunchAtLogin(loadAgent: Bool? = nil) {
    let loadAgent = loadAgent ?? Defaults[.loadAgent]
    let currentService = SMAppService.agent(plistName: "com.lowtechguys.StartupFolder.plist")
    if currentService.status == .notFound || !loadAgent {
        do {
            try currentService.unregister()
        } catch {
            log.error("Failed to unregister service: \(error)")
        }
    }

    guard loadAgent else {
        return
    }
    do {
        try currentService.register()
    } catch {
        log.error("Failed to register service: \(error)")
    }
}

class WindowManager: ObservableObject {
    @Published var windowToOpen: String? = nil

    func open(_ window: String) {
        windowToOpen = window
    }
}
let WM = WindowManager()

@main
struct StartupFolderApp: App {
    @Environment(\.openWindow) var openWindow
    @Environment(\.dismiss) var dismiss
    @ObservedObject var wm = WM

    @Default(.labelStyle) var labelStyle

    var body: some Scene {
        Window("Startup Folder", id: "main") {
            ContentView()
                .frame(minWidth: 800, minHeight: 200)
        }
        .defaultSize(width: 800, height: 750)
        .commandsReplaced {
            CommandGroup(after: .help) {
                Button("Check for updates (current version: v\(Bundle.main.version))") {
                    UM.updater?.checkForUpdates()
                }
                .keyboardShortcut("U", modifiers: [.command])
            }
        }
        .onChange(of: wm.windowToOpen) {
            guard let window = wm.windowToOpen, !SWIFTUI_PREVIEW else {
                return
            }
            if window == "main", let mainWindow = NSApp.windows.first(where: { $0.title == "Startup Folder" }) {
                focus()
                mainWindow.orderFrontRegardless()
                wm.windowToOpen = nil
                return
            }

            openWindow(id: window)
            focus()
            NSApp.keyWindow?.orderFrontRegardless()
            wm.windowToOpen = nil
        }

        Settings {
            SettingsView()
                .frame(minWidth: 600, minHeight: 600)
        }
        .defaultSize(width: 600, height: 600)
    }

    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

}
