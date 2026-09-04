import XCTest
@testable import QuotaGlance

final class UsagePercentEstimatorTests: XCTestCase {
    private let windowStart = Date(timeIntervalSince1970: 2_000_000_000)

    func testAdvancesBetweenCoarseOfficialUpdates() {
        let history = [
            checkpoint(minutes: 0, percent: 27, cost: 420),
            checkpoint(minutes: 5, percent: 27, cost: 430),
            checkpoint(minutes: 10, percent: 28, cost: 449),
            checkpoint(minutes: 20, percent: 29, cost: 477)
        ]

        let estimated = UsagePercentEstimator.estimate(
            officialPercent: 29,
            quotaWeightedUSD: 591,
            windowStart: windowStart,
            history: history
        )

        XCTAssertEqual(estimated, 33, accuracy: 0.01)
    }

    func testOfficialReadingRemainsAuthorityWhenCalibrationIsMissing() {
        let history = [checkpoint(minutes: 0, percent: 29, cost: 477)]
        XCTAssertEqual(
            UsagePercentEstimator.estimate(
                officialPercent: 29,
                quotaWeightedUSD: 591,
                windowStart: windowStart,
                history: history
            ),
            29
        )
    }

    func testIgnoresOtherWindowsAndNeverMovesBackward() {
        let otherWindow = windowStart.addingTimeInterval(-7 * 86_400)
        let history = [
            checkpoint(minutes: 0, percent: 10, cost: 10, windowStart: otherWindow),
            checkpoint(minutes: 5, percent: 90, cost: 11, windowStart: otherWindow),
            checkpoint(minutes: 10, percent: 32, cost: 500),
            checkpoint(minutes: 15, percent: 33, cost: 530)
        ]

        XCTAssertEqual(
            UsagePercentEstimator.estimate(
                officialPercent: 33,
                quotaWeightedUSD: 520,
                windowStart: windowStart,
                history: history
            ),
            33
        )
    }

    private func checkpoint(
        minutes: Double,
        percent: Double,
        cost: Double,
        windowStart overrideWindow: Date? = nil
    ) -> UsageCheckpoint {
        UsageCheckpoint(
            recordedAt: windowStart.addingTimeInterval(minutes * 60),
            windowStart: overrideWindow ?? windowStart,
            resetAt: windowStart.addingTimeInterval(7 * 86_400),
            usedPercent: percent,
            weeklyTokens: 0,
            localTokensTotal: nil,
            rollingFiveMinuteTokens: nil,
            apiEquivalentUSD: nil,
            quotaWeightedUSD: cost
        )
    }
}
