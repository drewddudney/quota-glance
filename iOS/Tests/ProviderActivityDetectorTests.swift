import XCTest
@testable import QuotaGlanceMobile

final class ProviderActivityDetectorTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func snapshot(at date: Date, codex: Double = 30, claude: Double = 40) -> QuotaSnapshot {
        var value = QuotaSnapshot.empty
        value.capturedAt = date
        value.usageUpdatedAt = date
        value.directCodexAccountID = "codex-account"
        value.usagePercent = codex
        value.resetAt = now.addingTimeInterval(3 * 86_400)
        value.claude = .init(capturedAt: date, usagePercent: claude, resetAt: now.addingTimeInterval(2 * 86_400),
                             planName: nil, accountID: "claude-account", verified: true, needsConnection: false,
                             fiveHourUsagePercent: 5, fiveHourResetAt: now.addingTimeInterval(3_600))
        return value
    }
    func testDetectsEachActiveProviderThenBothAndExpiresQuietProviders() {
        let old = snapshot(at: now.addingTimeInterval(-120))
        var codex = snapshot(at: now, codex: 31)
        codex.recentProviderActivity = ProviderActivityDetector.activity(previous: old, current: codex, now: now)
        XCTAssertEqual(ProviderActivityDetector.activeProviders(in: codex, now: now).map(\.rawValue), ["codex"])
        var both = snapshot(at: now.addingTimeInterval(120), codex: 31, claude: 41)
        both.recentProviderActivity = ProviderActivityDetector.activity(previous: codex, current: both, now: now.addingTimeInterval(120))
        XCTAssertEqual(ProviderActivityDetector.activeProviders(in: both, now: now.addingTimeInterval(120)).map(\.rawValue), ["codex", "claude"])
        XCTAssertEqual(ProviderActivityDetector.activeProviders(in: both, now: now.addingTimeInterval(400)).map(\.rawValue), ["claude"])
        XCTAssertTrue(ProviderActivityDetector.activeProviders(in: both, now: now.addingTimeInterval(700)).isEmpty)
    }
    func testFirstReadingOldHistoryAndAccountSwitchNeverPretendToBeActive() {
        let current = snapshot(at: now, codex: 90, claude: 95)
        XCTAssertTrue(ProviderActivityDetector.activity(previous: .empty, current: current, now: now).isEmpty)
        XCTAssertTrue(ProviderActivityDetector.activity(previous: snapshot(at: now.addingTimeInterval(-3_600)), current: current, now: now).isEmpty)
        var switched = current
        switched.directCodexAccountID = "another-codex"
        switched.claude?.accountID = "another-claude"
        XCTAssertTrue(ProviderActivityDetector.activity(previous: snapshot(at: now.addingTimeInterval(-120)), current: switched, now: now).isEmpty)
    }
    func testSessionIncreasesCountEvenWhenRoundedWeeklyQuotaDoesNotMove() {
        let previous = snapshot(at: now.addingTimeInterval(-120))
        var current = snapshot(at: now)
        current.claude?.fiveHourUsagePercent = 6
        XCTAssertEqual(ProviderActivityDetector.activity(previous: previous, current: current, now: now).keys.sorted(), ["claude"])
    }
    func testResetCelebratesWithoutCountingAsNewUsage() {
        let old = snapshot(at: now.addingTimeInterval(-120))
        let reset = snapshot(at: now, codex: 0, claude: 0)
        XCTAssertTrue(ProviderActivityDetector.activity(previous: old, current: reset, now: now).isEmpty)
        XCTAssertEqual(ProviderActivityDetector.resets(previous: old, current: reset, now: now).map(\.rawValue), ["codex", "claude"])
        var switched = reset
        switched.directCodexAccountID = "another-account"
        XCTAssertEqual(ProviderActivityDetector.resets(previous: old, current: switched, now: now).map(\.rawValue), ["claude"])
    }
}
