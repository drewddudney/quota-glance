import XCTest
@testable import QuotaGlance

final class ResetLifecycleTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ResetLifecycleStore.resetForTests()
    }

    override func tearDown() {
        ResetLifecycleStore.resetForTests()
        super.tearDown()
    }

    func testFirstAnnouncementTimeStaysPinnedAcrossProviderDrift() {
        let detected = Date(timeIntervalSince1970: 2_000_000_000)
        let fourPM = detected.addingTimeInterval(2 * 3_600)
        let fivePM = fourPM.addingTimeInterval(3_600)
        let first = ResetAnnouncement(
            id: "first-source",
            source: .lunarWerx,
            detectedAt: detected,
            expectedAt: fourPM,
            text: "Reset at 2pm PT",
            url: nil
        )
        let mirror = ResetAnnouncement(
            id: "late-mirror",
            source: .codexResets,
            detectedAt: detected.addingTimeInterval(2 * 60),
            expectedAt: fivePM,
            text: "Reset expected later",
            url: nil
        )

        XCTAssertEqual(ResetLifecycleStore.observeAnnouncement(first).expectedAt, fourPM)
        XCTAssertEqual(ResetLifecycleStore.observeAnnouncement(mirror).expectedAt, fourPM)
    }

    func testExistingLaterCacheCanMigrateToEarlierConcreteTime() {
        let detected = Date(timeIntervalSince1970: 2_000_000_000)
        let fourPM = detected.addingTimeInterval(2 * 3_600)
        let fivePM = fourPM.addingTimeInterval(3_600)
        let stale = ResetAnnouncement(
            id: "stale-provider",
            source: .codexResets,
            detectedAt: detected,
            expectedAt: fivePM,
            text: "Estimated reset",
            url: nil
        )
        let concrete = ResetAnnouncement(
            id: "tweet-time",
            source: .lunarWerx,
            detectedAt: detected.addingTimeInterval(2 * 60),
            expectedAt: fourPM,
            text: "Reset at 2pm PT",
            url: nil
        )

        XCTAssertNil(ResetLifecycleStore.observeAnnouncement(stale).activeExpectedAt())
        XCTAssertEqual(ResetLifecycleStore.observeAnnouncement(concrete).expectedAt, fourPM)
    }

    func testPassedAnnouncementBecomesDelayedWithoutCountingUp() {
        let detected = Date(timeIntervalSince1970: 2_000_000_000)
        let expected = detected.addingTimeInterval(60)
        let announcement = ResetAnnouncement(
            id: "announcement",
            source: .lunarWerx,
            detectedAt: detected,
            expectedAt: expected,
            text: "Reset at 4:30 PM CT",
            url: nil
        )
        let state = ResetLifecycleStore.observeAnnouncement(announcement)

        XCTAssertFalse(state.isDelayed(at: expected.addingTimeInterval(-1)))
        XCTAssertTrue(state.isDelayed(at: expected.addingTimeInterval(1)))
        XCTAssertEqual(state.expectedAt, expected)
    }

    func testConfirmedWindowResetClearsCountdownUntilLocalMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let start = try XCTUnwrap(calendar.date(from: .init(
            year: 2026, month: 8, day: 30, hour: 12
        )))
        _ = ResetLifecycleStore.observeUsage(windowStart: start, usedPercent: 42, observedAt: start)
        let completion = start.addingTimeInterval(4 * 3_600)
        let state = ResetLifecycleStore.observeUsage(
            windowStart: start.addingTimeInterval(7 * 86_400),
            usedPercent: 0,
            observedAt: completion
        )

        XCTAssertNil(state.expectedAt)
        XCTAssertEqual(state.completedAt, completion)
        let beforeMidnight = try XCTUnwrap(calendar.date(from: .init(
            year: 2026, month: 8, day: 30, hour: 23, minute: 59
        )))
        let midnight = try XCTUnwrap(calendar.date(from: .init(
            year: 2026, month: 8, day: 31, hour: 0
        )))
        XCTAssertTrue(state.isRecentlyCompleted(at: beforeMidnight, calendar: calendar))
        XCTAssertFalse(state.isRecentlyCompleted(at: midnight, calendar: calendar))
    }

    func testOldAnnouncementCannotReopenAfterConfirmedReset() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let expected = start.addingTimeInterval(2 * 3_600)
        let original = ResetAnnouncement(
            id: "original",
            source: .gussuri,
            detectedAt: start,
            expectedAt: expected,
            text: "Reset at 2 PM",
            url: nil
        )
        _ = ResetLifecycleStore.observeAnnouncement(original, observedAt: start)
        _ = ResetLifecycleStore.observeUsage(windowStart: start, usedPercent: 40, observedAt: start)

        let completion = expected.addingTimeInterval(3 * 3_600)
        _ = ResetLifecycleStore.observeUsage(
            windowStart: start.addingTimeInterval(7 * 86_400),
            usedPercent: 0,
            observedAt: completion
        )
        let rediscoveredMirror = ResetAnnouncement(
            id: "mirror-with-fresh-detection",
            source: .codexResets,
            detectedAt: completion.addingTimeInterval(60),
            expectedAt: expected,
            text: "Old reset rediscovered",
            url: nil
        )
        let state = ResetLifecycleStore.observeAnnouncement(
            rediscoveredMirror,
            observedAt: completion.addingTimeInterval(60)
        )

        XCTAssertNil(state.expectedAt)
        XCTAssertNil(state.announcementID)
        XCTAssertEqual(state.completedAt, completion)
    }

    func testAnnouncementActiveWindowDoesNotOutliveItsExpectedTimeByMoreThanThreeHours() {
        let detected = Date(timeIntervalSince1970: 2_000_000_000)
        let expected = detected.addingTimeInterval(3_600)
        let announcement = ResetAnnouncement(
            id: "timed-reset",
            source: .gussuri,
            detectedAt: detected,
            expectedAt: expected,
            text: "Reset at 4:30 PM CT",
            url: nil
        )

        XCTAssertTrue(announcement.isActive(at: expected.addingTimeInterval(3 * 3_600)))
        XCTAssertFalse(announcement.isActive(at: expected.addingTimeInterval(3 * 3_600 + 1)))
    }

    func testDelayedAnnouncementExpiresAfterOneDay() {
        let detected = Date(timeIntervalSince1970: 2_000_000_000)
        let expected = detected.addingTimeInterval(60)
        let announcement = ResetAnnouncement(
            id: "stale-delay",
            source: .lunarWerx,
            detectedAt: detected,
            expectedAt: expected,
            text: "Reset at 4:30 PM CT",
            url: nil
        )
        _ = ResetLifecycleStore.observeAnnouncement(announcement, observedAt: detected)

        let expiredAt = expected.addingTimeInterval(24 * 3_600)
        let state = ResetLifecycleStore.load(at: expiredAt)
        XCTAssertNil(state.expectedAt)
        XCTAssertNil(state.announcementID)
        XCTAssertFalse(state.isDelayed(at: expiredAt))
        XCTAssertNil(state.activeExpectedAt(at: expiredAt))
    }

    func testSingleZeroReadingWithoutNewBoundaryDoesNotConfirmReset() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        _ = ResetLifecycleStore.observeUsage(
            windowStart: start,
            usedPercent: 62,
            planName: "Pro 20X",
            observedAt: start
        )

        let candidate = ResetLifecycleStore.observeUsage(
            windowStart: start,
            usedPercent: 0,
            planName: "Pro 20X",
            observedAt: start.addingTimeInterval(10)
        )

        XCTAssertNil(candidate.completedAt)
        XCTAssertTrue(candidate.hasPendingResetCandidate)
    }

    func testProbabilityDeadlineNeverBecomesCountdownOrDelayedState() {
        let detected = Date(timeIntervalSince1970: 2_000_000_000)
        let inferred = ResetAnnouncement(
            id: "forecast-over-sixty",
            source: .codexResets,
            detectedAt: detected,
            expectedAt: detected.addingTimeInterval(3_600),
            text: "95% chance of reset by this evening",
            url: nil
        )

        let state = ResetLifecycleStore.observeAnnouncement(inferred, observedAt: detected)

        XCTAssertNil(state.activeExpectedAt(at: detected))
        XCTAssertFalse(state.isDelayed(at: detected.addingTimeInterval(2 * 3_600)))
    }

    func testSecondLowReadingConfirmsFallbackReset() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        _ = ResetLifecycleStore.observeUsage(
            windowStart: start,
            usedPercent: 62,
            planName: "Pro 20X",
            observedAt: start
        )
        _ = ResetLifecycleStore.observeUsage(
            windowStart: start,
            usedPercent: 0,
            planName: "Pro 20X",
            observedAt: start.addingTimeInterval(10)
        )
        let confirmedAt = start.addingTimeInterval(75)
        let confirmed = ResetLifecycleStore.observeUsage(
            windowStart: start,
            usedPercent: 1,
            planName: "Pro 20X",
            observedAt: confirmedAt
        )

        XCTAssertEqual(confirmed.completedAt, confirmedAt)
        XCTAssertFalse(confirmed.hasPendingResetCandidate)
    }

    func testZeroDropCanConfirmResetEvenWhenPreviousUsageWasBelowTwentyFivePercent() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        _ = ResetLifecycleStore.observeUsage(
            windowStart: start,
            usedPercent: 7,
            planName: "Pro 20X",
            observedAt: start
        )
        _ = ResetLifecycleStore.observeUsage(
            windowStart: start,
            usedPercent: 0,
            planName: "Pro 20X",
            observedAt: start.addingTimeInterval(10)
        )
        let confirmedAt = start.addingTimeInterval(75)
        let confirmed = ResetLifecycleStore.observeUsage(
            windowStart: start,
            usedPercent: 0,
            planName: "Pro 20X",
            observedAt: confirmedAt
        )

        XCTAssertEqual(confirmed.completedAt, confirmedAt)
    }

    func testPlanChangeClearsLowCandidateInsteadOfConfirmingReset() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        _ = ResetLifecycleStore.observeUsage(
            windowStart: start,
            usedPercent: 62,
            planName: "Pro 20X",
            observedAt: start
        )
        _ = ResetLifecycleStore.observeUsage(
            windowStart: start,
            usedPercent: 0,
            planName: "Pro 20X",
            observedAt: start.addingTimeInterval(10)
        )
        let changed = ResetLifecycleStore.observeUsage(
            windowStart: start,
            usedPercent: 0,
            planName: "Plus",
            observedAt: start.addingTimeInterval(80)
        )

        XCTAssertNil(changed.completedAt)
        XCTAssertFalse(changed.hasPendingResetCandidate)
    }
}
