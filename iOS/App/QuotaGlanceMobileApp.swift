import SwiftUI

@main
struct QuotaGlanceMobileApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = DashboardStore()

    var body: some Scene {
        WindowGroup {
            DashboardView(store: store)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await store.start()
                    await store.runForegroundSyncLoop()
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
}
