#!/usr/bin/env swift
//
// survey-tutorial-apps.swift — for each .app bundle in /Applications, launch
// the app, then ask its front window via Accessibility (the same path
// janzowm/WindowAX.swift uses) to occupy the left half / right half / full
// visibleFrame of the primary screen. Apps whose resulting rect doesn't match
// the requested rect within tolerance are logged to excluded-apps.txt; apps
// that fail to launch or never expose a window go to unverifiable-apps.txt.
//
// All knobs are static constants below — edit the source to tune.
//

import Cocoa
import ApplicationServices
import Darwin

// AppKit needs a shared NSApplication for `NSScreen.visibleFrame` to include
// the menu bar inset on secondary screens — same reason screen-info-helper.swift
// instantiates it. Harmless on a single-display setup.
_ = NSApplication.shared

// MARK: - Static config

let APPS_DIRS = [
    "/System/Applications",
    "/Applications",
    "~/Applications",
]
// Debug: when set, ignore APPS_DIRS and test exactly this one bundle ID.
// Resolved via NSWorkspace so apps in /System/Applications work too. Set to
// nil for a normal full-/Applications survey.
let ONLY_BUNDLE_ID: String? = nil
let EXCLUDED_PATH = "\(FileManager.default.currentDirectoryPath)/excluded-apps.txt"
let UNVERIFIABLE_PATH = "\(FileManager.default.currentDirectoryPath)/unverifiable-apps.txt"
let INCLUDED_PATH = "\(FileManager.default.currentDirectoryPath)/included-apps.txt"

let LAUNCH_TIMEOUT: TimeInterval = 10
let SETTLE_AFTER_ACTIVATE: TimeInterval = 0.2
let ASSERT_POLL_SECONDS: TimeInterval = 1.0
let SENTINEL_SETTLE: TimeInterval = 0.05
// After the first window appears, wait this long for additional windows
// (welcome dialogs, "what's new", template choosers) to show up. >1 window
// at startup makes the front-window target ambiguous and is a strong signal
// the app is unfit for the tutorial.
let MULTI_WINDOW_GRACE: TimeInterval = 0.8

// Position tolerance is absolute px; size tolerance is a fraction of the
// expected dimension. Stricter than test-lib.sh (20 / 15%) because we're
// surveying compliance, not running CI under AX latency.
let POS_TOLERANCE_PX: CGFloat = 15
let SIZE_TOLERANCE_PCT: Double = 0.10

// Bundle IDs we never want to launch from a survey: setup wizards,
// installers, anything that hijacks the user's session. Logged to
// excluded-apps.txt so the final exclusion list captures them automatically.
let DENYLISTED_BUNDLES: Set<String> = [
    "com.apple.MigrationAssistant",
    "com.apple.bootcampassistant",
    "com.apple.installer",
    "com.apple.FeedbackAssistant",
    "com.apple.ScreenSharing",
    "com.apple.RemoteDesktop",
]

// MARK: - Geometry (mirrors janzowm/Coords.rect(for:on:))

enum Position: String, CaseIterable { case left, right, full }

func expectedCGRect(_ pos: Position, screen: NSScreen) -> CGRect {
    let f = screen.visibleFrame
    let primaryH = NSScreen.screens[0].frame.height
    let ak: NSRect
    switch pos {
    case .left:
        ak = NSRect(x: f.origin.x, y: f.origin.y, width: f.width / 2, height: f.height)
    case .right:
        ak = NSRect(x: f.origin.x + f.width / 2, y: f.origin.y, width: f.width / 2, height: f.height)
    case .full:
        ak = f
    }
    return CGRect(x: ak.origin.x, y: primaryH - ak.origin.y - ak.height, width: ak.width, height: ak.height)
}

// MARK: - AX I/O (mirrors janzowm/WindowAX)

