import XCTest

final class WindowTilerGeometryTests: XCTestCase {

    // Simulated primary screen: 1920x1080 with 25px menu bar.
    // AppKit visibleFrame: origin=(0, 0), size=(1920, 1055)
    // (y=0 because Dock is hidden or on the side; menu bar subtracts from top)
    let frame = NSRect(x: 0, y: 0, width: 1920, height: 1055)
    let primaryHeight: CGFloat = 1080

    func testRectForPositionLeft() {
        let rect = WindowTiler.rectForPosition(.left, frame: frame, primaryHeight: primaryHeight)
        XCTAssertEqual(rect.origin.x, 0)
        XCTAssertEqual(rect.width, 960)
        XCTAssertEqual(rect.height, 1055)
        // CG y-flip: cgY = primaryHeight - appKitY - height = 1080 - 0 - 1055 = 25
        XCTAssertEqual(rect.origin.y, 25)
    }

    func testRectForPositionRight() {
        let rect = WindowTiler.rectForPosition(.right, frame: frame, primaryHeight: primaryHeight)
        XCTAssertEqual(rect.origin.x, 960)
        XCTAssertEqual(rect.width, 960)
        XCTAssertEqual(rect.height, 1055)
        XCTAssertEqual(rect.origin.y, 25)
    }

    func testRectForPositionFullScreen() {
        let rect = WindowTiler.rectForPosition(.fullScreen, frame: frame, primaryHeight: primaryHeight)
        XCTAssertEqual(rect.origin.x, 0)
        XCTAssertEqual(rect.width, 1920)
        XCTAssertEqual(rect.height, 1055)
        XCTAssertEqual(rect.origin.y, 25)
    }

    func testRectForPositionSecondaryScreen() {
        // Secondary screen to the right: AppKit frame origin at x=1920.
        // visibleFrame might have a different y if it doesn't have the menu bar.
        let secondaryFrame = NSRect(x: 1920, y: 0, width: 2560, height: 1440)
        // Primary height is still from screen[0], NOT the secondary screen.
        let rect = WindowTiler.rectForPosition(.left, frame: secondaryFrame, primaryHeight: primaryHeight)
        XCTAssertEqual(rect.origin.x, 1920)
        XCTAssertEqual(rect.width, 1280)
        XCTAssertEqual(rect.height, 1440)
        // cgY = 1080 - 0 - 1440 = -360 (negative is valid for secondary screens below/above primary)
        XCTAssertEqual(rect.origin.y, -360)
    }

    // MARK: - matchHalfPosition

    func testMatchHalfPositionLeft() {
        let leftRect = WindowTiler.rectForPosition(.left, frame: frame, primaryHeight: primaryHeight)
        XCTAssertEqual(
            WindowTiler.matchHalfPosition(windowRect: leftRect, frame: frame, primaryHeight: primaryHeight),
            .left
        )
    }

    func testMatchHalfPositionRight() {
        let rightRect = WindowTiler.rectForPosition(.right, frame: frame, primaryHeight: primaryHeight)
        XCTAssertEqual(
            WindowTiler.matchHalfPosition(windowRect: rightRect, frame: frame, primaryHeight: primaryHeight),
            .right
        )
    }

    func testMatchHalfPositionFullScreenReturnsNil() {
        let fullRect = WindowTiler.rectForPosition(.fullScreen, frame: frame, primaryHeight: primaryHeight)
        XCTAssertNil(
            WindowTiler.matchHalfPosition(windowRect: fullRect, frame: frame, primaryHeight: primaryHeight)
        )
    }

    func testMatchHalfPositionArbitraryRectReturnsNil() {
        let arbitrary = CGRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertNil(
            WindowTiler.matchHalfPosition(windowRect: arbitrary, frame: frame, primaryHeight: primaryHeight)
        )
    }

    func testMatchHalfPositionWithinPositionTolerance() {
        var leftRect = WindowTiler.rectForPosition(.left, frame: frame, primaryHeight: primaryHeight)
        // Offset by 15px (within 20px position tolerance)
        leftRect.origin.x += 15
        leftRect.origin.y -= 10
        XCTAssertEqual(
            WindowTiler.matchHalfPosition(windowRect: leftRect, frame: frame, primaryHeight: primaryHeight),
            .left
        )
    }

    func testMatchHalfPositionOutsidePositionTolerance() {
        var leftRect = WindowTiler.rectForPosition(.left, frame: frame, primaryHeight: primaryHeight)
        // Offset by 25px (outside 20px position tolerance)
        leftRect.origin.x += 25
        XCTAssertNil(
            WindowTiler.matchHalfPosition(windowRect: leftRect, frame: frame, primaryHeight: primaryHeight)
        )
    }

    func testMatchHalfPositionWithinSizeTolerance() {
        // Simulate Calendar-like case: roughly half-screen but not exact.
        // Left half width is 960, 10% wider = 1056 (within 15%).
        var leftRect = WindowTiler.rectForPosition(.left, frame: frame, primaryHeight: primaryHeight)
        leftRect.size.width *= 1.10
        XCTAssertEqual(
            WindowTiler.matchHalfPosition(windowRect: leftRect, frame: frame, primaryHeight: primaryHeight),
            .left
        )
    }

