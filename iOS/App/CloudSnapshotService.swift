import CloudKit
import Foundation

enum CloudSnapshotService {
    static var containerIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "QuotaGlanceCloudContainerIdentifier") as? String
            ?? "iCloud.com.example.quotaglance"
    }
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

    private static func keyValueSnapshot() -> QuotaSnapshot? {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
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
