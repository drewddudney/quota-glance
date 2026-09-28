import Foundation

enum PhoneSyncSettings {
    static let macDetailsKey = "QuotaGlance.mobile.optionalMacDetails"
    static var includesMacDetails: Bool { UserDefaults.standard.bool(forKey: macDetailsKey) }
    static var automaticUsageEnabled: Bool {
        let key = "QuotaGlance.mobile.automaticUsageActivity"
        return UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key)
    }
}

/// Phone connections own their provider's readings, even if an unrelated Mac
/// snapshot arrives later. A forecast refresh never changes the usage timestamp.
enum PhoneUsageMerge {
    static func merge(
        base: QuotaSnapshot,
        previous: QuotaSnapshot,
        readings: [DirectProviderUsage],
        connections: Set<DirectUsageProvider>,
        needsConnection: Set<DirectUsageProvider> = [],
        includeMacDetails: Bool = false,
        now: Date = Date()
    ) -> QuotaSnapshot {
        var result = base
        if !includeMacDetails { removeMacDetails(from: &result) }
        if connections.contains(.codex), let reading = readings.first(where: { $0.provider == .codex }) {
            applyCodex(reading, previous: previous, to: &result, now: now)
            result.codexNeedsConnection = needsConnection.contains(.codex)
        } else if connections.contains(.codex) || previous.directCodexAccountID != nil {
            // An explicit disconnect removes that account's saved usage too.
            result.directCodexAccountID = nil
            result.codexNeedsConnection = needsConnection.contains(.codex)
            result.usagePercent = nil
            result.usageUpdatedAt = nil
            result.resetAt = nil
            result.calendarDeadlineAt = nil
            result.usageWindowStart = nil
            result.windowDurationMinutes = nil
            result.weekElapsedPercent = nil
            result.secondaryQuota = nil
            result.planName = nil
            result.usageHistory = nil
            result.weeklyArchives = nil
            result.estimatedRunoutAt = nil
            result.paceWindowLabel = nil
        }
        if connections.contains(.claude), let reading = readings.first(where: { $0.provider == .claude }) {
            let current = ClaudeQuotaSnapshot(
                capturedAt: reading.measuredAt,
                usagePercent: reading.weekly?.usedPercent,
                resetAt: reading.weekly?.resetAt,
                planName: reading.planName,
                accountID: reading.accountID,
                verified: true,
                needsConnection: needsConnection.contains(.claude),
                fiveHourUsagePercent: reading.fiveHour?.usedPercent,
                fiveHourResetAt: reading.fiveHour?.resetAt,
                fetchedOnPhone: true
            )
            result.claude = ClaudeUsageHistory.record(current, previous: previous.claude, now: now)
            result.capturedAt = max(result.capturedAt, reading.measuredAt)
        } else if connections.contains(.claude) || previous.claude?.fetchedOnPhone == true {
            result.claude = nil
        }
        if !includeMacDetails { removeMacDetails(from: &result) }
        return result
    }

