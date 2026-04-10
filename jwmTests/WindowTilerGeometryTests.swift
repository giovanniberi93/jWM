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
