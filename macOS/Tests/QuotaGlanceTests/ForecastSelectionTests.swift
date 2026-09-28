import XCTest
@testable import QuotaGlance

final class ForecastSelectionTests: XCTestCase {
    func testPolymarketDiscoveryUsesOpenEventAndItsCurrentURL() throws {
        let market: [String: Any] = ["active": true, "closed": false, "endDate": "2030-01-02T00:00:00Z", "outcomes": "[\"Yes\",\"No\"]", "outcomePrices": "[\"0.45\",\"0.55\"]"]
        let open: [String: Any] = ["slug": "openai-resets-codex-weekly-usage-limit-by-20260914", "active": true, "closed": false, "markets": [market]]
        var closed = open
        closed["closed"] = true
        closed["startDate"] = "2031-01-01"
        let data = try JSONSerialization.data(withJSONObject: ["events": [closed, open]])
        let result = try ForecastService.polymarketSearchProvider(from: data, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(result.score, 45)
        XCTAssertEqual(result.polymarketForecast?.url.absoluteString, "https://polymarket.com/event/openai-resets-codex-weekly-usage-limit-by-20260914")
        XCTAssertNil(result.announcement)
    }

    func testPolymarketCurveKeepsEveryValidFutureDeadlineInOrder() throws {
        func market(_ day: String, _ yes: String, _ no: String, closed: Bool = false) -> [String: Any] {
            ["active": true, "closed": closed, "endDate": "2030-01-\(day)T00:00:00Z",
             "groupItemTitle": "January \(day)", "outcomes": "[\"No\",\"Yes\"]",
             "outcomePrices": "[\"\(no)\",\"\(yes)\"]"]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "markets": [
                market("04", "0.8", "0.2"), market("02", "0.45", "0.55"),
                market("03", "0.4", "0.6"), // Independent markets may disagree; preserve real odds.
                market("05", "1.2", "-0.2"), market("06", "NaN", "0.5"),
                market("07", "0.9", "0.1", closed: true), market("01", "0.1", "0.9")
            ]
        ])
        let now = ISO8601DateFormatter().date(from: "2030-01-01T12:00:00Z")!
        let result = try ForecastService.polymarketProvider(from: data, now: now)
        let points = try XCTUnwrap(result.polymarketForecast).points
        XCTAssertEqual(points.map(\.marketLabel), ["January 02", "January 03", "January 04"])
        XCTAssertEqual(points.map(\.yesPrice), [0.45, 0.4, 0.8])
        XCTAssertEqual(points.map(\.noPrice), [0.55, 0.6, 0.2])
        XCTAssertEqual(points.first?.axisLabel, "Jan 02")
        XCTAssertEqual(result.score, 45)
        XCTAssertEqual(result.forecastDeadline, points.first?.deadline)
        XCTAssertNil(result.announcement)
    }

    func testPolymarketMatchesDisplayedProbabilityForWideAndTightBooks() throws {
        let rows: [(String, Double, Double, Double, String)] = [
            ("02", 0.21, 0.69, 0.21, "0.45"),
            ("03", 0.40, 0.83, 0.40, "0.615"),
            ("04", 0.86, 0.89, 0.90, "0.875"),
            ("05", 0.40, 0.50, 0.30, "0.45")
        ]
        let markets: [[String: Any]] = rows.map { day, bid, ask, last, midpoint in
            ["endDate": "2030-01-\(day)T00:00:00Z",
             "outcomes": "[\"Yes\",\"No\"]", "outcomePrices": "[\"\(midpoint)\",\"0.5\"]",
             "bestBid": bid, "bestAsk": ask, "lastTradePrice": last]
        }
        let data = try JSONSerialization.data(withJSONObject: ["markets": markets])
        let result = try ForecastService.polymarketProvider(from: data, now: Date(timeIntervalSince1970: 1_800_000_000))
        let points = try XCTUnwrap(result.polymarketForecast).points
        XCTAssertEqual(points.map(\.yesPrice), [0.21, 0.40, 0.875, 0.45])
        XCTAssertEqual(points.map(\.usesLastTrade), [true, true, false, false])
        XCTAssertEqual(result.score, 21)
    }

    func testWillFlagCannotPromoteGenericResetTalkToAnnouncement() {
        let post = TiboTweet(id: "test", date: Date(), text: "I know you all want a reset", inReplyTo: nil, url: nil)
        XCTAssertNil(ForecastService.announcementFromTweets([post], source: .willCodexQuotaReset, explicitlyAnnounced: true))
        XCTAssertTrue(ForecastService.isExplicitResetAnnouncement("We're resetting usage limits today"))
        XCTAssertFalse(ForecastService.isExplicitResetAnnouncement("We're not resetting usage limits today"))
    }