    private static func applyCodex(
        _ incoming: DirectProviderUsage, previous: QuotaSnapshot,
        to result: inout QuotaSnapshot, now: Date
    ) {
        // A delayed completion cannot roll the connected account backwards.
        let sameAccount = previous.directCodexAccountID == incoming.accountID
        if sameAccount, incoming.measuredAt < previous.usageMeasurementDate {
            copyCodex(from: previous, to: &result)
            return
        }
        let accountChanged = previous.directCodexAccountID != nil && !sameAccount
        let end = incoming.weekly?.resetAt
        let duration = incoming.weekly?.durationMinutes ?? 10_080
        let start = end.map { $0.addingTimeInterval(-duration * 60) }
        let sameWindow = end != nil && previous.resetAt.map { abs($0.timeIntervalSince(end!)) < 60 } == true
        // Preserve the existing percentage graph on first connection only when
        // both endpoints agree on the quota window; token totals stay separate.
        let continuing = !accountChanged && sameWindow
        var points = continuing ? (previous.usageHistory ?? []) : []
        var archives = accountChanged ? [] : previous.weeklyArchives ?? []
        if sameAccount, !sameWindow,
           let oldStart = previous.usageWindowStart, let oldEnd = previous.resetAt,
           oldEnd <= now, let percent = previous.usagePercent,
           !archives.contains(where: { abs($0.windowStart.timeIntervalSince(oldStart)) < 60 }) {
            archives.append(QuotaWeeklyArchive(
                windowStart: oldStart, resetAt: oldEnd, finalUsedPercent: percent,
                totalTokens: previous.weeklyTokens, apiEquivalentUSD: previous.usageIntelligence?.apiEquivalentUSD,
                cacheHitRate: previous.usageIntelligence?.cacheHitRate,
                fastShare: previous.usageIntelligence?.fastShare, topModel: previous.usageIntelligence?.topModel,
                points: (previous.usageHistory ?? []).map {
                    QuotaWeeklyArchivePoint(date: $0.date, usedPercent: $0.usedPercent, apiEquivalentUSD: nil)
                }
            ))
        }
        result.directCodexAccountID = incoming.accountID
        result.usageUpdatedAt = incoming.measuredAt
        result.capturedAt = max(result.capturedAt, incoming.measuredAt)
        result.usagePercent = incoming.weekly?.usedPercent
        result.resetAt = end
        result.calendarDeadlineAt = end
        result.usageWindowStart = start
        result.windowDurationMinutes = incoming.weekly == nil ? nil : duration
        result.planName = incoming.planName
        result.weekElapsedPercent = end.map { min(100, max(0, (1 - $0.timeIntervalSince(now) / (duration * 60)) * 100)) }
        if let session = incoming.fiveHour, let used = session.usedPercent, let end = session.resetAt {
            result.secondaryQuota = QuotaSecondaryWindow(usedPercent: used, resetAt: end, windowDurationMinutes: session.durationMinutes ?? 300)
        } else { result.secondaryQuota = nil }
        if accountChanged {
            removeMacDetails(from: &result)
            result.resetCompletedAt = nil
        }
        if let used = incoming.weekly?.usedPercent, used.isFinite, (0...100).contains(used),
           let start, let end, incoming.measuredAt >= start, incoming.measuredAt <= end {
            points = points.filter { $0.date >= start && $0.date <= incoming.measuredAt }
            if points.last?.date != incoming.measuredAt {
                points.append(QuotaUsagePoint(date: incoming.measuredAt, usedPercent: used, tokens: nil))
            }
        }
        result.usageHistory = Array(points.suffix(12_000))
        result.weeklyArchives = Array(archives.sorted { $0.resetAt > $1.resetAt }.prefix(52))
        result.estimatedRunoutAt = nil
        result.paceWindowLabel = nil
        var recent = points.filter { $0.date >= incoming.measuredAt.addingTimeInterval(-3_600) }
        if let resetIndex = Array(zip(recent, recent.dropFirst()).enumerated()).last(where: { $0.element.1.usedPercent < $0.element.0.usedPercent })?.offset {
            recent = Array(recent.dropFirst(resetIndex + 1))
        }
        if let first = recent.first, let last = recent.last,
           last.date.timeIntervalSince(first.date) >= 60, last.usedPercent > first.usedPercent, last.usedPercent < 100 {
            let pointsPerSecond = (last.usedPercent - first.usedPercent) / last.date.timeIntervalSince(first.date)
            result.estimatedRunoutAt = last.date.addingTimeInterval((100 - last.usedPercent) / pointsPerSecond)
            result.paceWindowLabel = "recorded one-hour"
        }
    }

    private static func removeMacDetails(from value: inout QuotaSnapshot) {
        value.weeklyTokens = nil
        value.tokenPace = nil
        value.usageIntelligence = nil
        value.activeTasks = nil
        value.quotaInventory = nil
        value.creditSummary = nil
        value.resetCredits = nil
        value.renewalDate = nil
        value.resetCreditExpiresAt = nil
        value.usageHistory = value.usageHistory?.map { QuotaUsagePoint(date: $0.date, usedPercent: $0.usedPercent, tokens: nil) }
    }

    private static func copyCodex(from previous: QuotaSnapshot, to result: inout QuotaSnapshot) {
        result.directCodexAccountID = previous.directCodexAccountID
        result.usageUpdatedAt = previous.usageUpdatedAt
        result.usagePercent = previous.usagePercent
        result.resetAt = previous.resetAt
        result.calendarDeadlineAt = previous.calendarDeadlineAt
        result.usageWindowStart = previous.usageWindowStart
        result.windowDurationMinutes = previous.windowDurationMinutes
        result.weekElapsedPercent = previous.weekElapsedPercent
        result.secondaryQuota = previous.secondaryQuota
        result.planName = previous.planName
        result.usageHistory = previous.usageHistory
        result.weeklyArchives = previous.weeklyArchives
        result.estimatedRunoutAt = previous.estimatedRunoutAt
        result.paceWindowLabel = previous.paceWindowLabel
    }
}
