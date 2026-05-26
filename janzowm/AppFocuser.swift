import AppKit

enum AppFocuser {
    /// Focus a running app or launch it if not running.
    static func focusOrLaunch(bundleID: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            // If the app is running but has no windows (e.g. Chrome with all windows closed),
            // activate alone just shows the menu bar. Re-open the app to trigger a new window,
            // which is what Spotlight does.
            let hasWindows = appHasWindows(pid: app.processIdentifier)
            if hasWindows {
                app.activate()
            } else {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                    app.activate()
                    return
                }
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        } else {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    /// Launch (or focus) every app configured in any slot, tiling each
    /// fullscreen. Used by the "launch all" chord to bring up a startup
    /// workspace in one keystroke. Already-running apps are also fullscreened.
    static func launchAllConfigured() {
        let defaults = UserDefaults.standard
        var seen = Set<String>()
        for slot in 0...9 {
            for prefix in ["app\(slot)", "shiftApp\(slot)"] {
                let bundleID = defaults.string(forKey: "\(prefix)_bundleID") ?? ""
                guard !bundleID.isEmpty, seen.insert(bundleID).inserted else { continue }
                logger.info("Launch-all: \(bundleID)")
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
                   appHasWindows(pid: app.processIdentifier) {
                    WindowTiler.tile(.fullScreen, app: app)
                    app.activate()
                } else {
                    launchAndWaitForWindow(bundleID: bundleID) { app in
                        guard let app = app else { return }
                        WindowTiler.tile(.fullScreen, app: app)
                        app.activate()
                        WindowAX.guardPosition(pid: app.processIdentifier) {
                            WindowTiler.tile(.fullScreen, app: app)
                        }
                    }
                }
            }
        }
    }

    /// Launch an app and wait for its window to appear. The completion is
    /// always invoked on the main thread — with the app on success, or `nil`
    /// on timeout / bundle-not-found. Callers can rely on this to release any
    /// per-launch state (e.g. WindowTiler.suppressDisplaceForBundleID) without
    /// resorting to delay-based safety nets.
    static func launchAndWaitForWindow(
        bundleID: String,
        path: String? = nil,
        timeout: TimeInterval = 10.0,
        completion: @escaping (NSRunningApplication?) -> Void
    ) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        // With a launch path, route through `open(urls:withApplicationAt:)`
        // so macOS LaunchServices opens the document/folder in a new window —
        // matches `open -a <App> <path>`. Missing path → plain launch.
        if let path,
           !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = true
                NSWorkspace.shared.open([URL(fileURLWithPath: expanded)], withApplicationAt: url, configuration: cfg)
            } else {
                logger.info("Path missing for \(bundleID): \(expanded) — launching without path")
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        } else {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let start = Date()
            while Date().timeIntervalSince(start) < timeout {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
                   appHasWindows(pid: app.processIdentifier) {
                    DispatchQueue.main.async {
                        completion(app)
                    }
                    return
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            logger.info("Timed out waiting for \(bundleID) window")
            DispatchQueue.main.async {
                // Activate-on-timeout preserves prior behavior so the user at
                // least lands in the app; caller still gets nil so it can run
                // any cleanup.
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
                completion(nil)
            }
        }
    }

    /// Focus/launch with an optional launch path. When `path` is set we
    /// route through `NSWorkspace.open(_:withApplicationAt:configuration:)`
    /// so macOS LaunchServices opens the document/folder in a new window —
    /// matches `open -a <App> <path>` semantics. Missing path falls back to
    /// plain focus + an info log so the user is never blocked.
    ///
    /// For the running-but-window-less case (e.g. IntelliJ with no project
    /// open), we route through `launchAndWaitForWindow(path:)` and activate
    /// only once a window appears. Calling `cfg.activates = true` against an
    /// app with no current window can bounce focus to the next app while the
    /// target's window is still being constructed; waiting for a real window
    /// eliminates that race.
    static func focusOrLaunch(bundleID: String, path: String?) {
        guard let path, !path.isEmpty else {
            focusOrLaunch(bundleID: bundleID)
            return
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            focusOrLaunch(bundleID: bundleID)
            return
        }
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            logger.info("Path missing for \(bundleID): \(expanded) — launching without path")
            focusOrLaunch(bundleID: bundleID)
            return
        }
        let fileURL = URL(fileURLWithPath: expanded)

        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           appHasWindows(pid: app.processIdentifier) {
            // Running with at least one window — open the path (LaunchServices
            // routes it to the app to spawn a new window for the document) and
            // explicitly activate as belt-and-braces.
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: cfg) { _, _ in
                DispatchQueue.main.async { app.activate() }
            }
            return
        }

        // Not running, or running with no windows: wait for the path to
        // actually open a window, then activate.
        launchAndWaitForWindow(bundleID: bundleID, path: path) { app in
            app?.activate()
        }
    }

    /// Check if a process has any on-screen windows via the Accessibility API.
    static func appHasWindows(pid: pid_t) -> Bool {
        let appRef = makeApplicationAXElement(pid: pid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            return false
        }
        return !windows.isEmpty
    }
}
