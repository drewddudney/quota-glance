import SwiftUI
import WidgetKit

struct ProvidersWidget: Widget {
    let kind = "QuotaGlanceProviders"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaProvider()) { entry in
            ProvidersWidgetView(entry: entry)
                .containerBackground(CompanionStyle.paper, for: .widget)
        }
        .configurationDisplayName("Quota companions")
        .description("A little home for Codex and Clawd. Weekly usage, time elapsed, and reset or session readings follow your provider choice in the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct ProvidersWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuotaEntry
    var body: some View {
        CompanionWidgetContent(snapshot: entry.snapshot, date: entry.date, family: family)
    }
}
