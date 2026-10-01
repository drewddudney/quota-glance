import Foundation
import UserNotifications

struct NotificationPreferences: Equatable {
    private enum Key {
        static let reset = "QuotaGlance.notify.reset"
        static let resetCompleted = "QuotaGlance.notify.resetCompleted"
        static let prominentReset = "QuotaGlance.notify.prominentReset"
        static let usage = "QuotaGlance.notify.usage"
        static let usageThreshold = "QuotaGlance.notify.usageThreshold"
        static let renewal = "QuotaGlance.notify.renewal"
        static let resetCredit = "QuotaGlance.notify.resetCredit"
        static let pace = "QuotaGlance.notify.pace"
        static let stale = "QuotaGlance.notify.stale"
        static let tibo = "QuotaGlance.notify.tibo"
        static let codexTasks = "QuotaGlance.notify.codexTasks"
        static let claudeUsage = "QuotaGlance.notify.claudeUsage"
        static let claudeWeek = "QuotaGlance.notify.claudeWeek"
    }

    var resetAnnounced: Bool
    var resetCompleted: Bool
    var prominentResetAlert: Bool
    var usageApproachingLimit: Bool
    var usageThreshold: Double
    var renewalSoon: Bool
    var resetCreditExpiring: Bool
    var paceRisk: Bool
    var staleSync: Bool
    var tiboPosts: Bool
    var codexTasks: Bool
    var claudeUsage: Bool
    var claudeWeek: Bool

    static func load() -> NotificationPreferences {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Key.reset) == nil {
            defaults.set(true, forKey: Key.reset)
            defaults.set(true, forKey: Key.usage)
            defaults.set(90.0, forKey: Key.usageThreshold)
            defaults.set(true, forKey: Key.renewal)
            defaults.set(true, forKey: Key.resetCredit)
            defaults.set(true, forKey: Key.pace)
            defaults.set(false, forKey: Key.stale)
            defaults.set(true, forKey: Key.tibo)
        }
        return NotificationPreferences(
            resetAnnounced: defaults.bool(forKey: Key.reset),
            resetCompleted: defaults.object(forKey: Key.resetCompleted) == nil
                ? true
                : defaults.bool(forKey: Key.resetCompleted),
            // Existing builds always delivered reset announcements as Time
            // Sensitive. Preserve that behavior while making it user-facing
            // and independently switchable.
            prominentResetAlert: defaults.object(forKey: Key.prominentReset) == nil
                ? true
                : defaults.bool(forKey: Key.prominentReset),
            usageApproachingLimit: defaults.bool(forKey: Key.usage),
            usageThreshold: max(50, defaults.double(forKey: Key.usageThreshold)),
            renewalSoon: defaults.bool(forKey: Key.renewal),
            resetCreditExpiring: defaults.bool(forKey: Key.resetCredit),
            paceRisk: defaults.bool(forKey: Key.pace),
            staleSync: defaults.bool(forKey: Key.stale),
            tiboPosts: defaults.object(forKey: Key.tibo) == nil ? true : defaults.bool(forKey: Key.tibo),
            codexTasks: defaults.object(forKey: Key.codexTasks) == nil ? true : defaults.bool(forKey: Key.codexTasks),
            claudeUsage: defaults.object(forKey: Key.claudeUsage) == nil ? true : defaults.bool(forKey: Key.claudeUsage),
            claudeWeek: defaults.object(forKey: Key.claudeWeek) == nil ? true : defaults.bool(forKey: Key.claudeWeek)
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(resetAnnounced, forKey: Key.reset)
        defaults.set(resetCompleted, forKey: Key.resetCompleted)
        defaults.set(prominentResetAlert, forKey: Key.prominentReset)
        defaults.set(usageApproachingLimit, forKey: Key.usage)
        defaults.set(usageThreshold, forKey: Key.usageThreshold)
        defaults.set(renewalSoon, forKey: Key.renewal)
        defaults.set(resetCreditExpiring, forKey: Key.resetCredit)
        defaults.set(paceRisk, forKey: Key.pace)
        defaults.set(staleSync, forKey: Key.stale)
        defaults.set(tiboPosts, forKey: Key.tibo)
        defaults.set(codexTasks, forKey: Key.codexTasks)
        defaults.set(claudeUsage, forKey: Key.claudeUsage)
        defaults.set(claudeWeek, forKey: Key.claudeWeek)
    }
}

