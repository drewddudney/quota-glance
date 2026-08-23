import SwiftUI

@main
struct QuotaGlanceMobileApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = DashboardStore()

    var body: some Scene {
        WindowGroup {
            DashboardView(store: store)
                .task { await store.start() }
                .onReceive(NotificationCenter.default.publisher(for: .quotaCloudChanged)) { _ in
                    Task { await store.refresh() }
                }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task { await store.refresh() }
            }
        }
    }
}
