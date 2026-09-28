import SwiftUI

/// Uses the same calendar, percentage chart and pace controls as Codex.
/// Samples are restored from Claude's local usage cache after relaunch.
struct ProviderClaudeActivity: View {
    @ObservedObject var model: ClaudeUsageModel

    var body: some View {
        let value = model.mobileSnapshot
        VStack(alignment: .leading, spacing: 12) {
            Text("Usage & pace").font(.system(size: 13, weight: .semibold))
            if let end = value.resetAt {
                QuotaHistoryView(
                    current: .init(start: end.addingTimeInterval(-ClaudeUsageHistory.week), end: end,
                        points: (value.usageHistory ?? []).map { .init(date: $0.date, used: $0.usedPercent) },
                        used: value.usagePercent),
                    archives: (value.weeklyArchives ?? []).map {
                        .init(start: $0.windowStart, end: $0.resetAt,
                            points: $0.points.map { .init(date: $0.date, used: $0.usedPercent) }, used: $0.finalUsedPercent)
                    },
                    fallbackRunout: ClaudeUsageHistory.estimate(for: value),
                    tint: Color(red: 0.88, green: 0.59, blue: 0.45),
                    recordedMeasurementAt: value.isFresh(at: .now) ? value.capturedAt : .distantPast
                ).id(value.accountID)
                if value.usageHistory?.count == 1 {
                    Text("First reading recorded. Your graph and pace will build as Claude refreshes.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else {
                Text("Claude’s recorded usage will appear after a successful weekly usage refresh.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}
