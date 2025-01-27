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
    deinit {
        NSWorkspace.shared.removeObserver(self, forKeyPath: #keyPath(NSWorkspace.runningApplications))
    }

    var window: NSWindow?

    // if env contains login=true
    var isLaunchedAtLogin = ProcessInfo.processInfo.environment["login"] == "true"
    var launchTimestamp = Date()

    var mainWindow: NSWindow? {
        NSApp.windows.first { $0.title == "Startup Folder" }
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
            NSApp.setActivationPolicy(.accessory)
            mainWindow?.close()
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
        NSWorkspace.shared.addObserver(self, forKeyPath: #keyPath(NSWorkspace.runningApplications), options: [.new, .old], context: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeMain(_:)), name: NSWindow.didBecomeMainNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willCloseNotification(_:)), name: NSWindow.willCloseNotification, object: nil)
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
            guard let oldApps = change?[.oldKey] as? [NSRunningApplication],
                  let newApps = change?[.newKey] as? [NSRunningApplication]
            else {
                return
            }
            let terminatedApps = oldApps.filter { !newApps.contains($0) }
            for terminatedApp in terminatedApps {
                guard let item = SM.startupItems.first(where: { $0.app?.processIdentifier == terminatedApp.processIdentifier }) else {
                    continue
                }
                if item.status != .terminated {
                    item.status = .succeeded
                }
                item.app = nil
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
                for url in urls {
                    if url.pathExtension == "link", let fileURL = try (String(contentsOf: url)).url {
                        NSWorkspace.shared.open(fileURL)
                    }
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
        }
    }

    @objc func willCloseNotification(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window.title == "Startup Folder" {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc func applicationDidTerminate(_ notification: Notification) {
        guard let terminatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        for item in SM.startupItems {
            if item.app?.processIdentifier == terminatedApp.processIdentifier {
                if item.status != .terminated {
                    item.status = .succeeded
                }
                item.app = nil
            }
        }
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
        .commands {
            CommandMenu("Startup Folder") {
                Button("Check for Updates") {
                    UM.updater?.checkForUpdates()
                }
                .keyboardShortcut("U", modifiers: [.command, .shift])
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
                .frame(minWidth: 600, minHeight: 200)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 600, height: 500)
    }

    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

}
