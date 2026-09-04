import XCTest
@testable import QuotaGlanceMobile

final class QuotaSnapshotTests: XCTestCase {
    func testConditionalResetFallsBackToProviderPercentageWhenItDoesNotApply() {
        var snapshot = QuotaSnapshot.empty
        snapshot.resetChancePercent = 64
        snapshot.resetAnnounced = true
        snapshot.announcementID = "conditional-reset"
        snapshot.announcementRequiresApplicabilityConfirmation = true
        snapshot.announcementAppliesToAccount = false

        XCTAssertEqual(snapshot.effectiveResetChance, 64)
        XCTAssertFalse(snapshot.effectiveResetAnnounced)
        XCTAssertFalse(snapshot.needsResetApplicabilityAnswer)
    }

    func testConditionalResetPromptsUntilAnsweredAndUsesOneHundredWhenYes() {
        var snapshot = QuotaSnapshot.empty
        snapshot.resetChancePercent = 64
        snapshot.resetAnnounced = true
        snapshot.announcementID = "conditional-reset"
        snapshot.announcementRequiresApplicabilityConfirmation = true

        XCTAssertTrue(snapshot.needsResetApplicabilityAnswer)
        snapshot.announcementAppliesToAccount = true
        XCTAssertEqual(snapshot.effectiveResetChance, 100)
        XCTAssertTrue(snapshot.effectiveResetAnnounced)
        XCTAssertFalse(snapshot.needsResetApplicabilityAnswer)
    }

    func testForegroundSyncUsesCheapTenSecondLocalFallback() {
        XCTAssertEqual(DashboardStore.ForegroundSyncPolicy.localPollInterval, .seconds(10))
        XCTAssertEqual(DashboardStore.ForegroundSyncPolicy.cloudFallbackInterval, 5 * 60)
    }

    func testResetChanceIsNotForcedToZeroAfterCompletion() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let completion = try XCTUnwrap(calendar.date(from: .init(
            year: 2026, month: 8, day: 30, hour: 16
        )))
        let beforeMidnight = try XCTUnwrap(calendar.date(from: .init(
            year: 2026, month: 8, day: 30, hour: 23, minute: 59
        )))
        let midnight = try XCTUnwrap(calendar.date(from: .init(
            year: 2026, month: 8, day: 31, hour: 0
        )))
        var snapshot = QuotaSnapshot.empty
        snapshot.resetCompletedAt = completion
        snapshot.resetChancePercent = 74

