import CloudKit
import ActivityKit
import Foundation

enum CloudSnapshotService {
    static let containerIdentifier = "iCloud.com.drewdudney.quotaglance"
    static let recordType = "QuotaGlanceSnapshot"
    static let recordID = CKRecord.ID(recordName: "current-v1")
    static let keyValueSnapshotKey = "QuotaGlance.snapshot.v1"

    static func fetch() async throws -> QuotaSnapshot? {
#if targetEnvironment(simulator)
        // The simulator build used for automated UI/tests is intentionally
        // unsigned, so it cannot own an iCloud KVS container. Public reset
        // data still exercises the complete dashboard there.
        return nil
#else
        let keyValue = keyValueSnapshot()
        do {
            let record = try await database.record(for: recordID)
            guard let payload = record["payload"] as? Data else { return nil }
            let cloud = try decoder.decode(QuotaSnapshot.self, from: payload)
            guard let keyValue else { return cloud }
            return cloud.capturedAt >= keyValue.capturedAt ? cloud : keyValue
        } catch let error as CKError where error.code == .unknownItem {
            return keyValue
        } catch {
            if let keyValue { return keyValue }
            throw error
        }
#endif
    }

    /// The Mac mirrors every authoritative snapshot into private iCloud KVS.
    /// Reads the KVS process cache. External-change notifications keep it
    /// current, so forcing a synchronize operation on every poll is unnecessary.
    static func keyValueSnapshot() -> QuotaSnapshot? {
        let store = NSUbiquitousKeyValueStore.default
        guard let payload = store.data(forKey: keyValueSnapshotKey) else { return nil }
        return try? decoder.decode(QuotaSnapshot.self, from: payload)
    }

    static func installSubscriptionIfNeeded() async {
#if !targetEnvironment(simulator)
        let identifier = "quota-glance-snapshot-updates-v1"
        if (try? await database.subscription(for: identifier)) != nil { return }
        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: identifier,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let notification = CKSubscription.NotificationInfo()
        notification.shouldSendContentAvailable = true
        notification.desiredKeys = ["updatedAt"]
        subscription.notificationInfo = notification
        _ = try? await database.save(subscription)
#endif
    }

    private static let container = CKContainer(identifier: containerIdentifier)
    private static var database: CKDatabase { container.privateCloudDatabase }
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}

/// Publishes only the ephemeral token for the currently running Codex Live
/// Activity. iCloud KVS is already private to the signed-in Apple account and
/// avoids adding a public backend (or a new production CloudKit schema).
actor LiveActivityPushTokenPublisher {
    static let shared = LiveActivityPushTokenPublisher()

    private static let registrationKey = "QuotaGlance.liveActivity.codex.registration.v1"
    private static let pushToStartKey = "QuotaGlance.liveActivity.codex.pushToStart.v1"
    private var observers: [String: Task<Void, Never>] = [:]
    private var pushToStartObserver: Task<Void, Never>?
    private var activityObserver: Task<Void, Never>?

    func start() {
        if #available(iOS 17.2, *) {
            if let token = Activity<CodexSessionActivityAttributes>.pushToStartToken {
                publishPushToStart(token)
            }
            if pushToStartObserver == nil {
                pushToStartObserver = Task { [weak self] in
                    for await token in Activity<CodexSessionActivityAttributes>.pushToStartTokenUpdates {
                        guard !Task.isCancelled else { return }
                        await self?.publishPushToStart(token)
                    }
                }
            }
        }
        for activity in Activity<CodexSessionActivityAttributes>.activities {
            observe(activity)
        }
        if activityObserver == nil {
            activityObserver = Task { [weak self] in
                for await activity in Activity<CodexSessionActivityAttributes>.activityUpdates {
                    guard !Task.isCancelled else { return }
                    await self?.observe(activity)
                }
            }
        }
    }

    func observe(_ activity: Activity<CodexSessionActivityAttributes>) {
        guard observers[activity.id] == nil else { return }

        if let token = activity.pushToken {
            publish(token, for: activity)
        }
        observers[activity.id] = Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                guard !Task.isCancelled else { return }
                await self?.publish(token, for: activity)
            }
        }
    }

    func stopObserving(activityID: String) {
        observers.removeValue(forKey: activityID)?.cancel()
    }

    private func publish(
        _ token: Data,
        for activity: Activity<CodexSessionActivityAttributes>
    ) {
        let registration = LiveActivityPushRegistration(
            token: token.map { String(format: "%02x", $0) }.joined(),
            activityID: activity.id,
            sessionID: activity.attributes.sessionID,
            environment: Self.environment,
            updatedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(registration) else { return }
        let store = NSUbiquitousKeyValueStore.default
        store.set(data, forKey: Self.registrationKey)
        store.synchronize()
    }

    private func publishPushToStart(_ token: Data) {
        let registration = LiveActivityPushToStartRegistration(
            token: token.map { String(format: "%02x", $0) }.joined(),
            environment: Self.environment,
            updatedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(registration) else { return }
        let store = NSUbiquitousKeyValueStore.default
        store.set(data, forKey: Self.pushToStartKey)
        store.synchronize()
    }

    private static var environment: String {
#if DEBUG
        "development"
#else
        "production"
#endif
    }
}

struct LiveActivityPushToStartRegistration: Codable, Equatable, Sendable {
    let token: String
    let environment: String
    let updatedAt: Date
}

struct LiveActivityPushRegistration: Codable, Equatable, Sendable {
    let token: String
    let activityID: String
    let sessionID: String
    let environment: String
    let updatedAt: Date
}
