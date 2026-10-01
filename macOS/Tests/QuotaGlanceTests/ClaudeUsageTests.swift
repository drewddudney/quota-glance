import XCTest
@testable import QuotaGlance

final class ClaudeUsageTests: XCTestCase {
    func testWeeklyWindowIsNotConfusedWithSessionOrModelSpecificUsage() throws {
        let snapshot = try decode(#"{"five_hour":{"utilization":91,"resets_at":"2026-09-25T22:00:00Z"},"seven_day":{"utilization":37.5,"resets_at":"2026-09-30T19:40:00.123+00:00"},"seven_day_sonnet":{"utilization":84}}"#)
        XCTAssertEqual(snapshot.weekly?.usedPercent, 37.5)
        XCTAssertEqual(snapshot.fiveHour?.usedPercent, 91)
        XCTAssertEqual(snapshot.fiveHour?.resetAt, ClaudeUsageClient.parseDate("2026-09-25T22:00:00Z"))
        let end = try XCTUnwrap(snapshot.weekly?.resetAt)
        XCTAssertEqual(end, try XCTUnwrap(ClaudeUsageClient.parseDate("2026-09-30T19:40:00.123Z")))
        XCTAssertEqual(try XCTUnwrap(snapshot.weekly?.calendarPercent(at: end.addingTimeInterval(-3.5 * 86_400))), 50, accuracy: 0.0001)
    }

    func testMissingWeeklyDataNeverBecomesZeroOrSessionUsage() throws {
        let snapshot = try decode(#"{"five_hour":{"utilization":12},"seven_day":null}"#)
        XCTAssertNil(snapshot.weekly)
        XCTAssertThrowsError(try decode(#"{"five_hour":{"utilization":12}}"#))
    }

    func testUnusedWindowCanShowZeroWithoutInventingCalendarStart() throws {
        let snapshot = try decode(#"{"seven_day":{"utilization":0,"resets_at":null}}"#)
        XCTAssertEqual(snapshot.weekly?.usedPercent, 0)
        XCTAssertNil(snapshot.weekly?.calendarPercent(at: Date()))
    }

    func testCalendarUsesRollingSevenDaysAndDoesNotRollOldDataIntoNewWeek() throws {
        // This window spans the US autumn clock change; elapsed time is still 168 hours.
        let end = try XCTUnwrap(ClaudeUsageClient.parseDate("2026-11-04T19:40:00Z"))
        let weekly = ClaudeWeeklyUsage(usedPercent: 73, resetAt: end)
        XCTAssertEqual(weekly.calendarPercent(at: end.addingTimeInterval(-7 * 86_400)), 0)
        XCTAssertEqual(weekly.calendarPercent(at: end.addingTimeInterval(-8 * 86_400)), 0)
        XCTAssertEqual(weekly.calendarPercent(at: end), 100)
        XCTAssertEqual(weekly.calendarPercent(at: end.addingTimeInterval(86_400)), 100)
        XCTAssertFalse(weekly.hasEnded(at: end.addingTimeInterval(-1)))
        XCTAssertTrue(weekly.hasEnded(at: end))
    }

    func testMalformedUsageIsNotDisplayedAsAValidPercentage() {
        for raw in ["true", "-1", "101", "\"unknown\""] {
            XCTAssertThrowsError(try decode("{\"seven_day\":{\"utilization\":\(raw)}}"))
        }
    }

    func testCredentialExpiryUsesMillisecondsAndInferenceOnlyTokensAreRejected() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let valid = Data(#"{"claudeAiOauth":{"accessToken":"test-only-token","expiresAt":1800000060000,"scopes":["user:profile","user:inference"]}}"#.utf8)
        XCTAssertNoThrow(try ClaudeCredentialReader.decode(valid, now: now))
        XCTAssertThrowsError(try ClaudeCredentialReader.decode(valid, now: now.addingTimeInterval(61)))
        XCTAssertThrowsError(try ClaudeCredentialReader.decode(Data(#"{"claudeAiOauth":{"accessToken":"test-only-token","scopes":["user:inference"]}}"#.utf8), now: now))
        XCTAssertThrowsError(try ClaudeCredentialReader.decode(Data(#"{"mcpOAuth":{}}"#.utf8), now: now))
    }

    func testRateLimitRetryHonorsServerDeadlineWithAQuietMinimum() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(ClaudeUsageClient.retryDate("30", now: now), now.addingTimeInterval(300))
        XCTAssertEqual(ClaudeUsageClient.retryDate("900", now: now), now.addingTimeInterval(900))
        XCTAssertEqual(ClaudeUsageClient.retryDate("nonsense", now: now), now.addingTimeInterval(300))
    }

    private func decode(_ payload: String) throws -> ClaudeUsageSnapshot {
        try ClaudeUsageClient.decode(Data(payload.utf8), credentialID: "fixture", plan: nil)
    }

    func testEdgeWingsStayAtPhysicalTopAndAvoidTheCameraOnOffsetDisplays() {
        let screen = NSRect(x: -2560, y: 300, width: 2560, height: 1440)
        let external = ProviderDisplayGeometry.edgeFrames(screen: screen, safeTop: 0, leftArea: nil, rightArea: nil)
        XCTAssertEqual(external.count, 1)
        XCTAssertEqual(external[0].maxY, screen.maxY)
        XCTAssertEqual(external[0].midX, screen.midX)
        XCTAssertTrue((28...64).contains(external[0].height))

        let left = NSRect(x: screen.minX, y: screen.maxY - 37, width: 1180, height: 37)
        let right = NSRect(x: screen.minX + 1380, y: screen.maxY - 37, width: 1180, height: 37)
        let camera = NSRect(x: left.maxX, y: left.minY, width: right.minX - left.maxX, height: 37)
        let wings = ProviderDisplayGeometry.edgeFrames(screen: screen, safeTop: 37, leftArea: left, rightArea: right)
        XCTAssertEqual(wings.count, 2)
        for frame in wings {
            XCTAssertEqual(frame.maxY, screen.maxY)
            XCTAssertEqual(frame.height, external[0].height)
            XCTAssertFalse(frame.intersects(camera))
        }
        XCTAssertLessThan(wings[0].maxX, camera.minX)
        XCTAssertGreaterThan(wings[1].minX, camera.maxX)
    }

    func testLegacyDisplayChoicesMigrateWithoutLosingTheirPlacementIntent() {
        XCTAssertEqual(ProviderDisplayStyle.resolved("notch"), .edgeWings)
        XCTAssertEqual(ProviderDisplayStyle.resolved("rail"), .cornerBlade)
        XCTAssertEqual(ProviderDisplayStyle.resolved("strip"), .stackedSlate)
        XCTAssertEqual(ProviderDisplayStyle.resolved("separate"), .stackedSlate)
        XCTAssertEqual(ProviderDisplayStyle.resolved("twinDials"), .twinDials)
    }

    func testSidePetsAndPeekCardsStayInsideAnOffsetDisplayAboveTheDock() {
        let visible = NSRect(x: -1920, y: 76, width: 1920, height: 1004)
        for peek in [false, true] {
            for provider in DisplayProvider.allCases {
                let frame = ProviderCompanionGeometry.petFrame(provider: provider, peek: peek, in: visible)
                XCTAssertTrue(visible.contains(frame))
                if provider == .codex { XCTAssertEqual(frame.minX, visible.minX) }
                else { XCTAssertEqual(frame.maxX, visible.maxX) }
            }
        }
    }

    func testCreativeFloatingDefaultsFitWithinTheSelectedVisibleDisplay() {
        let visible = NSRect(x: -1600, y: -900, width: 1600, height: 860)
        for style in [ProviderDisplayStyle.twinDials, .stackedSlate, .metricMatrix, .cornerBlade] {
            let frame = NSRect(origin: ProviderDisplayGeometry.initialOrigin(style: style, in: visible), size: ProviderDisplayGeometry.size(style: style))
            XCTAssertTrue(visible.contains(frame))
        }
    }

    func testExistingClaudeCacheRemainsDecodableAfterAddingWebSource() throws {
        let data = Data(#"{"capturedAt":"2026-09-25T12:00:00Z","weekly":{"usedPercent":19,"resetAt":"2026-09-30T12:00:00Z"},"credentialID":"fixture","plan":"pro"}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(ClaudeUsageSnapshot.self, from: data)
        XCTAssertNil(old.source)
        XCTAssertNil(old.fiveHour)
        XCTAssertEqual(old.weekly?.usedPercent, 19)
        var web = old
        web.source = .web
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(ClaudeUsageSnapshot.self, from: encoder.encode(web)).source, .web)
    }

    func testFiveHourWindowExpiresIndependentlyOfTheWeeklyWindow() throws {
        let snapshot = try decode(#"{"seven_day":{"utilization":82,"resets_at":"2026-09-30T19:00:00Z"},"five_hour":{"utilization":95,"resets_at":"2026-09-25T22:00:00Z"}}"#)
        let session = try XCTUnwrap(snapshot.fiveHour)
        let end = try XCTUnwrap(session.resetAt)
        XCTAssertTrue(session.hasEnded(at: end))
        XCTAssertFalse(snapshot.weekly!.hasEnded(at: end))
        XCTAssertFalse(session.hasEnded(at: end.addingTimeInterval(-1)))
    }

    func testMissingOrMalformedFiveHourDataNeverBecomesWeeklyUsage() throws {
        XCTAssertNil(try decode(#"{"seven_day":{"utilization":82},"five_hour":null}"#).fiveHour)
        XCTAssertThrowsError(try decode(#"{"seven_day":{"utilization":82},"five_hour":{"utilization":true}}"#))
        XCTAssertThrowsError(try decode(#"{"seven_day":{"utilization":82},"five_hour":{"utilization":101}}"#))
    }

    func testRecordedClaudeHistorySurvivesCacheCodingAndMobilePublishing() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let end = now.addingTimeInterval(3 * 86_400)
        let first = ClaudeUsageSnapshot(capturedAt: now.addingTimeInterval(-120),
            weekly: .init(usedPercent: 50, resetAt: end), credentialID: "fixture", plan: "Max")
            .recordingHistory(previous: nil, now: now)
        XCTAssertNil(first.estimatedRunoutAt)
        let current = ClaudeUsageSnapshot(capturedAt: now, weekly: .init(usedPercent: 54, resetAt: end),
            credentialID: "fixture", plan: "Max").recordingHistory(previous: first, now: now)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(ClaudeUsageSnapshot.self, from: encoder.encode(current))
        XCTAssertEqual(restored.usageHistory?.map(\.usedPercent), [50, 54])
        let mobile = restored.quotaSnapshot(verified: true, needsConnection: false)
        XCTAssertEqual(mobile.usageHistory, restored.usageHistory)
        XCTAssertEqual(try XCTUnwrap(mobile.estimatedRunoutAt).timeIntervalSince(now), 1_380, accuracy: 0.001)
        XCTAssertNotEqual(mobile.accountID, "fixture")
        XCTAssertNil(ClaudeUsageHistory.estimate(for: mobile, now: now.addingTimeInterval(901)))
    }

    func testRecordedClaudeAccountSwitchAndDelayedReadDoNotCombinePace() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let end = now.addingTimeInterval(3 * 86_400)
        let first = ClaudeUsageSnapshot(capturedAt: now, weekly: .init(usedPercent: 70, resetAt: end),
            credentialID: "account-a", plan: nil).recordingHistory(previous: nil, now: now)
        let late = ClaudeUsageSnapshot(capturedAt: now.addingTimeInterval(-120), weekly: .init(usedPercent: 10, resetAt: end),
            credentialID: "account-a", plan: nil).recordingHistory(previous: first, now: now)
        XCTAssertEqual(late, first)
        let changed = ClaudeUsageSnapshot(capturedAt: now.addingTimeInterval(120), weekly: .init(usedPercent: 10, resetAt: end),
            credentialID: "account-b", plan: nil).recordingHistory(previous: first, now: now.addingTimeInterval(120))
        XCTAssertEqual(changed.usageHistory?.map(\.usedPercent), [10])
        XCTAssertEqual(changed.weeklyArchives, [])
        XCTAssertNil(changed.estimatedRunoutAt)
    }

    func testRecordedClaudeResetArchivesThePreviousAllowanceWithoutBackfill() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let end = now.addingTimeInterval(-60)
        let first = ClaudeUsageSnapshot(capturedAt: now.addingTimeInterval(-120), weekly: .init(usedPercent: 87, resetAt: end),
            credentialID: "fixture", plan: nil).recordingHistory(previous: nil, now: now.addingTimeInterval(-120))
        let renewed = ClaudeUsageSnapshot(capturedAt: now, weekly: .init(usedPercent: 2, resetAt: end.addingTimeInterval(7 * 86_400)),
            credentialID: "fixture", plan: nil).recordingHistory(previous: first, now: now)
        XCTAssertEqual(renewed.weeklyArchives?.first?.points, first.usageHistory)
        XCTAssertEqual(renewed.usageHistory?.map(\.usedPercent), [2])
        XCTAssertNil(renewed.estimatedRunoutAt)
    }
}
