import XCTest
@testable import QuotaGlance

final class ForecastSelectionTests: XCTestCase {
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

    func testProviderWithoutPercentageFallsBackToAvailableMeanInsteadOfZero() throws {
        let snapshot = try ForecastService.snapshot(from: fixtures(), selected: .codexResets)
        XCTAssertEqual(snapshot.score, (22.0 + 27.0 + 43.0) / 3.0, accuracy: 0.001)
        XCTAssertTrue(snapshot.headline?.contains("no live percentage") == true)
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
            XCTAssertEqual(snapshot.announcement, announcement)
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
            announcement: announcement
        )
    }
}