/// Notification request identifiers replace pending requests, but submitting an
/// already delivered identifier can still show another banner. Keep our own
/// durable record and reserve in-flight requests before yielding to iOS.
@MainActor
final class NotificationDelivery {
    static let shared = NotificationDelivery()
    static let eventKey = "QuotaGlance.deliveredNotificationEvents.v1"
    let defaults: UserDefaults
    private var pending = Set<String>()
    private let submit: (UNNotificationRequest) async throws -> Void

    init(defaults: UserDefaults = .standard,
         submit: @escaping (UNNotificationRequest) async throws -> Void = {
             try await UNUserNotificationCenter.current().add($0)
         }) {
        self.defaults = defaults
        self.submit = submit
    }

    func remember(_ identifiers: [String]) {
        var seen = Set<String>()
        let ordered = (identifiers + (defaults.stringArray(forKey: Self.eventKey) ?? []))
            .filter { seen.insert($0).inserted }
        defaults.set(Array(ordered.prefix(1_024)), forKey: Self.eventKey)
    }

    @discardableResult
    func add(_ content: UNNotificationContent, identifier: String, deduplicate: Bool = true) async -> Bool {
        guard !pending.contains(identifier),
              !deduplicate || !(defaults.stringArray(forKey: Self.eventKey) ?? []).contains(identifier) else { return false }
        pending.insert(identifier)
        defer { pending.remove(identifier) }
        do {
            try await submit(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            if deduplicate { remember([identifier]) }
            return true
        } catch {
            // A failed submission can be retried; a delivered event cannot.
            return false
        }
    }
}

enum NotificationManager {
    private static let lastAnnouncementKey = "QuotaGlance.notifiedAnnouncementID"
    private static let lastCompletionKey = "QuotaGlance.notifiedResetCompletionID"
    private static let lastCompletionAtKey = "QuotaGlance.notifiedResetCompletionAt"
    private static let usageWindowKey = "QuotaGlance.notifiedUsageWindow"
    private static let lastTiboPostKey = "QuotaGlance.notifiedTiboPostID"
    private static let seenTiboPostsKey = "QuotaGlance.notifiedTiboPostIDs.v2"
    private static let tiboWatermarkKey = "QuotaGlance.notifiedTiboPostDate.v2"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        )) == true
    }

    @MainActor static func evaluate(
        _ snapshot: QuotaSnapshot,
        previous: QuotaSnapshot? = nil,
        preferences: NotificationPreferences,
        delivery suppliedDelivery: NotificationDelivery? = nil
    ) async {
        let delivery = suppliedDelivery ?? .shared
        let defaults = delivery.defaults
        migrateDeliveredEvents(previous: previous, delivery: delivery)
        if preferences.claudeUsage || preferences.claudeWeek {
            await evaluateClaude(snapshot.claude, previous: previous?.claude, preferences: preferences)
        }
        let posts = snapshot.tiboPosts ?? []
        let tiboState = tiboNotificationState(posts: posts, defaults: defaults)
        // Reserve the feed before any notification awaits. A foreground refresh
        // and a finishing background refresh may otherwise both select it.
        saveTiboNotificationState(tiboState, defaults: defaults)
        let newestPost = tiboState.newPost
        let newlyConfirmedByTibo = newestPost.map { isResetCompletionPost($0) } ?? false
        let newlyConfirmedByUsage = didUsageReset(previous: previous, current: snapshot)
        let announcementIdentity = canonicalAnnouncementIdentity(snapshot)
        let announcementCoversPost = preferences.resetAnnounced && snapshot.effectiveResetAnnounced
            && announcementIdentity != nil && announcementIdentity == newestPost?.canonicalIdentity

        if preferences.resetCompleted,
           (newlyConfirmedByTibo || newlyConfirmedByUsage),
           !wasResetCompletionRecentlyNotified(defaults: defaults) {
            let completionID: String = {
                if newlyConfirmedByUsage {
                    let anchor = snapshot.usageWindowStart ?? snapshot.resetAt ?? snapshot.capturedAt
                    return "usage-\(Int(anchor.timeIntervalSince1970))"
                }
                return "tibo-\(newestPost?.canonicalIdentity ?? "confirmed")"
            }()
            let content = UNMutableNotificationContent()
            content.title = preferences.prominentResetAlert
                ? "✅ CODEX RESET IS LIVE"
                : "Codex reset is live"
            content.body = newlyConfirmedByUsage
                ? "Usage returned to 0%. Your new quota window is ready."
                : "Tibo confirmed the reset. Your refreshed quota should be available now."
            content.sound = UNNotificationSound(named: UNNotificationSoundName("QuotaResetFairy.caf"))
            content.interruptionLevel = preferences.prominentResetAlert ? .timeSensitive : .active
            content.relevanceScore = preferences.prominentResetAlert ? 1 : 0.6
            content.threadIdentifier = "codex-reset-announcements"
            if await delivery.add(content, identifier: "reset-completed-\(completionID)") {
                defaults.set(completionID, forKey: lastCompletionKey)
                defaults.set(Date().timeIntervalSince1970, forKey: lastCompletionAtKey)
            }
        }

        if preferences.tiboPosts, let newest = tiboState.newPost {
            if !(newlyConfirmedByTibo && preferences.resetCompleted) && !announcementCoversPost {
                let content = UNMutableNotificationContent()
                content.title = newest.isResetOriented ? "New Tibo reset post" : "New Tibo post"
                content.body = String(newest.text.prefix(180))
                content.sound = .default
                await delivery.add(content, identifier: "tibo-post-\(newest.canonicalIdentity)")
            }
        }

        if preferences.codexTasks, let previous {
            let old = Dictionary(uniqueKeysWithValues: (previous.activeTasks ?? []).map { ($0.id, $0) })
            for task in snapshot.activeTasks ?? [] {
                guard let before = old[task.id], before.state != task.state else { continue }
                let normalized = task.state.lowercased()
                guard normalized.contains("complete") || normalized.contains("approval") || normalized.contains("stalled") else { continue }
                let content = UNMutableNotificationContent()
                content.title = normalized.contains("approval") ? "Codex needs approval" : normalized.contains("stalled") ? "Codex task stalled" : "Codex task finished"
                content.body = task.name
                content.sound = .default
                await delivery.add(content, identifier: "codex-task-\(task.id)-\(task.state)", deduplicate: false)
            }
        }

        if preferences.resetAnnounced,
           snapshot.effectiveResetAnnounced,
           let announcementID = snapshot.announcementID,
           let announcementIdentity {
            let content = UNMutableNotificationContent()
            content.title = preferences.prominentResetAlert
                ? "⚠️ CODEX RESET INCOMING"
                : "Codex reset announced"
            if let expectedAt = snapshot.announcementExpectedAt, expectedAt > Date() {
                let remaining = expectedAt.timeIntervalSinceNow
                content.body = "Reset in \(countdown(remaining)) · \(expectedAt.formatted(date: .abbreviated, time: .shortened)) local time."
            } else {
                content.body = snapshot.announcementText ?? "Use the quota you have left before the reset lands."
            }
            content.sound = preferences.prominentResetAlert
                ? UNNotificationSound(named: UNNotificationSoundName("QuotaResetFairy.caf"))
                : .default
            content.interruptionLevel = preferences.prominentResetAlert ? .timeSensitive : .active
            content.relevanceScore = preferences.prominentResetAlert ? 1 : 0.5
            content.threadIdentifier = "codex-reset-announcements"
            if await delivery.add(content, identifier: "reset-announced-\(announcementIdentity)") {
                defaults.set(announcementID, forKey: lastAnnouncementKey)
            }
        }

        if preferences.usageApproachingLimit,
           let usage = snapshot.usagePercent,
           usage >= preferences.usageThreshold {
            let window = snapshot.usageWindowStart?.timeIntervalSince1970 ?? 0
            let key = "\(Int(window))-\(Int(preferences.usageThreshold))"
            if defaults.string(forKey: usageWindowKey) != key {
                let content = UNMutableNotificationContent()
                content.title = "Codex usage is at \(Int(usage.rounded()))%"
                content.body = snapshot.resetAt.map { "Your current limit resets \($0.formatted(.relative(presentation: .named)))." }
                    ?? "You’re approaching the weekly limit."
                content.sound = .default
                if await delivery.add(content, identifier: "usage-threshold-\(key)") {
                    defaults.set(key, forKey: usageWindowKey)
                }
            }
        }

        if preferences.renewalSoon, let renewal = snapshot.renewalDate {
            await scheduleDateAlert(
                identifier: "renewal-soon",
                title: "Codex subscription renews in 3 days",
                body: "Review your plan before the billing cycle changes.",
                date: renewal.addingTimeInterval(-3 * 86_400)
            )
        }

        if preferences.resetCreditExpiring, let expiry = snapshot.resetCreditExpiresAt {
            await scheduleDateAlert(
                identifier: "reset-credit-expiring",
                title: "Reset credit expires in 12 hours",
                body: "Use the banked Codex reset before it disappears.",
                date: expiry.addingTimeInterval(-12 * 3_600)
            )
        }

        if preferences.paceRisk,
           let runout = snapshot.estimatedRunoutAt,
           let reset = snapshot.resetAt,
           runout < reset.addingTimeInterval(-60 * 60) {
            let window = snapshot.usageWindowStart?.timeIntervalSince1970 ?? 0
            let identifier = "pace-risk-\(Int(window))-\(Int(runout.timeIntervalSince1970 / 3600))"
            let content = UNMutableNotificationContent()
            content.title = "Codex pace is running hot"
            content.body = "At the \(snapshot.paceWindowLabel ?? "recent") rate, quota may run out \(runout.formatted(.relative(presentation: .named)))."
            content.sound = .default
            await delivery.add(content, identifier: identifier, deduplicate: false)
        }

        if preferences.staleSync,
           Date().timeIntervalSince(snapshot.capturedAt) > 6 * 3_600 {
            let content = UNMutableNotificationContent()
            content.title = "Quota Glance hasn’t synced"
            content.body = "Open Quota Glance to refresh your connected accounts."
            await delivery.add(content, identifier: "stale-sync", deduplicate: false)
        }
    }

    @MainActor private static var pendingClaudeAlerts = Set<String>()

    @MainActor private static func evaluateClaude(
        _ current: ClaudeQuotaSnapshot?, previous: ClaudeQuotaSnapshot?, preferences: NotificationPreferences
    ) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
        let key = "QuotaGlance.notifiedClaudeEvents.v1"
        let defaults = UserDefaults.standard
        let seen = Set(defaults.stringArray(forKey: key) ?? []).union(pendingClaudeAlerts)
        let events = ClaudeNotificationPolicy.events(
            current: current, previous: previous, usageEnabled: preferences.claudeUsage,
            weekEnabled: preferences.claudeWeek, threshold: preferences.usageThreshold, seen: seen
        )
        pendingClaudeAlerts.formUnion(events.map(\.id))
        for event in events {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = .default
            content.threadIdentifier = "claude-usage"
            content.userInfo = ["provider": "claude"]
            do {
                try await center.add(UNNotificationRequest(identifier: event.id, content: content, trigger: nil))
                let saved = defaults.stringArray(forKey: key) ?? []
                defaults.set(Array(([event.id] + saved).prefix(64)), forKey: key)
            } catch { /* A later sync may retry an alert that could not be added. */ }
            pendingClaudeAlerts.remove(event.id)
        }
    }

    struct TiboNotificationState {
        let newPost: QuotaTiboPost?
        let identities: [String]
        let watermark: Date?
    }

    static func canonicalAnnouncementIdentity(_ snapshot: QuotaSnapshot) -> String? {
        guard let id = snapshot.announcementID else { return nil }
        return canonicalAnnouncementIdentity(id: id, url: snapshot.announcementURL)
    }

    private static func canonicalAnnouncementIdentity(id: String, url: URL? = nil) -> String {
        var sourceID = id
        let prefixes = ["lunar:", "will:", "gussuri:", "scheduled:"]
        while let prefix = prefixes.first(where: sourceID.hasPrefix) {
            sourceID.removeFirst(prefix.count)
        }
        let post = QuotaTiboPost(id: sourceID, date: nil, text: "", inReplyTo: nil,
                                 url: url, isResetOriented: true)
        let identity = post.canonicalIdentity
        return identity.hasPrefix("x:") ? identity : "id:\(sourceID)"
    }

    @MainActor private static func migrateDeliveredEvents(
        previous: QuotaSnapshot?, delivery: NotificationDelivery
    ) {
        let defaults = delivery.defaults
        guard defaults.object(forKey: NotificationDelivery.eventKey) == nil else { return }
        var known = (defaults.stringArray(forKey: seenTiboPostsKey) ?? []).map { "tibo-post-\($0)" }
        if let legacy = defaults.string(forKey: lastAnnouncementKey) {
            known.append("reset-announced-\(canonicalAnnouncementIdentity(id: legacy))")
        }
        // The saved dashboard was already shown by the previous build. Seed
        // it quietly on upgrade instead of announcing its contents again.
        if let previous, let identity = canonicalAnnouncementIdentity(previous) {
            known.append("reset-announced-\(identity)")
        }
        if let completion = defaults.string(forKey: lastCompletionKey) {
            known.append("reset-completed-\(completion)")
        }
        delivery.remember(known)
    }

    static func tiboNotificationState(
        posts: [QuotaTiboPost],
        defaults: UserDefaults
    ) -> TiboNotificationState {
        let existing = defaults.stringArray(forKey: seenTiboPostsKey)
        var seen = Set(existing ?? [])
        if let legacy = defaults.string(forKey: lastTiboPostKey) {
            seen.insert(legacy)
            if let canonical = posts.first(where: { $0.id == legacy })?.canonicalIdentity {
                seen.insert(canonical)
            }
        }
        let savedTimestamp = defaults.double(forKey: tiboWatermarkKey)
        let savedWatermark = savedTimestamp > 0 ? Date(timeIntervalSince1970: savedTimestamp) : nil
        let newestDate = posts.compactMap(\.date).max()

        // On upgrade, baseline the whole current feed. This prevents a post
        // already shown by an older build from being replayed once per mirror.
        let isMigrating = existing == nil
        let newPost: QuotaTiboPost? = isMigrating ? nil : posts
            .filter { post in
                guard !seen.contains(post.canonicalIdentity), let date = post.date else { return false }
                return savedWatermark.map { date > $0 } ?? true
            }
            .max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }

        let currentIdentities = posts.map(\.canonicalIdentity)
        let currentSet = Set(currentIdentities)
        let orderedIdentities = currentIdentities
            + seen.filter { !currentSet.contains($0) }
        return TiboNotificationState(
            newPost: newPost,
            identities: Array(orderedIdentities.prefix(256)),
            watermark: maxDate(savedWatermark, newestDate)
        )
    }

    static func saveTiboNotificationState(
        _ state: TiboNotificationState,
        defaults: UserDefaults
    ) {
        var seen = Set<String>()
        let identities = (state.identities + (defaults.stringArray(forKey: seenTiboPostsKey) ?? []))
            .filter { seen.insert($0).inserted }
        defaults.set(Array(identities.prefix(256)), forKey: seenTiboPostsKey)
        let previousWatermark = defaults.double(forKey: tiboWatermarkKey)
        if let watermark = state.watermark, watermark.timeIntervalSince1970 > previousWatermark {
            defaults.set(watermark.timeIntervalSince1970, forKey: tiboWatermarkKey)
        }
        if let newestIdentity = state.identities.first {
            defaults.set(newestIdentity, forKey: lastTiboPostKey)
        }
    }

    private static func maxDate(_ first: Date?, _ second: Date?) -> Date? {
        switch (first, second) {
        case let (.some(lhs), .some(rhs)): max(lhs, rhs)
        case let (.some(value), .none), let (.none, .some(value)): value
        case (.none, .none): nil
        }
    }

    private static func scheduleDateAlert(identifier: String, title: String, body: String, date: Date) async {
        guard date > Date() else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        )
    }

    static func didUsageReset(previous: QuotaSnapshot?, current: QuotaSnapshot) -> Bool {
        guard
            let previous,
            previous.directCodexAccountID == current.directCodexAccountID,
            current.codexNeedsConnection != true,
            previous.capturedAt < current.capturedAt,
            let oldUsage = previous.usagePercent,
            let newUsage = current.usagePercent,
            oldUsage >= 2,
            newUsage <= 0.5
        else { return false }

        // A fresh quota window is authoritative. The large fallback drop also
        // covers a provider that updates its percentage before the new window
        // timestamps arrive; Mac-side snapshot merging already rejects brief
        // zero/stale reads inside the same window.
        let windowChanged: Bool = {
            guard let oldStart = previous.usageWindowStart,
                  let newStart = current.usageWindowStart else { return false }
            return abs(newStart.timeIntervalSince(oldStart)) > 2 * 60 * 60
        }()
        return windowChanged || oldUsage - newUsage >= 2
    }

    static func isResetCompletionPost(_ post: QuotaTiboPost, now: Date = Date()) -> Bool {
        guard
            post.isResetOriented,
            let postedAt = post.date,
            postedAt >= now.addingTimeInterval(-6 * 60 * 60)
        else { return false }
        let text = post.text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if text == "reset" || text == "resets" { return true }
        let confirmations = [
            "reset is live", "reset's live", "reset has landed", "reset landed",
            "reset is done", "reset complete", "reset completed", "have been reset",
            "quotas reset", "credits applied"
        ]
        return confirmations.contains(where: text.contains)
    }

    private static func wasResetCompletionRecentlyNotified(
        now: Date = Date(), defaults: UserDefaults
    ) -> Bool {
        let timestamp = defaults.double(forKey: lastCompletionAtKey)
        guard timestamp > 0 else { return false }
        return now.timeIntervalSince1970 - timestamp < 6 * 60 * 60
    }

    private static func countdown(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(interval / 60))
        let days = minutes / (24 * 60)
        let hours = (minutes % (24 * 60)) / 60
        let remainingMinutes = minutes % 60
        if days > 0 { return "\(days)d \(hours)h \(remainingMinutes)m" }
        if hours > 0 { return "\(hours)h \(remainingMinutes)m" }
        return "\(remainingMinutes)m"
    }
}
