import XCTest
@testable import QuotaGlance

/// Exercise refresh ordering with mocked fetches and real cache/lifecycle stores.
/// Never instantiate the dashboard: its initializer starts live provider work.
final class CodexRefreshResetTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private let start = Date(timeIntervalSince1970: 2_000_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaGlanceRefreshTests-" + UUID().uuidString)
        suite = "QuotaGlanceTests.RefreshReset." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testSameWindowResetReachesDetectorAndSurvivesCacheReload() async throws {
        _ = try await refresh(percent: 62, offset: 0)
        let candidate = try await refresh(percent: 0, offset: 10)
        XCTAssertEqual(candidate.snapshot.usedPercent, 0)
        XCTAssertEqual(candidate.lifecycle.lastUsedPercent, 0)
        XCTAssertTrue(candidate.lifecycle.hasPendingResetCandidate)
        XCTAssertNil(candidate.lifecycle.completedAt)

        let confirmed = try await refresh(percent: 1, offset: 75)
        XCTAssertEqual(confirmed.lifecycle.completedAt, start.addingTimeInterval(75))
        XCTAssertFalse(confirmed.lifecycle.hasPendingResetCandidate)
        XCTAssertEqual(confirmed.snapshot.usedPercent, 1)
        XCTAssertEqual(CodexSnapshotStore.load(from: directory)?.snapshot.usedPercent, 1)
    }

    func testTransientZeroDoesNotConfirmResetAndRecoveryClearsCandidate() async throws {
        _ = try await refresh(percent: 62, offset: 0)
        let zero = try await refresh(percent: 0, offset: 10)
        XCTAssertNil(zero.lifecycle.completedAt)
        XCTAssertTrue(zero.lifecycle.hasPendingResetCandidate)

        let recovered = try await refresh(percent: 63, offset: 75)
        XCTAssertNil(recovered.lifecycle.completedAt)
        XCTAssertFalse(recovered.lifecycle.hasPendingResetCandidate)
        XCTAssertEqual(recovered.snapshot.usedPercent, 63)
    }

    func testSecondLowBeforeOneMinuteDoesNotConfirmReset() async throws {
        _ = try await refresh(percent: 62, offset: 0)
        _ = try await refresh(percent: 0, offset: 10)
        let early = try await refresh(percent: 1, offset: 69)
        XCTAssertNil(early.lifecycle.completedAt)
        XCTAssertTrue(early.lifecycle.hasPendingResetCandidate)
    }

    func testAdvancedBoundaryInsideCacheToleranceConfirmsResetImmediately() async throws {
        _ = try await refresh(percent: 62, offset: 0)
        // Cache tolerance is two hours; the lifecycle recognizes >30 minutes.
        let revisedStart = start.addingTimeInterval(31 * 60)
        let reset = try await refresh(percent: 0, offset: 7_200, windowStart: revisedStart)
        XCTAssertEqual(reset.snapshot.usageWindowStart, revisedStart)
        XCTAssertEqual(reset.lifecycle.completedAt, start.addingTimeInterval(7_200))
        XCTAssertFalse(reset.lifecycle.hasPendingResetCandidate)
        XCTAssertEqual(CodexSnapshotStore.load(from: directory)?.snapshot.usageWindowStart, revisedStart)
    }

    func testNewWeeklyWindowReplacesCachedHighUsage() async throws {
        _ = try await refresh(percent: 95, offset: 0)
        let newStart = start.addingTimeInterval(7 * 86_400)
        let reset = try await refresh(percent: 2, offset: 7 * 86_400, windowStart: newStart)
        XCTAssertEqual(reset.snapshot.usedPercent, 2)
        XCTAssertEqual(reset.snapshot.usageWindowStart, newStart)
        XCTAssertEqual(reset.lifecycle.completedAt, newStart)
    }

    func testPlanChangeBetweenLowReadingsDoesNotConfirmReset() async throws {
        _ = try await refresh(percent: 62, offset: 0)
        _ = try await refresh(percent: 0, offset: 10)
        let changed = try await refresh(percent: 0, offset: 75, planName: "Plus")
        XCTAssertNil(changed.lifecycle.completedAt)
        XCTAssertFalse(changed.lifecycle.hasPendingResetCandidate)
        XCTAssertEqual(changed.snapshot.planName, "Plus")
    }

    func testLowerLivePercentageKeepsLocalHistoryFallbacks() async throws {
        _ = try await refresh(percent: 62, offset: 0, tokens: 100)
        let lower = try await refresh(percent: 40, offset: 75, tokens: 50)
        XCTAssertEqual(lower.snapshot.usedPercent, 40)
        XCTAssertEqual(lower.snapshot.weeklyTokens, 100)
        XCTAssertEqual(lower.snapshot.localTokensTotal, 100)
        XCTAssertEqual(lower.snapshot.localTokenPace?.sinceReset, 100)
        XCTAssertEqual(lower.snapshot.usageDays.first?.tokens, 100)
        XCTAssertNil(lower.lifecycle.completedAt)
    }

    private func refresh(
        percent: Double,
        offset: TimeInterval,
        windowStart: Date? = nil,
        planName: String = "Pro 20X",
        tokens: Int64 = 100
    ) async throws -> (snapshot: CodexSnapshot, lifecycle: ResetLifecycleSnapshot) {
        let window = windowStart ?? start
        let fetch: () async throws -> CodexSnapshot = {
            CodexSnapshot(
                usedPercent: percent,
                resetAt: window.addingTimeInterval(7 * 86_400),
                resetDeadlineIsCredit: false,
                weeklyTokens: tokens,
                localTokensTotal: tokens,
                localTokenPace: LocalTokenPaceSnapshot(
                    fiveMinutes: tokens, oneHour: tokens,
                    twelveHours: tokens, twentyFourHours: tokens, sinceReset: tokens
                ),
                usageIntelligence: nil, secondaryQuota: nil,
                quotaInventory: nil, creditSummary: nil, resetCredits: nil, activeTasks: nil,
                usageDays: [UsageDay(date: window, tokens: tokens)],
                usageWindowStart: window, windowDurationMinutes: 10_080,
                weekElapsedPercent: 50, planName: planName
            )
        }
        let live = try await fetch()
        let cached = CodexSnapshotStore.save(live, at: start.addingTimeInterval(offset), in: directory)
        let lifecycle = ResetLifecycleStore.observeUsage(
            windowStart: cached.snapshot.usageWindowStart,
            usedPercent: cached.snapshot.usedPercent,
            planName: cached.snapshot.planName,
            observedAt: cached.savedAt,
            defaults: defaults
        )
        return (cached.snapshot, lifecycle)
    }
}
