import Foundation

struct ClaudeNotificationEvent: Equatable {
    let id: String
    let title: String
    let body: String
}

enum ClaudeNotificationPolicy {
    static func events(
        current: ClaudeQuotaSnapshot?, previous: ClaudeQuotaSnapshot?,
        usageEnabled: Bool, weekEnabled: Bool, threshold: Double,
        seen: Set<String>, now: Date = Date()
    ) -> [ClaudeNotificationEvent] {
        guard let current, current.isFresh(at: now), let capturedAt = current.capturedAt else { return [] }
        func window(_ date: Date) -> String {
            "\(current.accountID ?? "claude")-\(Int(date.timeIntervalSince1970 / 60))"
        }
        var result: [ClaudeNotificationEvent] = []
        if usageEnabled, let resetAt = current.resetAt,
           let usage = current.displayedUsage(at: now), usage >= threshold {
            result.append(.init(
                id: "claude-weekly-limit-\(window(resetAt))-\(Int(threshold))",
                title: "Claude weekly usage is at \(Int(usage.rounded()))%",
                body: "Your weekly allowance renews \(resetAt.formatted(date: .abbreviated, time: .shortened))."
            ))
        }
        if usageEnabled, let resetAt = current.fiveHourResetAt,
           let usage = current.displayedFiveHourUsage(at: now), usage >= threshold {
            result.append(.init(
                id: "claude-five-hour-limit-\(window(resetAt))-\(Int(threshold))",
                title: "Claude five-hour usage is at \(Int(usage.rounded()))%",
                body: "Your five-hour allowance renews at \(resetAt.formatted(date: .omitted, time: .shortened))."
            ))
        }
        // A deadline passing does not prove the allowance renewed. Require a
        // fresh measurement of a new weekly window for the same account.
        if weekEnabled, let resetAt = current.resetAt, resetAt > now,
           let previous, let oldEnd = previous.resetAt,
           let oldCapture = previous.capturedAt,
           let account = current.accountID, account == previous.accountID,
           capturedAt > oldCapture, oldEnd <= capturedAt,
           resetAt.timeIntervalSince(oldEnd) >= 5 * 86_400 {
            result.append(.init(
                id: "claude-week-\(window(resetAt))", title: "Your new Claude week is ready",
                body: "Claude confirmed a new weekly allowance."
            ))
        }
        return result.filter { !seen.contains($0.id) }
    }
}
