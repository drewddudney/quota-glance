import XCTest
@testable import QuotaGlance

final class TiboTweetFilterTests: XCTestCase {
    func testExplicitResetPostIsIncluded() {
        XCTAssertTrue(tweet("Resets.").isResetOriented)
    }

    func testShortReplyUsesParentContext() {
        XCTAssertTrue(
            tweet(
                "Yes, soon.",
                reply: "Any chance the weekly Codex quota gets replenished today?"
            ).isResetOriented
        )
    }

    func testCodexLimitLanguageIsIncludedWithoutWordReset() {
        XCTAssertTrue(tweet("We are looking at the Codex usage limits.").isResetOriented)
    }

    func testBlessingAndCircleBackLanguageIsIncluded() {
        XCTAssertTrue(tweet("Another blessing may be coming.").isResetOriented)
        XCTAssertTrue(tweet("Let's circle back soon.").isResetOriented)
    }

    func testUnrelatedModelPostIsExcluded() {
        XCTAssertFalse(tweet("The day we develop really good models, there will be signs.").isResetOriented)
    }

    func testSameXPostHasOneIdentityAcrossProviderIDs() {
        let firstSource = TiboTweet(
            id: "provider-guid-abc",
            date: Date(),
            text: "I come bearing great news.",
            inReplyTo: nil,
            url: URL(string: "https://x.com/thsottiaux/status/2090774982271848809")
        )
        let laterSource = TiboTweet(
            id: "2090774982271848809",
            date: Date(),
            text: "I come bearing great news.",
            inReplyTo: "Any news about limits?",
            url: nil
        )

        XCTAssertEqual(firstSource.alertIdentity, "x:2090774982271848809")
        XCTAssertEqual(firstSource.alertIdentity, laterSource.alertIdentity)
    }

    func testContentFallbackIgnoresFormattingAndAddedReplyContext() {
        let firstSource = tweet("Reset news — soon!")
        let laterSource = tweet("Reset news, soon.", reply: "What about Codex quota?")
        XCTAssertEqual(firstSource.alertIdentity, laterSource.alertIdentity)
    }

    func testLegacyNumericNotificationIDMigratesToCanonicalIdentity() {
        XCTAssertEqual(
            TiboTweet.canonicalizeStoredIdentity("2090774982271848809"),
            "x:2090774982271848809"
        )
    }

    private func tweet(_ text: String, reply: String? = nil) -> TiboTweet {
        TiboTweet(id: text, date: Date(), text: text, inReplyTo: reply, url: nil)
    }
}
