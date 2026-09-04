import XCTest
@testable import QuotaGlance

final class WeeklyUsageArchiveTests: XCTestCase {
    func testHourlyArchiveKeepsLastCheckpointPerHour() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            checkpoint(start: start, minutes: 5, percent: 1),
            checkpoint(start: start, minutes: 55, percent: 8),
            checkpoint(start: start, minutes: 65, percent: 10),
            checkpoint(start: start, minutes: 130, percent: 14),
        ]

        let compact = WeeklyUsageArchiveStore.hourlyPoints(points, windowStart: start)

        XCTAssertEqual(compact.count, 3)
        XCTAssertEqual(compact.map(\.usedPercent), [8, 10, 14])
    }

    func testHourlyArchiveRetainsCostAndTokenWitnesses() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let compact = WeeklyUsageArchiveStore.hourlyPoints(
            [checkpoint(start: start, minutes: 70, percent: 22, api: 91.25, tokens: 4_200)],
            windowStart: start
        )

        XCTAssertEqual(compact.first?.apiEquivalentUSD, 91.25)
        XCTAssertEqual(compact.first?.localTokensTotal, 4_200)
    }

    private func checkpoint(
        start: Date,
        minutes: Int,
        percent: Double,
        api: Double? = nil,
        tokens: Int64? = nil
    ) -> UsageCheckpoint {
        UsageCheckpoint(
            recordedAt: start.addingTimeInterval(Double(minutes) * 60),
            windowStart: start,
            resetAt: start.addingTimeInterval(7 * 86_400),
            usedPercent: percent,
            weeklyTokens: tokens ?? 0,
            localTokensTotal: tokens,
            rollingFiveMinuteTokens: nil,
            apiEquivalentUSD: api,
            quotaWeightedUSD: nil
        )
    }
}
