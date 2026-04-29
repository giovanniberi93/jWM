import AppKit

final class StubAppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private let initialWindows: Int
    private var sigSource: DispatchSourceSignal?

    init(initialWindows: Int) {
        self.initialWindows = max(1, initialWindows)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        for _ in 0..<initialWindows {
            spawnWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        installSignalHandler()
    }

    // SIGUSR1 → spawn a window. Lets tests grow a stub past its initial
    // window count without restarting the process (warm `open -b` ignores
    // --windows). Test harness: `kill -USR1 <pid>`.
    private func installSignalHandler() {
        signal(SIGUSR1, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        src.setEventHandler { [weak self] in
            self?.spawnWindow()
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

    private func spawnWindow() {
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
    }
}

let argv = CommandLine.arguments
var initialWindows = 1
if let i = argv.firstIndex(of: "--windows"), i + 1 < argv.count, let parsed = Int(argv[i + 1]) {
    initialWindows = parsed
}

let app = NSApplication.shared
let delegate = StubAppDelegate(initialWindows: initialWindows)
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
