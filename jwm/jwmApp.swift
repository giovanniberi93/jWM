import SwiftUI
import os

let logger = DualLogger()

struct DualLogger {
    private let osLog = Logger(subsystem: BundleIDs.releaseBundleID, category: "general")
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

    init() {
        // When stdout is a pipe/file (e.g. `make test-integration` redirects to
        // a log file), it block-buffers by default and the early startup lines
        // never appear before the harness kills the process. Force line buffering.
        setvbuf(stdout, nil, _IOLBF, 0)
    }

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
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var didInitialSize = false
    private var escMonitor: Any?

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "jWM Settings"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self

        let view = SettingsView { [weak self, weak window] height in
            guard let self, let window else { return }
            self.applyContentHeight(height, window: window)
        }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 760, height: 1200)
        hosting.layoutSubtreeIfNeeded()
        let initialContentHeight = hosting.fittingSize.height
        let initialFrame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 760, height: initialContentHeight))
        window.setFrame(initialFrame, display: false)
        window.contentView = hosting
        didInitialSize = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard event.keyCode == 53, let window, event.window === window else { return event }
            window.close()
            _ = self
            return nil
        }
    }

    private func applyContentHeight(_ contentHeight: CGFloat, window: NSWindow) {
        guard contentHeight > 1 else { return }
        let targetContentSize = NSSize(width: 760, height: contentHeight)
        let targetFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize))
        let current = window.frame
        guard abs(current.size.height - targetFrame.size.height) > 0.5 else { return }
        var newFrame = current
        let delta = targetFrame.size.height - current.size.height
        newFrame.size = targetFrame.size
        newFrame.origin.y -= delta
        if didInitialSize {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: false)
        }
    }

    var sheetParentWindow: NSWindow? { window }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === self.window else { return }
        // Don't close while presenting a sheet (e.g. NSOpenPanel from app picker).
        // The parent resigns key when the sheet attaches; we want it back when sheet ends.
        guard window.attachedSheet == nil else { return }
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
        }
        escMonitor = nil
        window = nil
        didInitialSize = false
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotkeyManager = HotkeyManager()
    private let snapManager = SnapManager()
    private var accessibilityTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dev/debug and installed builds have different bundle ids but both
        // register a global event tap, so any two running instances fight over
        // hotkeys. Count across both ids and bail if anyone else is up.
        let bundleIDs = [BundleIDs.releaseBundleID, BundleIDs.integrationTestBundleID]
        let total = bundleIDs.reduce(0) { $0 + NSRunningApplication.runningApplications(withBundleIdentifier: $1).count }
        if total > 1 {
            logger.info("Another jwm instance is already running, quitting")
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

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            logger.info("App activated: \(app.localizedName ?? app.bundleIdentifier ?? "unknown")")
            WindowTiler.guardActivation(app: app)
        }

        hotkeyManager.start(
            onFocus: { appKey in
                let bundleID = UserDefaults.standard.string(forKey: "\(appKey)_bundleID") ?? ""
                guard !bundleID.isEmpty else {
                    logger.info("\(appKey) has no app configured")
                    return
                }
                logger.info("Focusing \(appKey) -> \(bundleID)")
                UsageStats.record(.focus)
                AppFocuser.focusOrLaunch(bundleID: bundleID)
                // No explicit snapshot of the new app: NSWorkspace activation
                // notification will fire and guardActivation handles it.
            },
            onTile: { position in
                UsageStats.record(.tile)
                WindowTiler.tile(position)
            },
            onFocusTile: { appKey, position in
                let bundleID = UserDefaults.standard.string(forKey: "\(appKey)_bundleID") ?? ""
                guard !bundleID.isEmpty else {
                    logger.info("\(appKey) has no app configured")
                    return
                }
                logger.info("Tile + focus \(appKey) -> \(bundleID) -> \(position)")
                UsageStats.record(.focusTile)
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
                   AppFocuser.appHasWindows(pid: app.processIdentifier) {
                    WindowTiler.tile(position, app: app)
                    app.activate()
                } else {
                    logger.info("App \(bundleID) not running or has no windows, launching + tiling...")
                    AppFocuser.launchAndWaitForWindow(bundleID: bundleID) { app in
                        WindowTiler.tile(position, app: app)
                        app.activate()
                        WindowAX.guardPosition(pid: app.processIdentifier) {
                            WindowTiler.tile(position, app: app)
                        }
                    }
                }
            },
            onLaunchAll: {
                AppFocuser.launchAllConfigured()
            },
            onBeforeAction: {
                // Snapshot the current frontmost app right before any focus/tile
                // action, so its fullscreen state is captured even when no
                // NSWorkspace activation event would fire (e.g. ctrl+cmd+J on the
                // already-focused app, followed immediately by a chord).
                if let front = NSWorkspace.shared.frontmostApplication {
                    WindowTiler.snapshotIfFullScreen(app: front)
                }
            }
        )
    }
}
