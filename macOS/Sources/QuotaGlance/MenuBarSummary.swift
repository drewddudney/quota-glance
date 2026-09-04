import AppKit
import SwiftUI

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case smart
    case weekly
    case dual
    case iconOnly

    static let defaultsKey = "QuotaGlance.menuBarDisplayMode"
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smart: "Smart"
        case .weekly: "Weekly Usage"
        case .dual: "5-Hour + Weekly"
        case .iconOnly: "Icon Only"
        }
    }
}

struct MenuBarQuotaWindow: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let usedPercent: Double
    let resetAt: Date
    let durationMinutes: Double

    var isShort: Bool { durationMinutes > 0 && durationMinutes <= 24 * 60 }
    var isWeekly: Bool { durationMinutes >= 6 * 24 * 60 }
}

struct MenuBarSummaryPayload: Sendable {
    let primary: MenuBarQuotaWindow?
    let secondary: MenuBarQuotaWindow?
    let inventory: [MenuBarQuotaWindow]
    let planName: String
    let paceHeadline: String?
    let paceRunout: String?
    let forecastPercent: Double?
    let forecastRange: String?
    let expectedResetAt: Date?
    let resetIsDelayed: Bool
    let lastBlessingAt: Date?
    let unreadTweet: Bool
    let lastSuccessfulAt: Date?
    let lastAttemptFailed: Bool
    let statusMessage: String
}

@MainActor
final class MenuBarSummaryModel: ObservableObject {
    static let shared = MenuBarSummaryModel()

    @Published private(set) var payload = MenuBarSummaryPayload(
        primary: nil,
        secondary: nil,
        inventory: [],
        planName: "Codex",
        paceHeadline: nil,
        paceRunout: nil,
        forecastPercent: nil,
        forecastRange: nil,
        expectedResetAt: nil,
        resetIsDelayed: false,
        lastBlessingAt: nil,
        unreadTweet: false,
        lastSuccessfulAt: nil,
        lastAttemptFailed: false,
        statusMessage: "Connecting to Codex…"
    )

    private init() {}

    func update(_ payload: MenuBarSummaryPayload) {
        self.payload = payload
        NotificationCenter.default.post(name: .quotaGlanceMenuBarSummaryChanged, object: nil)
    }

    var allQuotaWindows: [MenuBarQuotaWindow] {
        var result: [MenuBarQuotaWindow] = []
        // Model-specific allowances (for example a five-hour Spark window)
        // belong in the detailed inventory, but are not the account's general
        // Codex quota. Only canonical Codex inventory entries may supplement
        // the primary/secondary account windows shown in the menu bar.
        let accountInventory = payload.inventory.filter {
            $0.id == "codex.primary" || $0.id == "codex.secondary"
        }
        for candidate in [payload.primary, payload.secondary].compactMap({ $0 }) + accountInventory {
            let duplicate = result.contains {
                abs($0.durationMinutes - candidate.durationMinutes) < 1
                    && abs($0.resetAt.timeIntervalSince(candidate.resetAt)) < 60
            }
            if !duplicate { result.append(candidate) }
        }
        return result
    }

    var shortWindow: MenuBarQuotaWindow? {
        allQuotaWindows.filter(\.isShort).min { $0.durationMinutes < $1.durationMinutes }
    }

    var weeklyWindow: MenuBarQuotaWindow? {
        allQuotaWindows.filter(\.isWeekly).max { $0.durationMinutes < $1.durationMinutes }
            ?? payload.primary
    }

    var freshness: CodexDataFreshness {
        CodexDataFreshness.resolve(
            lastSuccessfulAt: payload.lastSuccessfulAt,
            lastAttemptFailed: payload.lastAttemptFailed,
            hasCachedData: payload.primary != nil
        )
    }

    func statusText(mode: MenuBarDisplayMode, at now: Date = Date()) -> String {
        if mode == .smart, let expected = payload.expectedResetAt {
            if payload.resetIsDelayed { return "↻ DELAYED" }
            if expected > now { return "↻ \(Self.shortCountdown(to: expected, from: now))" }
        }

        let weekly = weeklyWindow.map { "W \(Int($0.usedPercent.rounded()))%" }
        let short = shortWindow.map { "5H \(Int($0.usedPercent.rounded()))%" }
        switch mode {
        case .smart, .weekly:
            return weekly ?? ">_"
        case .dual:
            return [short, weekly].compactMap { $0 }.joined(separator: " · ").nilIfEmpty ?? ">_"
        case .iconOnly:
            return ">_"
        }
    }

