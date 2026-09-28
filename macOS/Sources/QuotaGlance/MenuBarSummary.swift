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
    var calendarDeadlineAt: Date? = nil
    var newTweet: TiboTweet? = nil
    var tweets: [TiboTweet] = []
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

    var onClearTweet: (() -> Void)?

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
