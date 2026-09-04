import XCTest
@testable import QuotaGlance

final class ForecastSelectionTests: XCTestCase {
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
        XCTAssertEqual(try ForecastService.snapshot(from: providers, selected: .willCodexQuotaReset).score, 27, accuracy: 0.001)
        XCTAssertEqual(try ForecastService.snapshot(from: providers, selected: .gussuri).score, 43, accuracy: 0.001)
    }

    func testAverageUsesEveryAvailableCachedPercentage() throws {
        let snapshot = try ForecastService.snapshot(from: fixtures(), selected: .average)
        XCTAssertEqual(snapshot.score, (22.0 + 27.0 + 43.0) / 3.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.source, .average)
    }

    func testSelectedPolymarketOddsContributeToMultiSourceAverage() throws {
        var providers = fixtures()
        providers.append(provider(
            .polymarket,
            score: 82.5,
            forecastDeadline: Date().addingTimeInterval(5 * 86_400)
        ))

        let average = try ForecastService.snapshot(from: providers, selected: .average)
        let marketOnly = try ForecastService.snapshot(from: providers, selected: .polymarket)

        XCTAssertEqual(average.score, (22.0 + 27.0 + 43.0 + 82.5) / 4.0, accuracy: 0.001)
        XCTAssertNil(average.scheduledReset)
        XCTAssertEqual(marketOnly.score, 82.5, accuracy: 0.001)
        XCTAssertNotNil(marketOnly.scheduledReset)
    }

    func testPolymarketUsesEarliestOpenDeadlineAndPricesEightyDollarHedge() throws {
        let json = #"""
        {
          "updatedAt": "2026-09-02T14:23:00.42304Z",
          "markets": [
            {
              "groupItemTitle": "September 14",
              "endDate": "2026-09-15T03:59:00Z",
              "active": true,
              "closed": false,
              "outcomes": "[\"Yes\", \"No\"]",
              "outcomePrices": "[\"0.86\", \"0.14\"]"
            },
            {
              "groupItemTitle": "September 7",
              "endDate": "2026-09-08T03:59:00Z",
              "active": true,
              "closed": false,
              "outcomes": "[\"Yes\", \"No\"]",
              "outcomePrices": "[\"0.825\", \"0.175\"]"
            }
          ]
        }
        """#
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-02T14:00:00Z"))
        let provider = try ForecastService.polymarketProvider(from: Data(json.utf8), now: now)
        let hedge = try XCTUnwrap(provider.polymarketHedge)

        XCTAssertEqual(try XCTUnwrap(provider.score), 82.5, accuracy: 0.001)
        XCTAssertEqual(hedge.marketLabel, "September 7")
        XCTAssertEqual(hedge.noPrice, 0.175, accuracy: 0.001)
        XCTAssertEqual(hedge.stake, 14, accuracy: 0.001)
        XCTAssertEqual(hedge.grossProfit, 66, accuracy: 0.001)
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
        providers[3] = provider(.gussuri, score: 43, announcement: announcement)

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
        providers[3] = provider(.gussuri, score: 43, announcement: expired)

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
            provider(.willCodexQuotaReset, score: 27),
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
            announcement: announcement,
            polymarketHedge: nil
        )
    }
}
