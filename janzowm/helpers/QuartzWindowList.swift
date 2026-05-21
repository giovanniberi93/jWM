import CoreGraphics
import Foundation

struct QuartzWindowInfo: Equatable {
    let id: CGWindowID
    let level: CGWindowLevel
    let frame: CGRect
    let pid: pid_t
    let processName: String?
}

/// Looks up the window under a screen point via the Quartz window list, with
/// no AX/Mach IPC into the foreground app. Mirrors Rectangle's
/// `WindowUtil.getWindowList` + `getWindowInfo` path.
enum QuartzWindowList {
    private static let cache = TTLCache(
        ttl: 0.1,
        fetch: { fetchOnScreenWindows() }
    )

    /// `point` must be in CG screen coordinates (origin at top-left of primary screen).
    static func windowAtPoint(_ point: CGPoint) -> QuartzWindowInfo? {
        return windowAtPoint(point, in: cache.value())
    }

    /// All on-screen windows owned by the given pid, filtered to "normal"
    /// window levels (below Notification Center). Used by `WindowTiler` to
    /// enumerate an app's windows without an AX hop into that app — same
    /// motivation as SnapManager's switch to Quartz in commit 9088b8e
    /// (avoid blocking main thread when the foreground app is slow).
    /// One WindowServer IPC per call (cached for 100ms), regardless of how
    /// many windows the app has.
    static func windowsForPid(_ pid: pid_t) -> [QuartzWindowInfo] {
        return cache.value().filter { $0.pid == pid && $0.level < notificationCenterLevel }
    }

    // Notification Center sits at level 23. There is no public symbolic
    // constant for it (CGWindowLevel.h tops out at kCGAssistiveTechHighWindow);
    // Rectangle uses the same literal.
    static let notificationCenterLevel: CGWindowLevel = 23

    static func windowAtPoint(_ point: CGPoint, in windows: [QuartzWindowInfo]) -> QuartzWindowInfo? {
        return windows.first { info in
            info.frame.contains(point)
                && info.level < notificationCenterLevel
                && info.processName != "Dock"
                && info.processName != "WindowManager"
        }
    }

    private static func parse(_ rawInfos: CFArray) -> [QuartzWindowInfo] {
        let count = CFArrayGetCount(rawInfos)
        var infos: [QuartzWindowInfo] = []
        infos.reserveCapacity(count)
        for i in 0..<count {
            let raw = CFArrayGetValueAtIndex(rawInfos, i)
            let dict = unsafeBitCast(raw, to: CFDictionary.self) as NSDictionary
            guard let info = parseEntry(dict) else { continue }
            infos.append(info)
        }
        return infos
    }

    private static func parseEntry(_ dict: NSDictionary) -> QuartzWindowInfo? {
        guard let idNum = dict[kCGWindowNumber as String] as? NSNumber,
              let levelNum = dict[kCGWindowLayer as String] as? NSNumber,
              let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: boundsDict),
              let pidNum = dict[kCGWindowOwnerPID as String] as? NSNumber else { return nil }
        return QuartzWindowInfo(
            id: CGWindowID(truncating: idNum),
            level: CGWindowLevel(truncating: levelNum),
            frame: frame,
            pid: pid_t(truncating: pidNum),
            processName: dict[kCGWindowOwnerName as String] as? String
        )
    }

    private static func fetchOnScreenWindows() -> [QuartzWindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) else { return [] }
        return parse(raw)
    }
}

/// Single-slot TTL cache. Mouse-down events arrive in bursts during a drag;
/// caching the Quartz window list for ~100ms keeps `windowAtPoint` cheap
/// without hiding genuinely fresh state.
final class TTLCache<Value> {
    private let ttl: TimeInterval
    private let fetch: () -> Value
    private let clock: () -> TimeInterval
    private var cached: Value?
    private var expiresAt: TimeInterval = 0

    init(
        ttl: TimeInterval,
        fetch: @escaping () -> Value,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.ttl = ttl
        self.fetch = fetch
        self.clock = clock
    }

    func value() -> Value {
        let now = clock()
        if let cached, now < expiresAt {
            return cached
        }
        let fresh = fetch()
        cached = fresh
        expiresAt = now + ttl
        return fresh
    }

    // Workaround for Swift 6.2.4 optimizer crash in EarlyPerfInliner when
    // synthesizing deinit for TTLCache<Value> at deployment target < 26.0.
    deinit {}
}
