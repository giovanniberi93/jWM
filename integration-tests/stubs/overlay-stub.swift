import AppKit

// Test-only overlay app. Creates one borderless, transparent, mouse-ignoring
// window per screen at level 21 covering the entire screen frame. The whole
// point is to recreate the production Quartz/AX bug condition deterministically
// in integration tests:
//
//   - Level 21 is below `notificationCenterLevel` (23), so it PASSES
//     `QuartzWindowList.windowAtPoint`'s filter.
//   - processName isn't "Dock"/"WindowManager", so it also passes that filter.
//   - Bundle id `com.giovanniberi93.jwm.overlay` is in SnapManager's
//     `ignoredBundleIDs`, so `getWindowInfoUnderCursor` rejects this hit.
//   - That short-circuits `.first(where:)` before reaching the real victim
//     stub underneath — exactly the failure mode triggered in the wild by
//     Notification Center sitting over the click point.
//
// Mouse-tests launch this app before drags so the AX hit-test fallback in
// `getWindowInfoUnderCursor` is exercised on every mouseDown. Invisible to
// the user: clear backing, `ignoresMouseEvents = true`, no menu bar/dock entry.

final class OverlayAppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        for screen in NSScreen.screens {
            let w = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = NSWindow.Level(21)
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.setFrame(screen.frame, display: false)
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

let app = NSApplication.shared
let delegate = OverlayAppDelegate()
app.delegate = delegate
// Accessory policy: no Dock icon, no menu bar — keeps the test environment
// quiet. The window is still listed by CGWindowListCopyWindowInfo regardless.
app.setActivationPolicy(.accessory)
app.run()
