import ActivityKit
import Foundation

struct ResetCountdownAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let expectedAt: Date
        let sourceLabel: String
        let isDelayed: Bool
    }

    let announcementID: String
}

struct CodexSessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let taskName: String
        let usedPercent: Double
        let totalTokens: Int64
        let tokensPerMinute: Int64
        /// Estimated quota points consumed per minute at the measured token
        /// pace. Optional so an activity created by an older build still
        /// decodes after an update.
        let percentPerMinute: Double?
        let updatedAt: Date
    }

    let sessionID: String
}

enum CodexSessionUsageProjection {
    static let maximumProjectionDuration: TimeInterval = 10 * 60
    private static let maximumUnconfirmedFraction = 0.999

    static func tokensPerMinute(snapshot: QuotaSnapshot, now: Date = Date()) -> Int64 {
        if let fiveMinutes = snapshot.tokenPace?.fiveMinutes, fiveMinutes > 0 {
            return Int64((Double(fiveMinutes) / 5).rounded())
        }
        guard let burn = snapshot.tokenBurnSample(over: 5 * 60, now: now) else { return 0 }
        return Int64((Double(burn.tokens) / max(1, burn.duration) * 60).rounded())
    }

    /// Learns this quota window's observed token cost per percentage point,
    /// then converts the latest token pace into a percentage velocity.
    static func percentPerMinute(
        snapshot: QuotaSnapshot,
        tokensPerMinute: Int64
    ) -> Double {
        guard tokensPerMinute > 0,
              let currentPercent = snapshot.usagePercent,
              currentPercent > 0 else { return 0 }

        let points = (snapshot.usageHistory ?? [])
            .compactMap { point -> (percent: Double, tokens: Int64)? in
                guard let tokens = point.tokens, tokens >= 0 else { return nil }
                return (point.usedPercent, tokens)
            }

        var anchors: [(percent: Double, tokens: Int64)] = []
        var highWater = -Double.infinity
        for point in points where point.percent > highWater + 0.001 {
            anchors.append(point)
            highWater = point.percent
        }

        var tokensPerPoint: [Double] = []
        for pair in zip(anchors, anchors.dropFirst()) {
            let percentDelta = pair.1.percent - pair.0.percent
            let tokenDelta = pair.1.tokens - pair.0.tokens
            guard percentDelta > 0, percentDelta <= 20, tokenDelta > 0 else { continue }
            let ratio = Double(tokenDelta) / percentDelta
            if ratio.isFinite, ratio > 0 { tokensPerPoint.append(ratio) }
        }

        let calibratedTokensPerPoint: Double? = {
            guard !tokensPerPoint.isEmpty else { return nil }
            let recent = Array(tokensPerPoint.suffix(8)).sorted()
            let middle = recent.count / 2
            return recent.count.isMultiple(of: 2)
                ? (recent[middle - 1] + recent[middle]) / 2
                : recent[middle]
        }()

        let baselineTokens = points.first?.tokens ?? 0
        let observedTokens = max(0, (snapshot.bestTokenTotal ?? 0) - baselineTokens)
        let wholeWindowTokensPerPoint = observedTokens > 0
            ? Double(observedTokens) / currentPercent
            : nil
        guard let denominator = calibratedTokensPerPoint ?? wholeWindowTokensPerPoint,
              denominator > 0 else { return 0 }

        // The cap is a safety rail for malformed or rescaled history. A real
        // authoritative refresh replaces this projection on every sync.
        return min(5, max(0, Double(tokensPerMinute) / denominator))
    }

