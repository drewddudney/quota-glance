import Foundation

/// Quota providers expose measurements, not typing/task-presence signals.
/// Only a recent, comparable increase counts as activity; first connections,
/// old history, account switches and quota resets never count as usage.
enum ProviderActivityDetector {
    static let quietInterval: TimeInterval = 6 * 60
    static let maximumSampleGap: TimeInterval = 15 * 60

    static func activity(previous: QuotaSnapshot, current: QuotaSnapshot, now: Date = Date()) -> [String: Date] {
        var result = (previous.recentProviderActivity ?? [:]).filter { now.timeIntervalSince($0.value) < quietInterval }
        for provider in DisplayProvider.allCases {
            guard sameAccount(provider, previous, current), !needsConnection(provider, current) else {
                result.removeValue(forKey: provider.rawValue)
                continue
            }
            let oldDate = measurement(provider, previous)
            let newDate = measurement(provider, current)
            guard let oldDate, let newDate, newDate > oldDate,
                  newDate.timeIntervalSince(oldDate) <= maximumSampleGap,
                  (-60...quietInterval).contains(now.timeIntervalSince(newDate)) else { continue }
            if windows(provider, current).enumerated().contains(where: { index, new in
                let old = windows(provider, previous)[index]
                return comparable(old, new) && (new.percent ?? 0) > (old.percent ?? 0) + 0.001
            }) { result[provider.rawValue] = newDate }
        }
        return result
    }

    static func activeProviders(in snapshot: QuotaSnapshot, now: Date = Date()) -> [DisplayProvider] {
        DisplayProvider.allCases.filter {
            guard !needsConnection($0, snapshot), let date = snapshot.recentProviderActivity?[$0.rawValue] else { return false }
            return (-60...quietInterval).contains(now.timeIntervalSince(date))
        }
    }

    static func resets(previous: QuotaSnapshot, current: QuotaSnapshot, now: Date = Date()) -> [DisplayProvider] {
        DisplayProvider.allCases.filter { provider in
            guard sameAccount(provider, previous, current), !needsConnection(provider, current),
                  let oldDate = measurement(provider, previous), let newDate = measurement(provider, current),
                  newDate > oldDate, newDate.timeIntervalSince(oldDate) <= maximumSampleGap,
                  (-60...300).contains(now.timeIntervalSince(newDate)) else { return false }
            return windows(provider, current).enumerated().contains { index, new in
                let old = windows(provider, previous)[index]
                guard let oldPercent = old.percent, let newPercent = new.percent,
                      oldPercent >= 2, newPercent <= 1 else { return false }
                return comparable(old, new) || (new.deadline != nil && old.deadline.map { $0 <= newDate } == true)
            }
        }
    }

    private struct Window { let percent: Double?; let deadline: Date? }
    private static func windows(_ provider: DisplayProvider, _ snapshot: QuotaSnapshot) -> [Window] {
        if provider == .codex {
            return [Window(percent: snapshot.usagePercent, deadline: snapshot.resetAt),
                    Window(percent: snapshot.secondaryQuota?.usedPercent, deadline: snapshot.secondaryQuota?.resetAt)]
        }
        return [Window(percent: snapshot.claude?.usagePercent, deadline: snapshot.claude?.resetAt),
                Window(percent: snapshot.claude?.fiveHourUsagePercent, deadline: snapshot.claude?.fiveHourResetAt)]
    }
    private static func comparable(_ old: Window, _ new: Window) -> Bool {
        guard let oldPercent = old.percent, let newPercent = new.percent,
              oldPercent.isFinite, newPercent.isFinite else { return false }
        if let oldEnd = old.deadline, let newEnd = new.deadline { return abs(newEnd.timeIntervalSince(oldEnd)) < 120 }
        return old.deadline == nil && new.deadline == nil
    }
    private static func sameAccount(_ provider: DisplayProvider, _ old: QuotaSnapshot, _ new: QuotaSnapshot) -> Bool {
        provider == .codex ? old.directCodexAccountID == new.directCodexAccountID
            : old.claude?.accountID != nil && old.claude?.accountID == new.claude?.accountID
    }
    private static func measurement(_ provider: DisplayProvider, _ value: QuotaSnapshot) -> Date? {
        provider == .codex ? (value.usagePercent != nil || value.secondaryQuota != nil ? value.usageMeasurementDate : nil)
            : value.claude?.capturedAt
    }
    private static func needsConnection(_ provider: DisplayProvider, _ value: QuotaSnapshot) -> Bool {
        provider == .codex ? value.codexNeedsConnection == true : value.claude?.needsConnection == true
    }
}
