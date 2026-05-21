import XCTest
import CoreGraphics

final class QuartzWindowListTests: XCTestCase {

    private let normalLevel = CGWindowLevelForKey(.normalWindow)
    private let notificationLevel = QuartzWindowList.notificationCenterLevel

    private func info(level: CGWindowLevel, processName: String?) -> QuartzWindowInfo {
        QuartzWindowInfo(
            id: 1,
            level: level,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            pid: 1,
            processName: processName
        )
    }

    // MARK: - Filter rules
    // These encode product decisions in windowAtPoint's predicate. Deleting one
    // of the `&&` clauses is a silent regression — integration tests use stubs
    // that aren't named "Dock"/"WindowManager", so they wouldn't catch it.

    func testSkipsDockWindows() {
        let dock = info(level: normalLevel, processName: "Dock")
        let app = info(level: normalLevel, processName: "App")
        XCTAssertEqual(QuartzWindowList.windowAtPoint(.zero, in: [dock, app])?.processName, "App")
    }

    func testSkipsWindowManagerWindows() {
        let wm = info(level: normalLevel, processName: "WindowManager")
        let app = info(level: normalLevel, processName: "App")
        XCTAssertEqual(QuartzWindowList.windowAtPoint(.zero, in: [wm, app])?.processName, "App")
    }

    func testSkipsNotificationLevelWindows() {
        let notif = info(level: notificationLevel, processName: "NotificationCenter")
        let app = info(level: normalLevel, processName: "App")
        XCTAssertEqual(QuartzWindowList.windowAtPoint(.zero, in: [notif, app])?.processName, "App")
    }

    // MARK: - TTL cache

    func testTTLCacheReusesValueWithinTTL() {
        var now: TimeInterval = 0
        var fetches = 0
        let cache = TTLCache<Int>(
            ttl: 0.1,
            fetch: { fetches += 1; return fetches },
            clock: { now }
        )

        XCTAssertEqual(cache.value(), 1)
        now = 0.05
        XCTAssertEqual(cache.value(), 1)
        XCTAssertEqual(fetches, 1)
    }

    func testTTLCacheRefetchesAfterTTL() {
        var now: TimeInterval = 0
        var fetches = 0
        let cache = TTLCache<Int>(
            ttl: 0.1,
            fetch: { fetches += 1; return fetches },
            clock: { now }
        )

        _ = cache.value()
        now = 0.2
        XCTAssertEqual(cache.value(), 2)
        XCTAssertEqual(fetches, 2)
    }
}
