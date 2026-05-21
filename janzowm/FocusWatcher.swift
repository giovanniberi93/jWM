import Cocoa
import ApplicationServices

/// Per-pid AX observer that catches focus changes *within* a single app, which
/// `NSWorkspace.didActivateApplicationNotification` does not see. Cmd+`,
/// clicking a background window of the focused app, picking a window from the
/// Window menu, and Mission Control window picks all change the focused
/// window without firing a cross-app activation. Without this watcher, janzowm
/// has no chance to react — a half-tiled sibling coming forward over a
/// fullscreen window won't displace it.
///
/// Mechanism: `AXObserverCreate` per regular app, subscribed to
/// `kAXFocusedWindowChangedNotification` on its `AXUIElementCreateApplication`.
/// Handler routes into `WindowTiler.onFocusChanged` — same entry point the
/// NSWorkspace path uses. The `prev.pid != app.pid` early-return inside
/// onFocusChanged makes the call safe for intra-app re-entry (no spurious
/// defocus snapshot).
///
/// Lifecycle is driven by NSWorkspace launch/terminate notifications. The
/// observer map holds AXObserver strongly; dropping the entry releases the
/// CFRunLoop source automatically.
final class FocusWatcher {
    static let shared = FocusWatcher()

    private var observers: [pid_t: AXObserver] = [:]
    /// Last focused window id we saw per pid. Used to short-circuit the
    /// occasional duplicate fire — AX has been observed to emit the same
    /// kAXFocusedWindowChangedNotification twice when an app activates and
    /// its focused window happens to be the one it was already on.
    private var lastFocusedWindowID: [pid_t: CGWindowID] = [:]

    func start() {
        let ws = NSWorkspace.shared
        for app in ws.runningApplications where app.activationPolicy == .regular {
            attach(app)
        }
        ws.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }
            FocusWatcher.shared.attach(app)
        }
        ws.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            FocusWatcher.shared.detach(pid: app.processIdentifier)
        }
        logger.info("FocusWatcher: attached to \(self.observers.count) apps at start")
    }

    private func attach(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        // If we already have an entry for this pid, tear it down first. Two
        // cases hit this path: (a) a duplicate didLaunch for the same launch
        // (idempotent re-attach), (b) we missed a didTerminate and the pid
        // got reused by a new launch — in which case the old observer targets
        // a dead pid and the new one needs a fresh observer to actually
        // receive notifications.
        if observers[pid] != nil {
            detach(pid: pid)
        }

        var observer: AXObserver?
        let cb: AXObserverCallback = { _, _, _, refcon in
            guard let refcon = refcon else { return }
            let pid = pid_t(Int(bitPattern: refcon))
            DispatchQueue.main.async {
                FocusWatcher.shared.handleFocusChange(pid: pid)
            }
        }
        let createErr = AXObserverCreate(pid, cb, &observer)
        guard createErr == .success, let observer else {
            // Apps without AX support (e.g. some helper processes) fail
            // creation. Not actionable; log and move on.
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = UnsafeMutableRawPointer(bitPattern: Int(pid))
        let addErr = AXObserverAddNotification(
            observer,
            appElement,
            kAXFocusedWindowChangedNotification as CFString,
            refcon
        )
        // .cannotComplete is common for apps that haven't finished launching
        // their AX tree yet; the didLaunch path catches them later via re-attach
        // only if they restart, so we accept the gap for now (matches "keep it
        // easy" — debouncing/retry is the next iteration).
        guard addErr == .success else { return }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        observers[pid] = observer
    }

    private func detach(pid: pid_t) {
        observers[pid] = nil
        lastFocusedWindowID[pid] = nil
    }

    private func handleFocusChange(pid: pid_t) {
        // Only act when the event is for the *frontmost* app. Focus shuffles
        // inside background apps (e.g. an editor that flips focused doc on
        // load) shouldn't trigger displacement.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }

        let wid = WindowAX.getFocusedWindowId(pid: pid) ?? 0
        if lastFocusedWindowID[pid] == wid { return }
        lastFocusedWindowID[pid] = wid

        logger.info("FocusWatcher: focused window changed in \(app.localizedName ?? "?") pid=\(pid) wid=\(wid)")
        WindowTiler.onFocusChanged(app: app)
    }
}
