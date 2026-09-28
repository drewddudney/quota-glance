import XCTest
import AVFoundation
@testable import QuotaGlance

final class ProviderResetPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testShuffleVisitsEverySceneAndAvoidsBoundaryRepeats() throws {
        var shuffle = ProviderResetShuffle()
        var random = SystemRandomNumberGenerator()
        var previous: ProviderResetAnimation?
        for _ in 0..<4 {
            let cycle = try (0..<ProviderResetAnimation.performances.count).map { _ in
                let next = try XCTUnwrap(shuffle.resolve(.shuffle, for: .codex, using: &random))
                XCTAssertNotEqual(next, previous)
                previous = next
                return next
            }
            XCTAssertEqual(Set(cycle), Set(ProviderResetAnimation.performances))
        }
        XCTAssertNil(shuffle.resolve(.off, for: .codex, using: &random))
        XCTAssertEqual(shuffle.resolve(.tokenPool, for: .codex, using: &random), .tokenPool)
    }

    func testShuffleKeepsEachProvidersBagIndependent() throws {
        var shuffle = ProviderResetShuffle()
        var random = SystemRandomNumberGenerator()
        let first = try XCTUnwrap(shuffle.resolve(.shuffle, for: .codex, using: &random))
        let claude = try (0..<ProviderResetAnimation.performances.count).map { _ in
            try XCTUnwrap(shuffle.resolve(.shuffle, for: .claude, using: &random))
        }
        let rest = try (1..<ProviderResetAnimation.performances.count).map { _ in
            try XCTUnwrap(shuffle.resolve(.shuffle, for: .codex, using: &random))
        }
        XCTAssertEqual(Set([first] + rest), Set(ProviderResetAnimation.performances))
        XCTAssertEqual(Set(claude), Set(ProviderResetAnimation.performances))
    }

    func testAllEffectsDecodeAsAudioAndEndWithinTheirScene() throws {
        for animation in ProviderResetAnimation.performances {
            let data = try XCTUnwrap(ProviderResetSoundtrack.data(for: animation))
            let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
            XCTAssertEqual(player.numberOfChannels, 1)
            XCTAssertGreaterThan(player.duration, 0.1)
            XCTAssertLessThan(player.duration, animation.duration)
            let reduced = try XCTUnwrap(ProviderResetSoundtrack.data(for: animation, reducedMotion: true))
            XCTAssertLessThan(try AVAudioPlayer(data: reduced).duration, 1)
        }
        XCTAssertNil(ProviderResetSoundtrack.data(for: .off))
        XCTAssertNil(ProviderResetSoundtrack.data(for: .shuffle))
    }

    func testCodexOnlyCelebratesNewConfirmedCompletion() {
        var detector = ProviderResetDetector()
        XCTAssertNil(detector.codex(completedAt: now.addingTimeInterval(-10), now: now))
        XCTAssertNil(detector.codex(completedAt: now.addingTimeInterval(-10), now: now))
        XCTAssertEqual(detector.codex(completedAt: now, now: now)?.provider, .codex)
        XCTAssertNil(detector.codex(completedAt: now, now: now))
        XCTAssertNil(detector.codex(completedAt: now.addingTimeInterval(-5), now: now))
    }

    func testCodexIgnoresOldAndFutureCompletions() {
        var detector = ProviderResetDetector()
        XCTAssertNil(detector.codex(completedAt: nil, now: now))
        XCTAssertNil(detector.codex(completedAt: now.addingTimeInterval(-400), now: now))
        XCTAssertNil(detector.codex(completedAt: now.addingTimeInterval(30), now: now))
    }

    func testClaudeSessionResetDoesNotRequireWeeklyReset() {
        var detector = ProviderResetDetector()
        let end = now.addingTimeInterval(-30)
        let before = snapshot(captured: now.addingTimeInterval(-60), sessionEnd: end, used: 94)
        let after = snapshot(captured: now, sessionEnd: end.addingTimeInterval(5 * 3_600), used: 1)
        XCTAssertNil(detector.claude(snapshot: before, verified: true, now: before.capturedAt))
        XCTAssertEqual(detector.claude(snapshot: after, verified: true, now: now)?.caption, "Claude’s session is refilled")
        XCTAssertNil(detector.claude(snapshot: after, verified: true, now: now))
        XCTAssertNil(detector.claude(snapshot: snapshot(captured: now.addingTimeInterval(120), sessionEnd: after.fiveHour!.resetAt!, used: 8), verified: true, now: now.addingTimeInterval(120)))
    }

    func testClaudeWeeklyAndSessionResetTogetherProduceOneWeeklyEvent() {
        var detector = ProviderResetDetector()
        let end = now.addingTimeInterval(-30)
        var before = snapshot(captured: now.addingTimeInterval(-60), sessionEnd: end, used: 90)
        before = ClaudeUsageSnapshot(capturedAt: before.capturedAt, weekly: ClaudeWeeklyUsage(usedPercent: 98, resetAt: end), credentialID: "same-account", plan: "max", source: .web, fiveHour: before.fiveHour)
        let after = ClaudeUsageSnapshot(capturedAt: now, weekly: ClaudeWeeklyUsage(usedPercent: 1, resetAt: end.addingTimeInterval(7 * 86_400)), credentialID: "same-account", plan: "max", source: .web, fiveHour: ClaudeFiveHourUsage(usedPercent: 1, resetAt: end.addingTimeInterval(5 * 3_600)))
        XCTAssertNil(detector.claude(snapshot: before, verified: true, now: before.capturedAt))
        XCTAssertEqual(detector.claude(snapshot: after, verified: true, now: now)?.caption, "Claude’s week is refilled")
        XCTAssertNil(detector.claude(snapshot: after, verified: true, now: now))
    }

    func testClaudeIgnoresAccountChangesStaleValuesAndPercentageDrops() {
        let end = now.addingTimeInterval(-30)
        let before = snapshot(captured: now.addingTimeInterval(-60), sessionEnd: end, used: 95)
        let candidates = [
            snapshot(captured: now, sessionEnd: end.addingTimeInterval(5 * 3_600), used: 1, account: "different-account"),
            snapshot(captured: now.addingTimeInterval(-400), sessionEnd: end.addingTimeInterval(5 * 3_600), used: 1),
            snapshot(captured: now, sessionEnd: end, used: 0),
            snapshot(captured: now, sessionEnd: end.addingTimeInterval(60), used: 0),
            snapshot(captured: now, sessionEnd: end.addingTimeInterval(5 * 3_600), used: nil)
        ]
        for candidate in candidates {
            var detector = ProviderResetDetector()
            _ = detector.claude(snapshot: before, verified: true, now: before.capturedAt)
            XCTAssertNil(detector.claude(snapshot: candidate, verified: true, now: now))
        }
        var detector = ProviderResetDetector()
        _ = detector.claude(snapshot: before, verified: true, now: before.capturedAt)
        XCTAssertNil(detector.claude(snapshot: snapshot(captured: now, sessionEnd: end.addingTimeInterval(5 * 3_600), used: 1), verified: false, now: now))
    }

    private func snapshot(captured: Date, sessionEnd: Date, used: Double?, account: String = "same-account") -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(capturedAt: captured, weekly: ClaudeWeeklyUsage(usedPercent: 72, resetAt: now.addingTimeInterval(86_400)), credentialID: account, plan: "max", source: .web, fiveHour: ClaudeFiveHourUsage(usedPercent: used, resetAt: sessionEnd))
    }
}