    func testRestoredProviderSelectionIsPreserved() {
        let defaults = UserDefaults(suiteName: "RemovedProvider-\(UUID().uuidString)")!
        defaults.set(["willCodexQuotaReset"], forKey: ForecastSourceSelection.defaultsKey)
        defaults.set("willCodexQuotaReset", forKey: ForecastSource.defaultsKey)
        XCTAssertEqual(ForecastSourceSelection.load(from: defaults), [.willCodexQuotaReset])
        defaults.set(["willCodexQuotaReset", "gussuri"], forKey: ForecastSourceSelection.defaultsKey)
        XCTAssertEqual(ForecastSourceSelection.load(from: defaults), [.willCodexQuotaReset, .gussuri])
    }

    func testConditionalResetAnnouncementRequiresAccountAnswer() throws {
        let announcement = ResetAnnouncement(
            id: "conditional-reset",
            source: .codexResets,
            detectedAt: Date(),
            expectedAt: nil,
            text: "Some Plus users who don't have access to Astra will receive a banked reset.",
            url: nil
        )
        var providers = fixtures()
        providers[1] = provider(.codexResets, score: 61, announcement: announcement)

        let snapshot = try ForecastService.snapshot(from: providers, selected: [.codexResets])

        XCTAssertTrue(try XCTUnwrap(snapshot.announcement).requiresApplicabilityConfirmation)
        XCTAssertEqual(snapshot.score, 100, accuracy: 0.001)
        XCTAssertEqual(snapshot.baselineScore, 61, accuracy: 0.001)
    }

    func testUniversalResetAnnouncementDoesNotRequireAccountAnswer() {
        XCTAssertFalse(ResetApplicability.requiresConfirmation(
            "We reset usage limits for all paid Codex users."
        ))
    }

    func testEachCalculatorUsesItsCachedPercentageImmediately() throws {
        let providers = fixtures()

        XCTAssertEqual(try ForecastService.snapshot(from: providers, selected: .lunarWerx).score, 22, accuracy: 0.001)
        XCTAssertEqual(try ForecastService.snapshot(from: providers, selected: .gussuri).score, 43, accuracy: 0.001)
    }

    func testAverageUsesEveryAvailableCachedPercentage() throws {
        let snapshot = try ForecastService.snapshot(from: fixtures(), selected: .average)
        XCTAssertEqual(snapshot.score, (22.0 + 43.0) / 2.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.source, .average)
    }

    func testRestoredPolymarketSelectionPreservesOtherSources() {
        let suite = "RemovedPolymarket-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["polymarket", "codexResets"], forKey: ForecastSourceSelection.defaultsKey)
        XCTAssertEqual(ForecastSourceSelection.load(from: defaults), [.polymarket, .codexResets])
        defaults.set(["polymarket"], forKey: ForecastSourceSelection.defaultsKey)
        defaults.set("polymarket", forKey: ForecastSource.defaultsKey)
        XCTAssertEqual(ForecastSourceSelection.load(from: defaults), [.polymarket])
    }

    func testProviderWithoutPercentageShowsZeroWithoutBorrowingUnselectedSources() throws {
        let snapshot = try ForecastService.snapshot(from: fixtures(), selected: .codexResets)
        XCTAssertEqual(snapshot.score, 0, accuracy: 0.001)
        XCTAssertTrue(snapshot.headline?.contains("no live percentage") == true)
    }

    func testMultipleSelectionAveragesOnlyCheckedProvidersWithPercentages() throws {
        let snapshot = try ForecastService.snapshot(
            from: fixtures(),
            selected: [.lunarWerx, .codexResets, .gussuri]
        )
        XCTAssertEqual(snapshot.score, (22.0 + 43.0) / 2.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.selectedSources, [.lunarWerx, .codexResets, .gussuri])
        XCTAssertEqual(snapshot.source, .average)
    }

    func testSelectedProviderKeepsItsOwnConfidenceRange() throws {
        let snapshot = try ForecastService.snapshot(from: fixtures(), selected: .lunarWerx)
        let range = try XCTUnwrap(snapshot.range)
        XCTAssertEqual(range.lowerBound, 8, accuracy: 0.001)
        XCTAssertEqual(range.upperBound, 53, accuracy: 0.001)
    }

    func testAnyProviderAnnouncementOverridesEveryCalculatorToOneHundredPercent() throws {
        let announcement = ResetAnnouncement(
            id: "gussuri:test",
            source: .gussuri,
            detectedAt: Date().addingTimeInterval(-300),
            expectedAt: Date().addingTimeInterval(3_600),
            text: "A full reset was announced.",
            url: URL(string: "https://example.com/reset")
        )
        var providers = fixtures()
        providers[2] = provider(.gussuri, score: 43, announcement: announcement)

        for source in ForecastSource.allCases {
            let snapshot = try ForecastService.snapshot(from: providers, selected: source)
            XCTAssertEqual(snapshot.score, 100, accuracy: 0.001)
            XCTAssertEqual(snapshot.announcement?.id, announcement.id)
            XCTAssertNil(snapshot.announcement?.expectedAt)
            XCTAssertEqual(snapshot.displayLabel, nil)
        }
    }

