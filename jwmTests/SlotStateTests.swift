import XCTest

final class SlotStateTests: XCTestCase {

    // MARK: - upsert / contains

    func testUpsertAndContains() {
        var slots = SlotState()
        slots.upsert(windowId: 100, pid: 42, displayID: 1)
        XCTAssertTrue(slots.contains(windowId: 100))
        XCTAssertFalse(slots.contains(windowId: 200))
    }

    func testUpsertSameWindowUpdatesDisplay() {
        var slots = SlotState()
        slots.upsert(windowId: 100, pid: 42, displayID: 1)
        slots.upsert(windowId: 100, pid: 42, displayID: 2)

        // Old display no longer carries the window; new one does.
        XCTAssertNil(slots.mostRecentFullScreen(forDisplay: 1, excluding: 0))
        XCTAssertEqual(slots.mostRecentFullScreen(forDisplay: 2, excluding: 0)?.windowId, 100)
    }

    // MARK: - remove

    func testRemove() {
        var slots = SlotState()
        slots.upsert(windowId: 100, pid: 42, displayID: 1)
        slots.remove(windowId: 100)
        XCTAssertFalse(slots.contains(windowId: 100))
        XCTAssertNil(slots.mostRecentFullScreen(forDisplay: 1, excluding: 0))
    }

    func testRemoveAbsentWindowIsNoop() {
        var slots = SlotState()
        slots.upsert(windowId: 100, pid: 42, displayID: 1)
        slots.remove(windowId: 999) // not there
        XCTAssertTrue(slots.contains(windowId: 100))
    }

    func testRemoveAllForPidDropsEveryWindow() {
        // Multi-window app dying should clear ALL its entries in one call —
        // the app-death cleanup path in findDisplacementCandidate.
        var slots = SlotState()
        slots.upsert(windowId: 100, pid: 42, displayID: 1)
        slots.upsert(windowId: 101, pid: 42, displayID: 1)
        slots.upsert(windowId: 200, pid: 99, displayID: 1)

        slots.removeAll(forPid: 42)

        XCTAssertFalse(slots.contains(windowId: 100))
        XCTAssertFalse(slots.contains(windowId: 101))
        XCTAssertTrue(slots.contains(windowId: 200))
    }

    // MARK: - mostRecentFullScreen ordering

    func testMostRecentReturnsHighestSeq() {
        var slots = SlotState()
        slots.upsert(windowId: 100, pid: 42, displayID: 1)
        slots.upsert(windowId: 200, pid: 99, displayID: 1)
        slots.upsert(windowId: 300, pid: 7, displayID: 1)

        let result = slots.mostRecentFullScreen(forDisplay: 1, excluding: 0)
        XCTAssertEqual(result?.windowId, 300)
        XCTAssertEqual(result?.pid, 7)
    }

    func testMostRecentExcludesGivenWindow() {
        var slots = SlotState()
        slots.upsert(windowId: 100, pid: 42, displayID: 1)
        slots.upsert(windowId: 200, pid: 99, displayID: 1)

        let result = slots.mostRecentFullScreen(forDisplay: 1, excluding: 200)
        XCTAssertEqual(result?.windowId, 100)
        XCTAssertEqual(result?.pid, 42)
    }

    func testMostRecentSameAppDifferentWindowsPicksSibling() {
        // The multi-window bug: w1 and w2 share a pid. Tiling w2 (excluding
        // its own id) must surface w1 as a candidate.
        var slots = SlotState()
        slots.upsert(windowId: 100, pid: 42, displayID: 1) // w1
        slots.upsert(windowId: 101, pid: 42, displayID: 1) // w2 (same app)

        let result = slots.mostRecentFullScreen(forDisplay: 1, excluding: 101)
        XCTAssertEqual(result?.windowId, 100)
        XCTAssertEqual(result?.pid, 42)
    }

    func testMostRecentReupsertReorders() {
        var slots = SlotState()
        slots.upsert(windowId: 100, pid: 42, displayID: 1)
        slots.upsert(windowId: 200, pid: 99, displayID: 1)
        // Re-upsert 100 → it becomes the newest.
        slots.upsert(windowId: 100, pid: 42, displayID: 1)

        XCTAssertEqual(slots.mostRecentFullScreen(forDisplay: 1, excluding: 0)?.windowId, 100)
    }

    func testMostRecentEmptyReturnsNil() {
        let slots = SlotState()
        XCTAssertNil(slots.mostRecentFullScreen(forDisplay: 1, excluding: 0))
    }

    func testMostRecentExcludingOnlyEntryReturnsNil() {
        var slots = SlotState()
        slots.upsert(windowId: 100, pid: 42, displayID: 1)
        XCTAssertNil(slots.mostRecentFullScreen(forDisplay: 1, excluding: 100))
    }

    // MARK: - per-display isolation

    func testDisplaysAreIndependent() {
        var slots = SlotState()
        slots.upsert(windowId: 100, pid: 42, displayID: 1)
        slots.upsert(windowId: 200, pid: 99, displayID: 2)

        XCTAssertEqual(slots.mostRecentFullScreen(forDisplay: 1, excluding: 0)?.windowId, 100)
        XCTAssertEqual(slots.mostRecentFullScreen(forDisplay: 2, excluding: 0)?.windowId, 200)
    }

    // MARK: - test 12 scenario (ordered list survives displacement)

    func testOrderedListSurvivesDisplacement() {
        // Three apps go fullscreen in order, then the newest is displaced
        // (its entry removed). Next-most-recent should still be discoverable.
        var slots = SlotState()
        slots.upsert(windowId: 100, pid: 1, displayID: 10)
        slots.upsert(windowId: 200, pid: 2, displayID: 10)
        slots.upsert(windowId: 300, pid: 3, displayID: 10)

        // Displace win 300 → only its entry is removed; 100 & 200 stay.
        slots.remove(windowId: 300)

        // Next-most-recent fullscreen on display 10 (excluding the
        // currently-tiling window 999) is win 200.
        let result = slots.mostRecentFullScreen(forDisplay: 10, excluding: 999)
        XCTAssertEqual(result?.windowId, 200)
        XCTAssertEqual(result?.pid, 2)
    }
}
