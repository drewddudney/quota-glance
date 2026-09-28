import XCTest
@testable import QuotaGlanceMobile

final class ClaudeQuotaTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(weekly: Double = 92, fiveHour: Double = 95) -> ClaudeQuotaSnapshot {
        ClaudeQuotaSnapshot(capturedAt: now, usagePercent: weekly,
            resetAt: now.addingTimeInterval(3 * 86_400), planName: "Max", accountID: "account-a",
            verified: true, needsConnection: false, fiveHourUsagePercent: fiveHour,
            fiveHourResetAt: now.addingTimeInterval(2 * 3_600))
    }

    private func events(_ current: ClaudeQuotaSnapshot, previous: ClaudeQuotaSnapshot? = nil,
                        usage: Bool = true, week: Bool = true, seen: Set<String> = []) -> [ClaudeNotificationEvent] {
        ClaudeNotificationPolicy.events(current: current, previous: previous, usageEnabled: usage,
            weekEnabled: week, threshold: 90, seen: seen, now: now)
    }

    func testIndependentWindowsAndRollingCalendar() throws {
        var value = reading()
        XCTAssertEqual(try XCTUnwrap(value.weekElapsedPercent(at: now)), 400.0 / 7, accuracy: 0.0001)
        value.fiveHourResetAt = now
        XCTAssertNil(value.displayedFiveHourUsage(at: now))
        XCTAssertEqual(value.displayedUsage(at: now), 92)
        value.fiveHourResetAt = now.addingTimeInterval(3600)
        value.resetAt = now
        XCTAssertNil(value.displayedUsage(at: now))
        XCTAssertEqual(value.displayedFiveHourUsage(at: now), 95)
        XCTAssertEqual(value.weekElapsedPercent(at: now), 100)
    }

    func testAlertsDeduplicateEachWindowSeparately() {
        let value = reading()
        let first = events(value)
        XCTAssertEqual(first.count, 2)
        XCTAssertTrue(first.contains { $0.id.hasPrefix("claude-weekly-limit-") })
        XCTAssertTrue(first.contains { $0.id.hasPrefix("claude-five-hour-limit-") })
        let seen = Set(first.map(\.id))
        XCTAssertTrue(events(value, seen: seen).isEmpty)
        var next = value
        next.fiveHourResetAt = value.fiveHourResetAt?.addingTimeInterval(5 * 3600)
        let newSession = events(next, seen: seen)
        XCTAssertEqual(newSession.count, 1)
        XCTAssertTrue(newSession[0].id.hasPrefix("claude-five-hour-limit-"))
    }

    func testStaleDisconnectedAndExpiredReadingsDoNotNotify() {
        var value = reading()
        value.capturedAt = now.addingTimeInterval(-901)
        XCTAssertTrue(events(value).isEmpty)
        value = reading(); value.needsConnection = true
        XCTAssertTrue(events(value).isEmpty)
        value = reading(); value.verified = false
        XCTAssertTrue(events(value).isEmpty)
        value = reading(); value.fiveHourResetAt = now
        XCTAssertEqual(events(value).count, 1)
        value.resetAt = now
        XCTAssertTrue(events(value).isEmpty)
        XCTAssertTrue(events(reading(), usage: false, week: false).isEmpty)
    }

    func testWeeklyRenewalRequiresFreshConfirmedWindowOnSameAccount() {
        var old = reading(weekly: 82, fiveHour: 12)
        old.capturedAt = now.addingTimeInterval(-120)
        old.resetAt = now.addingTimeInterval(-60)
        var current = reading(weekly: 0, fiveHour: 12)
        current.resetAt = old.resetAt?.addingTimeInterval(7 * 86_400)
        let renewed = events(current, previous: old)
        XCTAssertEqual(renewed.count, 1)
        XCTAssertEqual(renewed[0].title, "Your new Claude week is ready")
        XCTAssertTrue(events(current, previous: old, seen: Set(renewed.map(\.id))).isEmpty)
        XCTAssertTrue(events(old, previous: old).isEmpty)
        current.accountID = "account-b"
        XCTAssertTrue(events(current, previous: old).isEmpty)
        current.accountID = "account-a"
        current.resetAt = old.resetAt?.addingTimeInterval(3600)
        XCTAssertTrue(events(current, previous: old).isEmpty)
    }

    func testOldMacPayloadAndNewClaudePayloadRoundTripWithoutChangingCodex() throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        var snapshot = QuotaSnapshot.empty
        snapshot.capturedAt = now
        snapshot.usageUpdatedAt = now.addingTimeInterval(-600)
        snapshot.usagePercent = 15
        snapshot.resetChancePercent = 56
        let oldData = try encoder.encode(snapshot)
        XCTAssertNil(try decoder.decode(QuotaSnapshot.self, from: oldData).claude)
        snapshot.claude = reading()
        let restored = try decoder.decode(QuotaSnapshot.self, from: encoder.encode(snapshot))
        XCTAssertEqual(restored.claude, reading())
        XCTAssertEqual(restored.usagePercent, 15)
        XCTAssertEqual(restored.resetChancePercent, 56)
        XCTAssertEqual(restored.usageMeasurementDate, now.addingTimeInterval(-600))
        XCTAssertEqual(restored.claude?.capturedAt, now)
    }

    func testMissingPercentagesRemainUnavailable() {
        var value = reading()
        value.usagePercent = nil
        value.fiveHourUsagePercent = nil
        value.resetAt = nil
        XCTAssertNil(value.displayedUsage(at: now))
        XCTAssertNil(value.displayedFiveHourUsage(at: now))
        XCTAssertNil(value.weekElapsedPercent(at: now))
        XCTAssertTrue(events(value).isEmpty)
    }

    private func sample(_ used: Double?, at date: Date, account: String = "account-a", end: Date? = nil) -> ClaudeQuotaSnapshot {
        ClaudeQuotaSnapshot(capturedAt: date, usagePercent: used, resetAt: end ?? now.addingTimeInterval(3 * 86_400),
                            planName: "Max", accountID: account, verified: true, needsConnection: false)
    }

    func testClaudeRecordsActualSamplesAndLearnsPaceAfterAMinute() throws {
        let first = ClaudeUsageHistory.record(sample(50, at: now.addingTimeInterval(-120)), previous: nil, now: now)
        XCTAssertEqual(first.usageHistory?.map(\.usedPercent), [50])
        XCTAssertNil(first.estimatedRunoutAt)
        let current = ClaudeUsageHistory.record(sample(54, at: now), previous: first, now: now)
        XCTAssertEqual(current.usageHistory?.map(\.usedPercent), [50, 54])
        XCTAssertEqual(try XCTUnwrap(current.estimatedRunoutAt).timeIntervalSince(now), 1_380, accuracy: 0.001)
        let encoded = try JSONEncoder().encode(current)
        let restored = try JSONDecoder().decode(ClaudeQuotaSnapshot.self, from: encoded)
        let overlay = ClaudeUsageHistory.record(current, previous: restored, now: now.addingTimeInterval(900))
        XCTAssertEqual(overlay.usageHistory, current.usageHistory)
        XCTAssertEqual(overlay.capturedAt, now)
        XCTAssertEqual(ClaudeUsageHistory.record(current, previous: restored, now: now.addingTimeInterval(901)).estimatedRunoutAt, nil)
    }

    func testClaudeFrequentRefreshesDoNotManufactureFastBurn() {
        let first = ClaudeUsageHistory.record(sample(10, at: now), previous: nil, now: now)
        let next = ClaudeUsageHistory.record(sample(11, at: now.addingTimeInterval(20)), previous: first, now: now.addingTimeInterval(20))
        XCTAssertEqual(next.usagePercent, 11)
        XCTAssertEqual(next.usageHistory?.count, 1)
        XCTAssertNil(next.estimatedRunoutAt)
        let minute = ClaudeUsageHistory.record(sample(12, at: now.addingTimeInterval(60)), previous: next, now: now.addingTimeInterval(60))
        XCTAssertEqual(minute.usageHistory?.map(\.usedPercent), [10, 12])
        XCTAssertNotNil(minute.estimatedRunoutAt)
    }

    func testClaudeMigrationKeepsOnlyThePreviousRealCachedMeasurement() {
        let saved = sample(50, at: now.addingTimeInterval(-120))
        XCTAssertNil(saved.usageHistory)
        let migrated = ClaudeUsageHistory.record(sample(54, at: now), previous: saved, now: now)
        XCTAssertEqual(migrated.usageHistory?.map(\.date), [now.addingTimeInterval(-120), now])
        XCTAssertEqual(migrated.usageHistory?.map(\.usedPercent), [50, 54])
        XCTAssertNotNil(migrated.estimatedRunoutAt)
        let repeated = ClaudeUsageHistory.record(saved, previous: saved, now: now)
        XCTAssertEqual(repeated.usageHistory?.map(\.date), [saved.capturedAt!])
    }

    func testClaudeDecreaseWithinSamplingMinuteStartsANewPaceSegment() {
        let first = ClaudeUsageHistory.record(sample(80, at: now.addingTimeInterval(-120)), previous: nil, now: now)
        let second = ClaudeUsageHistory.record(sample(81, at: now.addingTimeInterval(-10)), previous: first, now: now)
        let reset = ClaudeUsageHistory.record(sample(1, at: now), previous: second, now: now)
        XCTAssertEqual(reset.usageHistory?.map(\.usedPercent), [80, 81, 1])
        XCTAssertNil(reset.estimatedRunoutAt)
    }

    func testClaudeNormalRenewalArchivesOnlyRealOldPoints() {
        let oldEnd = now.addingTimeInterval(-60)
        let old = ClaudeUsageHistory.record(sample(87, at: now.addingTimeInterval(-120), end: oldEnd), previous: nil,
                                           now: now.addingTimeInterval(-120))
        let current = ClaudeUsageHistory.record(sample(2, at: now, end: oldEnd.addingTimeInterval(7 * 86_400)), previous: old, now: now)
        XCTAssertEqual(current.usageHistory?.map(\.usedPercent), [2])
        XCTAssertNil(current.estimatedRunoutAt)
        XCTAssertEqual(current.weeklyArchives?.first?.resetAt, oldEnd)
        XCTAssertEqual(current.weeklyArchives?.first?.points, old.usageHistory)
        XCTAssertEqual(current.weeklyArchives?.first?.finalUsedPercent, 87)
    }

    func testClaudeSwitchAndOutOfOrderCompletionCannotReuseOtherHistory() {
        let first = ClaudeUsageHistory.record(sample(50, at: now.addingTimeInterval(-120)), previous: nil, now: now)
        let current = ClaudeUsageHistory.record(sample(54, at: now), previous: first, now: now)
        let late = ClaudeUsageHistory.record(sample(90, at: now.addingTimeInterval(-60)), previous: current, now: now)
        XCTAssertEqual(late.usagePercent, 54)
        XCTAssertEqual(late.usageHistory, current.usageHistory)
        XCTAssertEqual(late.capturedAt, now)
        let switched = ClaudeUsageHistory.record(sample(90, at: now, account: "account-b"), previous: current, now: now)
        XCTAssertEqual(switched.usageHistory?.map(\.usedPercent), [90])
        XCTAssertEqual(switched.weeklyArchives, [])
        XCTAssertNil(switched.estimatedRunoutAt)
    }

    func testClaudePaceRestartsAfterADecreaseEvenWithUnchangedWindow() throws {
        var value: ClaudeQuotaSnapshot?
        for (seconds, used) in [(-600.0, 85.0), (-300, 90), (-120, 1), (0, 3)] {
            value = ClaudeUsageHistory.record(sample(used, at: now.addingTimeInterval(seconds)), previous: value, now: now)
        }
        XCTAssertEqual(value?.usageHistory?.map(\.usedPercent), [85, 90, 1, 3])
        XCTAssertEqual(try XCTUnwrap(value?.estimatedRunoutAt).timeIntervalSince(now), 5_820, accuracy: 0.001)
        var invalid = try XCTUnwrap(value)
        invalid.needsConnection = true
        XCTAssertNil(ClaudeUsageHistory.estimate(for: invalid, now: now))
        invalid.needsConnection = false
        invalid.resetAt = now
        XCTAssertNil(ClaudeUsageHistory.estimate(for: invalid, now: now))
    }

    func testClaudeMissingInvalidAndFutureSamplesNeverBecomeZeroHistory() {
        for percent in [Double?.none, .some(.nan), .some(.infinity), .some(-1), .some(101)] {
            let result = ClaudeUsageHistory.record(sample(percent, at: now), previous: nil, now: now)
            XCTAssertEqual(result.usageHistory, [])
            XCTAssertNil(result.estimatedRunoutAt)
        }
        let future = ClaudeUsageHistory.record(sample(90, at: now.addingTimeInterval(61)), previous: nil, now: now)
        XCTAssertEqual(future.usageHistory, [])
        var noWindow = sample(20, at: now)
        noWindow.resetAt = nil
        XCTAssertEqual(ClaudeUsageHistory.record(noWindow, previous: nil, now: now).usageHistory, [])
    }

    func testClaudeHistoryIsOrderedDeduplicatedAndBounded() {
        var old = sample(60, at: now.addingTimeInterval(-60))
        old.usageHistory = (3...13_002).reversed().map {
            .init(date: now.addingTimeInterval(-Double($0) * 20), usedPercent: 60)
        }
        old.usageHistory?.append(.init(date: now.addingTimeInterval(-60), usedPercent: 60))
        old.usageHistory?.append(.init(date: now.addingTimeInterval(-60), usedPercent: -1))
        let current = ClaudeUsageHistory.record(sample(61, at: now), previous: old, now: now)
        XCTAssertEqual(current.usageHistory?.count, ClaudeUsageHistory.maximumPoints)
        let dates = current.usageHistory?.map(\.date) ?? []
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(Set(dates).count, dates.count)
        XCTAssertEqual(current.usageHistory?.last?.usedPercent, 61)
    }

    func testLegacyClaudeSnapshotWithoutHistoryStillDecodes() throws {
        let data = try JSONEncoder().encode(reading())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["usageHistory", "weeklyArchives", "estimatedRunoutAt", "paceWindowLabel"] { object.removeValue(forKey: key) }
        let value = try JSONDecoder().decode(ClaudeQuotaSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(value.usageHistory)
        XCTAssertNil(value.estimatedRunoutAt)
        XCTAssertEqual(value.usagePercent, 92)
    }
}
