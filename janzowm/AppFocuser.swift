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
            logger.info("launchAndWaitForWindow: urlForApplication returned nil for \(bundleID)")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        // Resolve the path once; the wait loop may need to reissue the
        // LaunchServices call if a quitting instance swallowed our first one.
        let resolvedPath: String? = {
            guard let path, !path.isEmpty else { return nil }
            let expanded = (path as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expanded) else {
                logger.info("Path missing for \(bundleID): \(expanded) — launching without path")
                return nil
            }
            return expanded
        }()

        // Single dispatch closure so the wait loop can re-issue the launch
        // if the running pid we were waiting on disappears (cmd+Q tear-down
        // in flight when LS routed our open).
        func dispatchLaunch(reason: String) {
            if let expanded = resolvedPath {
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = true
                logger.info("LaunchServices open \(bundleID) at \(url.path) with path \(expanded)\(reason)")
                NSWorkspace.shared.open(
                    [URL(fileURLWithPath: expanded)],
                    withApplicationAt: url,
                    configuration: cfg
                ) { app, error in
                    if let error = error {
                        logger.error("LaunchServices open(\(bundleID), path: \(expanded)) failed: \(error.localizedDescription)")
                    } else {
                        logger.info("LaunchServices open(\(bundleID), path: \(expanded)) → pid=\(app?.processIdentifier ?? -1)")
                    }
                }
            } else {
                logger.info("LaunchServices openApplication \(bundleID) at \(url.path)\(reason)")
                NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                    if let error = error {
                        logger.error("LaunchServices openApplication(\(bundleID)) failed: \(error.localizedDescription)")
                    }
                }
            }
        }

        // Capture the pid we observed before we asked LS to open. If this
        // pid disappears mid-wait, we know our LS event was routed into a
        // quitting instance and we need to reissue against a fresh launch.
        let initialPid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier ?? -1
        dispatchLaunch(reason: "")

        DispatchQueue.global(qos: .userInitiated).async {
            let start = Date()
            var didRetry = false
            while Date().timeIntervalSince(start) < timeout {
                let runningNow = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
                if let app = runningNow, appHasWindows(pid: app.processIdentifier) {
                    DispatchQueue.main.async {
                        completion(app)
                    }
                    return
                }
                // If we had an existing pid before we issued the open and it
                // has now exited (e.g. IntelliJ's ~3-4s post-cmd+Q tear-down
                // was still in flight when LS routed our open into it), the
                // first LS event was dropped — reissue. Only once, to avoid
                // any infinite loops if relaunch keeps failing.
                if !didRetry, initialPid > 0, runningNow == nil {
                    didRetry = true
                    logger.info("\(bundleID) (pid=\(initialPid)) exited during wait — reissuing LaunchServices launch")
                    DispatchQueue.main.async {
                        dispatchLaunch(reason: " (retry after quit)")
                    }
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            // Cross-check via Quartz: AX may miss windows for an app that's
            // still loading (splash/welcome) where the welcome view isn't a
            // kAXWindow. Quartz sees what WindowServer sees, so it's the
            // tiebreaker when we hit the timeout.
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            let pid = running?.processIdentifier ?? -1
            let quartzCount = pid > 0 ? QuartzWindowList.windowsForPid(pid).count : 0
            logger.info("Timed out waiting for \(bundleID) window — running=\(running != nil) pid=\(pid) quartzWindows=\(quartzCount)")
            DispatchQueue.main.async {
                // Activate-on-timeout preserves prior behavior so the user at
                // least lands in the app; caller still gets nil so it can run
                // any cleanup.
                running?.activate()
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
            logger.info("LaunchServices open \(bundleID) at \(appURL.path) with path \(expanded) (running, has windows)")
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: cfg) { opened, error in
                if let error = error {
                    logger.error("LaunchServices open(\(bundleID), path: \(expanded)) failed: \(error.localizedDescription)")
                } else {
                    logger.info("LaunchServices open(\(bundleID), path: \(expanded)) → pid=\(opened?.processIdentifier ?? -1)")
                }
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