enum AX {
    static func appElement(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    /// Front window or first window. Same fallback chain as WindowAX.getRect.
    static func frontWindow(of appRef: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &ref) == .success,
           let r = ref {
            return (r as! AXUIElement)
        }
        var listRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &listRef) == .success,
           let arr = listRef as? [AXUIElement], let first = arr.first {
            return first
        }
        return nil
    }

    /// The window we want to *tile*. janzowm uses focusedWindow because it's
    /// driven by the user's intent, but a survey running unattended can't
    /// trust focus — apps like Chess put a "New Game" dialog on top at
    /// launch, and the dialog becomes the focused window. Tile that and it
    /// fails because the dialog has a fixed size.
    ///
    /// Preference order: subrole == AXStandardWindow → focused → first.
    static func tileTarget(of appRef: AXUIElement) -> AXUIElement? {
        let ws = windows(of: appRef)
        if let std = ws.first(where: { stringAttr($0, kAXSubroleAttribute as String) == "AXStandardWindow" }) {
            return std
        }
        return frontWindow(of: appRef)
    }

    static func windowCount(of appRef: AXUIElement) -> Int {
        windows(of: appRef).count
    }

    static func windows(of appRef: AXUIElement) -> [AXUIElement] {
        var listRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &listRef) == .success,
           let arr = listRef as? [AXUIElement] {
            return arr
        }
        return []
    }

    /// User-facing windows only. Some apps (Chess at launch, observed in
    /// practice) expose a second AX entry alongside the real window with
    /// subrole=AXUnknown and an empty title, whose rect sits inside the
    /// standard window's frame. The cause isn't documented as far as we've
    /// found; treat anything that isn't AXStandardWindow as not-a-window for
    /// counting and for the launch-readiness wait.
    static func standardWindows(of appRef: AXUIElement) -> [AXUIElement] {
        windows(of: appRef).filter {
            stringAttr($0, kAXSubroleAttribute as String) == "AXStandardWindow"
        }
    }

    static func stringAttr(_ el: AXUIElement, _ key: String) -> String? {
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, key as CFString, &ref) == .success {
            return ref as? String
        }
        return nil
    }

    /// Print one line per window with role/subrole/title/rect. Useful when
    /// triaging multi-window-startup unverifiable cases.
    static func dumpWindows(of appRef: AXUIElement, indent: String = "      ") {
        let ws = windows(of: appRef)
        if ws.isEmpty {
            print("\(indent)<no windows>")
            return
        }
        for (i, w) in ws.enumerated() {
            let role = stringAttr(w, kAXRoleAttribute as String) ?? "?"
            let sub = stringAttr(w, kAXSubroleAttribute as String) ?? "-"
            let title = stringAttr(w, kAXTitleAttribute as String) ?? ""
            let rect = getRect(w).map { "(\(Int($0.origin.x)),\(Int($0.origin.y)) \(Int($0.width))x\(Int($0.height)))" } ?? "?"
            print("\(indent)[\(i)] role=\(role) subrole=\(sub) title=\"\(title)\" rect=\(rect)")
        }
    }

    static func getRect(_ window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    /// 3-op size→position→size, same as janzowm's applySizePositionSize. Setting
    /// size first avoids macOS clamping position to keep the old frame on
    /// screen; the trailing size write corrects any clamp.
    static func setRect(_ window: AXUIElement, _ rect: CGRect) {
        var size = CGSize(width: rect.width, height: rect.height)
        var pos = CGPoint(x: rect.origin.x, y: rect.origin.y)
        if let sv = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sv)
        }
        if let pv = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pv)
        }
        if let sv = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sv)
        }
    }

    /// Mirrors WindowAX.setPosition's enhanced-UI dance: Spotify/Electron set
    /// AXEnhancedUserInterface=true, which animates moves and breaks
    /// instantaneous AX writes. Disable, do the writes, restore.
    static func withEnhancedUIDisabled(_ appRef: AXUIElement, _ body: () -> Void) {
        let key = "AXEnhancedUserInterface" as CFString
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(appRef, key, &ref)
        let had = (ref as? Bool) == true
        if had { AXUIElementSetAttributeValue(appRef, key, kCFBooleanFalse) }
        body()
        if had { AXUIElementSetAttributeValue(appRef, key, kCFBooleanTrue) }
    }
}

