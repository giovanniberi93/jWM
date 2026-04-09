import SwiftUI
import os

let logger = DualLogger()

struct DualLogger {
    private let osLog = Logger(subsystem: "com.giovanniberi93.jwm", category: "general")
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private var timestamp: String { formatter.string(from: Date()) }

    func info(_ message: String) {
        osLog.info("\(message)")
        print("[\(timestamp)] jwm: \(message)")
    }

    func error(_ message: String) {
        osLog.error("\(message)")
        print("[\(timestamp)] jwm: ERROR: \(message)")
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
/// Pauses the global event tap while the window is open to avoid lag in system panels.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    weak var hotkeyManager: HotkeyManager?
    weak var snapManager: SnapManager?

    func show() {
        hotkeyManager?.pause()
        snapManager?.pause()

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
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        hotkeyManager?.resume()
        snapManager?.resume()
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
        SettingsWindowController.shared.hotkeyManager = hotkeyManager
        SettingsWindowController.shared.snapManager = snapManager

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

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            logger.info("App activated: \(app.localizedName ?? app.bundleIdentifier ?? "unknown")")
            WindowTiler.promoteIfFullScreen(app: app)
        }

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
                        WindowTiler.guardPosition(pid: app.processIdentifier) {
                            WindowTiler.tile(position, app: app)
                        }
                    }
                }
            }
        )
    }
}
