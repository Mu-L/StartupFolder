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
        if !SWIFTUI_PREVIEW, let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != NSRunningApplication.current.processIdentifier }) {
            #if DEBUG
                app.forceTerminate()
            #else
                app.activate()
                NSApp.terminate(nil)
            #endif
            return
        }

        super.applicationDidFinishLaunching(notification)
        setupCleanup()
        UM.updater = updateController.updater
        setupLaunchAtLogin()
        SM.setupStartupFolder()
        SM.loadStartupItems()
        SM.watchStartupFolder()
        if isLaunchedAtLogin {
            NSApp.setActivationPolicy(.accessory)
            mainWindow?.close()
            SM.launchStartupItems()
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

        if let mainWindow {
            focus()
            mainWindow.orderFrontRegardless()
        } else {
            WM.open("main")
        }
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
        WindowGroup("Startup Folder", id: "main") {
            ContentView()
                .frame(minWidth: 800, minHeight: 200)
        }
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandMenu("Startup Folder") {
                Button("Check for Updates") {
                    UM.updater?.checkForUpdates()
                }
                .keyboardShortcut("U", modifiers: [.command, .shift])
            }
        }
        .onChange(of: wm.windowToOpen) {
            guard let window = wm.windowToOpen else {
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
