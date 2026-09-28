import ActivityKit
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

struct QuotaWidgetView: View {
    let entry: QuotaEntry
    var body: some View { ProvidersWidgetView(entry: entry) }
}

struct QuotaGlanceWidget: Widget {
    let kind = "QuotaGlanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaProvider()) { entry in
            QuotaWidgetView(entry: entry)
                .containerBackground(CompanionStyle.paper, for: .widget)
        }
        .configurationDisplayName("Quota Glance")
        .description("Codex, Claude, or Both. Follows the provider choice in the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct ResetCountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ResetCountdownAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "hourglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(hex: QuotaColors.reset))
                    .frame(width: 42, height: 42)
                    .background(Color(hex: QuotaColors.reset).opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.isDelayed ? "RESET DELAYED" : "CODEX RESET")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    countdownText(context.state)
                        .font(.system(size: context.state.isDelayed ? 17 : 25, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(context.state.expectedAt, format: .dateTime.hour().minute())
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(TimeZone.autoupdatingCurrent.abbreviation() ?? "LOCAL")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .activityBackgroundTint(Color(hex: 0x0A0E11))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "hourglass")
                        .foregroundStyle(Color(hex: QuotaColors.reset))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.expectedAt, format: .dateTime.hour().minute())
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.isDelayed ? "Reset delayed" : "Codex reset")
                            .foregroundStyle(.secondary)
                        Spacer()
                        countdownText(context.state)
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                    }
                }
            } compactLeading: {
                Image(systemName: "hourglass")
                    .foregroundStyle(Color(hex: QuotaColors.reset))
            } compactTrailing: {
                countdownText(context.state)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "hourglass")
                    .foregroundStyle(Color(hex: QuotaColors.reset))
            }
            .keylineTint(Color(hex: QuotaColors.reset))
        }
    }

    @ViewBuilder
    private func countdownText(_ state: ResetCountdownAttributes.ContentState) -> some View {
        if state.isDelayed {
            Text("DELAYED")
        } else {
            // A timer interval stops at zero. Date's `.timer` style begins
            // counting upward after its target, which made late resets lie.
            Text(timerInterval: min(Date(), state.expectedAt)...state.expectedAt, countsDown: true)
        }
    }
}

struct CodexSessionLiveActivity: Widget {
    private let blue = Color(hex: QuotaColors.usage)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CodexSessionActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Text(">_")
                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                    .foregroundStyle(blue)
                    .frame(width: 44, height: 44)
                    .background(blue.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.isStale ? "Waiting for Mac update" : context.state.taskName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text("Mac: \(tokenText(context.state.totalTokens))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 3) {
                    measuredPercentage(context.state, size: 22)
                    Text(context.state.updatedAt, style: .relative)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 108, alignment: .trailing)
                .layoutPriority(2)
            }
            .padding(.horizontal, 16)
            .activityBackgroundTint(Color(hex: 0x0A0E11))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(">_")
                        .font(.system(.body, design: .monospaced, weight: .bold))
                        .foregroundStyle(blue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    measuredPercentage(context.state, size: 18)
                        .frame(minWidth: 76, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.isStale ? "Waiting for Mac update" : context.state.taskName)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label("Mac: " + tokenText(context.state.totalTokens), systemImage: "number")
                        Spacer()
                        Text(context.isStale ? "Update delayed" : rateText(context.state.tokensPerMinute))
                    }
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Text(">_")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(blue)
            } compactTrailing: {
                measuredPercentage(context.state, size: 10)
            } minimal: {
                Text(">_")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(blue)
            }
            .keylineTint(blue)
        }
    }

    private func measuredPercentage(
        _ state: CodexSessionActivityAttributes.ContentState,
        size: CGFloat
    ) -> some View {
        Text(String(format: "%.0f%%", state.usedPercent))
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(blue)
            .accessibilityLabel("Account quota used, \(Int(state.usedPercent)) percent")
    }

    private func tokenText(_ tokens: Int64) -> String {
        compact(tokens, suffix: " tokens")
    }

    private func rateText(_ tokens: Int64) -> String {
        tokens > 0 ? compact(tokens, suffix: "/min") : "syncing"
    }

    private func compact(_ value: Int64, suffix: String) -> String {
        let number = Double(max(0, value))
        if number >= 1_000_000_000 {
            return String(format: "%.2fB", number / 1_000_000_000) + suffix
        }
        if number >= 1_000_000 {
            return String(format: "%.1fM", number / 1_000_000) + suffix
        }
        if number >= 1_000 {
            return String(format: "%.1fK", number / 1_000) + suffix
        }
        return "\(value)" + suffix
    }
}

@main
struct QuotaGlanceWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuotaGlanceWidget()
        ProvidersWidget()
        ResetCountdownLiveActivity()
        CodexSessionLiveActivity()
        ProviderUsageLiveActivity()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
