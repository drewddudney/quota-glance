import XCTest
@testable import QuotaGlance

final class UsageIntelligenceTests: XCTestCase {
    func testTokenBreakdownDoesNotDoubleCountCachedOrReasoningTokens() {
        let tokens = UsageIntelligenceStore.normalizedTokens([
            "input_tokens": 1_000,
            "cached_input_tokens": 600,
            "cache_write_input_tokens": 100,
            "output_tokens": 400,
            "reasoning_output_tokens": 250
        ])

        XCTAssertEqual(tokens?.uncachedInput, 300)
        XCTAssertEqual(tokens?.cachedInput, 600)
        XCTAssertEqual(tokens?.cacheWriteInput, 100)
        XCTAssertEqual(tokens?.outputText, 150)
        XCTAssertEqual(tokens?.reasoningOutput, 250)
        XCTAssertEqual(tokens?.total, 1_400)
    }

    func testAPIEquivalentUsesSeparateInputCacheAndOutputPrices() {
        let tokens = UsageTokenBreakdown(
            uncachedInput: 1_000_000,
            cachedInput: 1_000_000,
            cacheWriteInput: 0,
            outputText: 500_000,
            reasoningOutput: 500_000
        )
        let price = UsagePriceCatalog.price(
            tokens: tokens,
            model: "gpt-5.6-sol",
            contextWindow: 100_000,
            at: Date()
        )

        XCTAssertEqual(price.usd ?? 0, 35.5, accuracy: 0.000_001)
        XCTAssertEqual(price.pricedTokens, 3_000_000)
    }

    func testFastQuotaMultipliersRemainSeparateFromAPIPrice() {
        XCTAssertEqual(UsagePriceCatalog.fastMultiplier(model: "gpt-6-astra"), 2)
        XCTAssertEqual(UsagePriceCatalog.fastMultiplier(model: "gpt-5.6-sol"), 2.5)
        XCTAssertEqual(UsagePriceCatalog.fastMultiplier(model: "gpt-5.4"), 2)
        XCTAssertNil(UsagePriceCatalog.fastMultiplier(model: "gpt-4.1"))
    }

    func testAstraAPIEquivalentUsesPublishedShortContextPrices() {
        let tokens = UsageTokenBreakdown(
            uncachedInput: 1_000_000,
            cachedInput: 1_000_000,
            cacheWriteInput: 0,
            outputText: 500_000,
            reasoningOutput: 500_000
        )
        let price = UsagePriceCatalog.price(
            tokens: tokens,
            model: "gpt-6-astra",
            contextWindow: 100_000,
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(price.usd ?? 0, 61, accuracy: 0.000_001)
        XCTAssertEqual(price.pricedTokens, 3_000_000)
    }

    func testAstraAPIEquivalentUsesPublishedLongContextMultiplier() {
        let card = UsagePriceCatalog.card(
            model: "gpt-6-astra",
            contextWindow: 300_000,
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(card?.inputPerMillion, 20)
        XCTAssertEqual(card?.cachedInputPerMillion, 2)
        XCTAssertEqual(card?.cacheWritePerMillion, 25)
        XCTAssertEqual(card?.outputPerMillion, 75)
    }

    func testUnknownModelIsExplicitlyUnpriced() {
        let price = UsagePriceCatalog.price(
            tokens: UsageTokenBreakdown(uncachedInput: 100, outputText: 100),
            model: "future-model",
            contextWindow: nil,
            at: Date()
        )
        XCTAssertNil(price.usd)
        XCTAssertEqual(price.pricedTokens, 0)
    }

    func testLargeLedgerLagJumpsToLiveTail() {
        XCTAssertEqual(
            UsageIntelligenceStore.liveTailCatchUpStart(
                fileSize: 780 * 1_024 * 1_024,
                cursorOffset: 436 * 1_024 * 1_024,
                liveReadLimit: 8 * 1_024 * 1_024
            ),
            772 * 1_024 * 1_024
        )
    }

    func testSmallLedgerLagContinuesFromCursor() {
        XCTAssertNil(
            UsageIntelligenceStore.liveTailCatchUpStart(
                fileSize: 443 * 1_024 * 1_024,
                cursorOffset: 436 * 1_024 * 1_024,
                liveReadLimit: 8 * 1_024 * 1_024
            )
        )
    }

    func testRollingTokenPaceUsesLiveLedgerEvents() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let pace = UsageIntelligenceStore.rollingTokenPace(
            samples: [
                (now.addingTimeInterval(-60), 2_000_000),
                (now.addingTimeInterval(-240), 1_500_000),
                (now.addingTimeInterval(-600), 4_000_000)
            ],
            windowStart: now.addingTimeInterval(-86_400),
            now: now
        )
        XCTAssertEqual(pace.fiveMinutes, 3_500_000)
        XCTAssertEqual(pace.oneHour, 7_500_000)
        XCTAssertEqual(pace.sinceReset, 7_500_000)
    }
}
