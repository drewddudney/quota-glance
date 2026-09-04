import Foundation

struct AdaptiveRefreshPolicy: Sendable {
    enum Reason: String, Sendable {
        case resetConfirmation
        case recentInteraction
        case codingActivity
        case warm
        case idle
        case longIdle
        case constrained
    }

    struct Input: Sendable {
        let now: Date
        let lastInteractionAt: Date?
        let lastCodingActivityAt: Date?
        let isConstrained: Bool
        let pendingResetConfirmation: Bool
    }

    struct Decision: Sendable, Equatable {
        let interval: TimeInterval
        let reason: Reason
    }

    func nextDelay(for input: Input) -> Decision {
        if input.pendingResetConfirmation {
            return Decision(interval: 60, reason: .resetConfirmation)
        }
        if input.isConstrained {
            return Decision(interval: 30 * 60, reason: .constrained)
        }
        if age(of: input.lastCodingActivityAt, at: input.now) <= 5 * 60 {
            return Decision(interval: 15, reason: .codingActivity)
        }
        if age(of: input.lastInteractionAt, at: input.now) <= 5 * 60 {
            return Decision(interval: 2 * 60, reason: .recentInteraction)
        }
        if age(of: input.lastInteractionAt, at: input.now) <= 60 * 60 {
            return Decision(interval: 5 * 60, reason: .warm)
        }
        if age(of: input.lastInteractionAt, at: input.now) < 4 * 60 * 60 {
            return Decision(interval: 15 * 60, reason: .idle)
        }
        return Decision(interval: 30 * 60, reason: .longIdle)
    }

    private func age(of date: Date?, at now: Date) -> TimeInterval {
        guard let date else { return .greatestFiniteMagnitude }
        return max(0, now.timeIntervalSince(date))
    }
}

enum CodexDataFreshness: String, Sendable {
    case live
    case stale
    case offline

    static func resolve(
        lastSuccessfulAt: Date?,
        lastAttemptFailed: Bool,
        hasCachedData: Bool,
        at now: Date = Date()
    ) -> Self {
        guard let lastSuccessfulAt else { return hasCachedData ? .stale : .offline }
        let age = max(0, now.timeIntervalSince(lastSuccessfulAt))
        if lastAttemptFailed && age >= 60 * 60 { return .offline }
        if lastAttemptFailed || age >= 35 * 60 { return .stale }
        return .live
    }
}

/// A cheap activity signal used while the expensive Codex usage scan sleeps.
/// Codex appends to rollout JSONL files while turns are active, so checking the
/// current session directory lets Quota Glance wake without polling app-server
/// and rebuilding token intelligence every minute all day.
enum CodexActivityProbe {
    private static let activityNeedles = [
        Data("\"task_started\"".utf8),
        Data("\"task_complete\"".utf8)
    ]

    static func latestActivity(
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy/MM/dd"

        var latest: Date?
        for dayOffset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let directory = sessionsRoot.appendingPathComponent(
                formatter.string(from: day),
                isDirectory: true
            )
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let modified = try? file.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate else { continue }
                if latest.map({ modified > $0 }) ?? true { latest = modified }
            }
        }
        return latest
    }

    /// A separately launched `codex app-server` reports already-open desktop
    /// threads as `notLoaded`, even while their turn is running. The rollout is
    /// the authoritative local state: the newest task lifecycle event tells us
    /// whether the turn is still active.
    static func isTurnActive(
        rolloutURL: URL,
        now: Date = Date(),
        maximumTailBytes: Int = 32 * 1_024 * 1_024
    ) -> Bool {
        guard let values = try? rolloutURL.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey]
        ), let fileSize = values.fileSize, fileSize > 0 else { return false }

        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: rolloutURL) }
        catch { return false }
        defer { try? handle.close() }

        var requested = min(fileSize, 256 * 1_024)
        while requested <= min(fileSize, maximumTailBytes) {
            do {
                try handle.seek(toOffset: UInt64(fileSize - requested))
                let data = try handle.readToEnd() ?? Data()
                for line in data.split(separator: 0x0A).reversed() {
                    let candidate = Data(line)
                    guard activityNeedles.contains(where: { candidate.range(of: $0) != nil }),
                          let object = try? JSONSerialization.jsonObject(with: candidate) as? [String: Any],
                          object["type"] as? String == "event_msg",
                          let payload = object["payload"] as? [String: Any],
                          let type = payload["type"] as? String
                    else { continue }
                    if type == "task_started" { return true }
                    if type == "task_complete" { return false }
                }
            } catch { return false }

            if requested == fileSize || requested == maximumTailBytes { break }
            requested = min(fileSize, maximumTailBytes, requested * 2)
        }

        // A single enormous output can push the start marker outside the tail.
        // Treat only a file that is being written right now as active; the short
        // grace period prevents a completed turn from lingering for minutes.
        guard let modified = values.contentModificationDate else { return false }
        return now.timeIntervalSince(modified) >= 0 && now.timeIntervalSince(modified) <= 20
    }
}
