import XCTest
@testable import QuotaGlance

final class ProviderTravelTests: XCTestCase {
    private let screen = CGRect(x: -1600, y: -800, width: 1600, height: 1000)

    func testEveryRideEntersAndFullyExitsEitherSideOfAnOffsetScreen() {
        for kind in [ProviderTravelKind.plane, .balloon, .skateboard] {
            for fromLeft in [true, false] {
                var ride = ProviderTravelPhysics(kind: kind, bounds: screen, fromLeft: fromLeft)
                XCTAssertFalse(screen.intersects(ride.vehicleRect))
                var entered = false
                for _ in 0..<2400 {
                    ride.step(1.0 / 30)
                    entered = entered || screen.intersects(ride.vehicleRect)
                    if ride.hasExited { break }
                }
                XCTAssertTrue(entered, "\(kind) never entered")
                XCTAssertTrue(ride.hasExited, "\(kind) never completed its visit")
                XCTAssertFalse(screen.intersects(ride.renderBounds))
            }
        }
    }

    func testPlaneCanBeCaughtThrownBackwardAndBankWithoutTeleportingItsBanner() {
        var ride = ProviderTravelPhysics(kind: .plane, bounds: screen, parked: true)
        let original = ride.position
        ride.isPaused = true
        for _ in 0..<90 { ride.step(1.0 / 30) }
        XCTAssertEqual(ride.position, original)
        ride.grab()
        let oldBanner = ride.bannerPosition
        let target = CGPoint(x: original.x - 180, y: original.y - 130)
        ride.drag(to: target, velocity: CGVector(dx: -600, dy: -320))
        XCTAssertEqual(ride.position, target)
        XCTAssertEqual(ride.bannerPosition, oldBanner, "A spring-towed banner should not snap with a drag")
        ride.release()
        ride.step(1.0 / 30)
        XCTAssertEqual(ride.heading, -1)
        XCTAssertLessThan(ride.position.x, target.x)
        XCTAssertLessThan(ride.position.y, target.y)
        XCTAssertLessThan(ride.velocity.dx, -500, "Throw momentum should survive release")
        XCTAssertNotEqual(ride.bank, 0)
        XCTAssertNotEqual(ride.bannerPosition, oldBanner)
    }

    func testDragClampsToSelectedScreenAndRejectsInvalidInput() {
        for kind in [ProviderTravelKind.plane, .balloon, .skateboard] {
            var ride = ProviderTravelPhysics(kind: kind, bounds: screen, parked: true)
            ride.grab()
            ride.drag(to: CGPoint(x: 9000, y: -9000), velocity: CGVector(dx: 9000, dy: -9000))
            XCTAssertTrue(screen.contains(ride.vehicleRect))
            let valid = ride.position
            ride.drag(to: CGPoint(x: CGFloat.nan, y: 0), velocity: .zero)
            XCTAssertEqual(ride.position, valid)
            ride.release()
            for _ in 0..<120 {
                ride.step(1.0 / 30)
                XCTAssertGreaterThanOrEqual(ride.vehicleRect.minY, screen.minY)
                XCTAssertLessThanOrEqual(ride.vehicleRect.maxY, screen.maxY)
                XCTAssertTrue(ride.bannerPosition.x.isFinite && ride.bannerPosition.y.isFinite)
            }
        }
    }

    func testDroppedSkateboardBouncesThenSettlesAboveTheDock() {
        var ride = ProviderTravelPhysics(kind: .skateboard, bounds: screen, parked: true)
        let floor = ride.position.y
        ride.grab()
        ride.drag(to: CGPoint(x: screen.midX, y: floor + 250), velocity: .zero)
        ride.release()
        var bounced = false
        for _ in 0..<300 {
            let falling = ride.velocity.dy < -60
            ride.step(1.0 / 30)
            bounced = bounced || (falling && ride.velocity.dy > 0)
            XCTAssertGreaterThanOrEqual(ride.position.y, floor)
        }
        XCTAssertTrue(bounced)
        XCTAssertEqual(ride.position.y, floor, accuracy: 0.1)
        XCTAssertEqual(ride.velocity.dy, 0, accuracy: 0.1)
    }

    func testBannerSettlesUnderBalloonWhileHeldAndReducedMotionDoesNotCruise() {
        var ride = ProviderTravelPhysics(kind: .balloon, bounds: screen, parked: true)
        let original = ride.position
        for _ in 0..<90 { ride.step(1.0 / 30, parked: true) }
        XCTAssertEqual(ride.position, original)
        XCTAssertEqual(ride.bank, 0)
        ride.grab()
        ride.drag(to: CGPoint(x: original.x + 150, y: original.y - 80), velocity: .zero)
        for _ in 0..<300 { ride.step(1.0 / 30) }
        XCTAssertEqual(ride.bannerPosition.x, ride.bannerTarget.x, accuracy: 0.1)
        XCTAssertEqual(ride.bannerPosition.y, ride.bannerTarget.y, accuracy: 0.1)
    }

    func testCadenceIsMeasuredBetweenStartsAndLongInteractionsStillGetABreak() {
        XCTAssertEqual(ProviderTravelFrequency.often.rest(after: 25), 20)
        XCTAssertEqual(ProviderTravelFrequency.often.rest(after: 100), 4)
        XCTAssertEqual(ProviderTravelFrequency.continuous.rest(after: 25), 4)
        XCTAssertEqual(ProviderTravelFrequency.relaxed.rest(after: 25), 95)
    }
}
