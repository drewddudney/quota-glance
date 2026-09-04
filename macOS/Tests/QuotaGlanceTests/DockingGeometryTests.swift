import AppKit
import XCTest
@testable import QuotaGlance

final class DockingGeometryTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 24, width: 1440, height: 876)

    func testEveryCornerWinsOverItsAdjacentSides() {
        XCTAssertEqual(DockingGeometry.candidate(for: NSRect(x: 5, y: 720, width: 175, height: 175), in: screen), .topLeft)
        XCTAssertEqual(DockingGeometry.candidate(for: NSRect(x: 1260, y: 720, width: 175, height: 175), in: screen), .topRight)
        XCTAssertEqual(DockingGeometry.candidate(for: NSRect(x: 5, y: 29, width: 175, height: 175), in: screen), .bottomLeft)
        XCTAssertEqual(DockingGeometry.candidate(for: NSRect(x: 1260, y: 29, width: 175, height: 175), in: screen), .bottomRight)
    }

    func testEverySideSnapsAwayFromCorners() {
        XCTAssertEqual(DockingGeometry.candidate(for: NSRect(x: 5, y: 350, width: 180, height: 180), in: screen), .left)
        XCTAssertEqual(DockingGeometry.candidate(for: NSRect(x: 1255, y: 350, width: 180, height: 180), in: screen), .right)
        XCTAssertEqual(DockingGeometry.candidate(for: NSRect(x: 620, y: 715, width: 200, height: 180), in: screen), .top)
        XCTAssertEqual(DockingGeometry.candidate(for: NSRect(x: 620, y: 29, width: 200, height: 180), in: screen), .bottom)
    }

    func testWindowAwayFromScreenBoundaryRemainsFloating() {
        XCTAssertEqual(DockingGeometry.candidate(for: NSRect(x: 500, y: 350, width: 220, height: 220), in: screen), .floating)
    }

    func testFloatingLayoutsNormalizeToValidAspectRatios() {
        XCTAssertEqual(FloatingLayoutGeometry.normalized(NSSize(width: 176, height: 176)), NSSize(width: 176, height: 176))
        XCTAssertEqual(FloatingLayoutGeometry.normalized(NSSize(width: 590, height: 621)), NSSize(width: 207, height: 621))
        XCTAssertEqual(FloatingLayoutGeometry.normalized(NSSize(width: 700, height: 300)), NSSize(width: 700, height: 700.0 / 3.0))
    }

    func testResizeHandleCannotCreateBoxyLayouts() {
        XCTAssertEqual(
            FloatingLayoutGeometry.resized(from: NSSize(width: 200, height: 600), deltaX: 50, deltaY: 0),
            NSSize(width: 250, height: 750)
        )
        XCTAssertEqual(
            FloatingLayoutGeometry.resized(from: NSSize(width: 600, height: 200), deltaX: 0, deltaY: -50),
            NSSize(width: 750, height: 250)
        )
        XCTAssertEqual(
            FloatingLayoutGeometry.resized(from: NSSize(width: 176, height: 176), deltaX: 30, deltaY: 0),
            NSSize(width: 206, height: 206)
        )
    }

    func testCompactLayoutOnlyEngagesAtTheEndOfTheSqueeze() {
        // Saved square compact windows remain valid at every supported size.
        XCTAssertTrue(FloatingLayoutGeometry.isCompact(NSSize(width: 132, height: 132)))
        XCTAssertFalse(FloatingLayoutGeometry.isCompact(NSSize(width: 124, height: 122)))
        XCTAssertTrue(FloatingLayoutGeometry.isCompact(NSSize(width: 120, height: 120)))
        XCTAssertTrue(FloatingLayoutGeometry.isCompact(NSSize(width: 176, height: 176)))

        let almostCompact = FloatingLayoutGeometry.resized(
            from: NSSize(width: 600, height: 200),
            deltaX: -477,
            deltaY: 0
        )
        XCTAssertEqual(almostCompact, NSSize(width: 132.5, height: 132))
        XCTAssertFalse(FloatingLayoutGeometry.isCompact(almostCompact))

        let compact = FloatingLayoutGeometry.resized(
            from: NSSize(width: 600, height: 200),
            deltaX: -482,
            deltaY: 0
        )
        XCTAssertEqual(compact, NSSize(width: 118, height: 118))
        XCTAssertTrue(FloatingLayoutGeometry.isCompact(compact))
    }

    func testShrinkingVerticalStripSquishesContinuouslyBeforeCompactSquare() {
        XCTAssertEqual(
            FloatingLayoutGeometry.resized(from: NSSize(width: 200, height: 600), deltaX: -68, deltaY: 0),
            NSSize(width: 132, height: 396)
        )
        XCTAssertEqual(
            FloatingLayoutGeometry.resized(from: NSSize(width: 200, height: 600), deltaX: -69, deltaY: 0),
            NSSize(width: 132, height: 395)
        )
        XCTAssertEqual(
            FloatingLayoutGeometry.resized(from: NSSize(width: 200, height: 600), deltaX: -200, deltaY: 0),
            NSSize(width: 132, height: 264)
        )
        XCTAssertEqual(
            FloatingLayoutGeometry.resized(from: NSSize(width: 200, height: 600), deltaX: -332, deltaY: 0),
            NSSize(width: 132, height: 132.5)
        )
    }

    func testShrinkingHorizontalStripSquishesContinuouslyBeforeCompactSquare() {
        XCTAssertEqual(
            FloatingLayoutGeometry.resized(from: NSSize(width: 600, height: 200), deltaX: -204, deltaY: 0),
            NSSize(width: 396, height: 132)
        )
        let justInsideTransition = FloatingLayoutGeometry.resized(
            from: NSSize(width: 600, height: 200),
            deltaX: -205,
            deltaY: 0
        )
        XCTAssertEqual(justInsideTransition.width, 395, accuracy: 0.001)
        XCTAssertEqual(justInsideTransition.height, 132, accuracy: 0.001)
        XCTAssertEqual(
            FloatingLayoutGeometry.resized(from: NSSize(width: 600, height: 200), deltaX: -336, deltaY: 0),
            NSSize(width: 264, height: 132)
        )
        XCTAssertEqual(
            FloatingLayoutGeometry.resized(from: NSSize(width: 600, height: 200), deltaX: -468, deltaY: 0),
            NSSize(width: 132.5, height: 132)
        )
    }

    func testStripKeepsItsAspectRatioUntilCompactThreshold() {
        XCTAssertEqual(
            FloatingLayoutGeometry.resized(from: NSSize(width: 200, height: 600), deltaX: -49, deltaY: 0),
            NSSize(width: 151, height: 453)
        )
        XCTAssertEqual(
            FloatingLayoutGeometry.resized(from: NSSize(width: 600, height: 200), deltaX: 0, deltaY: 49),
            NSSize(width: 453, height: 151)
        )
    }

    func testCursorCanMountTheDialEvenWhenGrabbedFromItsCenter() {
        XCTAssertEqual(DockingGeometry.candidate(for: NSPoint(x: 8, y: 892), in: screen), .topLeft)
        XCTAssertEqual(DockingGeometry.candidate(for: NSPoint(x: 1434, y: 450), in: screen), .right)
    }

    func testCursorOutsideTightEightPointZoneDoesNotMount() {
        XCTAssertEqual(DockingGeometry.candidate(for: NSPoint(x: 12, y: 450), in: screen), .floating)
        XCTAssertEqual(DockingGeometry.candidate(for: NSPoint(x: 720, y: 888), in: screen), .floating)
    }

    func testMountedFramesMeetExactVisibleScreenEdges() {
        let topLeft = DockingGeometry.mountedFrame(for: .topLeft, in: screen, sideFraction: 0.5)
        XCTAssertEqual(topLeft.minX, screen.minX)
        XCTAssertEqual(topLeft.maxY, screen.maxY)

        let right = DockingGeometry.mountedFrame(for: .right, in: screen, sideFraction: 0.7)
        XCTAssertEqual(right.maxX, screen.maxX)

        let bottom = DockingGeometry.mountedFrame(for: .bottom, in: screen, sideFraction: 0.25)
        XCTAssertEqual(bottom.minY, screen.minY)
    }

    func testScaledMountedFramesKeepTheirAnchorAndShape() {
        let corner = DockingGeometry.mountedFrame(
            for: .topLeft,
            in: screen,
            sideFraction: 0.5,
            scale: 1.5
        )
        XCTAssertEqual(corner.size, NSSize(width: 264, height: 264))
        XCTAssertEqual(corner.minX, screen.minX)
        XCTAssertEqual(corner.maxY, screen.maxY)

        let side = DockingGeometry.mountedFrame(
            for: .right,
            in: screen,
            sideFraction: 0.7,
            scale: 0.8
        )
        XCTAssertEqual(side.width, 89.6, accuracy: 0.001)
        XCTAssertEqual(side.height, 264, accuracy: 0.001)
        XCTAssertEqual(side.maxX, screen.maxX)
        XCTAssertEqual(
            DockingGeometry.sideFraction(for: side, position: .right, in: screen),
            0.7,
            accuracy: 0.001
        )
    }

    func testSideMountsUseSlenderRailsWhileCornersKeepTheirRadialSize() {
        XCTAssertEqual(DockPosition.topLeft.mountedSize, NSSize(width: 176, height: 176))
        XCTAssertEqual(DockPosition.left.mountedSize, NSSize(width: 112, height: 330))
        XCTAssertEqual(DockPosition.right.mountedSize, NSSize(width: 112, height: 330))
        XCTAssertEqual(DockPosition.top.mountedSize, NSSize(width: 330, height: 112))
    }

    func testSideFractionPreservesPlacementAlongAnEdge() {
        let source = NSRect(x: 0, y: 230, width: 126, height: 236)
        let fraction = DockingGeometry.sideFraction(for: source, position: .left, in: screen)
        let restored = DockingGeometry.mountedFrame(for: .left, in: screen, sideFraction: fraction)
        XCTAssertEqual(restored.midY, source.midY, accuracy: 0.001)
    }
}
