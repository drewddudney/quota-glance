import ActivityKit
import BackgroundTasks
import CloudKit
import Foundation
import OSLog
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

@MainActor
final class DashboardStore: ObservableObject {
    enum ForegroundSyncPolicy {
        static let localPollInterval: Duration = .seconds(10)
        static let cloudFallbackInterval: TimeInterval = 5 * 60
    }

    enum SyncState: Equatable {
        case idle
        case syncing
        case current
        case partial(String)

        var label: String {
            switch self {
            case .idle: "Waiting"
            case .syncing: "Syncing"
            case .current: "Live"
            case .partial(let message): message
            }
        }
    }

    @Published private(set) var snapshot = SharedSnapshotStore.load()
    @Published private(set) var state: SyncState = .idle
    @Published var selectedSources: Set<ResetSource> {
        didSet {
            let ordered = ResetSource.calculatorCases.filter(selectedSources.contains)
            guard !ordered.isEmpty else { return }
            UserDefaults.standard.set(ordered.map(\.rawValue), forKey: Self.sourcesKey)
            UserDefaults.standard.set(
                ordered.count == 1 ? ordered[0].rawValue : ResetSource.average.rawValue,
                forKey: Self.sourceKey
            )
            Task { await refresh() }
        }
    }

    private static let sourceKey = "QuotaGlance.mobile.resetSource"
    private static let sourcesKey = "QuotaGlance.mobile.resetSources"
    private var isRefreshing = false
    private var hasStarted = false

    init() {
        selectedSources = Self.loadSelectedSources()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--quota-preview") {
            snapshot = Self.previewSnapshot()
        }
#endif
    }

#if DEBUG
    private static func previewSnapshot(now: Date = Date()) -> QuotaSnapshot {
        let windowStart = now.addingTimeInterval(-4 * 86_400)
        let resetAt = windowStart.addingTimeInterval(7 * 86_400)
        let samples = (0...36).map { index in
            let fraction = Double(index) / 36
            let date = now.addingTimeInterval(-12 * 3_600 + Double(index) * 20 * 60)
            let tokenFraction = pow(fraction, 0.72)
            return QuotaUsagePoint(
                date: date,
                usedPercent: 34 + tokenFraction * 37,
                tokens: Int64(34_000 + tokenFraction * 37_200)
            )
        }
        return QuotaSnapshot(
            capturedAt: now,
            weekElapsedPercent: 86,
            usagePercent: 71,
            resetChancePercent: 56,
            resetAt: resetAt,
            usageWindowStart: windowStart,
            windowDurationMinutes: 10_080,
            weeklyTokens: 71_200,
            planName: "Pro 20x",
            renewalDate: now.addingTimeInterval(17 * 86_400),
            selectedSource: .average,
            providers: [
                .init(source: .lunarWerx, percent: 58, updatedAt: now),
                .init(source: .codexResets, percent: 55, updatedAt: now),
                .init(source: .willCodexQuotaReset, percent: 54, updatedAt: now)
            ],
            resetAnnounced: false,
            announcementID: nil,
            announcementText: nil,
            announcementDate: nil,
            announcementExpectedAt: nil,
            resetCompletedAt: nil,
            announcementURL: nil,
            lastBlessingAt: now.addingTimeInterval(-2 * 86_400),
            resetCreditExpiresAt: nil,
            estimatedRunoutAt: now.addingTimeInterval(3 * 86_400 + 5 * 3_600),
            paceWindowLabel: "12-hour",
            forecastUpdatedAt: now,
            usageHistory: samples,
            tokenPace: .init(fiveMinutes: 410, oneHour: 4_920, twelveHours: 37_200, twentyFourHours: 61_800, sinceReset: 71_200),
            usageIntelligence: .init(
                apiEquivalentUSD: 18.42,
                quotaWeightedUSD: 31.08,
                pricingCoverage: 0.98,
                speedCoverage: 0.91,
                fastShare: 0.37,
                eventCount: 1_319,
                ledgerBytes: 284_000,
                topModel: "gpt-5.6-sol",
                totalTokens: 1_284_000_000,
                cacheHitRate: 0.96,
                costTimeline: samples.map {
                    .init(
                        date: $0.date,
                        apiEquivalentUSD: 18.42 * max(0, ($0.usedPercent - 34) / 37)
                    )
                }
            ),
            secondaryQuota: .init(usedPercent: 24, resetAt: now.addingTimeInterval(3 * 3_600), windowDurationMinutes: 300),
            weeklyArchives: (1...4).map { week in
                let end = windowStart.addingTimeInterval(-Double(week - 1) * 7 * 86_400)
                let start = end.addingTimeInterval(-7 * 86_400)
                let final = [84.0, 67.0, 93.0, 76.0][week - 1]
                return QuotaWeeklyArchive(
                    windowStart: start,
                    resetAt: end,
                    finalUsedPercent: final,
                    totalTokens: Int64(final * 17_000_000),
                    apiEquivalentUSD: final * 1.12,
                    cacheHitRate: 0.93 + Double(week) * 0.01,
                    fastShare: 0.08 + Double(week) * 0.03,
                    topModel: "gpt-5.6-sol",
                    points: (0...7).map { day in
                        .init(
                            date: start.addingTimeInterval(Double(day) * 86_400),
                            usedPercent: final * Double(day) / 7,
                            apiEquivalentUSD: final * 1.12 * Double(day) / 7
                        )
                    }
                )
            },
            tiboPosts: [
                .init(
                    id: "preview-reset-post",
                    date: now.addingTimeInterval(-120),
                    text: "New reset post",
                    inReplyTo: "Tibo replied to your thread",
                    url: URL(string: "https://x.com/thsottiaux"),
                    isResetOriented: true
                )
            ]
        )
    }
