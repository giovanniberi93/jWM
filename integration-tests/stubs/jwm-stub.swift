import AppKit

private struct StubConfig {
    var initialWindows: Int = 1
    var spawnDelayMs: Int = 0
    var driftBackTimes: Int = 0
    var driftBackDelayMs: Int = 50
}

private func parseConfig(_ argv: [String]) -> StubConfig {
    var c = StubConfig()
    func intArg(_ name: String) -> Int? {
        guard let i = argv.firstIndex(of: name), i + 1 < argv.count else { return nil }
        return Int(argv[i + 1])
    }
    if let v = intArg("--windows") { c.initialWindows = max(0, v) }
    if let v = intArg("--spawn-delay-ms") { c.spawnDelayMs = max(0, v) }
    if let v = intArg("--drift-back-times") { c.driftBackTimes = max(0, v) }
    if let v = intArg("--drift-back-delay-ms") { c.driftBackDelayMs = max(0, v) }
    return c
}

private func framesNearlyEqual(_ a: NSRect, _ b: NSRect, tolerance: CGFloat = 1) -> Bool {
    abs(a.origin.x - b.origin.x) < tolerance
        && abs(a.origin.y - b.origin.y) < tolerance
        && abs(a.size.width - b.size.width) < tolerance
        && abs(a.size.height - b.size.height) < tolerance
}

// Mimics Electron-style async drift: after every external frame change, wait
// briefly (so jwm's 3-op size→pos→size sequence settles) then snap back to
// the window's preferred frame, up to `remainingReverts` times. Exists so
// integration tests can exercise WindowAX.guardPosition without depending on
// a real Electron build.
final class DriftWindowDelegate: NSObject, NSWindowDelegate {
    private weak var window: NSWindow?
    private let preferredFrame: NSRect
    private var remainingReverts: Int
    private let debounceMs: Int
    private var pending: DispatchWorkItem?

    init(window: NSWindow, preferredFrame: NSRect, remainingReverts: Int, debounceMs: Int) {
        self.window = window
        self.preferredFrame = preferredFrame
        self.remainingReverts = remainingReverts
        self.debounceMs = debounceMs
    }

    func windowDidResize(_ note: Notification) { scheduleRevert() }
    func windowDidMove(_ note: Notification) { scheduleRevert() }

    private func scheduleRevert() {
        guard remainingReverts > 0, let w = window else { return }
        if framesNearlyEqual(w.frame, preferredFrame) { return }
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, let w = self.window else { return }
            guard self.remainingReverts > 0 else { return }
            if framesNearlyEqual(w.frame, self.preferredFrame) { return }
            self.remainingReverts -= 1
            w.setFrame(self.preferredFrame, display: true, animate: false)
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(debounceMs), execute: item)
    }
}

final class StubAppDelegate: NSObject, NSApplicationDelegate {
    private let config: StubConfig
    private var windows: [NSWindow] = []
    private var windowDelegates: [DriftWindowDelegate] = []
    private var sigSource: DispatchSourceSignal?

    fileprivate init(config: StubConfig) {
        self.config = config
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if config.spawnDelayMs > 0 {
            // Fire activation while still windowless so jwm's guardActivation
            // and launchAndWaitForWindow hit their poll-until-window-appears
            // paths.
            NSApp.activate(ignoringOtherApps: true)
            spawnInitialWindows()
        } else {
            spawnInitialWindows()
            NSApp.activate(ignoringOtherApps: true)
        }
        installSignalHandler()
    }

    private func spawnInitialWindows() {
        let n = config.initialWindows
        guard n > 0 else { return }
        for _ in 0..<n { spawnWindow() }
    }

    // SIGUSR1 → spawn a window. Lets tests grow a stub past its initial
    // window count without restarting the process (warm `open -b` ignores
    // --windows). Test harness: `kill -USR1 <pid>`. Bypasses --spawn-delay-ms
    // so existing tests that USR1-then-poll don't slow down.
    private func installSignalHandler() {
        signal(SIGUSR1, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        src.setEventHandler { [weak self] in
            self?.actuallySpawnWindow()
        }
        src.resume()
        sigSource = src
    }

    // `open -b <bundle>` on an already-running app with no visible windows
    // routes here. Spawning a window keeps victim_launch idempotent without
    // per-app AppleScript hacks.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            spawnWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // Routed through this so --spawn-delay-ms applies uniformly to the
    // initial cohort and to applicationShouldHandleReopen-spawned windows
    // (the path that exercises launchAndWaitForWindow's poll loop).
    private func spawnWindow() {
        if config.spawnDelayMs > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(config.spawnDelayMs)) { [weak self] in
                self?.actuallySpawnWindow()
            }
        } else {
            actuallySpawnWindow()
        }
    }

    private func actuallySpawnWindow() {
        let idx = windows.count
        let bundleName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Stub"
        let offset = CGFloat(idx) * 28
        let w = NSWindow(
            contentRect: NSRect(x: 200 + offset, y: 200 + offset, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "\(bundleName) #\(idx + 1)"
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        windows.append(w)

        if config.driftBackTimes > 0 {
            // NSWindow.delegate is unowned; retain the delegate ourselves.
            let d = DriftWindowDelegate(
                window: w,
                preferredFrame: w.frame,
                remainingReverts: config.driftBackTimes,
                debounceMs: config.driftBackDelayMs
            )
            w.delegate = d
            windowDelegates.append(d)
        }
    }
}

let app = NSApplication.shared
let delegate = StubAppDelegate(config: parseConfig(CommandLine.arguments))
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
