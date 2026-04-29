import XCTest

final class SlotStateTests: XCTestCase {

    // MARK: - upsert / contains

    func testUpsertAndContains() {
        var slots = SlotState()
        slots.upsert(pid: 42, displayID: 1)
        XCTAssertTrue(slots.contains(pid: 42))
        XCTAssertFalse(slots.contains(pid: 99))
    }

    func testUpsertSamePidUpdatesDisplay() {
        var slots = SlotState()
        slots.upsert(pid: 42, displayID: 1)
        slots.upsert(pid: 42, displayID: 2)

        // Old display no longer carries the pid; new one does.
        XCTAssertNil(slots.mostRecentFullScreen(forDisplay: 1, excluding: 0))
        XCTAssertEqual(slots.mostRecentFullScreen(forDisplay: 2, excluding: 0), 42)
    }

    // MARK: - remove

    func testRemove() {
        var slots = SlotState()
        slots.upsert(pid: 42, displayID: 1)
        slots.remove(pid: 42)
        XCTAssertFalse(slots.contains(pid: 42))
        XCTAssertNil(slots.mostRecentFullScreen(forDisplay: 1, excluding: 0))
    }

    func testRemoveAbsentPidIsNoop() {
        var slots = SlotState()
        slots.upsert(pid: 42, displayID: 1)
        slots.remove(pid: 99) // not there
        XCTAssertTrue(slots.contains(pid: 42))
    }

    // MARK: - mostRecentFullScreen ordering

    func testMostRecentReturnsHighestSeq() {
        var slots = SlotState()
        slots.upsert(pid: 42, displayID: 1)
        slots.upsert(pid: 99, displayID: 1)
        slots.upsert(pid: 7, displayID: 1)

        XCTAssertEqual(slots.mostRecentFullScreen(forDisplay: 1, excluding: 0), 7)
    }

    func testMostRecentExcludesGivenPid() {
        var slots = SlotState()
        slots.upsert(pid: 42, displayID: 1)
        slots.upsert(pid: 99, displayID: 1)

        XCTAssertEqual(slots.mostRecentFullScreen(forDisplay: 1, excluding: 99), 42)
    }

    func testMostRecentReupsertReorders() {
        var slots = SlotState()
        slots.upsert(pid: 42, displayID: 1)
        slots.upsert(pid: 99, displayID: 1)
        // Re-upsert 42 → it becomes the newest.
        slots.upsert(pid: 42, displayID: 1)

        XCTAssertEqual(slots.mostRecentFullScreen(forDisplay: 1, excluding: 0), 42)
    }

    func testMostRecentEmptyReturnsNil() {
        let slots = SlotState()
        XCTAssertNil(slots.mostRecentFullScreen(forDisplay: 1, excluding: 0))
    }

    func testMostRecentExcludingOnlyEntryReturnsNil() {
        var slots = SlotState()
        slots.upsert(pid: 42, displayID: 1)
        XCTAssertNil(slots.mostRecentFullScreen(forDisplay: 1, excluding: 42))
    }

    // MARK: - per-display isolation

    func testDisplaysAreIndependent() {
        var slots = SlotState()
        slots.upsert(pid: 42, displayID: 1)
        slots.upsert(pid: 99, displayID: 2)

        XCTAssertEqual(slots.mostRecentFullScreen(forDisplay: 1, excluding: 0), 42)
        XCTAssertEqual(slots.mostRecentFullScreen(forDisplay: 2, excluding: 0), 99)
    }

    // MARK: - test 12 scenario (ordered list survives displacement)

    func testOrderedListSurvivesDisplacement() {
        // Three apps go fullscreen in order, then the newest is displaced
        // (its entry removed). Next-most-recent should still be discoverable.
        var slots = SlotState()
        slots.upsert(pid: 1, displayID: 10)
        slots.upsert(pid: 2, displayID: 10)
        slots.upsert(pid: 3, displayID: 10)

        // Displace pid 3 → only its entry is removed; pids 1 & 2 stay.
        slots.remove(pid: 3)

        // Next-most-recent fullscreen on display 10 (excluding the
        // currently-tiling app, say pid 99) is pid 2.
        XCTAssertEqual(slots.mostRecentFullScreen(forDisplay: 10, excluding: 99), 2)
    }
}
