import SwiftUI

struct ProviderCodexActivity: View {
    @ObservedObject var model: DashboardModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Usage & pace").font(.system(size: 15, weight: .semibold, design: .rounded))
            if let start = model.usageWindowStart, let end = model.resetAt, end > start {
                QuotaHistoryView(current: .init(start: start, end: end,
                    points: model.usageHistory.filter { abs($0.windowStart.timeIntervalSince(start)) < UsageHistoryStore.windowTolerance }
                        .map { .init(date: $0.recordedAt, used: $0.usedPercent) },
                    used: model.usedPercent, tokens: model.localTokensTotal ?? model.weeklyTokens,
                    apiValue: model.usageIntelligence?.apiEquivalentUSD),
                    archives: model.weeklyArchives.map {
                        .init(start: $0.windowStart, end: $0.resetAt,
                              points: $0.points.map { .init(date: $0.date, used: $0.usedPercent) },
                              used: $0.finalUsedPercent, tokens: $0.totalTokens, apiValue: $0.apiEquivalentUSD)
                    }, fallbackRunout: model.providerRunoutAt)
            } else {
                Text("Your usage calendar will appear when Codex reports its quota window.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}
