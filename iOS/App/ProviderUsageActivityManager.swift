import ActivityKit
import Foundation
import UIKit

@MainActor
final class ProviderUsageActivityManager: ObservableObject {
    static let shared = ProviderUsageActivityManager()
    private static let enabledKey = "QuotaGlance.mobile.automaticUsageActivity"
    @Published private(set) var isRunning = !Activity<ProviderUsageActivityAttributes>.activities.isEmpty
    @Published private(set) var isEnabled = UserDefaults.standard.object(forKey: enabledKey) == nil || UserDefaults.standard.bool(forKey: enabledKey)
    @Published private(set) var message: String?
    private var lastStartedSignal: Date?

    func setEnabled(_ enabled: Bool, snapshot: QuotaSnapshot) async {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            lastStartedSignal = nil
            await sync(snapshot: snapshot)
        } else { await stop() }
    }

    func sync(snapshot: QuotaSnapshot, now: Date = Date()) async {
        guard isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else {
            await stop()
            return
        }
        let providers = ProviderActivityDetector.activeProviders(in: snapshot, now: now)
        let state = ProviderUsageActivityAttributes.state(snapshot: snapshot, providers: providers, now: now)
        let activities = Activity<ProviderUsageActivityAttributes>.activities
        isRunning = !activities.isEmpty
        guard !state.readings.isEmpty else {
            await stop()
            return
        }
        let freshUntil = providers.compactMap { snapshot.recentProviderActivity?[$0.rawValue]?.addingTimeInterval(ProviderActivityDetector.quietInterval) }.min()
        let content = ActivityContent(state: state, staleDate: freshUntil)
        if let current = activities.first {
            if current.content.state != state || current.content.staleDate != freshUntil { await current.update(content) }
            for duplicate in activities.dropFirst() { await duplicate.end(nil, dismissalPolicy: .immediate) }
            return
        }
        // iOS requires a foreground start unless a push service starts it.
        // A swipe-to-dismiss is respected until genuinely new usage is seen.
        let signal = providers.compactMap { snapshot.recentProviderActivity?[$0.rawValue] }.max()
        guard UIApplication.shared.applicationState == .active,
              let signal, lastStartedSignal.map({ signal > $0 }) ?? true else { return }
        do {
            _ = try Activity.request(attributes: ProviderUsageActivityAttributes(startedAt: now), content: content, pushType: nil)
            lastStartedSignal = signal
            isRunning = true
            message = nil
        } catch {
            message = "Live Activity unavailable. Check Quota Glance in iPhone Settings."
        }
    }

    func stop() async {
        for activity in Activity<ProviderUsageActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        isRunning = false
        message = nil
    }
}
