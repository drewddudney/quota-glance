import XCTest
@testable import QuotaGlance

final class AdaptiveRefreshTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testPendingResetGetsOneMinuteConfirmationRefresh() {
        let decision = AdaptiveRefreshPolicy().nextDelay(for: .init(
            now: now,
            lastInteractionAt: nil,
            lastCodingActivityAt: nil,
            isConstrained: false,
            pendingResetConfirmation: true
        ))
        XCTAssertEqual(decision, .init(interval: 60, reason: .resetConfirmation))
    }

    func testRecentMenuInteractionRefreshesInTwoMinutes() {
        let decision = AdaptiveRefreshPolicy().nextDelay(for: .init(
            now: now,
            lastInteractionAt: now.addingTimeInterval(-30),
            lastCodingActivityAt: nil,
            isConstrained: false,
            pendingResetConfirmation: false
        ))
        XCTAssertEqual(decision, .init(interval: 120, reason: .recentInteraction))
    }

    func testActiveCodingRefreshesEveryFifteenSeconds() {
        let decision = AdaptiveRefreshPolicy().nextDelay(for: .init(
            now: now,
            lastInteractionAt: now,
            lastCodingActivityAt: now.addingTimeInterval(-30),
            isConstrained: false,
            pendingResetConfirmation: false
        ))
        XCTAssertEqual(decision, .init(interval: 15, reason: .codingActivity))
    }

    func testLongIdleAndConstrainedUseThirtyMinutes() {
        let policy = AdaptiveRefreshPolicy()
        let idle = policy.nextDelay(for: .init(
            now: now,
            lastInteractionAt: now.addingTimeInterval(-5 * 60 * 60),
            lastCodingActivityAt: nil,
            isConstrained: false,
            pendingResetConfirmation: false
        ))
        let constrained = policy.nextDelay(for: .init(
            now: now,
            lastInteractionAt: now,
            lastCodingActivityAt: now,
            isConstrained: true,
            pendingResetConfirmation: false
        ))
        XCTAssertEqual(idle.interval, 1_800)
        XCTAssertEqual(constrained.reason, .constrained)
    }

    func testFreshnessSeparatesLiveStaleAndOffline() {
        XCTAssertEqual(
            CodexDataFreshness.resolve(
                lastSuccessfulAt: now.addingTimeInterval(-60),
                lastAttemptFailed: false,
                hasCachedData: true,
                at: now
            ),
            .live
        )
        XCTAssertEqual(
            CodexDataFreshness.resolve(
                lastSuccessfulAt: now.addingTimeInterval(-60),
                lastAttemptFailed: true,
                hasCachedData: true,
                at: now
            ),
            .stale
        )
        XCTAssertEqual(
            CodexDataFreshness.resolve(
                lastSuccessfulAt: now.addingTimeInterval(-2 * 60 * 60),
                lastAttemptFailed: true,
                hasCachedData: true,
                at: now
            ),
            .offline
        )
    }
}
