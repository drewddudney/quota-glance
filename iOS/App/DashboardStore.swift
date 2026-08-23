import ActivityKit
import BackgroundTasks
import CloudKit
import Foundation
import UIKit
import UserNotifications
import WidgetKit

@MainActor
final class DashboardStore: ObservableObject {
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
    @Published var selectedSource: ResetSource {
        didSet {
            UserDefaults.standard.set(selectedSource.rawValue, forKey: Self.sourceKey)
            Task { await refresh() }
        }
    }

    private static let sourceKey = "QuotaGlance.mobile.resetSource"
    private var isRefreshing = false

    init() {
        selectedSource = ResetSource(
            rawValue: UserDefaults.standard.string(forKey: Self.sourceKey) ?? ""
        ) ?? .average
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
            announcementURL: nil,
            lastBlessingAt: now.addingTimeInterval(-2 * 86_400),
            resetCreditExpiresAt: nil,
            estimatedRunoutAt: now.addingTimeInterval(3 * 86_400 + 5 * 3_600),
            paceWindowLabel: "12-hour",
            forecastUpdatedAt: now,
            usageHistory: samples,
            tokenPace: .init(fiveMinutes: 410, oneHour: 4_920, twelveHours: 37_200, twentyFourHours: 61_800, sinceReset: 71_200),
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
        await CloudSnapshotService.installSubscriptionIfNeeded()
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        state = .syncing
        defer { isRefreshing = false }

        async let cloudResult = cloudSnapshot()
        async let publicResult = try? ResetProviderService.fetch(selected: selectedSource)
        let cloud = await cloudResult
        let forecast = await publicResult

        let previousSnapshot = snapshot
        var merged = cloud ?? snapshot
        merged.selectedSource = selectedSource
        if let forecast {
            merged.forecastUpdatedAt = Date()
            merged.providers = forecast.providers
            merged.resetChancePercent = forecast.selectedPercent
            merged.resetAnnounced = forecast.resetAnnounced
            merged.announcementID = forecast.announcementID
            merged.announcementText = forecast.announcementText
            merged.announcementDate = forecast.announcementDate
            merged.announcementExpectedAt = forecast.announcementExpectedAt
            merged.announcementURL = forecast.announcementURL
            merged.lastBlessingAt = forecast.lastBlessingAt
            merged.tiboPosts = Self.mergePosts(forecast.tiboPosts, merged.tiboPosts ?? [])
        }
        if let resetAt = merged.resetAt {
            let start = resetAt.addingTimeInterval(-7 * 86_400)
            merged.weekElapsedPercent = Self.progress(from: start, to: resetAt, now: Date())
        }

        snapshot = merged
        SharedSnapshotStore.save(merged)
        WidgetCenter.shared.reloadAllTimelines()
        await ResetLiveActivityManager.shared.sync(with: merged)
        await NotificationManager.evaluate(merged, previous: previousSnapshot, preferences: .load())
        state = cloud == nil && forecast == nil
            ? .partial("Cached")
            : (cloud == nil ? .partial("Reset data live · Mac pending") : .current)
        AppDelegate.scheduleRefresh()
    }

    private func cloudSnapshot() async -> QuotaSnapshot? {
        try? await CloudSnapshotService.fetch()
    }

    private static func progress(from start: Date, to end: Date, now: Date) -> Double {
        guard end > start else { return now >= end ? 100 : 0 }
        return max(0, min(100, now.timeIntervalSince(start) / end.timeIntervalSince(start) * 100))
    }

    fileprivate static func mergePosts(_ first: [QuotaTiboPost], _ second: [QuotaTiboPost]) -> [QuotaTiboPost] {
        var byID: [String: QuotaTiboPost] = [:]
        for post in first + second {
            let previous = byID[post.id]
            let oldDetail = (previous?.text.count ?? 0) + (previous?.inReplyTo?.count ?? 0)
            let newDetail = post.text.count + (post.inReplyTo?.count ?? 0)
            if previous == nil || newDetail > oldDetail { byID[post.id] = post }
        }
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        return byID.values
            .filter { ($0.date ?? .distantPast) >= cutoff }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var refreshIdentifier: String {
        "\(Bundle.main.bundleIdentifier ?? "com.example.quotaglance.mobile").refresh"
    }

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
        NotificationCenter.default.post(name: .quotaCloudChanged, object: nil)
        completionHandler(.newData)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        scheduleRefresh()
        let work = Task {
            let selected = ResetSource(
                rawValue: UserDefaults.standard.string(forKey: "QuotaGlance.mobile.resetSource") ?? ""
            ) ?? .average
            guard let forecast = try? await ResetProviderService.fetch(selected: selected) else {
                task.setTaskCompleted(success: false)
                return
            }
            var snapshot = (try? await CloudSnapshotService.fetch()) ?? SharedSnapshotStore.load()
            let previousSnapshot = SharedSnapshotStore.load()
            snapshot.forecastUpdatedAt = Date()
            snapshot.selectedSource = selected
            snapshot.providers = forecast.providers
            snapshot.resetChancePercent = forecast.selectedPercent
            snapshot.resetAnnounced = forecast.resetAnnounced
            snapshot.announcementID = forecast.announcementID
            snapshot.announcementText = forecast.announcementText
            snapshot.announcementDate = forecast.announcementDate
            snapshot.announcementExpectedAt = forecast.announcementExpectedAt
            snapshot.announcementURL = forecast.announcementURL
            snapshot.lastBlessingAt = forecast.lastBlessingAt
            snapshot.tiboPosts = DashboardStore.mergePosts(forecast.tiboPosts, snapshot.tiboPosts ?? [])
            SharedSnapshotStore.save(snapshot)
            await ResetLiveActivityManager.shared.sync(with: snapshot)
            await NotificationManager.evaluate(snapshot, previous: previousSnapshot, preferences: .load())
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
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
            snapshot.resetAnnounced,
            let expectedAt = snapshot.announcementExpectedAt,
            expectedAt > now
        else {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        let announcementID = snapshot.announcementID ?? "reset-\(Int(expectedAt.timeIntervalSince1970))"
        let state = ResetCountdownAttributes.ContentState(
            expectedAt: expectedAt,
            sourceLabel: snapshot.selectedSource.name
        )
        let content = ActivityContent(
            state: state,
            staleDate: expectedAt.addingTimeInterval(10 * 60)
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