    static func shortCountdown(to date: Date, from now: Date = Date()) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes >= 24 * 60 { return "\(minutes / (24 * 60))D \((minutes % (24 * 60)) / 60)H" }
        if minutes >= 60 { return "\(minutes / 60)H \(minutes % 60)M" }
        return "\(minutes)M"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct MenuBarSummaryPopover: View {
    @ObservedObject var summary: MenuBarSummaryModel
    @AppStorage(WidgetTheme.defaultsKey) private var themeRawValue = WidgetTheme.current.rawValue
    let onOpenWidget: () -> Void
    let onOpenTweets: () -> Void
    let onRefresh: () -> Void

    private var theme: WidgetTheme { WidgetTheme(rawValue: themeRawValue) ?? .current }
    private var palette: PopoverPalette { theme.popoverPalette }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header

            if let short = summary.shortWindow {
                quotaRow(short, title: short.durationMinutes == 300 ? "5-HOUR" : "SESSION")
            }
            if let weekly = summary.weeklyWindow {
                quotaRow(weekly, title: "WEEKLY")
            }

            if summary.payload.primary == nil {
                Text(summary.payload.statusMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondary)
                    .padding(.vertical, 12)
            }

            if summary.payload.paceHeadline != nil || summary.payload.paceRunout != nil {
                paceRow
            }

            resetSignalRow
            actions
        }
        .padding(16)
        .frame(width: 386)
        .background(palette.background)
        .preferredColorScheme(theme.isLight ? .light : .dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(">_")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.pace)
            VStack(alignment: .leading, spacing: 1) {
                Text("CODEX · \(summary.payload.planName.uppercased())")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.primary)
                Text(updatedText)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.tertiary)
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(freshnessColor).frame(width: 6, height: 6)
                Text(summary.freshness.rawValue.uppercased())
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(freshnessColor)
        }
    }

    private func quotaRow(_ window: MenuBarQuotaWindow, title: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.rule)
                    Capsule()
                        .fill(palette.pace)
                        .frame(width: proxy.size.width * min(1, max(0, window.usedPercent / 100)))
                }
            }
            .frame(height: 6)
            HStack {
                Text("\(Int(window.usedPercent.rounded()))% USED")
                Spacer()
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(window.resetAt > context.date
                         ? "RESETS IN \(MenuBarSummaryModel.shortCountdown(to: window.resetAt, from: context.date))"
                         : "RESET DUE")
                }
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(palette.tertiary)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 10).fill(palette.surface))
    }

    private var paceRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(palette.pace)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.payload.paceHeadline?.uppercased() ?? "PACE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                if let runout = summary.payload.paceRunout {
                    Text("TO EMPTY · \(runout.uppercased())")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 11)
    }

    private var resetSignalRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(palette.reset)
                Text("RESET SIGNAL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                Spacer()
                Text("\(Int((summary.payload.forecastPercent ?? 0).rounded()))%")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.reset)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.rule)
                    Capsule().fill(palette.reset)
                        .frame(width: proxy.size.width * min(1, max(0, (summary.payload.forecastPercent ?? 0) / 100)))
                }
            }
            .frame(height: 5)
            HStack(spacing: 8) {
                if let expected = summary.payload.expectedResetAt {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(summary.payload.resetIsDelayed
                             ? "RESET DELAYED"
                             : "↻ \(MenuBarSummaryModel.shortCountdown(to: expected, from: context.date))")
                    }
                } else if let range = summary.payload.forecastRange {
                    Text("NEXT 24H · \(range)")
                } else {
                    Text("NEXT 24H")
                }
                Spacer()
                if let blessing = summary.payload.lastBlessingAt {
                    Text("🙏 \(age(blessing))")
                }
                if summary.payload.unreadTweet {
                    Image(systemName: "text.bubble.fill").foregroundStyle(Color(hex: 0x58B9F3))
                }
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(palette.tertiary)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 10).fill(palette.surface))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            actionButton("Open Widget", icon: "dial.medium", action: onOpenWidget)
            actionButton("Tweets", icon: "text.bubble", action: onOpenTweets)
            actionButton("Refresh", icon: "arrow.clockwise", action: onRefresh)
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.raisedSurface))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var freshnessColor: Color {
        switch summary.freshness {
        case .live: palette.reset
        case .stale: palette.billing
        case .offline: Color.red.opacity(0.82)
        }
    }

    private var updatedText: String {
        guard let date = summary.payload.lastSuccessfulAt else { return "WAITING FOR LIVE DATA" }
        return "UPDATED \(age(date)) AGO"
    }

    private func age(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "NOW" }
        if seconds < 3_600 { return "\(Int(seconds / 60))M" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))H" }
        return "\(Int(seconds / 86_400))D"
    }
}