// MARK: - Self-protection

/// Parent pid of `pid` via sysctl, or 0 on failure.
func parentPID(of pid: pid_t) -> pid_t {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    let rc = mib.withUnsafeMutableBufferPointer { buf -> Int32 in
        sysctl(buf.baseAddress, u_int(buf.count), &info, &size, nil, 0)
    }
    return rc == 0 ? info.kp_eproc.e_ppid : 0
}

/// Walk the parent process chain and collect bundle IDs of any ancestor that
/// is a registered NSRunningApplication. Catches the controlling terminal
/// (kitty/iTerm/Terminal/Ghostty/...) so the script doesn't tile the window
/// it's running inside.
func ancestorAppBundleIDs() -> Set<String> {
    var ids = Set<String>()
    var pid = getpid()
    var seen = Set<pid_t>()
    while pid > 1 && !seen.contains(pid) {
        seen.insert(pid)
        if let app = NSRunningApplication(processIdentifier: pid),
           let bid = app.bundleIdentifier {
            ids.insert(bid)
        }
        let ppid = parentPID(of: pid)
        if ppid == pid || ppid <= 1 { break }
        pid = ppid
    }
    return ids
}

// MARK: - Bundle scan

struct AppEntry {
    let path: String
    let bundleID: String
    let displayName: String
    /// LSUIElement=true (menu bar agent) or LSBackgroundOnly=true (daemon).
    /// Such apps never open a regular window so we mark them unverifiable
    /// without launching — saves the full LAUNCH_TIMEOUT per app.
    let isAgent: Bool
}

func discoverApps(in dirs: [String]) -> [AppEntry] {
    let fm = FileManager.default
    var out: [AppEntry] = []
    var seenBundleIDs = Set<String>()
    for dir in dirs {
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
        for e in entries where e.hasSuffix(".app") {
            let path = "\(dir)/\(e)"
            guard let bundle = Bundle(path: path),
                  let bid = bundle.bundleIdentifier,
                  seenBundleIDs.insert(bid).inserted else { continue }
            let info = bundle.infoDictionary ?? [:]
            // Info.plist booleans should be <true/>/<false/>, but real-world
            // bundles sometimes store them as <string>YES</string> or
            // <string>1</string>. Accept both shapes.
            func plistTruthy(_ key: String) -> Bool {
                if let b = info[key] as? Bool { return b }
                if let n = info[key] as? NSNumber { return n.boolValue }
                if let s = info[key] as? String {
                    let lower = s.lowercased()
                    return lower == "yes" || lower == "true" || lower == "1"
                }
                return false
            }
            let lsui = plistTruthy("LSUIElement")
            let lsbg = plistTruthy("LSBackgroundOnly")
            let name = fm.displayName(atPath: path)
            out.append(AppEntry(path: path, bundleID: bid, displayName: name, isAgent: lsui || lsbg))
        }
    }
    return out.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
}

/// Resolve a single bundle ID to an AppEntry via NSWorkspace, so apps outside
/// APPS_DIRS (e.g. /System/Applications/Chess.app) can be targeted directly.
func resolveBundle(_ bundleID: String) -> AppEntry? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
          let bundle = Bundle(url: url) else { return nil }
    let info = bundle.infoDictionary ?? [:]
    func plistTruthy(_ key: String) -> Bool {
        if let b = info[key] as? Bool { return b }
        if let n = info[key] as? NSNumber { return n.boolValue }
        if let s = info[key] as? String {
            let lower = s.lowercased()
            return lower == "yes" || lower == "true" || lower == "1"
        }
        return false
    }
    let name = FileManager.default.displayName(atPath: url.path)
    return AppEntry(
        path: url.path,
        bundleID: bundleID,
        displayName: name,
        isAgent: plistTruthy("LSUIElement") || plistTruthy("LSBackgroundOnly")
    )
}

