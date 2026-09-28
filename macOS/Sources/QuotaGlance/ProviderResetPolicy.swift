import Foundation

/// A forecast, an expired cached meter, or a sign-in change is not a refill.
/// The first observation establishes a baseline; only fresh transitions play.
struct ProviderResetDetector {
    private var codexStarted = false
    private var codexCompletedAt: Date?
    private var claudePrevious: ClaudeUsageSnapshot?

    mutating func codex(completedAt: Date?, now: Date) -> ProviderResetEvent? {
        let previous = codexCompletedAt
        defer { codexStarted = true; codexCompletedAt = completedAt }
        guard codexStarted, let completedAt, previous != completedAt,
              previous == nil || completedAt > previous!,
              completedAt <= now, now.timeIntervalSince(completedAt) < 5 * 60 else { return nil }
        return ProviderResetEvent(provider: .codex,
                                  identity: "codex-\(Int(completedAt.timeIntervalSince1970))",
                                  caption: "Codex is refilled")
    }

    mutating func claude(snapshot: ClaudeUsageSnapshot?, verified: Bool, now: Date) -> ProviderResetEvent? {
        guard let current = snapshot else { claudePrevious = nil; return nil }
        guard verified, current.capturedAt <= now,
              now.timeIntervalSince(current.capturedAt) < 5 * 60 else { return nil }
        let previous = claudePrevious
        guard previous == nil || current.capturedAt > previous!.capturedAt else { return nil }
        defer { claudePrevious = current }
        guard let previous, previous.credentialID == current.credentialID,
              previous.source == current.source, previous.plan == current.plan else { return nil }

        if let end = renewed(oldEnd: previous.weekly?.resetAt, newEnd: current.weekly?.resetAt,
                             used: current.weekly?.usedPercent, advance: 5 * 86_400, capturedAt: current.capturedAt, now: now) {
            return ProviderResetEvent(provider: .claude, identity: "claude-week-\(Int(end.timeIntervalSince1970 / 60))",
                                      caption: "Claude’s week is refilled")
        }
        if let end = renewed(oldEnd: previous.fiveHour?.resetAt, newEnd: current.fiveHour?.resetAt,
                             used: current.fiveHour?.usedPercent, advance: 4 * 3_600, capturedAt: current.capturedAt, now: now) {
            return ProviderResetEvent(provider: .claude, identity: "claude-session-\(Int(end.timeIntervalSince1970 / 60))",
                                      caption: "Claude’s session is refilled")
        }
        return nil
    }

    private func renewed(oldEnd: Date?, newEnd: Date?, used: Double?, advance: TimeInterval, capturedAt: Date, now: Date) -> Date? {
        guard let oldEnd, let newEnd, let used, used.isFinite, (0...100).contains(used),
              oldEnd <= capturedAt, now.timeIntervalSince(oldEnd) < 15 * 60,
              newEnd > now, newEnd.timeIntervalSince(oldEnd) >= advance else { return nil }
        return newEnd
    }
}