    /// Reconstructs the progress hidden behind Codex's whole-number quota
    /// reading. The first checkpoint on the current percentage plateau is the
    /// best available threshold-crossing time; applying the measured pace from
    /// that point prevents every Live Activity refresh from restarting at .000.
    static func estimatedPercentAtRefresh(
        snapshot: QuotaSnapshot,
        percentPerMinute: Double
    ) -> Double {
        guard let authoritativePercent = snapshot.usagePercent else { return 0 }
        guard percentPerMinute > 0, percentPerMinute.isFinite else {
            return authoritativePercent
        }

        let points = (snapshot.usageHistory ?? [])
            .filter { $0.date <= snapshot.capturedAt }
            .sorted { $0.date < $1.date }
        guard let latest = points.last,
              abs(latest.usedPercent - authoritativePercent) < 0.001 else {
            // The percentage changed after the last saved checkpoint, so the
            // current capture itself is the only defensible threshold anchor.
            return authoritativePercent
        }

        var thresholdAt = latest.date
        for point in points.dropLast().reversed() {
            guard abs(point.usedPercent - authoritativePercent) < 0.001 else { break }
            thresholdAt = point.date
        }

        let minutesSinceThreshold = max(
            0,
            snapshot.capturedAt.timeIntervalSince(thresholdAt) / 60
        )
        let inferred = authoritativePercent + percentPerMinute * minutesSinceThreshold
        return min(authoritativePercent + maximumUnconfirmedFraction, max(authoritativePercent, inferred))
    }

    static func projectedPercent(
        basePercent: Double,
        percentPerMinute: Double,
        updatedAt: Date,
        now: Date
    ) -> Double {
        let elapsed = min(
            maximumProjectionDuration,
            max(0, now.timeIntervalSince(updatedAt))
        )
        let inferred = basePercent + percentPerMinute * elapsed / 60
        let nextUnconfirmedPercent = floor(basePercent) + maximumUnconfirmedFraction
        return min(100, nextUnconfirmedPercent, max(0, inferred))
    }
}

enum ResetSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case lunarWerx
    case codexResets
    case willCodexQuotaReset
    case gussuri
    case polymarket
    case average

    var id: String { rawValue }

    var name: String {
        switch self {
        case .lunarWerx: "LunarWerx"
        case .codexResets: "Codex Resets"
        case .willCodexQuotaReset: "Will Codex Reset?"
        case .gussuri: "Reset Observatory"
        case .polymarket: "Polymarket"
        case .average: "Average of all"
        }
    }

    static let calculatorCases: [ResetSource] = [
        .lunarWerx, .codexResets, .willCodexQuotaReset, .gussuri, .polymarket
    ]

    static func selectionLabel(_ selection: Set<ResetSource>) -> String {
        let ordered = calculatorCases.filter(selection.contains)
        if ordered.count == 1 { return ordered[0].name }
        return "Average of \(ordered.count)"
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

enum QuotaChartHistory {
    /// The Mac already publishes the authoritative percentage captured at
    /// every checkpoint. Token totals are a separate cumulative series and
    /// must never be used to rewrite those saved percentages: local ledger
    /// totals can plateau or be rescaled independently of the quota meter.
    static func currentPoints(
        from snapshot: QuotaSnapshot,
        now: Date = Date()
    ) -> [QuotaUsagePoint] {
        var points = (snapshot.usageHistory ?? []).sorted { $0.date < $1.date }
        if let current = snapshot.usagePercent,
           points.last.map({ now.timeIntervalSince($0.date) > 30 }) ?? true {
            points.append(
                QuotaUsagePoint(
                    date: now,
                    usedPercent: current,
                    tokens: snapshot.bestTokenTotal
                )
            )
        }
        return points
    }
}

struct QuotaTokenBurnSample: Equatable, Sendable {
    let tokens: Int64
    let duration: TimeInterval
}

struct QuotaTokenPace: Codable, Equatable, Sendable {
    let fiveMinutes: Int64
    let oneHour: Int64
    let twelveHours: Int64
    let twentyFourHours: Int64
    let sinceReset: Int64
}

struct QuotaUsageIntelligence: Codable, Equatable, Sendable {
    let apiEquivalentUSD: Double
    let quotaWeightedUSD: Double
    let gpt6CodexCredits: Double?
    let pricingCoverage: Double
    let speedCoverage: Double
    let fastShare: Double
    let eventCount: Int
    let ledgerBytes: Int64
    let topModel: String?
    let totalTokens: Int64?
    let cacheHitRate: Double?
    let costTimeline: [QuotaCostPoint]?
}

struct QuotaCostPoint: Codable, Identifiable, Equatable, Sendable {
    let date: Date
    let apiEquivalentUSD: Double
    var id: Date { date }
}

struct QuotaWeeklyArchivePoint: Codable, Identifiable, Equatable, Sendable {
    let date: Date
    let usedPercent: Double
    let apiEquivalentUSD: Double?
    var id: Date { date }
}

struct QuotaWeeklyArchive: Codable, Identifiable, Equatable, Sendable {
    let windowStart: Date
    let resetAt: Date
    let finalUsedPercent: Double
    let totalTokens: Int64?
    let apiEquivalentUSD: Double?
    let cacheHitRate: Double?
    let fastShare: Double?
    let topModel: String?
    let points: [QuotaWeeklyArchivePoint]
    var id: Date { windowStart }
}

struct QuotaSecondaryWindow: Codable, Equatable, Sendable {
    let usedPercent: Double
    let resetAt: Date
    let windowDurationMinutes: Double
}

struct QuotaAllowanceWindow: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let scope: String
    let usedPercent: Double
    let resetAt: Date
    let windowDurationMinutes: Double
}