// MARK: - Lifecycle

func runningApp(forBundleID bid: String) -> NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bid }
}

/// Synchronous wrapper around NSWorkspace.openApplication. Returns the
/// NSRunningApplication on success, nil if the open failed within timeout.
func launch(_ entry: AppEntry) -> NSRunningApplication? {
    if let already = runningApp(forBundleID: entry.bundleID) { return already }
    let url = URL(fileURLWithPath: entry.path)
    let cfg = NSWorkspace.OpenConfiguration()
    cfg.activates = true
    cfg.addsToRecentItems = false
    let sem = DispatchSemaphore(value: 0)
    var result: NSRunningApplication?
    NSWorkspace.shared.openApplication(at: url, configuration: cfg) { app, _ in
        result = app
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + LAUNCH_TIMEOUT)
    return result ?? runningApp(forBundleID: entry.bundleID)
}

/// Poll AX for at least one user-facing (AXStandardWindow) window. Synthetic
/// AX-only windows (subrole AXUnknown) don't count — they appear before the
/// real window does and would cause us to proceed too early.
func waitForWindow(pid: pid_t) -> Bool {
    let deadline = Date().addingTimeInterval(LAUNCH_TIMEOUT)
    let appRef = AX.appElement(pid: pid)
    while Date() < deadline {
        if !AX.standardWindows(of: appRef).isEmpty { return true }
        Thread.sleep(forTimeInterval: 0.15)
    }
    return false
}

// MARK: - Tile attempt