#endif

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await LiveActivityPushTokenPublisher.shared.start()
        await CloudSnapshotService.installSubscriptionIfNeeded()
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        state = .syncing
        defer { isRefreshing = false }

        async let cloudResult = cloudSnapshot()
        async let publicResult = try? ResetProviderService.fetch(selected: selectedSources)
        let cloud = await cloudResult
        let forecast = await publicResult

        let previousSnapshot = snapshot
        var merged = cloud ?? snapshot
        merged.selectedSources = ResetSource.calculatorCases.filter(selectedSources.contains)
        merged.selectedSource = selectedSources.count == 1 ? selectedSources.first! : .average
        if let forecast {
            merged.forecastUpdatedAt = Date()
            merged.providers = forecast.providers
            merged.resetChancePercent = forecast.selectedPercent
            merged.mergeAnnouncement(
                announced: forecast.resetAnnounced,
                id: forecast.announcementID,
                text: forecast.announcementText,
                detectedAt: forecast.announcementDate,
                expectedAt: forecast.announcementExpectedAt,
                requiresApplicabilityConfirmation: forecast.announcementRequiresApplicabilityConfirmation,
                url: forecast.announcementURL
            )
            merged.lastBlessingAt = forecast.lastBlessingAt
            merged.tiboPosts = Self.mergePosts(forecast.tiboPosts, merged.tiboPosts ?? [])
        }
        merged.applyResetApplicabilityResponse(ResetApplicability.load())
        if let resetAt = merged.resetAt {
            let start = resetAt.addingTimeInterval(-7 * 86_400)
            merged.weekElapsedPercent = Self.progress(from: start, to: resetAt, now: Date())
        }

        snapshot = merged
        SharedSnapshotStore.save(merged)
        WidgetCenter.shared.reloadAllTimelines()
        await ResetLiveActivityManager.shared.sync(with: merged)
        await CodexSessionLiveActivityManager.shared.sync(with: merged)
        await NotificationManager.evaluate(merged, previous: previousSnapshot, preferences: .load())
        state = cloud == nil && forecast == nil
            ? .partial("Cached")
            : (cloud == nil ? .partial("Reset data live · Mac pending") : .current)
        AppDelegate.scheduleRefresh()
    }

    /// KVS notifications are the primary foreground path. This modest polling
    /// loop is only a reliability fallback for missed notifications.
    func runForegroundSyncLoop() async {
        var nextCloudFallback = Date().addingTimeInterval(
            Self.ForegroundSyncPolicy.cloudFallbackInterval
        )
        while !Task.isCancelled {
            await refreshCloudSnapshotIfNew()
            try? await Task.sleep(for: Self.ForegroundSyncPolicy.localPollInterval)
            guard !Task.isCancelled else { return }
            if Date() >= nextCloudFallback {
                await refreshCloudSnapshotIfNew(useCloudKitFallback: true)
                nextCloudFallback = Date().addingTimeInterval(
                    Self.ForegroundSyncPolicy.cloudFallbackInterval
                )
            }
        }
    }

    /// Applies work already completed by a background refresh without
    /// immediately repeating its CloudKit and public-provider requests.
    func refreshFromSharedSnapshotIfNew() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let incoming = SharedSnapshotStore.load()
        guard incoming != snapshot else { return }
        await applyIncomingSnapshot(incoming)
    }

    func refreshCloudSnapshotIfNew(useCloudKitFallback: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var incoming = CloudSnapshotService.keyValueSnapshot()
        if useCloudKitFallback,
           incoming == nil || incoming!.capturedAt <= snapshot.capturedAt {
            incoming = try? await CloudSnapshotService.fetch()
        }
        guard let incoming, incoming.capturedAt > snapshot.capturedAt else { return }

        await applyIncomingSnapshot(incoming)
    }

    private func applyIncomingSnapshot(_ value: QuotaSnapshot) async {
        let previousSnapshot = snapshot
        var incoming = value
        incoming.applyResetApplicabilityResponse(ResetApplicability.load())
        incoming.selectedSources = ResetSource.calculatorCases.filter(selectedSources.contains)
        incoming.selectedSource = selectedSources.count == 1 ? selectedSources.first! : .average
        if let resetAt = incoming.resetAt {
            let start = resetAt.addingTimeInterval(-7 * 86_400)
            incoming.weekElapsedPercent = Self.progress(from: start, to: resetAt, now: Date())
        }
        guard incoming != previousSnapshot else { return }

        snapshot = incoming
        state = .current
        SharedSnapshotStore.save(incoming)
        WidgetCenter.shared.reloadAllTimelines()
        await ResetLiveActivityManager.shared.sync(with: incoming)
        await CodexSessionLiveActivityManager.shared.sync(with: incoming)
        await NotificationManager.evaluate(incoming, previous: previousSnapshot, preferences: .load())
    }

    func answerResetApplicability(_ applies: Bool) async {
        guard let announcementID = snapshot.announcementID else { return }
        ResetApplicability.save(announcementID: announcementID, applies: applies)
        let previous = snapshot
        snapshot.applyResetApplicabilityResponse(ResetApplicability.load())
        SharedSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        await ResetLiveActivityManager.shared.sync(with: snapshot)
        await NotificationManager.evaluate(snapshot, previous: previous, preferences: .load())
    }

    func refreshResetApplicabilityFromCloud() async {
        let previous = snapshot
        snapshot.applyResetApplicabilityResponse(ResetApplicability.load())
        guard snapshot != previous else { return }
        SharedSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        await ResetLiveActivityManager.shared.sync(with: snapshot)
    }

    private func cloudSnapshot() async -> QuotaSnapshot? {
        try? await CloudSnapshotService.fetch()
    }

    func binding(for source: ResetSource) -> Binding<Bool> {
        Binding(
            get: { self.selectedSources.contains(source) },
            set: { enabled in
                var next = self.selectedSources
                if enabled {
                    next.insert(source)
                } else if next.count > 1 {
                    next.remove(source)
                }
                guard !next.isEmpty, next != self.selectedSources else { return }
                self.selectedSources = next
            }
        )
    }

    private static func loadSelectedSources() -> Set<ResetSource> {
        if let stored = UserDefaults.standard.array(forKey: sourcesKey) as? [String] {
            let sources = Set(stored.compactMap(ResetSource.init(rawValue:)))
                .intersection(ResetSource.calculatorCases)
            if !sources.isEmpty { return sources }
        }
        let legacy = ResetSource(
            rawValue: UserDefaults.standard.string(forKey: sourceKey) ?? ""
        ) ?? .average
        return legacy == .average ? Set(ResetSource.calculatorCases) : [legacy]
    }

    fileprivate static func progress(from start: Date, to end: Date, now: Date) -> Double {
        guard end > start else { return now >= end ? 100 : 0 }
        return max(0, min(100, now.timeIntervalSince(start) / end.timeIntervalSince(start) * 100))
    }

    fileprivate static func mergePosts(_ first: [QuotaTiboPost], _ second: [QuotaTiboPost]) -> [QuotaTiboPost] {
        var byID: [String: QuotaTiboPost] = [:]
        for post in first + second {
            let identity = post.canonicalIdentity
            let previous = byID[identity]
            let oldDetail = (previous?.text.count ?? 0) + (previous?.inReplyTo?.count ?? 0)
            let newDetail = post.text.count + (post.inReplyTo?.count ?? 0)
            if previous == nil || newDetail > oldDetail { byID[identity] = post }
        }
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        return byID.values
            .filter { ($0.date ?? .distantPast) >= cutoff }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let refreshIdentifier = "com.drewdudney.quotaglance.refresh"
    private static let logger = Logger(
        subsystem: "com.drewdudney.quotaglance.mobile",
        category: "BackgroundRefresh"
    )

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Self.handle(refreshTask)
        }
        Self.scheduleRefresh()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let result = await Self.refreshInBackground(reason: "cloud-push")
            completionHandler(result)
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Self.scheduleRefresh()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    static func scheduleRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        let active = SharedSnapshotStore.load().hasActiveCodexSession()
        request.earliestBeginDate = Date().addingTimeInterval(active ? 5 * 60 : 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("Could not schedule background refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        scheduleRefresh()
        let work = Task { @MainActor in
            let result = await refreshInBackground(reason: "scheduled-task")
            task.setTaskCompleted(success: result != .failed)
        }
        task.expirationHandler = { work.cancel() }
    }

    @MainActor
    private static func refreshInBackground(reason: String) async -> UIBackgroundFetchResult {
        let previous = SharedSnapshotStore.load()
        let storedSources = UserDefaults.standard.array(forKey: "QuotaGlance.mobile.resetSources") as? [String]
        let decodedSources = Set((storedSources ?? []).compactMap(ResetSource.init(rawValue:)))
            .intersection(ResetSource.calculatorCases)
        let legacy = ResetSource(
            rawValue: UserDefaults.standard.string(forKey: "QuotaGlance.mobile.resetSource") ?? ""
        ) ?? .average
        let selected = decodedSources.isEmpty
            ? (legacy == .average ? Set(ResetSource.calculatorCases) : [legacy])
            : decodedSources

        async let cloudRequest: QuotaSnapshot? = try? CloudSnapshotService.fetch()
        async let forecastRequest = try? ResetProviderService.fetch(selected: selected)
        let (cloud, forecast) = await (cloudRequest, forecastRequest)

        guard cloud != nil || forecast != nil else {
            logger.error("Background refresh failed (\(reason, privacy: .public)): no source returned data")
            return .failed
        }

        var snapshot = cloud ?? previous
        snapshot.selectedSources = ResetSource.calculatorCases.filter(selected.contains)
        snapshot.selectedSource = selected.count == 1 ? selected.first! : .average
        if let forecast {
            snapshot.forecastUpdatedAt = Date()
            snapshot.providers = forecast.providers
            snapshot.resetChancePercent = forecast.selectedPercent
            snapshot.mergeAnnouncement(
                announced: forecast.resetAnnounced,
                id: forecast.announcementID,
                text: forecast.announcementText,
                detectedAt: forecast.announcementDate,
                expectedAt: forecast.announcementExpectedAt,
                requiresApplicabilityConfirmation: forecast.announcementRequiresApplicabilityConfirmation,
                url: forecast.announcementURL
            )
            snapshot.lastBlessingAt = forecast.lastBlessingAt
            snapshot.tiboPosts = DashboardStore.mergePosts(forecast.tiboPosts, snapshot.tiboPosts ?? [])
        }
        snapshot.applyResetApplicabilityResponse(ResetApplicability.load())
        if let resetAt = snapshot.resetAt {
            let start = resetAt.addingTimeInterval(-7 * 86_400)
            snapshot.weekElapsedPercent = DashboardStore.progress(from: start, to: resetAt, now: Date())
        }

        let changed = snapshot != previous
        if changed {
            SharedSnapshotStore.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
            await ResetLiveActivityManager.shared.sync(with: snapshot)
            await CodexSessionLiveActivityManager.shared.sync(with: snapshot)
            await NotificationManager.evaluate(snapshot, previous: previous, preferences: .load())
            if UIApplication.shared.applicationState == .active {
                NotificationCenter.default.post(name: .quotaCloudChanged, object: nil)
            }
        }
        logger.notice("Background refresh completed (\(reason, privacy: .public)); changed=\(changed)")
        return changed ? .newData : .noData
    }
}

