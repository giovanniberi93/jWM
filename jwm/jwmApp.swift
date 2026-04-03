import SwiftUI
import os

let logger = DualLogger()

struct DualLogger {
    private let osLog = Logger(subsystem: "giober.jwm", category: "general")

    func info(_ message: String) {
        osLog.info("\(message)")
        print("jwm: \(message)")
    }

    func error(_ message: String) {
        osLog.error("\(message)")
        print("jwm: ERROR: \(message)")
    }
}

@main
struct jwmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("jwm", image: "MenuBarIcon") {
            Button("Settings...") {
                SettingsWindowController.shared.show()
            }
            .keyboardShortcut(",")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

/// Manages a standalone settings window for the menu bar app.
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "jWM Settings"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotkeyManager = HotkeyManager()
    private let snapManager = SnapManager()
    private var accessibilityTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!).count > 1 {
            logger.info("Another instance is already running, quitting")
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)

        if AXIsProcessTrusted() {
            logger.info("Accessibility trusted, starting hotkeys")
            startHotkeys()
        } else {
            logger.info("Requesting Accessibility permission...")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            // Poll until permission is granted
            accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    logger.info("Accessibility permission granted")
                    timer.invalidate()
                    self?.accessibilityTimer = nil
                    self?.startHotkeys()
                }
            }
        }
    }

    private func startHotkeys() {
        snapManager.start()
        hotkeyManager.start(
            onFocus: { appKey in
                let bundleID = UserDefaults.standard.string(forKey: "\(appKey)_bundleID") ?? ""
                guard !bundleID.isEmpty else {
                    logger.info("\(appKey) has no app configured")
                    return
                }
                logger.info("Focusing \(appKey) -> \(bundleID)")
                AppFocuser.focusOrLaunch(bundleID: bundleID)
            },
            onTile: { position in
                logger.info("Tiling current window -> \(position)")
                WindowTiler.tile(position)
            },
            onFocusTile: { appKey, position in
                let bundleID = UserDefaults.standard.string(forKey: "\(appKey)_bundleID") ?? ""
                guard !bundleID.isEmpty else {
                    logger.info("\(appKey) has no app configured")
                    return
                }
                logger.info("Tile + focus \(appKey) -> \(bundleID) -> \(position)")
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
                   AppFocuser.appHasWindows(pid: app.processIdentifier) {
                    WindowTiler.tile(position, app: app)
                    app.activate()
                } else {
                    logger.info("App \(bundleID) not running or has no windows, launching + tiling...")
                    AppFocuser.launchAndWaitForWindow(bundleID: bundleID) { app in
                        WindowTiler.tile(position, app: app)
                        app.activate()
                        let expectedRect = WindowTiler.getWindowRect(pid: app.processIdentifier)
                        // Poll briefly: if the app restores its own window state, re-tile
                        DispatchQueue.global(qos: .userInitiated).async {
                            let start = Date()
                            while Date().timeIntervalSince(start) < 0.5 {
                                Thread.sleep(forTimeInterval: 0.05)
                                if let current = WindowTiler.getWindowRect(pid: app.processIdentifier),
                                   current != expectedRect {
                                    logger.info("Window moved after launch, re-tiling")
                                    DispatchQueue.main.async {
                                        WindowTiler.tile(position, app: app)
                                    }
                                    return
                                }
                            }
                        }
                    }
                }
            }
        )
    }
}
