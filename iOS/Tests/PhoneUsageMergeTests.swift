import XCTest
@testable import QuotaGlanceMobile

final class PhoneUsageMergeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(_ provider: DirectUsageProvider = .codex, account: String = "phone-account", used: Double = 40,
                         measuredAt: Date? = nil, deadline: Date? = nil) -> DirectProviderUsage {
        DirectProviderUsage(provider: provider, measuredAt: measuredAt ?? now, accountID: account,
                            weekly: DirectUsageWindow(usedPercent: used, resetAt: deadline ?? now.addingTimeInterval(3 * 86_400), durationMinutes: 10_080),
                            fiveHour: DirectUsageWindow(usedPercent: 12, resetAt: now.addingTimeInterval(3_600), durationMinutes: 300), planName: nil)
    }

    func testPhoneUsageWinsEvenWhenMacSnapshotIsNewer() {
        var mac = QuotaSnapshot.empty
        mac.capturedAt = now.addingTimeInterval(30)
        mac.usageUpdatedAt = mac.capturedAt
        mac.usagePercent = 95
        mac.resetChancePercent = 71
        let result = PhoneUsageMerge.merge(base: mac, previous: .empty, readings: [reading()], connections: [.codex], now: now)
        XCTAssertEqual(result.usagePercent, 40)
        XCTAssertEqual(result.usageMeasurementDate, now)
        XCTAssertEqual(result.resetChancePercent, 71)
        XCTAssertEqual(result.secondaryQuota?.usedPercent, 12)
    }

    func testFiveHourReadingIsNeverSubstitutedForMissingWeeklyQuota() {
        let sessionOnly = DirectProviderUsage(provider: .codex, measuredAt: now, accountID: "account", weekly: nil,
                                             fiveHour: DirectUsageWindow(usedPercent: 23, resetAt: now.addingTimeInterval(3_600), durationMinutes: 300), planName: nil)
        var previous = QuotaSnapshot.empty
        previous.usagePercent = 99
        let result = PhoneUsageMerge.merge(base: previous, previous: previous, readings: [sessionOnly], connections: [.codex], now: now)
        XCTAssertNil(result.usagePercent)
        XCTAssertNil(result.resetAt)
        XCTAssertNil(result.weekElapsedPercent)
        XCTAssertEqual(result.secondaryQuota?.usedPercent, 23)
    }

    func testSwitchingAccountsClearsHistoryAndDoesNotAnnounceFalseReset() {
        var old = PhoneUsageMerge.merge(base: .empty, previous: .empty, readings: [reading(used: 80, measuredAt: now.addingTimeInterval(-300))], connections: [.codex], now: now)
        old.weeklyTokens = 5_000_000
        old.weeklyArchives = [.init(windowStart: now.addingTimeInterval(-14 * 86_400), resetAt: now.addingTimeInterval(-7 * 86_400),
                                  finalUsedPercent: 50, totalTokens: 100, apiEquivalentUSD: nil, cacheHitRate: nil, fastShare: nil, topModel: nil, points: [])]
        let result = PhoneUsageMerge.merge(base: old, previous: old, readings: [reading(account: "different-account", used: 0)], connections: [.codex], includeMacDetails: true, now: now)
        XCTAssertEqual(result.usageHistory?.map(\.usedPercent), [0])
        XCTAssertEqual(result.weeklyArchives?.count, 0)
        XCTAssertNil(result.weeklyTokens)
        XCTAssertFalse(NotificationManager.didUsageReset(previous: old, current: result))
    }

    func testRepeatedOverlayKeepsOneSampleAndForecastCannotRefreshUsage() {
        let usage = reading()
        let first = PhoneUsageMerge.merge(base: .empty, previous: .empty, readings: [usage], connections: [.codex], now: now)
        var forecast = first
        forecast.capturedAt = now.addingTimeInterval(3_600)
        forecast.forecastUpdatedAt = forecast.capturedAt
        let result = PhoneUsageMerge.merge(base: forecast, previous: first, readings: [usage], connections: [.codex], now: forecast.capturedAt)
        XCTAssertEqual(result.usageHistory?.count, 1)
        XCTAssertEqual(result.usageMeasurementDate, now)
        XCTAssertEqual(result.usageHistory?.first?.date, now)
    }

    func testIndependentClaudeConnectionPreservesCodexAndDisconnectClearsClaude() {
        var base = QuotaSnapshot.empty
        base.usagePercent = 62
        let connected = PhoneUsageMerge.merge(base: base, previous: base, readings: [reading(.claude)], connections: [.claude], now: now)
        XCTAssertEqual(connected.usagePercent, 62)
        XCTAssertEqual(connected.claude?.usagePercent, 40)
        XCTAssertEqual(connected.claude?.fetchedOnPhone, true)
        let disconnected = PhoneUsageMerge.merge(base: connected, previous: connected, readings: [], connections: [], now: now)
        XCTAssertNil(disconnected.claude)
        XCTAssertEqual(disconnected.usagePercent, 62)
    }

    func testAuthFailureKeepsSavedNumbersAndMarksReconnect() {
        let result = PhoneUsageMerge.merge(base: .empty, previous: .empty, readings: [reading(), reading(.claude)],
                                          connections: [.codex, .claude], needsConnection: [.codex, .claude], now: now)
        XCTAssertEqual(result.usagePercent, 40)
        XCTAssertEqual(result.claude?.usagePercent, 40)
        XCTAssertTrue(MobileProviderReading(provider: .codex, snapshot: result, at: now).needsConnection)
        XCTAssertTrue(MobileProviderReading(provider: .claude, snapshot: result, at: now).needsConnection)
        XCTAssertTrue(ProviderUsageActivityAttributes.state(snapshot: result, providers: [.codex, .claude], now: now).readings.isEmpty)
    }

    func testNewWindowArchivesPhoneSamplesAndStartsFresh() {
        let old = PhoneUsageMerge.merge(base: .empty, previous: .empty,
                                       readings: [reading(used: 87, measuredAt: now.addingTimeInterval(-120), deadline: now.addingTimeInterval(-60))],
                                       connections: [.codex], now: now.addingTimeInterval(-120))
        let result = PhoneUsageMerge.merge(base: old, previous: old, readings: [reading(used: 2, deadline: now.addingTimeInterval(7 * 86_400 - 60))],
                                          connections: [.codex], now: now)
        XCTAssertEqual(result.weeklyArchives?.first?.finalUsedPercent, 87)
        XCTAssertEqual(result.weeklyArchives?.first?.points.count, 1)
        XCTAssertEqual(result.usageHistory?.map(\.usedPercent), [2])
    }

    func testLiveActivityHonorsProviderSelectionAndOriginalMeasurementTime() {
        let saved = now.addingTimeInterval(-1_800)
        let value = PhoneUsageMerge.merge(base: .empty, previous: .empty,
                                         readings: [reading(measuredAt: saved), reading(.claude)], connections: [.codex, .claude], now: now)
        let both = ProviderUsageActivityAttributes.state(snapshot: value, providers: [.codex, .claude], now: now)
        XCTAssertEqual(both.readings.map(\.provider), ["codex", "claude"])
        XCTAssertEqual(both.readings.first?.measuredAt, saved)
        XCTAssertEqual(ProviderUsageActivityAttributes.state(snapshot: value, providers: [.claude], now: now).readings.map(\.provider), ["claude"])
    }

    func testClaudeHistorySurvivesSavedSnapshotAndNewerMacOverlay() throws {
        let first = PhoneUsageMerge.merge(base: .empty, previous: .empty,
            readings: [reading(.claude, used: 50, measuredAt: now.addingTimeInterval(-120))], connections: [.claude], now: now)
        let restored = try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(first))
        var mac = QuotaSnapshot.empty
        mac.capturedAt = now.addingTimeInterval(30)
        mac.claude = ClaudeQuotaSnapshot(capturedAt: mac.capturedAt, usagePercent: 99, resetAt: now.addingTimeInterval(3 * 86_400),
            planName: nil, accountID: "mac-account", verified: true, needsConnection: false)
        let result = PhoneUsageMerge.merge(base: mac, previous: restored,
            readings: [reading(.claude, used: 54)], connections: [.claude], includeMacDetails: true, now: now)
        XCTAssertEqual(result.claude?.usageHistory?.map(\.usedPercent), [50, 54])
        XCTAssertEqual(result.claude?.usagePercent, 54)
        XCTAssertEqual(result.claude?.accountID, "phone-account")
        XCTAssertNotNil(result.claude?.estimatedRunoutAt)
        let repeated = PhoneUsageMerge.merge(base: mac, previous: result,
            readings: [reading(.claude, used: 54)], connections: [.claude], now: now.addingTimeInterval(60))
        XCTAssertEqual(repeated.claude?.usageHistory, result.claude?.usageHistory)
        XCTAssertEqual(repeated.claude?.capturedAt, now)
    }
}
