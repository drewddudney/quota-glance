import SwiftUI
import WidgetKit

struct QuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: QuotaSnapshot
}

struct QuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: Date(), snapshot: preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(QuotaEntry(date: Date(), snapshot: context.isPreview ? preview : SharedSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let now = Date()
        completion(Timeline(
            entries: [QuotaEntry(date: now, snapshot: SharedSnapshotStore.load())],
            policy: .after(now.addingTimeInterval(15 * 60))
        ))
    }

    private var preview: QuotaSnapshot {
        var snapshot = QuotaSnapshot.empty
        snapshot.capturedAt = Date()
        snapshot.weekElapsedPercent = 72
        snapshot.usagePercent = 88
        snapshot.resetChancePercent = 70
        snapshot.claude = ClaudeQuotaSnapshot(capturedAt: Date(), usagePercent: 82,
            resetAt: Date().addingTimeInterval(3 * 86_400), planName: nil,
            accountID: "preview", verified: true, needsConnection: false,
            fiveHourUsagePercent: 31, fiveHourResetAt: Date().addingTimeInterval(2 * 3_600))
        snapshot.providers = [
            ProviderReading(source: .lunarWerx, percent: 74, updatedAt: Date()),
            ProviderReading(source: .gussuri, percent: 66, updatedAt: Date())
        ]
        return snapshot
    }
}


/// Keep the previous WidgetKit kind alive so existing Home Screen placements
/// render the current companion face after an update.
struct QuotaGlanceWidget: Widget {
    let kind = "QuotaGlanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaProvider()) { entry in
            ProvidersWidgetView(entry: entry)
                .containerBackground(CompanionStyle.paper, for: .widget)
        }
        .configurationDisplayName("Quota companions")
        .description("Codex, Claude, or both, in the current companion design.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

@main
struct QuotaGlanceWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuotaGlanceWidget()
        ProvidersWidget()
        ProviderUsageLiveActivity()
    }
}
