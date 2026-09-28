import SwiftUI

@main
struct QuotaGlanceMobileApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = DashboardStore()

    var body: some Scene {
        WindowGroup {
            rootContent
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await store.start()
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--quota-preview-live-system") {
                        var sample = store.snapshot
                        let args = ProcessInfo.processInfo.arguments
                        if args.contains("--quota-preview-live-codex") { sample.recentProviderActivity = ["codex": .now] }
                        if args.contains("--quota-preview-live-claude") { sample.recentProviderActivity = ["claude": .now] }
                        await ProviderUsageActivityManager.shared.sync(snapshot: sample)
                    }
#endif
                    await store.runForegroundSyncLoop()
                }
                .onReceive(NotificationCenter.default.publisher(for: .directProviderUsageChanged)) { _ in
                    Task { await store.refreshPhoneUsage() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .quotaCloudChanged)) { _ in
                    Task { await store.refreshFromSharedSnapshotIfNew() }
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSUbiquitousKeyValueStore.didChangeExternallyNotification
                    )
                ) { notification in
                    let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey]
                        as? [String]
                    if changedKeys == nil
                        || changedKeys?.contains(ResetApplicability.cloudKey) == true {
                        Task { await store.refreshResetApplicabilityFromCloud() }
                    }
                    if changedKeys == nil
                        || changedKeys?.contains(CloudSnapshotService.keyValueSnapshotKey) == true {
                        Task { await store.refreshCloudSnapshotIfNew() }
                    }
                }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--quota-preview-widgets")
            || ProcessInfo.processInfo.arguments.contains("--quota-preview-lock-widgets")
            || ProcessInfo.processInfo.arguments.contains("--quota-preview-live-activity") {
            WidgetPreviewGallery(snapshot: ProcessInfo.processInfo.arguments.contains("--quota-preview-empty") ? .empty : store.snapshot)
        } else {
            DashboardView(store: store)
        }
#else
        DashboardView(store: store)
#endif
    }

}
