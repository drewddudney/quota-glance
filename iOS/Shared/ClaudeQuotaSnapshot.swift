import Foundation

/// Non-secret usage data shared with widgets. Sign-in credentials are excluded.
struct ClaudeQuotaSnapshot: Codable, Equatable, Sendable {
    var capturedAt: Date?
    var usagePercent: Double?
    var resetAt: Date?
    var planName: String?
    var accountID: String?
    var verified: Bool
    var needsConnection: Bool
    var fiveHourUsagePercent: Double? = nil
    var fiveHourResetAt: Date? = nil
    var fetchedOnPhone: Bool? = nil
    var usageHistory: [ClaudeUsagePoint]? = nil
    var weeklyArchives: [ClaudeUsageArchive]? = nil
    var estimatedRunoutAt: Date? = nil
    var paceWindowLabel: String? = nil

    func displayedFiveHourUsage(at now: Date) -> Double? {
        guard fiveHourResetAt.map({ $0 > now }) ?? true,
              let fiveHourUsagePercent, fiveHourUsagePercent.isFinite,
              (0...100).contains(fiveHourUsagePercent) else { return nil }
        return fiveHourUsagePercent
    }

    func hasEnded(at now: Date) -> Bool { resetAt.map { $0 <= now } ?? false }

    func displayedUsage(at now: Date) -> Double? {
        guard !hasEnded(at: now), let usagePercent,
              usagePercent.isFinite, (0...100).contains(usagePercent) else { return nil }
        return usagePercent
    }

    func weekElapsedPercent(at now: Date) -> Double? {
        guard let resetAt else { return nil }
        return min(100, max(0, (1 - resetAt.timeIntervalSince(now) / (7 * 86_400)) * 100))
    }

    func isFresh(at now: Date) -> Bool {
        guard verified, !needsConnection, let capturedAt else { return false }
        return (-60...900).contains(now.timeIntervalSince(capturedAt))
    }

    func status(at now: Date) -> String {
        if needsConnection { return "Connect Claude in Settings" }
        guard let capturedAt else { return "Connect Claude to see usage" }
        if hasEnded(at: now) { return "Waiting for the new weekly window" }
        let age = max(0, Int(now.timeIntervalSince(capturedAt) / 60))
        let label = age == 0 ? "just now" : age < 60 ? "\(age)m ago" : "\(age / 60)h ago"
        return (isFresh(at: now) ? "Synced " : "Saved ") + label
    }
}

struct ClaudeUsagePoint: Codable, Equatable, Sendable {
    let date: Date
    let usedPercent: Double
}

struct ClaudeUsageArchive: Codable, Equatable, Sendable {
    let windowStart: Date
    let resetAt: Date
    let finalUsedPercent: Double
    let points: [ClaudeUsagePoint]
}

/// Keeps only measured percentages. A provider refresh is the only source of a
/// new point; opening a chart, a clock tick or a forecast never adds a sample.
enum ClaudeUsageHistory {
    static let week: TimeInterval = 7 * 86_400
    static let maximumPoints = 12_000
    static let maximumArchives = 52