/// Returns true iff the chosen tile-target window's rect lands within
/// tolerance of the expected tile rect for `position` within
/// ASSERT_POLL_SECONDS.
func tryTile(pid: pid_t, position: Position, screen: NSScreen) -> Bool {
    let appRef = AX.appElement(pid: pid)
    guard let window = AX.tileTarget(of: appRef) else { return false }
    let expected = expectedCGRect(position, screen: screen)

    if ONLY_BUNDLE_ID != nil {
        let role = AX.stringAttr(window, kAXRoleAttribute as String) ?? "?"
        let sub = AX.stringAttr(window, kAXSubroleAttribute as String) ?? "-"
        let title = AX.stringAttr(window, kAXTitleAttribute as String) ?? ""
        let before = AX.getRect(window).map { "(\(Int($0.origin.x)),\(Int($0.origin.y)) \(Int($0.width))x\(Int($0.height)))" } ?? "?"
        print("    [\(position.rawValue)] target: role=\(role) subrole=\(sub) title=\"\(title)\" before=\(before) expected=(\(Int(expected.origin.x)),\(Int(expected.origin.y)) \(Int(expected.width))x\(Int(expected.height)))")
    }

    // Park at a sentinel rect so a passing assertion can't be a coincidence
    // (window already at the expected rect).
    let sentinel = CGRect(x: 120, y: 120, width: 640, height: 420)
    AX.withEnhancedUIDisabled(appRef) {
        AX.setRect(window, sentinel)
    }
    Thread.sleep(forTimeInterval: SENTINEL_SETTLE)

    AX.withEnhancedUIDisabled(appRef) {
        AX.setRect(window, expected)
    }

    // Poll: AX writes are sometimes settled-by-the-time-we-return, but apps
    // (especially Electron) process them async.
    let deadline = Date().addingTimeInterval(ASSERT_POLL_SECONDS)
    var lastRect: CGRect? = nil
    while Date() < deadline {
        if let cur = AX.getRect(window) {
            lastRect = cur
            let dx = abs(cur.origin.x - expected.origin.x)
            let dy = abs(cur.origin.y - expected.origin.y)
            let dw = abs(cur.width - expected.width)
            let dh = abs(cur.height - expected.height)
            let wTol = expected.width * CGFloat(SIZE_TOLERANCE_PCT)
            let hTol = expected.height * CGFloat(SIZE_TOLERANCE_PCT)
            if dx < POS_TOLERANCE_PX && dy < POS_TOLERANCE_PX
                && dw <= wTol && dh <= hTol {
                if ONLY_BUNDLE_ID != nil {
                    print("      after=(\(Int(cur.origin.x)),\(Int(cur.origin.y)) \(Int(cur.width))x\(Int(cur.height)))  PASS")
                }
                return true
            }
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    if ONLY_BUNDLE_ID != nil, let last = lastRect {
        print("      after=(\(Int(last.origin.x)),\(Int(last.origin.y)) \(Int(last.width))x\(Int(last.height)))  FAIL")
    }
    return false
}

// MARK: - Output

/// One bundle ID per line per file. Every scanned app lands in exactly one
/// of {excluded, unverifiable, included} — together they enumerate the full
/// scan set, which is the partition the tutorial author needs.
final class ResultLogger {
    let excluded: FileHandle
    let unverifiable: FileHandle
    let included: FileHandle

    init() throws {
        let fm = FileManager.default
        for path in [EXCLUDED_PATH, UNVERIFIABLE_PATH, INCLUDED_PATH] {
            if fm.fileExists(atPath: path) { try fm.removeItem(atPath: path) }
            fm.createFile(atPath: path, contents: nil)
        }
        excluded = try FileHandle(forWritingTo: URL(fileURLWithPath: EXCLUDED_PATH))
        unverifiable = try FileHandle(forWritingTo: URL(fileURLWithPath: UNVERIFIABLE_PATH))
        included = try FileHandle(forWritingTo: URL(fileURLWithPath: INCLUDED_PATH))
    }

    func logExcluded(_ entry: AppEntry)     { excluded.write(Data("\(entry.bundleID)\n".utf8)) }
    func logUnverifiable(_ entry: AppEntry) { unverifiable.write(Data("\(entry.bundleID)\n".utf8)) }
    func logIncluded(_ entry: AppEntry)     { included.write(Data("\(entry.bundleID)\n".utf8)) }
}

// MARK: - Main

if !AXIsProcessTrusted() {
    FileHandle.standardError.write(Data("""
    error: this process is not trusted for Accessibility.
    Add the terminal you're running from (Terminal/iTerm/kitty/Ghostty) to
    System Settings → Privacy & Security → Accessibility, then re-run.
    Without this, every AX setRect will silently no-op and every app will be
    reported as excluded.

    """.utf8))
    exit(1)
}

// Auto-skip any ancestor app of this process — overwhelmingly the terminal
// this script is running in. Tiling that window would throw the running
// script around mid-survey. These go to unverifiable, NOT excluded — the
// terminal might be perfectly tutorial-suitable, we just can't test it
// from inside itself. Re-run from a different terminal to verify.
let ancestorBundles = ancestorAppBundleIDs()
if !ancestorBundles.isEmpty {
    print("auto-skipping ancestor process bundles: \(ancestorBundles.sorted().joined(separator: ", "))")
}

let screen = NSScreen.main ?? NSScreen.screens[0]

let apps: [AppEntry]
if let only = ONLY_BUNDLE_ID {
    guard let entry = resolveBundle(only) else {
        FileHandle.standardError.write(Data("ONLY_BUNDLE_ID=\(only) — could not resolve via NSWorkspace\n".utf8))
        exit(1)
    }
    print("debug mode: targeting only \(entry.displayName) (\(entry.bundleID)) at \(entry.path)")
    apps = [entry]
} else {
    apps = discoverApps(in: APPS_DIRS)
}
guard !apps.isEmpty else {
    FileHandle.standardError.write(Data("no .app bundles found in \(APPS_DIRS.joined(separator: ", "))\n".utf8))
    exit(1)
}

let logger: ResultLogger
do {
    logger = try ResultLogger()
} catch {
    FileHandle.standardError.write(Data("could not open output files: \(error)\n".utf8))
    exit(1)
}

print("scanning \(apps.count) app(s) in \(APPS_DIRS.joined(separator: ", "))")
print("primary screen visibleFrame: \(screen.visibleFrame)")
print("tolerance: ±\(Int(POS_TOLERANCE_PX))px pos / ±\(Int(SIZE_TOLERANCE_PCT * 100))% size")
print("")

var included = 0, excluded = 0, unverifiable = 0

for (idx, entry) in apps.enumerated() {
    let prefix = "[\(idx + 1)/\(apps.count)]"

    if DENYLISTED_BUNDLES.contains(entry.bundleID) {
        print("\(prefix) skip   \(entry.displayName) — denylist (-> excluded)")
        logger.logExcluded(entry)
        excluded += 1
        continue
    }

    if ancestorBundles.contains(entry.bundleID) {
        print("\(prefix) skip   \(entry.displayName) — ancestor of survey process (-> unverifiable)")
        logger.logUnverifiable(entry)
        unverifiable += 1
        continue
    }

    if entry.isAgent {
        print("\(prefix) skip   \(entry.displayName) — LSUIElement/LSBackgroundOnly (agent) (-> unverifiable)")
        logger.logUnverifiable(entry)
        unverifiable += 1
        continue
    }

    let wasRunning = runningApp(forBundleID: entry.bundleID) != nil
    print("\(prefix) test   \(entry.displayName) (\(entry.bundleID))\(wasRunning ? "  [already running]" : "")")

    guard let app = launch(entry) else {
        print("    -> unverifiable: launch-failed")
        logger.logUnverifiable(entry)
        unverifiable += 1
        continue
    }

    let pid = app.processIdentifier
    if !waitForWindow(pid: pid) {
        print("    -> unverifiable: no window after \(Int(LAUNCH_TIMEOUT))s")
        logger.logUnverifiable(entry)
        unverifiable += 1
        continue
    }

    // Settle period for late-arriving secondary windows (welcome dialogs,
    // template choosers, "what's new" popups) before we sample the count.
    Thread.sleep(forTimeInterval: MULTI_WINDOW_GRACE)

    let appRef = AX.appElement(pid: pid)
    // Count only user-facing windows for the multi-window heuristic. macOS
    // routinely exposes synthetic AXUnknown shadows alongside the real
    // window (Chess at launch is a classic case — 1 visible window, 2 in
    // kAXWindows).
    let stdCount = AX.standardWindows(of: appRef).count
    if ONLY_BUNDLE_ID != nil {
        let total = AX.windowCount(of: appRef)
        print("    windows after \(MULTI_WINDOW_GRACE)s grace (raw=\(total), standard=\(stdCount)):")
        AX.dumpWindows(of: appRef)
    }
    if stdCount > 1 {
        print("    -> unverifiable: \(stdCount) standard windows at startup")
        logger.logUnverifiable(entry)
        unverifiable += 1
        continue
    }

    app.activate(options: [])
    Thread.sleep(forTimeInterval: SETTLE_AFTER_ACTIVATE)

    let allPassed = Position.allCases.allSatisfy { pos in
        tryTile(pid: pid, position: pos, screen: screen)
    }

    if allPassed {
        print("    -> included")
        logger.logIncluded(entry)
        included += 1
    } else {
        print("    -> excluded: tile-failed")
        logger.logExcluded(entry)
        excluded += 1
    }
}

print("")
print("summary:")
print("  total apps:    \(apps.count)")
print("  included:      \(included)   (\(INCLUDED_PATH))")
print("  excluded:      \(excluded)   (\(EXCLUDED_PATH))")
print("  unverifiable:  \(unverifiable)   (\(UNVERIFIABLE_PATH))")
let accounted = included + excluded + unverifiable
if accounted != apps.count {
    print("  WARNING: \(apps.count - accounted) app(s) unaccounted for — partition is broken")
}
