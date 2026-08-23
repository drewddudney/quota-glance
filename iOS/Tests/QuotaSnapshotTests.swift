import XCTest
@testable import QuotaGlanceMobile

final class QuotaSnapshotTests: XCTestCase {
    func testAnnouncementAlwaysOverridesResetChanceToOneHundred() {
        var snapshot = QuotaSnapshot.empty
        snapshot.resetChancePercent = 18
        snapshot.resetAnnounced = true
        XCTAssertEqual(snapshot.effectiveResetChance, 100)
    }

    func testSnapshotRoundTripsForCloudKitPayload() throws {
        var snapshot = QuotaSnapshot.empty
        snapshot.capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        snapshot.usagePercent = 91
        snapshot.weekElapsedPercent = 44
        snapshot.resetChancePercent = 73
        snapshot.selectedSource = .gussuri
        snapshot.providers = [ProviderReading(source: .gussuri, percent: 73, updatedAt: snapshot.capturedAt)]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let restored = try decoder.decode(QuotaSnapshot.self, from: encoder.encode(snapshot))
        XCTAssertEqual(restored, snapshot)
    }

    func testPacificAnnouncementConvertsToCentralAbsoluteTime() throws {
        let postedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-23T06:29:05Z"))
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-23T21:00:00Z"))
        let parsed = ResetAnnouncementTimeParser.expectedDate(
            in: "Reset will land around 14pm PST tomorrow.",
            postedAt: postedAt
        )
        XCTAssertEqual(parsed, expected)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(parsed)), 16)
    }

    func testTweetDerivedPacificTimeOverridesFixedPSTProviderTimestamp() throws {
        let provider = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-23T22:00:00Z"))
        let tweet = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-23T21:00:00Z"))
        XCTAssertEqual(
            ResetProviderService.resolvedExpectedAt(
                providerExpectedAt: provider,
                tweetExpectedAt: tweet
            ),
            tweet
        )
    }

    func testUsageDropToZeroDetectsCompletedReset() {
        var previous = QuotaSnapshot.empty
        previous.capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        previous.usagePercent = 64
        previous.usageWindowStart = previous.capturedAt.addingTimeInterval(-4 * 86_400)

        var current = previous
        current.capturedAt = previous.capturedAt.addingTimeInterval(5 * 60)
        current.usagePercent = 0
        current.usageWindowStart = previous.capturedAt

        XCTAssertTrue(NotificationManager.didUsageReset(previous: previous, current: current))
    }

    func testFlatZeroDoesNotDetectCompletedReset() {
        var previous = QuotaSnapshot.empty
        previous.capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        previous.usagePercent = 0
        var current = previous
        current.capturedAt = previous.capturedAt.addingTimeInterval(5 * 60)
        XCTAssertFalse(NotificationManager.didUsageReset(previous: previous, current: current))
    }

    func testExplicitFreshTiboResetPostConfirmsCompletion() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let post = QuotaTiboPost(
            id: "reset-confirmation",
            date: now.addingTimeInterval(-60),
            text: "Resets.",
            inReplyTo: nil,
            url: nil,
            isResetOriented: true
        )
        XCTAssertTrue(NotificationManager.isResetCompletionPost(post, now: now))
    }

    func testFutureResetAnnouncementIsNotCompletion() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let post = QuotaTiboPost(
            id: "future-reset",
            date: now.addingTimeInterval(-60),
            text: "Reset tomorrow at 2pm PST.",
            inReplyTo: nil,
            url: nil,
            isResetOriented: true
        )
        XCTAssertFalse(NotificationManager.isResetCompletionPost(post, now: now))
    }
}
