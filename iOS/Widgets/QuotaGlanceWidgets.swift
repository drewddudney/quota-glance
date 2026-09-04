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
        snapshot.providers = [
            ProviderReading(source: .lunarWerx, percent: 74, updatedAt: Date()),
            ProviderReading(source: .gussuri, percent: 66, updatedAt: Date())
        ]
        return snapshot
    }
}

struct QuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuotaEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            LockScreenRings(snapshot: entry.snapshot)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Week, Codex usage, and reset chance")
                .accessibilityValue(
                    "Week \(percent(entry.snapshot.weekElapsedPercent)), "
                    + "usage \(percent(entry.snapshot.usagePercent)), "
                    + "reset \(percent(entry.snapshot.effectiveResetChance))"
                )
        case .accessoryRectangular:
            HStack(spacing: 10) {
                miniMetric("W", entry.snapshot.weekElapsedPercent)
                miniMetric("U", entry.snapshot.usagePercent)
                miniMetric("R", entry.snapshot.effectiveResetChance)
            }
        case .accessoryInline:
            Text("Codex \(percent(entry.snapshot.usagePercent)) · Reset \(Int(entry.snapshot.effectiveResetChance.rounded()))%")
        case .systemMedium:
            HStack(spacing: 16) {
                WidgetRings(snapshot: entry.snapshot)
                    .frame(width: 118, height: 118)
                VStack(alignment: .leading, spacing: 12) {
                    row("WEEK", entry.snapshot.weekElapsedPercent, Color(hex: QuotaColors.calendar))
                    row("USED", entry.snapshot.usagePercent, Color(hex: QuotaColors.usage))
                    row("RESET", entry.snapshot.effectiveResetChance, Color(hex: QuotaColors.reset))
                    Text(entry.snapshot.effectiveResetAnnounced ? "🔥 USE IT NOW" : entry.snapshot.resetSourceLabel.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(entry.snapshot.effectiveResetAnnounced ? Color.orange : .white.opacity(0.42))
                        .lineLimit(1)
                }
            }
            .padding(4)
        default:
            WidgetRings(snapshot: entry.snapshot)
                .padding(2)
        }
    }

    private func miniMetric(_ label: String, _ value: Double?) -> some View {
        VStack(spacing: 0) {
            Text(label).font(.caption2.bold())
            Text(percent(value)).font(.system(.body, design: .rounded, weight: .semibold))
        }
    }

    private func row(_ label: String, _ value: Double?, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
            Spacer()
            Text(percent(value)).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
        }
    }

    private func percent(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))%" } ?? "—"
    }
}

private struct LockScreenRings: View {
    let snapshot: QuotaSnapshot

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let stroke = max(2, side * 0.065)
            let gap = max(1.5, side * 0.025)
            let step = stroke + gap

            ZStack {
                ring(
                    snapshot.weekElapsedPercent ?? 0,
                    color: Color(hex: QuotaColors.calendar),
                    inset: stroke * 0.55,
                    stroke: stroke
                )
                ring(
                    snapshot.usagePercent ?? 0,
                    color: Color(hex: QuotaColors.usage),
                    inset: stroke * 0.55 + step,
                    stroke: stroke
                )
                ring(
                    snapshot.effectiveResetChance,
                    color: snapshot.effectiveResetAnnounced ? .orange : Color(hex: QuotaColors.reset),
                    inset: stroke * 0.55 + step * 2,
                    stroke: stroke
                )
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func ring(_ value: Double, color: Color, inset: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: stroke)
            Circle()
                .trim(from: 0, to: max(0, min(1, value / 100)))
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }
}

private struct WidgetRings: View {
    let snapshot: QuotaSnapshot

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                ring(snapshot.weekElapsedPercent ?? 0, Color(hex: QuotaColors.calendar), side * 0.08)
                ring(snapshot.usagePercent ?? 0, Color(hex: QuotaColors.usage), side * 0.19)
                ring(
                    snapshot.effectiveResetChance,
                    snapshot.effectiveResetAnnounced ? Color.orange : Color(hex: QuotaColors.reset),
                    side * 0.30
                )
                Image(systemName: snapshot.effectiveResetAnnounced ? "flame.fill" : "arrow.triangle.2.circlepath")
                    .font(.system(size: side * 0.13, weight: .bold))
                    .foregroundStyle(snapshot.effectiveResetAnnounced ? Color.orange : Color(hex: QuotaColors.reset))
            }
            .frame(width: side, height: side)
        }
    }

    private func ring(_ value: Double, _ color: Color, _ inset: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0, min(1, value / 100)))
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }
}

struct QuotaGlanceWidget: Widget {
    let kind = "QuotaGlanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaProvider()) { entry in
            QuotaWidgetView(entry: entry)
                .containerBackground(Color(hex: 0x0A0E11), for: .widget)
        }
        .configurationDisplayName("Quota Glance")
        .description("Codex usage, week progress, and reset chance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
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
                    Text(context.state.taskName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text("\(tokenText(context.state.totalTokens)) · \(rateText(context.state.tokensPerMinute))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 3) {
                    projectedPercentage(context.state, size: 22)
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
                    projectedPercentage(context.state, size: 18)
                        .frame(minWidth: 76, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.taskName)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(tokenText(context.state.totalTokens), systemImage: "number")
                        Spacer()
                        Label(rateText(context.state.tokensPerMinute), systemImage: "gauge.with.dots.needle.67percent")
                    }
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Text(">_")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(blue)
            } compactTrailing: {
                projectedPercentage(context.state, size: 10)
            } minimal: {
                Text(">_")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(blue)
            }
            .keylineTint(blue)
        }
    }

    @ViewBuilder
    private func projectedPercentage(
        _ state: CodexSessionActivityAttributes.ContentState,
        size: CGFloat
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let percent = CodexSessionUsageProjection.projectedPercent(
                basePercent: state.usedPercent,
                percentPerMinute: state.percentPerMinute ?? 0,
                updatedAt: state.updatedAt,
                now: timeline.date
            )
            Text(String(format: "%.3f%%", percent))
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
                .layoutPriority(2)
                .foregroundStyle(blue)
        }
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
        ResetCountdownLiveActivity()
        CodexSessionLiveActivity()
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
