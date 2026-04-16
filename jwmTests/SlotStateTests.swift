import XCTest

final class SlotStateTests: XCTestCase {

    // MARK: - Basic add / read

    func testAddAndGetFullScreen() {
        var slots = SlotState()
        let displayID: CGDirectDisplayID = 1
        let pid: pid_t = 42

        slots.addFullScreen(pid, forDisplay: displayID)
        XCTAssertEqual(slots.fullScreen(forDisplay: displayID), pid)
        XCTAssertEqual(slots.allFullScreen(forDisplay: displayID), [pid])
    }

    func testFullScreenReturnsNewest() {
        var slots = SlotState()
        let display: CGDirectDisplayID = 1
        slots.addFullScreen(42, forDisplay: display)
        slots.addFullScreen(99, forDisplay: display)
        // fullScreen returns last (newest)
        XCTAssertEqual(slots.fullScreen(forDisplay: display), 99)
        XCTAssertEqual(slots.allFullScreen(forDisplay: display), [42, 99])
    }

    // MARK: - No duplicates

    func testAddFullScreenNoDuplicates() {
        var slots = SlotState()
        let display: CGDirectDisplayID = 1
        slots.addFullScreen(42, forDisplay: display)
        slots.addFullScreen(42, forDisplay: display)
        XCTAssertEqual(slots.allFullScreen(forDisplay: display), [42])
    }

    // MARK: - Clear by display

    func testClearDisplay() {
        var slots = SlotState()
        let display: CGDirectDisplayID = 1
        slots.addFullScreen(42, forDisplay: display)
        slots.addFullScreen(99, forDisplay: display)

        slots.clearDisplay(display)
        XCTAssertNil(slots.fullScreen(forDisplay: display))
        XCTAssertEqual(slots.allFullScreen(forDisplay: display), [])
    }

    // MARK: - Clear by PID

    func testClearFullScreenByPid() {
        var slots = SlotState()
        let display1: CGDirectDisplayID = 1
        let display2: CGDirectDisplayID = 2
        let pid: pid_t = 42

        slots.addFullScreen(pid, forDisplay: display1)
        slots.addFullScreen(pid, forDisplay: display2)
        slots.clearFullScreen(pid: pid)

        XCTAssertNil(slots.fullScreen(forDisplay: display1))
        XCTAssertNil(slots.fullScreen(forDisplay: display2))
    }

    func testClearFullScreenByPidPreservesOthers() {
        var slots = SlotState()
        let display: CGDirectDisplayID = 1
        slots.addFullScreen(42, forDisplay: display)
        slots.addFullScreen(99, forDisplay: display)

        slots.clearFullScreen(pid: 42)
        XCTAssertEqual(slots.allFullScreen(forDisplay: display), [99])
        XCTAssertEqual(slots.fullScreen(forDisplay: display), 99)
    }

    // MARK: - Multiple displays independent

    func testMultipleDisplaysIndependent() {
        var slots = SlotState()
        let display1: CGDirectDisplayID = 1
        let display2: CGDirectDisplayID = 2

        slots.addFullScreen(42, forDisplay: display1)
        slots.addFullScreen(99, forDisplay: display2)

        XCTAssertEqual(slots.fullScreen(forDisplay: display1), 42)
        XCTAssertEqual(slots.fullScreen(forDisplay: display2), 99)

        slots.clearDisplay(display1)
        XCTAssertNil(slots.fullScreen(forDisplay: display1))
        XCTAssertEqual(slots.fullScreen(forDisplay: display2), 99)
    }

    // MARK: - Empty display returns nil / empty

    func testEmptyDisplayReturnsNil() {
        let slots = SlotState()
        XCTAssertNil(slots.fullScreen(forDisplay: 1))
        XCTAssertEqual(slots.allFullScreen(forDisplay: 1), [])
    }

    // MARK: - Cross-display move (clear + add)

    func testMoveAcrossDisplays() {
        var slots = SlotState()
        let display1: CGDirectDisplayID = 1
        let display2: CGDirectDisplayID = 2

        slots.addFullScreen(42, forDisplay: display1)
        // Simulate nextScreen: clear from all, add to new display
        slots.clearFullScreen(pid: 42)
        slots.addFullScreen(42, forDisplay: display2)

        XCTAssertNil(slots.fullScreen(forDisplay: display1))
        XCTAssertEqual(slots.fullScreen(forDisplay: display2), 42)
    }

    // MARK: - Bug scenario: second promote doesn't evict first

    func testPromoteSecondAppPreservesFirst() {
        var slots = SlotState()
        let display: CGDirectDisplayID = 1

        // kitty tiled fullscreen
        slots.addFullScreen(42, forDisplay: display)
        // WhatsApp focused, also fullscreen-sized — promoted
        slots.addFullScreen(99, forDisplay: display)

        // Both tracked
        XCTAssertEqual(slots.allFullScreen(forDisplay: display), [42, 99])

        // Tile WhatsApp to half — clear it
        slots.clearFullScreen(pid: 99)
        // kitty still tracked
        XCTAssertEqual(slots.allFullScreen(forDisplay: display), [42])
        XCTAssertEqual(slots.fullScreen(forDisplay: display), 42)
    }
}