        XCTAssertEqual(snapshot.effectiveResetChance(at: beforeMidnight, calendar: calendar), 74)
        XCTAssertEqual(snapshot.effectiveResetChance(at: midnight, calendar: calendar), 74)
    }

    func testResidualTokenBurnDoesNotCountAsAnActiveCodexSession() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = QuotaSnapshot.empty
        snapshot.capturedAt = now
        snapshot.usageWindowStart = now.addingTimeInterval(-10 * 60)
        snapshot.activeTasks = []
        snapshot.usageHistory = [
            .init(date: now.addingTimeInterval(-5 * 60), usedPercent: 10, tokens: 10_000_000),
            .init(date: now, usedPercent: 11, tokens: 12_000_000)
        ]

        XCTAssertFalse(snapshot.hasActiveCodexSession(at: now))
    }

    func testReportedTaskCountsAsAnActiveCodexSession() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = QuotaSnapshot.empty
        snapshot.capturedAt = now
        snapshot.activeTasks = [
            .init(id: "task-1", name: "Test task", state: "running", source: "codex", updatedAt: now)
        ]

        XCTAssertTrue(snapshot.hasActiveCodexSession(at: now))
    }

    func testAnnouncementAlwaysOverridesResetChanceToOneHundred() {
        var snapshot = QuotaSnapshot.empty
        snapshot.resetChancePercent = 18
        snapshot.resetAnnounced = true
        XCTAssertEqual(snapshot.effectiveResetChance, 100)
    }

    func testCompletedResetPreventsOldAnnouncementReturningToOneHundredNextDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let announced = try XCTUnwrap(calendar.date(from: .init(
            year: 2026, month: 8, day: 30, hour: 15
        )))
        let completed = try XCTUnwrap(calendar.date(from: .init(
            year: 2026, month: 8, day: 30, hour: 16
        )))
        let nextMorning = try XCTUnwrap(calendar.date(from: .init(
            year: 2026, month: 8, day: 31, hour: 8
        )))
        var snapshot = QuotaSnapshot.empty
        snapshot.resetChancePercent = 41
        snapshot.resetAnnounced = true
        snapshot.announcementDate = announced
        snapshot.resetCompletedAt = completed

        XCTAssertEqual(
            snapshot.effectiveResetChance(at: nextMorning, calendar: calendar),
            41
        )
    }

    func testNewAnnouncementAfterCompletedResetCanReturnToOneHundredNextDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let completed = try XCTUnwrap(calendar.date(from: .init(
            year: 2026, month: 8, day: 30, hour: 16
        )))
        let newAnnouncement = try XCTUnwrap(calendar.date(from: .init(
            year: 2026, month: 8, day: 31, hour: 8
        )))
        var snapshot = QuotaSnapshot.empty
        snapshot.resetChancePercent = 41
        snapshot.resetAnnounced = true
        snapshot.resetCompletedAt = completed
        snapshot.announcementDate = newAnnouncement

        XCTAssertEqual(
            snapshot.effectiveResetChance(
                at: newAnnouncement.addingTimeInterval(1),
                calendar: calendar
            ),
            100
        )
    }

    func testMergeClearsEveryFieldForAnnouncementBeforeCompletedReset() {
        let completion = Date(timeIntervalSince1970: 2_000_000_000)
        var snapshot = QuotaSnapshot.empty
        snapshot.resetCompletedAt = completion
        snapshot.announcementText = "Old reset"
        snapshot.announcementDate = completion.addingTimeInterval(-60)
        snapshot.announcementURL = URL(string: "https://example.com/old")

        snapshot.mergeAnnouncement(
            announced: true,
            id: "old",
            text: "Old reset",
            detectedAt: completion.addingTimeInterval(-60),
            expectedAt: completion.addingTimeInterval(-1),
            requiresApplicabilityConfirmation: false,
            url: URL(string: "https://example.com/old")
        )

        XCTAssertFalse(snapshot.resetAnnounced)
        XCTAssertNil(snapshot.announcementID)
        XCTAssertNil(snapshot.announcementText)
        XCTAssertNil(snapshot.announcementDate)
        XCTAssertNil(snapshot.announcementExpectedAt)
        XCTAssertNil(snapshot.announcementURL)
    }

    func testSameTweetHasOneCanonicalIdentityAcrossProviderIDs() {
        let postedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let first = QuotaTiboPost(
            id: "provider-guid",
            date: postedAt,
            text: "I come bearing great news.",
            inReplyTo: nil,
            url: URL(string: "https://x.com/thsottiaux/status/2090774982271848809"),
            isResetOriented: true
        )
        let laterMirror = QuotaTiboPost(
            id: "2090774982271848809",
            date: postedAt,
            text: "I come bearing great news.",
            inReplyTo: "Any news about limits?",
            url: nil,
            isResetOriented: true
        )

        XCTAssertEqual(first.canonicalIdentity, "x:2090774982271848809")
        XCTAssertEqual(first.canonicalIdentity, laterMirror.canonicalIdentity)
    }

    func testTiboNotificationsIgnoreDuplicateAndLateProviderPosts() throws {
        let suiteName = "QuotaSnapshotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstDate = Date(timeIntervalSince1970: 2_000_000_000)
        let first = tiboPost(
            id: "provider-a",
            status: "2090774982271848809",
            date: firstDate,
            text: "First post"
        )

        let baseline = NotificationManager.tiboNotificationState(posts: [first], defaults: defaults)
        XCTAssertNil(baseline.newPost)
        NotificationManager.saveTiboNotificationState(baseline, defaults: defaults)

        let samePostFromSlowProvider = tiboPost(
            id: "2090774982271848809",
            status: nil,
            date: firstDate,
            text: "First post"
        )
        let duplicate = NotificationManager.tiboNotificationState(
            posts: [samePostFromSlowProvider],
            defaults: defaults
        )
        XCTAssertNil(duplicate.newPost)

        let second = tiboPost(
            id: "provider-b",
            status: "2090774982271848810",
            date: firstDate.addingTimeInterval(3_600),
            text: "Actually new post"
        )
        let fresh = NotificationManager.tiboNotificationState(
            posts: [second, samePostFromSlowProvider],
            defaults: defaults
        )
        XCTAssertEqual(fresh.newPost?.canonicalIdentity, second.canonicalIdentity)
        NotificationManager.saveTiboNotificationState(fresh, defaults: defaults)

        let lateOldPost = tiboPost(
            id: "late-provider-guid",
            status: "2090774982271848808",
            date: firstDate.addingTimeInterval(-3_600),
            text: "Older post discovered late"
        )
        let late = NotificationManager.tiboNotificationState(
            posts: [second, lateOldPost],
            defaults: defaults
        )
        XCTAssertNil(late.newPost)
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

    private func tiboPost(
        id: String,
        status: String?,
        date: Date,
        text: String
    ) -> QuotaTiboPost {
        QuotaTiboPost(
            id: id,
            date: date,
            text: text,
            inReplyTo: nil,
            url: status.flatMap { URL(string: "https://x.com/thsottiaux/status/\($0)") },
            isResetOriented: true
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

    func testTokenBurnUsesAvailableWindowWhenItIsYoungerThanRequestedRate() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = QuotaSnapshot.empty
        snapshot.usageWindowStart = now.addingTimeInterval(-30 * 60)
        snapshot.usageHistory = [
            .init(date: try XCTUnwrap(snapshot.usageWindowStart), usedPercent: 0, tokens: 0),
            .init(date: now, usedPercent: 8, tokens: 12_000_000)
        ]

        let sample = try XCTUnwrap(snapshot.tokenBurnSample(over: 60 * 60, now: now))
        XCTAssertEqual(sample.tokens, 12_000_000)
        XCTAssertEqual(sample.duration, 30 * 60, accuracy: 0.1)
    }

    func testTokenBurnInterpolatesAtRequestedCutoff() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = QuotaSnapshot.empty
        snapshot.usageWindowStart = now.addingTimeInterval(-3 * 60 * 60)
        snapshot.usageHistory = [
            .init(date: now.addingTimeInterval(-2 * 60 * 60), usedPercent: 2, tokens: 0),
            .init(date: now, usedPercent: 10, tokens: 20_000_000)
        ]

        let sample = try XCTUnwrap(snapshot.tokenBurnSample(over: 60 * 60, now: now))
        XCTAssertEqual(sample.tokens, 10_000_000)
        XCTAssertEqual(sample.duration, 60 * 60, accuracy: 0.1)
    }

    func testBestTokenTotalUsesLargestCumulativeCheckpoint() {
        var snapshot = QuotaSnapshot.empty
        snapshot.weeklyTokens = 12_000_000
        snapshot.usageHistory = [
            .init(date: Date(), usedPercent: 8, tokens: 18_000_000)
        ]
        XCTAssertEqual(snapshot.bestTokenTotal, 18_000_000)
    }

    func testChartPreservesSavedPercentagesWhenTokenTotalsPlateauAtCurrentTotal() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = QuotaSnapshot.empty
        snapshot.usagePercent = 5
        snapshot.weeklyTokens = 103_100_000
        snapshot.usageHistory = [
            .init(date: now.addingTimeInterval(-6 * 3_600), usedPercent: 0, tokens: 0),
            .init(date: now.addingTimeInterval(-5 * 3_600), usedPercent: 0, tokens: 103_100_000),
            .init(date: now.addingTimeInterval(-4 * 3_600), usedPercent: 1, tokens: 103_100_000),
            .init(date: now.addingTimeInterval(-3 * 3_600), usedPercent: 2, tokens: 103_100_000),
            .init(date: now.addingTimeInterval(-2 * 3_600), usedPercent: 3, tokens: 103_100_000),
            .init(date: now.addingTimeInterval(-60 * 60), usedPercent: 4, tokens: 103_100_000),
            .init(date: now, usedPercent: 5, tokens: 103_100_000)
        ]

        let points = QuotaChartHistory.currentPoints(from: snapshot, now: now)

        XCTAssertEqual(points.map(\.usedPercent), [0, 0, 1, 2, 3, 4, 5])
    }

    func testLiveActivityProjectsPercentageFromMeasuredTokenPace() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = QuotaSnapshot.empty
        snapshot.capturedAt = now
        snapshot.usagePercent = 19
        snapshot.weeklyTokens = 243_700_000
        snapshot.usageHistory = [
            .init(date: now.addingTimeInterval(-60 * 60), usedPercent: 0, tokens: 0),
            .init(date: now, usedPercent: 19, tokens: 243_700_000)
        ]

        let velocity = CodexSessionUsageProjection.percentPerMinute(
            snapshot: snapshot,
            tokensPerMinute: 670_800
        )
        let projected = CodexSessionUsageProjection.projectedPercent(
            basePercent: 19,
            percentPerMinute: velocity,
            updatedAt: now,
            now: now.addingTimeInterval(30)
        )

        XCTAssertEqual(velocity, 0.0523, accuracy: 0.0001)
        XCTAssertEqual(projected, 19.026, accuracy: 0.001)
    }

    func testLiveActivityStartsFromProgressSinceLastPercentageChange() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = QuotaSnapshot.empty
        snapshot.capturedAt = now
        snapshot.usagePercent = 19
        snapshot.usageHistory = [
            .init(date: now.addingTimeInterval(-12 * 60), usedPercent: 18, tokens: 220_000_000),
            .init(date: now.addingTimeInterval(-6 * 60), usedPercent: 19, tokens: 228_000_000),
            .init(date: now.addingTimeInterval(-3 * 60), usedPercent: 19, tokens: 232_000_000),
            .init(date: now, usedPercent: 19, tokens: 236_000_000)
        ]

        let refreshed = CodexSessionUsageProjection.estimatedPercentAtRefresh(
            snapshot: snapshot,
            percentPerMinute: 0.05
        )
        let projected = CodexSessionUsageProjection.projectedPercent(
            basePercent: refreshed,
            percentPerMinute: 0.05,
            updatedAt: now,
            now: now.addingTimeInterval(30)
        )

        XCTAssertEqual(refreshed, 19.3, accuracy: 0.0001)
        XCTAssertEqual(projected, 19.325, accuracy: 0.0001)
    }

    func testLiveActivityDoesNotEstimatePastNextUnconfirmedPercentage() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = QuotaSnapshot.empty
        snapshot.capturedAt = now
        snapshot.usagePercent = 19
        snapshot.usageHistory = [
            .init(date: now.addingTimeInterval(-60 * 60), usedPercent: 18, tokens: 100),
            .init(date: now.addingTimeInterval(-30 * 60), usedPercent: 19, tokens: 200),
            .init(date: now, usedPercent: 19, tokens: 300)
        ]

        let refreshed = CodexSessionUsageProjection.estimatedPercentAtRefresh(
            snapshot: snapshot,
            percentPerMinute: 0.2
        )
        let projected = CodexSessionUsageProjection.projectedPercent(
            basePercent: refreshed,
            percentPerMinute: 0.2,
            updatedAt: now,
            now: now.addingTimeInterval(10 * 60)
        )

        XCTAssertEqual(refreshed, 19.999, accuracy: 0.0001)
        XCTAssertEqual(projected, 19.999, accuracy: 0.0001)
    }

    func testLiveActivityProjectionStopsAfterTenMinutesWithoutRefresh() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let projected = CodexSessionUsageProjection.projectedPercent(
            basePercent: 19,
            percentPerMinute: 0.05,
            updatedAt: start,
            now: start.addingTimeInterval(60 * 60)
        )

        XCTAssertEqual(projected, 19.5, accuracy: 0.0001)
    }
}