extension Notification.Name {
    static let quotaCloudChanged = Notification.Name("QuotaGlance.cloudChanged")
}

actor ResetLiveActivityManager {
    static let shared = ResetLiveActivityManager()

    func sync(with snapshot: QuotaSnapshot, now: Date = Date()) async {
        let activities = Activity<ResetCountdownAttributes>.activities
        guard
            ActivityAuthorizationInfo().areActivitiesEnabled,
            let expectedAt = snapshot.activeAnnouncementExpectedAt,
            !snapshot.resetRecentlyCompleted
        else {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        let announcementID = snapshot.announcementID ?? "reset-\(Int(expectedAt.timeIntervalSince1970))"
        let state = ResetCountdownAttributes.ContentState(
            expectedAt: expectedAt,
            sourceLabel: snapshot.resetSourceLabel,
            isDelayed: expectedAt <= now
        )
        let content = ActivityContent(
            state: state,
            staleDate: expectedAt
        )

        if let current = activities.first(where: { $0.attributes.announcementID == announcementID }) {
            await current.update(content)
            for duplicate in activities where duplicate.id != current.id {
                await duplicate.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        for old in activities {
            await old.end(nil, dismissalPolicy: .immediate)
        }
        do {
            _ = try Activity.request(
                attributes: ResetCountdownAttributes(announcementID: announcementID),
                content: content,
                pushType: nil
            )
        } catch {
            // The in-app countdown remains available if Live Activities are disabled.
        }
    }
}

actor CodexSessionLiveActivityManager {
    static let shared = CodexSessionLiveActivityManager()
    private var projectionTask: Task<Void, Never>?

    func sync(
        with snapshot: QuotaSnapshot,
        preferences: NotificationPreferences = .load(),
        now: Date = Date()
    ) async {
        let activities = Activity<CodexSessionActivityAttributes>.activities
        guard
            preferences.sessionLiveActivity,
            ActivityAuthorizationInfo().areActivitiesEnabled,
            snapshot.hasActiveCodexSession(at: now)
        else {
            projectionTask?.cancel()
            projectionTask = nil
            for activity in activities {
                await LiveActivityPushTokenPublisher.shared.stopObserving(activityID: activity.id)
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        let anchor = snapshot.usageWindowStart ?? snapshot.capturedAt
        let sessionID = "usage-\(Int(anchor.timeIntervalSince1970))"
        let task = snapshot.activeTasks?.first
        let perMinute = CodexSessionUsageProjection.tokensPerMinute(snapshot: snapshot, now: now)
        let percentPerMinute = CodexSessionUsageProjection.percentPerMinute(
            snapshot: snapshot,
            tokensPerMinute: perMinute
        )
        let estimatedPercent = CodexSessionUsageProjection.estimatedPercentAtRefresh(
            snapshot: snapshot,
            percentPerMinute: percentPerMinute
        )
        let state = CodexSessionActivityAttributes.ContentState(
            taskName: (snapshot.activeTasks?.count ?? 0) > 1
                ? "\(snapshot.activeTasks?.count ?? 0) Codex sessions active"
                : task?.name ?? "Codex is working",
            usedPercent: estimatedPercent,
            totalTokens: snapshot.bestTokenTotal ?? 0,
            tokensPerMinute: perMinute,
            percentPerMinute: percentPerMinute,
            updatedAt: snapshot.capturedAt
        )
        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(10 * 60))

        if let current = activities.first(where: { $0.attributes.sessionID == sessionID }) {
            await LiveActivityPushTokenPublisher.shared.observe(current)
            await current.update(content)
            for duplicate in activities where duplicate.id != current.id {
                await LiveActivityPushTokenPublisher.shared.stopObserving(activityID: duplicate.id)
                await duplicate.end(nil, dismissalPolicy: .immediate)
            }
            beginProjectionUpdates(for: current, from: state)
            return
        }

        for old in activities {
            await LiveActivityPushTokenPublisher.shared.stopObserving(activityID: old.id)
            await old.end(nil, dismissalPolicy: .immediate)
        }
        do {
            let activity = try Activity.request(
                attributes: CodexSessionActivityAttributes(sessionID: sessionID),
                content: content,
                pushType: .token
            )
            await LiveActivityPushTokenPublisher.shared.observe(activity)
            beginProjectionUpdates(for: activity, from: state)
        } catch {
            // The in-app activity remains optional when iOS has disabled it.
        }
    }

    /// Send occasional ActivityKit anchors while the app process is available.
    /// The widget interpolates between them, avoiding a system state write every second.
    private func beginProjectionUpdates(
        for activity: Activity<CodexSessionActivityAttributes>,
        from anchor: CodexSessionActivityAttributes.ContentState
    ) {
        projectionTask?.cancel()
        guard (anchor.percentPerMinute ?? 0) > 0 else {
            projectionTask = nil
            return
        }

        projectionTask = Task {
            let expiresAt = anchor.updatedAt.addingTimeInterval(
                CodexSessionUsageProjection.maximumProjectionDuration
            )
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }

                let now = Date()
                guard now <= expiresAt else { return }
                let projected = CodexSessionUsageProjection.projectedPercent(
                    basePercent: anchor.usedPercent,
                    percentPerMinute: anchor.percentPerMinute ?? 0,
                    updatedAt: anchor.updatedAt,
                    now: now
                )
                let state = CodexSessionActivityAttributes.ContentState(
                    taskName: anchor.taskName,
                    usedPercent: projected,
                    totalTokens: anchor.totalTokens,
                    tokensPerMinute: anchor.tokensPerMinute,
                    percentPerMinute: anchor.percentPerMinute,
                    updatedAt: now
                )
                await activity.update(
                    ActivityContent(state: state, staleDate: expiresAt)
                )

                if projected >= floor(anchor.usedPercent) + 0.999 { return }
            }
        }
    }
}