struct QuotaCreditSummary: Codable, Equatable, Sendable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

struct QuotaResetCredit: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let resetType: String
    let status: String
    let expiresAt: Date?
    let description: String?
}

struct QuotaCodexTask: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let state: String
    let source: String
    let updatedAt: Date
}

struct QuotaTiboPost: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let date: Date?
    let text: String
    let inReplyTo: String?
    let url: URL?
    let isResetOriented: Bool

    /// Stable when different reset providers use different GUIDs for the same
    /// X post. Text is the fallback because some mirrors omit the source URL.
    var canonicalIdentity: String {
        if let status = Self.xStatusID(in: url?.absoluteString ?? "")
            ?? Self.xStatusID(in: id) {
            return "x:\(status)"
        }
        let normalized = text.lowercased()
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "text:\(Self.fnv1a64(normalized))"
    }

    private static func xStatusID(in value: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?:/status/|^x:|^)([0-9]{12,})(?:\D|$)"#
        ), let match = expression.firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ), let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }

    private static func fnv1a64(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
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
    var claude: ClaudeQuotaSnapshot? = nil
    var directCodexAccountID: String? = nil
    var codexNeedsConnection: Bool? = nil
    var recentProviderActivity: [String: Date]? = nil
    var usageUpdatedAt: Date? = nil
    var usageMeasurementDate: Date { usageUpdatedAt ?? capturedAt }
    var capturedAt: Date
    var weekElapsedPercent: Double?
    var calendarDeadlineAt: Date? = nil
    var usagePercent: Double?
    var resetChancePercent: Double?
    var resetAt: Date?
    var usageWindowStart: Date?
    var windowDurationMinutes: Double? = nil
    var weeklyTokens: Int64?
    var planName: String?
    var renewalDate: Date?
    var selectedSource: ResetSource
    var selectedSources: [ResetSource]? = nil
    var providers: [ProviderReading]
    var resetAnnounced: Bool
    var announcementID: String?
    var announcementText: String?
    var announcementDate: Date?
    var announcementExpectedAt: Date? = nil
    var announcementRequiresApplicabilityConfirmation: Bool? = nil
    var announcementAppliesToAccount: Bool? = nil
    var announcementApplicabilityAnsweredAt: Date? = nil
    var resetCompletedAt: Date? = nil
    var announcementURL: URL?
    var lastBlessingAt: Date?
    var resetCreditExpiresAt: Date?
    var estimatedRunoutAt: Date? = nil
    var paceWindowLabel: String? = nil
    var forecastUpdatedAt: Date? = nil
    var usageHistory: [QuotaUsagePoint]? = nil
    var tokenPace: QuotaTokenPace? = nil
    var usageIntelligence: QuotaUsageIntelligence? = nil
    var secondaryQuota: QuotaSecondaryWindow? = nil
    var quotaInventory: [QuotaAllowanceWindow]? = nil
    var creditSummary: QuotaCreditSummary? = nil
    var resetCredits: [QuotaResetCredit]? = nil
    var activeTasks: [QuotaCodexTask]? = nil
    var weeklyArchives: [QuotaWeeklyArchive]? = nil
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
        resetCompletedAt: nil,
        announcementURL: nil,
        lastBlessingAt: nil,
        resetCreditExpiresAt: nil,
        estimatedRunoutAt: nil,
        paceWindowLabel: nil,
        forecastUpdatedAt: nil,
        usageHistory: nil,
        tokenPace: nil,
        usageIntelligence: nil,
        secondaryQuota: nil,
        quotaInventory: nil,
        creditSummary: nil,
        resetCredits: nil,
        activeTasks: nil,
        weeklyArchives: nil,
        tiboPosts: nil
    )

    var resetSourceSelection: Set<ResetSource> {
        let decoded = Set(selectedSources ?? []).intersection(ResetSource.calculatorCases)
        if !decoded.isEmpty { return decoded }
        return selectedSource == .average ? Set(ResetSource.calculatorCases) : [selectedSource]
    }

    var resetSourceLabel: String {
        ResetSource.selectionLabel(resetSourceSelection)
    }

    var effectiveResetChance: Double {
        effectiveResetChance(at: Date())
    }

    func effectiveResetChance(
        at date: Date,
        calendar: Calendar = .current
    ) -> Double {
        return hasActiveResetAnnouncement(at: date)
            ? 100
            : max(0, min(100, resetChancePercent ?? 0))
    }

    /// A provider can continue returning the announcement that preceded a
    /// completed reset. Treat the completion boundary as authoritative so an
    /// old cloud payload cannot force the dial back to 100% the next day.
    func hasActiveResetAnnouncement(at date: Date = Date()) -> Bool {
        guard resetAnnounced else { return false }
        if announcementRequiresApplicabilityConfirmation == true,
           announcementAppliesToAccount == false {
            return false
        }
        if let resetCompletedAt {
            if let announcementDate, announcementDate <= resetCompletedAt { return false }
            if let announcementExpectedAt, announcementExpectedAt <= resetCompletedAt { return false }
        }
        if let announcementExpectedAt,
           date.timeIntervalSince(announcementExpectedAt) >= 24 * 60 * 60 {
            return false
        }
        if announcementExpectedAt == nil,
           let announcementDate,
           date.timeIntervalSince(announcementDate) >= 36 * 60 * 60 {
            return false
        }
        return true
    }

    var effectiveResetAnnounced: Bool {
        hasActiveResetAnnouncement()
    }

    var resetRecentlyCompleted: Bool {
        isResetCompletionSuppressed()
    }

    func isResetCompletionSuppressed(
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let resetCompletedAt, date >= resetCompletedAt else { return false }
        return calendar.isDate(date, inSameDayAs: resetCompletedAt)
    }

    var activeAnnouncementExpectedAt: Date? {
        guard hasActiveResetAnnouncement(), !resetRecentlyCompleted,
              let announcementExpectedAt else { return nil }
        guard Date().timeIntervalSince(announcementExpectedAt) < 24 * 60 * 60 else { return nil }
        return announcementExpectedAt
    }

    var needsResetApplicabilityAnswer: Bool {
        guard resetAnnounced,
              announcementRequiresApplicabilityConfirmation == true,
              announcementAppliesToAccount == nil,
              announcementID != nil else { return false }
        return hasActiveResetAnnouncement()
    }

    mutating func applyResetApplicabilityResponse(_ response: ResetApplicabilityResponse?) {
        guard let response, response.announcementID == announcementID else { return }
        guard announcementApplicabilityAnsweredAt.map({ response.answeredAt >= $0 }) ?? true else { return }
        announcementAppliesToAccount = response.applies
        announcementApplicabilityAnsweredAt = response.answeredAt
    }

    var bestTokenTotal: Int64? {
        let values = [
            weeklyTokens,
            usageIntelligence?.totalTokens,
            usageHistory?.compactMap(\.tokens).max()
        ].compactMap { $0 }
        return values.max()
    }

    /// Derives burn from the cumulative points when the Mac's precomputed
    /// interval happens to be zero or unavailable. If the current quota
    /// window is younger than the requested interval, the available duration
    /// is used rather than pretending a full interval elapsed.
    func tokenBurnSample(over interval: TimeInterval?, now: Date = Date()) -> QuotaTokenBurnSample? {
        let points = (usageHistory ?? [])
            .compactMap { point -> (Date, Int64)? in
                guard point.date <= now, let tokens = point.tokens else { return nil }
                return (point.date, tokens)
            }
            .sorted { $0.0 < $1.0 }
        guard let latest = points.last, points.count >= 2 else { return nil }

        let requestedStart = interval.map { now.addingTimeInterval(-$0) }
            ?? usageWindowStart
            ?? points[0].0
        let start = max(requestedStart, usageWindowStart ?? requestedStart)
        let startTokens = Self.interpolatedTokens(at: start, in: points)
        let duration = latest.0.timeIntervalSince(start)
        guard duration > 0 else { return nil }
        return QuotaTokenBurnSample(tokens: max(0, latest.1 - startTokens), duration: duration)
    }

    func hasActiveCodexSession(at now: Date = Date()) -> Bool {
        guard now.timeIntervalSince(usageMeasurementDate) <= 10 * 60 else { return false }
        // Recent token history lingers after a turn finishes. ActivityKit should only
        // remain visible while the Mac reports an actual running Codex task.
        return !(activeTasks ?? []).isEmpty
    }

    private static func interpolatedTokens(at date: Date, in points: [(Date, Int64)]) -> Int64 {
        if date <= points[0].0 { return points[0].1 }
        if date >= points[points.count - 1].0 { return points[points.count - 1].1 }
        guard let upperIndex = points.firstIndex(where: { $0.0 >= date }), upperIndex > 0 else {
            return points[0].1
        }
        let lower = points[upperIndex - 1], upper = points[upperIndex]
        let span = upper.0.timeIntervalSince(lower.0)
        guard span > 0 else { return upper.1 }
        let fraction = date.timeIntervalSince(lower.0) / span
        return lower.1 + Int64((Double(upper.1 - lower.1) * fraction).rounded())
    }

    mutating func mergeAnnouncement(
        announced: Bool,
        id: String?,
        text: String?,
        detectedAt: Date?,
        expectedAt candidateExpectedAt: Date?,
        requiresApplicabilityConfirmation: Bool,
        url: URL?
    ) {
        if let resetCompletedAt,
           let candidateExpectedAt,
           candidateExpectedAt <= resetCompletedAt {
            clearResetAnnouncement()
            return
        }
        if let candidateExpectedAt,
           Date().timeIntervalSince(candidateExpectedAt) >= 24 * 60 * 60 {
            clearResetAnnouncement()
            return
        }
        if let resetCompletedAt, let detectedAt, detectedAt <= resetCompletedAt {
            clearResetAnnouncement()
            return
        }

        if let id, id != announcementID {
            announcementAppliesToAccount = nil
            announcementApplicabilityAnsweredAt = nil
        }
        resetAnnounced = announced
        announcementText = text
        announcementRequiresApplicabilityConfirmation = announced
            ? requiresApplicabilityConfirmation : announcementRequiresApplicabilityConfirmation
        announcementURL = url
        let isNewer = detectedAt.map { candidate in
            announcementDate.map { candidate > $0.addingTimeInterval(10 * 60) } ?? true
        } ?? false
        let correctsSameAnnouncementEarlier = announcementExpectedAt.map {
            guard let candidateExpectedAt else { return false }
            return candidateExpectedAt < $0
                && detectedAt.map { $0 <= (announcementDate ?? $0).addingTimeInterval(10 * 60) } == true
        } ?? false
        if announcementExpectedAt == nil || isNewer || correctsSameAnnouncementEarlier {
            announcementID = id
            announcementDate = detectedAt
            announcementExpectedAt = candidateExpectedAt
        }
    }

    private mutating func clearResetAnnouncement() {
        resetAnnounced = false
        announcementID = nil
        announcementText = nil
        announcementDate = nil
        announcementExpectedAt = nil
        announcementRequiresApplicabilityConfirmation = nil
        announcementAppliesToAccount = nil
        announcementApplicabilityAnsweredAt = nil
        announcementURL = nil
    }
}

enum SharedSnapshotStore {
    static let appGroup = "group.com.example.quotaglance"
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
    static let usage: UInt32 = 0x2F80ED
    static let reset: UInt32 = 0x68D9A0
}
