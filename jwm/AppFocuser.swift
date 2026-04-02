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

    /// Launch an app and wait for its window to appear, then call completion on the main thread.
    static func launchAndWaitForWindow(
        bundleID: String,
        timeout: TimeInterval = 10.0,
        completion: @escaping (NSRunningApplication) -> Void
    ) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())

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
            // Timeout: activate without tiling
            logger.info("Timed out waiting for \(bundleID) window")
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                DispatchQueue.main.async {
                    app.activate()
                }
            }
        }
    }

    /// Check if a process has any on-screen windows via the Accessibility API.
    private static func appHasWindows(pid: pid_t) -> Bool {
        let appRef = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            return false
        }
        return !windows.isEmpty
    }
}
