import ActivityKit
import Foundation

struct ResetCountdownAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let expectedAt: Date
        let sourceLabel: String
    }

    let announcementID: String
}

enum ResetSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case lunarWerx
    case codexResets
    case willCodexQuotaReset
    case gussuri
    case average

    var id: String { rawValue }

    var name: String {
        switch self {
        case .lunarWerx: "LunarWerx"
        case .codexResets: "Codex Resets"
        case .willCodexQuotaReset: "Will Codex Reset?"
        case .gussuri: "Reset Observatory"
        case .average: "Average of all"
        }
    }
}

struct ProviderReading: Codable, Identifiable, Equatable, Sendable {
    var id: ResetSource { source }
    let source: ResetSource
    let percent: Double?
    let updatedAt: Date?
}

struct QuotaUsagePoint: Codable, Identifiable, Equatable, Sendable {
    let date: Date
    let usedPercent: Double
    let tokens: Int64?

    var id: Date { date }
}

struct QuotaTokenPace: Codable, Equatable, Sendable {
    let fiveMinutes: Int64
    let oneHour: Int64
    let twelveHours: Int64
    let twentyFourHours: Int64
    let sinceReset: Int64
}

struct QuotaTiboPost: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let date: Date?
    let text: String
    let inReplyTo: String?
    let url: URL?
    let isResetOriented: Bool
}

enum ResetAnnouncementTimeParser {
    static func expectedDate(in text: String, postedAt: Date) -> Date? {
        let normalized = text
            .replacingOccurrences(of: "a.m.", with: "am", options: .caseInsensitive)
            .replacingOccurrences(of: "p.m.", with: "pm", options: .caseInsensitive)

        if let relative = relativeExpectedDate(in: normalized, postedAt: postedAt) { return relative }
        guard let expression = try? NSRegularExpression(
            pattern: #"\b([0-2]?\d)(?::([0-5]\d))?\s*(am|pm)?\s*(PST|PDT|PT|MST|MDT|MT|CST|CDT|CT|EST|EDT|ET|UTC|GMT)?\b"#,
            options: [.caseInsensitive]
        ) else { return nil }

        for match in expression.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
            guard let hourRange = Range(match.range(at: 1), in: normalized),
                  let rawHour = Int(normalized[hourRange]) else { continue }
            let meridiem = Range(match.range(at: 3), in: normalized).map { String(normalized[$0]).lowercased() }
            let zoneToken = Range(match.range(at: 4), in: normalized).map { String(normalized[$0]).uppercased() }
            guard meridiem != nil || zoneToken != nil else { continue }
            let minute = Range(match.range(at: 2), in: normalized).flatMap { Int(normalized[$0]) } ?? 0
            guard let hour = normalizedHour(rawHour, meridiem: meridiem) else { continue }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone(for: zoneToken)
            let postedComponents = calendar.dateComponents([.year, .month, .day], from: postedAt)
            guard let postedDay = calendar.date(from: postedComponents) else { continue }
            let lower = normalized.lowercased()
            let dayOffset = lower.contains("tomorrow") ? 1 : 0
            guard let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: postedDay) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: targetDay)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard var candidate = calendar.date(from: components) else { continue }
            if dayOffset == 0, !lower.contains("today"), !lower.contains("tonight"), candidate < postedAt {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            return candidate
        }
        return nil
    }

    private static func relativeExpectedDate(in text: String, postedAt: Date) -> Date? {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?:in|within|over(?:\s+the)?|next)\s+(?:(\d+)\s*)?(minutes?|mins?|hours?|hrs?)"#,
            options: [.caseInsensitive]
        ), let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let unitRange = Range(match.range(at: 2), in: text) else { return nil }
        let amount = Range(match.range(at: 1), in: text).flatMap { Double(text[$0]) } ?? 1
        return postedAt.addingTimeInterval(amount * (text[unitRange].lowercased().hasPrefix("h") ? 3_600 : 60))
    }

    private static func normalizedHour(_ hour: Int, meridiem: String?) -> Int? {
        guard (0...23).contains(hour) else { return nil }
        guard hour <= 12 else { return hour }
        if meridiem == "am" { return hour == 12 ? 0 : hour }
        if meridiem == "pm" { return hour == 12 ? 12 : hour + 12 }
        return hour
    }

    private static func timeZone(for token: String?) -> TimeZone {
        let identifier: String
        switch token {
        case "MST", "MDT", "MT": identifier = "America/Denver"
        case "CST", "CDT", "CT": identifier = "America/Chicago"
        case "EST", "EDT", "ET": identifier = "America/New_York"
        case "UTC", "GMT": identifier = "UTC"
        default: identifier = "America/Los_Angeles"
        }
        return TimeZone(identifier: identifier) ?? TimeZone(secondsFromGMT: 0)!
    }
}

struct QuotaSnapshot: Codable, Equatable, Sendable {
    var capturedAt: Date
    var weekElapsedPercent: Double?
    var usagePercent: Double?
    var resetChancePercent: Double?
    var resetAt: Date?
    var usageWindowStart: Date?
    var windowDurationMinutes: Double? = nil
    var weeklyTokens: Int64?
    var planName: String?
    var renewalDate: Date?
    var selectedSource: ResetSource
    var providers: [ProviderReading]
    var resetAnnounced: Bool
    var announcementID: String?
    var announcementText: String?
    var announcementDate: Date?
    var announcementExpectedAt: Date? = nil
    var announcementURL: URL?
    var lastBlessingAt: Date?
    var resetCreditExpiresAt: Date?
    var estimatedRunoutAt: Date? = nil
    var paceWindowLabel: String? = nil
    var forecastUpdatedAt: Date? = nil
    var usageHistory: [QuotaUsagePoint]? = nil
    var tokenPace: QuotaTokenPace? = nil
    var tiboPosts: [QuotaTiboPost]? = nil

    static let empty = QuotaSnapshot(
        capturedAt: .distantPast,
        weekElapsedPercent: nil,
        usagePercent: nil,
        resetChancePercent: nil,
        resetAt: nil,
        usageWindowStart: nil,
        windowDurationMinutes: nil,
        weeklyTokens: nil,
        planName: nil,
        renewalDate: nil,
        selectedSource: .average,
        providers: [],
        resetAnnounced: false,
        announcementID: nil,
        announcementText: nil,
        announcementDate: nil,
        announcementExpectedAt: nil,
        announcementURL: nil,
        lastBlessingAt: nil,
        resetCreditExpiresAt: nil,
        estimatedRunoutAt: nil,
        paceWindowLabel: nil,
        forecastUpdatedAt: nil,
        usageHistory: nil,
        tokenPace: nil,
        tiboPosts: nil
    )

    var effectiveResetChance: Double {
        resetAnnounced ? 100 : max(0, min(100, resetChancePercent ?? 0))
    }
}

enum SharedSnapshotStore {
    static var appGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "QuotaGlanceAppGroupIdentifier") as? String
            ?? "group.com.example.quotaglance"
    }
    private static let snapshotKey = "QuotaGlance.mobile.snapshot.v1"

    static func load() -> QuotaSnapshot {
        guard
            let data = UserDefaults(suiteName: appGroup)?.data(forKey: snapshotKey),
            let snapshot = try? decoder.decode(QuotaSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    static func save(_ snapshot: QuotaSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: snapshotKey)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}

enum QuotaColors {
    static let calendar: UInt32 = 0xF2AD3E
    static let usage: UInt32 = 0x7EE6AE
    static let reset: UInt32 = 0x58B9F3
}
