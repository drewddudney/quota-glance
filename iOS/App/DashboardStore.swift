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
    static var isPreview: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--quota-preview")
#else
        false
#endif
    }

    private var hasStarted = false

    init() {
        selectedSources = Self.loadSelectedSources()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--quota-preview") {
            snapshot = Self.previewSnapshot()
            if ProcessInfo.processInfo.arguments.contains("--quota-preview-live-system") {
                snapshot.recentProviderActivity = ["codex": .now, "claude": .now]
            }
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
        var claude = ClaudeQuotaSnapshot(capturedAt: now, usagePercent: 82, resetAt: resetAt,
            planName: "Max", accountID: "preview", verified: true, needsConnection: false,
            fiveHourUsagePercent: 31, fiveHourResetAt: now.addingTimeInterval(2 * 3_600),
            usageHistory: samples.map { .init(date: $0.date, usedPercent: 49 + ($0.usedPercent - 34) / 37 * 33) },
            weeklyArchives: [.init(windowStart: windowStart.addingTimeInterval(-7 * 86_400), resetAt: windowStart,
                finalUsedPercent: 82, points: samples.map {
                    .init(date: $0.date.addingTimeInterval(-7 * 86_400), usedPercent: 49 + ($0.usedPercent - 34) / 37 * 33)
                })])
        claude.estimatedRunoutAt = ClaudeUsageHistory.estimate(for: claude, now: now)
        claude.paceWindowLabel = "recorded one-hour"
        return QuotaSnapshot(
            claude: claude,
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
                gpt6CodexCredits: 2_480,
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
        guard !Self.isPreview else { return }
        guard !hasStarted else { await refresh(); return }
        hasStarted = true
        await RetiredActivityCleanup.run()
        if PhoneSyncSettings.includesMacDetails { await CloudSnapshotService.installSubscriptionIfNeeded() }
        await refresh()
    }

    func refresh() async {
        guard !Self.isPreview else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        state = .syncing
        defer { isRefreshing = false }

        async let directResult = ProviderConnectionService.shared.refreshAll()
        async let cloudResult = cloudSnapshot()
        async let publicResult = try? ResetProviderService.fetch(selected: selectedSources)
        let cloud = await cloudResult
        let forecast = await publicResult
        _ = await directResult

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
        merged = Self.withPhoneUsage(merged, previous: previousSnapshot)
        merged.applyResetApplicabilityResponse(ResetApplicability.load())
        if let resetAt = merged.resetAt {
            let start = resetAt.addingTimeInterval(-7 * 86_400)
            merged.weekElapsedPercent = Self.progress(from: start, to: resetAt, now: Date())
        }

        snapshot = merged
        SharedSnapshotStore.save(merged)
        WidgetCenter.shared.reloadAllTimelines()
        await ProviderUsageActivityManager.shared.sync(snapshot: merged)
        PhonePetCelebrationCoordinator.shared.observe(previous: previousSnapshot, current: merged)
        await NotificationManager.evaluate(merged, previous: previousSnapshot, preferences: .load())
        state = Self.syncState(for: merged)
        AppDelegate.scheduleRefresh()
    }

    /// Phone sessions refresh independently; optional Mac details use their
    /// existing inexpensive iCloud notification path.
    func runForegroundSyncLoop() async {
        guard !Self.isPreview else { return }
        var nextCloudFallback = Date().addingTimeInterval(
            Self.ForegroundSyncPolicy.cloudFallbackInterval
        )
        var nextDirectRefresh = Date().addingTimeInterval(120)
        while !Task.isCancelled {
            if Date() >= nextDirectRefresh {
                _ = await ProviderConnectionService.shared.refreshAll()
                await refreshPhoneUsage()
                nextDirectRefresh = Date().addingTimeInterval(120)
            }
            await refreshCloudSnapshotIfNew()
            await ProviderUsageActivityManager.shared.sync(snapshot: snapshot)
            try? await Task.sleep(for: Self.ForegroundSyncPolicy.localPollInterval)
            guard !Task.isCancelled else { return }
            if Date() >= nextCloudFallback {
                await refresh()
                nextCloudFallback = Date().addingTimeInterval(
                    Self.ForegroundSyncPolicy.cloudFallbackInterval
                )
            }
        }
    }

    /// Applies work already completed by a background refresh without
    /// immediately repeating its CloudKit and public-provider requests.
    func refreshFromSharedSnapshotIfNew() async {
        guard !Self.isPreview else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let incoming = SharedSnapshotStore.load()
        guard incoming != snapshot else { return }
        await applyIncomingSnapshot(incoming)
    }

    func refreshCloudSnapshotIfNew(useCloudKitFallback: Bool = false) async {
        guard !Self.isPreview, PhoneSyncSettings.includesMacDetails else { return }
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
        var incoming = Self.withPhoneUsage(value, previous: previousSnapshot)
        incoming.applyResetApplicabilityResponse(ResetApplicability.load())
        incoming.selectedSources = ResetSource.calculatorCases.filter(selectedSources.contains)
        incoming.selectedSource = selectedSources.count == 1 ? selectedSources.first! : .average
        if let resetAt = incoming.resetAt {
            let start = resetAt.addingTimeInterval(-7 * 86_400)
            incoming.weekElapsedPercent = Self.progress(from: start, to: resetAt, now: Date())
        }
        guard incoming != previousSnapshot else { return }

        snapshot = incoming
        state = Self.syncState(for: incoming)
        SharedSnapshotStore.save(incoming)
        WidgetCenter.shared.reloadAllTimelines()
        await ProviderUsageActivityManager.shared.sync(snapshot: incoming)
        PhonePetCelebrationCoordinator.shared.observe(previous: previousSnapshot, current: incoming)
        await NotificationManager.evaluate(incoming, previous: previousSnapshot, preferences: .load())
    }

    func answerResetApplicability(_ applies: Bool) async {
        guard let announcementID = snapshot.announcementID else { return }
        ResetApplicability.save(announcementID: announcementID, applies: applies)
        let previous = snapshot
        snapshot.applyResetApplicabilityResponse(ResetApplicability.load())
        SharedSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        await NotificationManager.evaluate(snapshot, previous: previous, preferences: .load())
    }

    func refreshResetApplicabilityFromCloud() async {
        guard !Self.isPreview else { return }
        let previous = snapshot
        snapshot.applyResetApplicabilityResponse(ResetApplicability.load())
        guard snapshot != previous else { return }
        SharedSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func cloudSnapshot() async -> QuotaSnapshot? {
        guard PhoneSyncSettings.includesMacDetails else { return nil }
        return try? await CloudSnapshotService.fetch()
    }

    func refreshPhoneUsage() async {
        guard !Self.isPreview, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await applyIncomingSnapshot(snapshot)
    }

    static func withPhoneUsage(_ value: QuotaSnapshot, previous: QuotaSnapshot) -> QuotaSnapshot {
        let service = ProviderConnectionService.shared
        var result = PhoneUsageMerge.merge(
            base: value, previous: previous,
            readings: DirectUsageProvider.allCases.compactMap { service.latestUsage(for: $0) },
            connections: Set(DirectUsageProvider.allCases.filter { service.hasConnection($0) }),
            needsConnection: Set(DirectUsageProvider.allCases.filter { service.needsSignIn($0) }),
            includeMacDetails: PhoneSyncSettings.includesMacDetails
        )
        result.recentProviderActivity = ProviderActivityDetector.activity(previous: previous, current: result)
        return result
    }

    private static func syncState(for value: QuotaSnapshot) -> SyncState {
        let service = ProviderConnectionService.shared
        let selected = MobileProviderSelection.current.providers
        let allFresh = selected.allSatisfy { provider in
            let reading = MobileProviderReading(provider: provider, snapshot: value, at: Date())
            guard let measuredAt = reading.capturedAt else { return false }
            return !reading.needsConnection && Date().timeIntervalSince(measuredAt) <= 15 * 60
        }
        if allFresh { return .current }
        if selected.contains(where: { !service.hasConnection($0 == .codex ? .codex : .claude) }), !PhoneSyncSettings.includesMacDetails {
            return .partial("Connect accounts in Settings")
        }
        return .partial("Saved usage")
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
    static let refreshIdentifier = "com.example.quotaglance.refresh"
    private static let logger = Logger(
        subsystem: "com.example.quotaglance.mobile",
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

        async let directRequest = ProviderConnectionService.shared.refreshAll(inBackground: true)
        async let cloudRequest: QuotaSnapshot? = PhoneSyncSettings.includesMacDetails ? try? CloudSnapshotService.fetch() : nil
        async let forecastRequest = try? ResetProviderService.fetch(selected: selected)
        let (cloud, forecast, direct) = await (cloudRequest, forecastRequest, directRequest)

        guard cloud != nil || forecast != nil || !direct.isEmpty else {
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
        snapshot = DashboardStore.withPhoneUsage(snapshot, previous: previous)
        snapshot.applyResetApplicabilityResponse(ResetApplicability.load())
        if let resetAt = snapshot.resetAt {
            let start = resetAt.addingTimeInterval(-7 * 86_400)
            snapshot.weekElapsedPercent = DashboardStore.progress(from: start, to: resetAt, now: Date())
        }

        let changed = snapshot != previous
        if changed {
            SharedSnapshotStore.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
            await ProviderUsageActivityManager.shared.sync(snapshot: snapshot)
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

/// Keep the retired ActivityKit schemas for one upgrade path so activities
/// created by older builds are dismissed immediately when the app launches.
@MainActor
enum RetiredActivityCleanup {
    private static var completed = false
    private static let tokenKeys = [
        "QuotaGlance.liveActivity.codex.registration.v1",
        "QuotaGlance.liveActivity.codex.pushToStart.v1"
    ]

    static func run() async {
        guard !completed else { return }
        completed = true
        let store = NSUbiquitousKeyValueStore.default
        for key in tokenKeys { store.removeObject(forKey: key) }
        store.synchronize()
        for activity in Activity<CodexSessionActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        for activity in Activity<ResetCountdownAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
