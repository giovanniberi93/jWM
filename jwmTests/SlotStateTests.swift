import XCTest

final class SlotStateTests: XCTestCase {

    func testSetAndGetFullScreen() {
        var slots = SlotState()
        let displayID: CGDirectDisplayID = 1
        let pid: pid_t = 42

        slots.setFullScreen(pid, forDisplay: displayID)
        XCTAssertEqual(slots.fullScreen(forDisplay: displayID), pid)
    }

    func testClearFullScreenByDisplay() {
        var slots = SlotState()
        let displayID: CGDirectDisplayID = 1
        slots.setFullScreen(42, forDisplay: displayID)

        slots.setFullScreen(nil, forDisplay: displayID)
        XCTAssertNil(slots.fullScreen(forDisplay: displayID))
    }

    func testClearFullScreenByPid() {
        var slots = SlotState()
        let display1: CGDirectDisplayID = 1
        let display2: CGDirectDisplayID = 2
        let pid: pid_t = 42

        slots.setFullScreen(pid, forDisplay: display1)
        slots.setFullScreen(pid, forDisplay: display2)
        slots.clearFullScreen(pid: pid)

        XCTAssertNil(slots.fullScreen(forDisplay: display1))
        XCTAssertNil(slots.fullScreen(forDisplay: display2))
    }

    func testMultipleDisplaysIndependent() {
        var slots = SlotState()
        let display1: CGDirectDisplayID = 1
        let display2: CGDirectDisplayID = 2

        slots.setFullScreen(42, forDisplay: display1)
        slots.setFullScreen(99, forDisplay: display2)

        XCTAssertEqual(slots.fullScreen(forDisplay: display1), 42)
        XCTAssertEqual(slots.fullScreen(forDisplay: display2), 99)

        slots.setFullScreen(nil, forDisplay: display1)
        XCTAssertNil(slots.fullScreen(forDisplay: display1))
        XCTAssertEqual(slots.fullScreen(forDisplay: display2), 99)
    }
}
