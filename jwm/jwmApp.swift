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
        positionNearTop(window)
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

    private func positionNearTop(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? window.screen
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            window.center()
            return
        }
        var f = window.frame
        f.origin.x = visible.midX - f.size.width / 2
        let topInset: CGFloat = 10
        f.origin.y = visible.maxY - f.size.height - topInset
        if f.origin.y < visible.minY { f.origin.y = visible.minY }
        window.setFrame(f, display: false)
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
    /// Retained so the SIGUSR1 handler keeps firing — DispatchSourceSignal
    /// is cancelled when its last strong reference drops.
    private var slotResetSignalSource: DispatchSourceSignal?

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
        installSlotResetSignalHandler()

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
                OnboardingCoordinator.shared.observeAction(.focus(slotKey: appKey))
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
                    // Block guardActivation's displaceIfHalf from acting on
                    // the launching app's restored geometry — our tile() below
                    // owns positioning for this chord. The flag is cleared in
                    // the completion (deterministic: main queue is serial, so
                    // no displaceIfHalf can interleave between entry and exit,
                    // and by exit the window is at the chord's target).
                    WindowTiler.suppressDisplaceForBundleID = bundleID
                    AppFocuser.launchAndWaitForWindow(bundleID: bundleID) { app in
                        defer {
                            if WindowTiler.suppressDisplaceForBundleID == bundleID {
                                WindowTiler.suppressDisplaceForBundleID = nil
                            }
                        }
                        guard let app = app else { return }
                        WindowTiler.tile(position, app: app)
                        app.activate()
                        WindowAX.guardPosition(pid: app.processIdentifier) {
                            WindowTiler.tile(position, app: app)
                        }
                    }
                }
                OnboardingCoordinator.shared.observeAction(.focusTile(slotKey: appKey, position: position))
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
            },
            onAbortIntegrationTests: {
                // Bailout for a wedged integration test run: nuke every
                // known stub and shut jwm down. Stubs are matched against
                // BundleIDs.integrationTestStubBundleIDs (a fixed list) so
                // this can't ever kill a user-owned app — only the known
                // test victims.
                logger.error("Aborting integration tests — terminating stubs and exiting jwm")
                for bundleID in BundleIDs.integrationTestStubBundleIDs {
                    for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                        logger.info("Abort: terminating \(app.localizedName ?? bundleID) (pid=\(app.processIdentifier))")
                        app.terminate()
                    }
                }
                NSApp.terminate(nil)
            }
        )

        // Surface the onboarding tutorial once hotkeys are running so the
        // chord-rehearsal steps can actually fire. Skipped if the user has
        // already finished the tutorial in a prior session.
        OnboardingCoordinator.shared.presentIfFirstRun()
    }

    /// Listen for SIGUSR1 → clear `WindowTiler.slots`. The integration test
    /// harness fires this between cases so a stale fullscreen entry recorded
    /// for a user-owned app (typically the developer's terminal, which sits
    /// at the fullscreen rect while the suite runs) can't bleed into the
    /// next test as a phantom displacement candidate. We always honor the
    /// signal — even outside test mode, since clearing slots is harmless —
    /// but log an error if `integrationTestMode` isn't set so an accidental
    /// `kill -USR1` against a normal user session is visible in the log.
    private func installSlotResetSignalHandler() {
        // DispatchSource.makeSignalSource requires the default disposition be
        // SIG_IGN, otherwise the kernel still delivers the signal via the
        // C-level handler and terminates us.
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler {
            let isIntegrationTest = UserDefaults.standard.bool(forKey: "integrationTestMode")
            if !isIntegrationTest {
                logger.error("SIGUSR1: WindowTiler state reset requested outside integrationTestMode — proceeding, but this signal is only expected from the integration-test harness.")
            } else {
                logger.info("SIGUSR1: resetting WindowTiler state for next integration test")
            }
            WindowTiler.resetForIntegrationTest()
        }
        source.resume()
        slotResetSignalSource = source
    }
}