    func testMatchHalfPositionOutsideSizeTolerance() {
        // 20% wider than half-screen (outside 15% tolerance)
        var leftRect = WindowTiler.rectForPosition(.left, frame: frame, primaryHeight: primaryHeight)
        leftRect.size.width *= 1.20
        XCTAssertNil(
            WindowTiler.matchHalfPosition(windowRect: leftRect, frame: frame, primaryHeight: primaryHeight)
        )
    }

    func testMatchHalfPositionWithinBothTolerances() {
        // Real-world Calendar/Mail case: app restores at slightly-off origin
        // AND slightly-off size, both within their respective tolerances.
        // matchHalfPosition must accept the combination, not just each axis alone.
        var leftRect = WindowTiler.rectForPosition(.left, frame: frame, primaryHeight: primaryHeight)
        leftRect.origin.x += 12       // within 20px position tolerance
        leftRect.origin.y -= 8        // within 20px position tolerance
        leftRect.size.width *= 1.08   // 8% wider, within 15% size tolerance
        leftRect.size.height *= 0.93  // 7% shorter, within 15% size tolerance
        XCTAssertEqual(
            WindowTiler.matchHalfPosition(windowRect: leftRect, frame: frame, primaryHeight: primaryHeight),
            .left
        )
    }

    func testMatchHalfPositionSecondaryScreen() {
        let secondaryFrame = NSRect(x: 1920, y: 0, width: 2560, height: 1440)
        let rightRect = WindowTiler.rectForPosition(.right, frame: secondaryFrame, primaryHeight: primaryHeight)
        XCTAssertEqual(
            WindowTiler.matchHalfPosition(windowRect: rightRect, frame: secondaryFrame, primaryHeight: primaryHeight),
            .right
        )
    }

    func testLeftAndRightCoverFullWidth() {
        let left = WindowTiler.rectForPosition(.left, frame: frame, primaryHeight: primaryHeight)
        let right = WindowTiler.rectForPosition(.right, frame: frame, primaryHeight: primaryHeight)
        // Left and right halves should tile the full width with no gap or overlap.
        XCTAssertEqual(left.origin.x + left.width, right.origin.x)
        XCTAssertEqual(left.width + right.width, frame.width)
        // Same y and height.
        XCTAssertEqual(left.origin.y, right.origin.y)
        XCTAssertEqual(left.height, right.height)
    }
}

// MARK: - Suppression staleness

/// Belt-and-suspenders coverage for the displaceIfHalf suppression flag.
/// The primary clear path (launchAndWaitForWindow's defer) is integration-
/// tested by integration-tests/test-cases/18_chord_launch_uses_chord_target.sh.
/// These tests cover the self-heal backstop in isolation.
final class WindowTilerSuppressionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        WindowTiler.suppressDisplaceForBundleID = nil
    }

    override func tearDown() {
        WindowTiler.suppressDisplaceForBundleID = nil
        super.tearDown()
    }

    func testClearSuppressionIfStaleClearsOldFlag() {
        WindowTiler.suppressDisplaceForBundleID = "com.example.app"
        // 1000s in the future is comfortably past any plausible maxSuppressionAge.
        let cleared = WindowTiler.clearSuppressionIfStale(now: Date().addingTimeInterval(1000))
        XCTAssertTrue(cleared)
        XCTAssertNil(WindowTiler.suppressDisplaceForBundleID)
    }

    func testClearSuppressionIfStalePreservesFreshFlag() {
        WindowTiler.suppressDisplaceForBundleID = "com.example.app"
        let cleared = WindowTiler.clearSuppressionIfStale(now: Date())
        XCTAssertFalse(cleared)
        XCTAssertEqual(WindowTiler.suppressDisplaceForBundleID, "com.example.app")
    }

    func testClearSuppressionIfStaleNoopWhenUnset() {
        XCTAssertNil(WindowTiler.suppressDisplaceForBundleID)
        let cleared = WindowTiler.clearSuppressionIfStale(now: Date().addingTimeInterval(1000))
        XCTAssertFalse(cleared)
        XCTAssertNil(WindowTiler.suppressDisplaceForBundleID)
    }

    func testSettingNilSuppressionDoesNotMarkAsStale() {
        // Setting to nil shouldn't leave a stale timestamp behind that
        // could later trigger a false self-heal log on the next set.
        WindowTiler.suppressDisplaceForBundleID = "com.example.app"
        WindowTiler.suppressDisplaceForBundleID = nil
        // Setting nil clears the timestamp via didSet; reading "stale" now
        // is a no-op because the flag is nil.
        let cleared = WindowTiler.clearSuppressionIfStale(now: Date().addingTimeInterval(1000))
        XCTAssertFalse(cleared)
    }
}