    static func record(
        _ incoming: ClaudeQuotaSnapshot,
        previous: ClaudeQuotaSnapshot?,
        now: Date = Date()
    ) -> ClaudeQuotaSnapshot {
        var result = incoming
        result.estimatedRunoutAt = nil
        result.paceWindowLabel = nil
        let sameAccount = incoming.accountID != nil && incoming.accountID == previous?.accountID
        if sameAccount, let old = previous, let oldDate = old.capturedAt,
           let date = incoming.capturedAt, date < oldDate || (date == oldDate && old.usageHistory != nil) {
            // Cached overlays and delayed requests cannot create points or
            // replace a newer reading, even if a cloud snapshot arrived later.
            result = old
            result.verified = incoming.verified
            result.needsConnection = incoming.needsConnection
            result.estimatedRunoutAt = estimate(for: result, now: now)
            result.paceWindowLabel = result.estimatedRunoutAt == nil ? nil : "recorded one-hour"
            return result
        }

        let windowMatches = sameAccount && sameWindow(previous?.resetAt, incoming.resetAt)
        var points = windowMatches ? previous?.usageHistory ?? [] : []
        if windowMatches, previous?.usageHistory == nil,
           let date = previous?.capturedAt, let used = valid(previous?.usagePercent),
           let end = incoming.resetAt, date >= end.addingTimeInterval(-week), date < end,
           date <= now.addingTimeInterval(60) {
            // Migration can keep the previous build's real cached measurement;
            // it must not invent observations before that timestamp.
            points = [.init(date: date, usedPercent: used)]
        }
        var archives = sameAccount ? previous?.weeklyArchives ?? [] : []
        if sameAccount, !windowMatches, let old = previous,
           let end = old.resetAt, let nextEnd = incoming.resetAt,
           let measuredAt = incoming.capturedAt, end <= measuredAt, nextEnd > end,
           let used = valid(old.usagePercent),
           !archives.contains(where: { sameWindow($0.resetAt, end) }) {
            let saved = clean(old.usageHistory ?? [], start: end.addingTimeInterval(-week), end: end)
            if !saved.isEmpty {
                archives.append(ClaudeUsageArchive(windowStart: end.addingTimeInterval(-week), resetAt: end,
                    finalUsedPercent: used, points: compact(saved, limit: 2_048)))
            }
        }

        if let end = incoming.resetAt, end.timeIntervalSince1970.isFinite,
           let measuredAt = incoming.capturedAt, measuredAt.timeIntervalSince1970.isFinite {
            let start = end.addingTimeInterval(-week)
            points = clean(points, start: start, end: min(end, measuredAt))
            if incoming.verified, !incoming.needsConnection, let used = valid(incoming.usagePercent),
               measuredAt >= start, measuredAt < end, measuredAt <= now.addingTimeInterval(60),
               points.last.map({ measuredAt.timeIntervalSince($0.date) >= 60 ||
                   (measuredAt > $0.date && used < $0.usedPercent) }) ?? true {
                points.append(.init(date: measuredAt, usedPercent: used))
            }
        } else { points = [] }
        result.usageHistory = Array(points.suffix(maximumPoints))
        result.weeklyArchives = Array(archives.filter {
            $0.windowStart.timeIntervalSince1970.isFinite && $0.resetAt > $0.windowStart &&
            valid($0.finalUsedPercent) != nil
        }.sorted { $0.resetAt > $1.resetAt }.prefix(maximumArchives))
        result.estimatedRunoutAt = estimate(for: result, now: now)
        result.paceWindowLabel = result.estimatedRunoutAt == nil ? nil : "recorded one-hour"
        return result
    }

    static func hourlyRate(
        points: [ClaudeUsagePoint], resetAt: Date, measuredAt: Date?,
        now: Date = Date(), lookback: TimeInterval? = 3_600
    ) -> Double? {
        guard let measuredAt, (-60...900).contains(now.timeIntervalSince(measuredAt)), resetAt > now else { return nil }
        let start = max(resetAt.addingTimeInterval(-week), lookback.map { now.addingTimeInterval(-$0) } ?? .distantPast)
        var recent = clean(points, start: start, end: min(now.addingTimeInterval(60), measuredAt))
        // A decrease may be a provider correction or an early reset. Neither
        // permits combining the previous burn with the new allowance.
        if let index = recent.indices.dropFirst().last(where: { recent[$0].usedPercent < recent[$0 - 1].usedPercent }) {
            recent = Array(recent[index...])
        }
        guard let first = recent.first, let last = recent.last,
              last.date.timeIntervalSince(first.date) >= 60,
              (-60...900).contains(now.timeIntervalSince(last.date)) else { return nil }
        let rate = (last.usedPercent - first.usedPercent) / last.date.timeIntervalSince(first.date) * 3_600
        return rate.isFinite && rate >= 0 ? rate : nil
    }

    static func estimate(for snapshot: ClaudeQuotaSnapshot, now: Date = Date()) -> Date? {
        guard snapshot.verified, !snapshot.needsConnection,
              let end = snapshot.resetAt, let measuredAt = snapshot.capturedAt,
              let used = valid(snapshot.usagePercent), used < 100,
              let last = snapshot.usageHistory?.last, last.usedPercent <= used,
              let rate = hourlyRate(points: snapshot.usageHistory ?? [], resetAt: end,
                                    measuredAt: measuredAt, now: now), rate > 0 else { return nil }
        let seconds = (100 - last.usedPercent) / rate * 3_600
        guard seconds.isFinite, seconds > 0 else { return nil }
        let date = last.date.addingTimeInterval(seconds)
        return date > now ? date : nil
    }

    static func sameWindow(_ left: Date?, _ right: Date?) -> Bool {
        guard let left, let right else { return false }
        return abs(left.timeIntervalSince(right)) < 60
    }

    private static func valid(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }

    private static func clean(_ points: [ClaudeUsagePoint], start: Date, end: Date) -> [ClaudeUsagePoint] {
        var lastDate: Date?
        return points.filter { valid($0.usedPercent) != nil && $0.date >= start && $0.date <= end }
            .sorted { $0.date < $1.date }.filter {
                guard lastDate != $0.date else { return false }
                lastDate = $0.date
                return true
            }
    }

    /// Bounds archive storage while retaining actual observations, including
    /// the first and last; it never interpolates or fills a missing interval.
    private static func compact(_ points: [ClaudeUsagePoint], limit: Int) -> [ClaudeUsagePoint] {
        guard points.count > limit else { return points }
        return (0..<limit).map { points[$0 * (points.count - 1) / (limit - 1)] }
    }
}