    func testExpiredAnnouncementDoesNotOverrideCurrentEstimate() throws {
        let expired = ResetAnnouncement(
            id: "gussuri:expired",
            source: .gussuri,
            detectedAt: Date().addingTimeInterval(-48 * 3_600),
            expectedAt: nil,
            text: "Old reset announcement",
            url: nil
        )
        var providers = fixtures()
        providers[2] = provider(.gussuri, score: 43, announcement: expired)

        let snapshot = try ForecastService.snapshot(from: providers, selected: .gussuri)
        XCTAssertEqual(snapshot.score, 43, accuracy: 0.001)
        XCTAssertNil(snapshot.announcement)
    }

    func testForecastDeadlineDoesNotMasqueradeAsConfirmedAnnouncement() throws {
        let deadline = Date().addingTimeInterval(8 * 3_600)
        let providers = [provider(.codexResets, score: 95, forecastDeadline: deadline)]

        let snapshot = try ForecastService.snapshot(from: providers, selected: .codexResets)

        XCTAssertEqual(snapshot.score, 95, accuracy: 0.001)
        XCTAssertNil(snapshot.announcement)
        XCTAssertEqual(snapshot.scheduledReset?.expectedAt, deadline)
        XCTAssertTrue(snapshot.headline?.contains("95% chance by") == true)
    }

    func testNewestExplicitTimeSupersedesOlderAnnouncement() throws {
        let now = Date()
        let older = ResetAnnouncement(
            id: "older-time",
            source: .lunarWerx,
            detectedAt: now.addingTimeInterval(-600),
            expectedAt: now.addingTimeInterval(3_600),
            text: "Reset at 11:58 PM PT tomorrow",
            url: nil
        )
        let newer = ResetAnnouncement(
            id: "newer-time",
            source: .gussuri,
            detectedAt: now.addingTimeInterval(-60),
            expectedAt: now.addingTimeInterval(7_200),
            text: "Actually, reset at 11:59 PM PT tomorrow",
            url: nil
        )

        let snapshot = try ForecastService.snapshot(
            from: [
                provider(.lunarWerx, score: 70, announcement: older),
                provider(.gussuri, score: 80, announcement: newer)
            ],
            selected: .average
        )

        XCTAssertEqual(snapshot.announcement?.text, newer.text)
        XCTAssertEqual(snapshot.scheduledReset?.text, newer.text)
    }

    func testCodexResetsWatchCardParsesChanceDeadlinePollAndEveryTweet() throws {
        let html = #"""
        <section class="watch-card watch-card--elevated" data-role="reset-watch"
          data-expires-at="2026-08-30T07:00:00.000Z" aria-label="95 percent chance of reset">
          <h2><span data-role="watch-heading-chance"><number-flow data-role="watch-chance">95</number-flow>% chance of reset</span></h2>
          <a class="watch-tweet" href="https://x.com/thsottiaux/status/2093551005711679557">
            <span data-datetime="2026-08-29T04:07:10.000Z">14 hours ago</span>
            <span class="watch-tweet-context">Replying to &ldquo;Sounds like it’s time for another limit reset&rdquo;</span>
            <span class="watch-tweet-text">There is a place and a time for resets. Soon, but not today</span>
          </a>
          <a class="watch-tweet is-active" href="https://x.com/thsottiaux/status/2093573991965557198">
            <span data-datetime="2026-08-29T05:38:31.000Z">13 hours ago</span>
            <span class="watch-tweet-text">Looking at the dashboard we might hit a new milestone to celebrate tomorrow.</span>
          </a>
          <div class="watch-poll" data-yes="1655" data-no="85"></div>
        </section>
        """#

        let signal = try XCTUnwrap(ForecastService.codexResetsWatchSignal(in: html))

        XCTAssertEqual(signal.score, 95, accuracy: 0.001)
        XCTAssertEqual(signal.expectedAt, ISO8601DateFormatter().date(from: "2026-08-30T07:00:00Z"))
        XCTAssertEqual(signal.yesVotes, 1_655)
        XCTAssertEqual(signal.noVotes, 85)
        XCTAssertEqual(signal.tweets.count, 2)
        XCTAssertEqual(signal.tweets.first?.inReplyTo, "Sounds like it’s time for another limit reset")
    }

    private func fixtures() -> [ResetProviderSnapshot] {
        [
            provider(.lunarWerx, score: 22, range: 8...53),
            provider(.codexResets, score: nil),
            provider(.gussuri, score: 43)
        ]
    }

    private func provider(
        _ source: ForecastSource,
        score: Double?,
        range: ClosedRange<Double>? = nil,
        forecastDeadline: Date? = nil,
        announcement: ResetAnnouncement? = nil
    ) -> ResetProviderSnapshot {
        ResetProviderSnapshot(
            source: source,
            score: score,
            displayLabel: nil,
            headline: source.displayName,
            range: range,
            lastBlessingAt: nil,
            tweets: [],
            metrics: [],
            signals: [],
            updatedAt: Date(),
            forecastDeadline: forecastDeadline,
            announcement: announcement
        )
    }
}
