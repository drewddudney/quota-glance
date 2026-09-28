import CloudKit
import Foundation
import OSLog
import Security

struct MobileProviderReading: Codable, Sendable {
    let source: String
    let percent: Double?
    let updatedAt: Date?
}

struct MobileUsagePoint: Codable, Sendable {
    let date: Date
    let usedPercent: Double
    let tokens: Int64?
}

struct MobileTokenPace: Codable, Sendable {
    let fiveMinutes: Int64
    let oneHour: Int64
    let twelveHours: Int64
    let twentyFourHours: Int64
    let sinceReset: Int64
}

struct MobileUsageIntelligence: Codable, Sendable {
    let apiEquivalentUSD: Double
    let quotaWeightedUSD: Double
    let gpt6CodexCredits: Double?
    let pricingCoverage: Double
    let speedCoverage: Double
    let fastShare: Double
    let eventCount: Int
    let ledgerBytes: Int64
    let topModel: String?
    let totalTokens: Int64?
    let cacheHitRate: Double?
    let costTimeline: [MobileCostPoint]?
}

struct MobileCostPoint: Codable, Sendable {
    let date: Date
    let apiEquivalentUSD: Double
}

struct MobileWeeklyArchivePoint: Codable, Sendable {
    let date: Date
    let usedPercent: Double
    let apiEquivalentUSD: Double?
}

struct MobileWeeklyArchive: Codable, Sendable {
    let windowStart: Date
    let resetAt: Date
    let finalUsedPercent: Double
    let totalTokens: Int64?
    let apiEquivalentUSD: Double?
    let cacheHitRate: Double?
    let fastShare: Double?
    let topModel: String?
    let points: [MobileWeeklyArchivePoint]
}

struct MobileSecondaryQuota: Codable, Sendable {
    let usedPercent: Double
    let resetAt: Date
    let windowDurationMinutes: Double
}

struct MobileQuotaWindow: Codable, Sendable {
    let id: String
    let label: String
    let scope: String
    let usedPercent: Double
    let resetAt: Date
    let windowDurationMinutes: Double
}

struct MobileCreditSummary: Codable, Sendable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

struct MobileResetCredit: Codable, Sendable {
    let id: String
    let resetType: String
    let status: String
    let expiresAt: Date?
    let description: String?
}

struct MobileCodexTask: Codable, Sendable {
    let id: String
    let name: String
    let state: String
    let source: String
    let updatedAt: Date
}

struct MobileTiboPost: Codable, Sendable {
    let id: String
    let date: Date?
    let text: String
    let inReplyTo: String?
    let url: URL?
    let isResetOriented: Bool
}

struct MobileQuotaSnapshot: Codable, Sendable {
    var claude: ClaudeQuotaSnapshot? = nil
    var usageUpdatedAt: Date? = nil
    let capturedAt: Date
    let weekElapsedPercent: Double?
    let usagePercent: Double?
    let resetChancePercent: Double?
    let resetAt: Date?
    let usageWindowStart: Date?
    let windowDurationMinutes: Double?
    let weeklyTokens: Int64?
    let planName: String?
    let renewalDate: Date?
    let selectedSource: String
    let selectedSources: [String]?
    let providers: [MobileProviderReading]
    let resetAnnounced: Bool
    let announcementID: String?
    let announcementText: String?
    let announcementDate: Date?
    let announcementExpectedAt: Date?
    let announcementRequiresApplicabilityConfirmation: Bool?
    let announcementAppliesToAccount: Bool?
    let announcementApplicabilityAnsweredAt: Date?
    let resetCompletedAt: Date?
    let announcementURL: URL?
    let lastBlessingAt: Date?
    let resetCreditExpiresAt: Date?
    let estimatedRunoutAt: Date?
    let paceWindowLabel: String?
    let forecastUpdatedAt: Date?
    let usageHistory: [MobileUsagePoint]?
    let tokenPace: MobileTokenPace?
    let usageIntelligence: MobileUsageIntelligence?
    let secondaryQuota: MobileSecondaryQuota?
    let quotaInventory: [MobileQuotaWindow]?
    let creditSummary: MobileCreditSummary?
    let resetCredits: [MobileResetCredit]?
    let activeTasks: [MobileCodexTask]?
    let weeklyArchives: [MobileWeeklyArchive]?
    let tiboPosts: [MobileTiboPost]?
}

actor MobileSnapshotPublisher {
    static let shared = MobileSnapshotPublisher()

    private static let containerIdentifier = "iCloud.com.example.quotaglance"
    private static let keyValueSnapshotKey = "QuotaGlance.snapshot.v1"
    private static let recordType = "QuotaGlanceSnapshot"
    private static let recordID = CKRecord.ID(recordName: "current-v1")
    private static let logger = Logger(subsystem: "com.example.quotaglance", category: "PhoneSync")
    private static let lastAttemptKey = "mobileSnapshotLastAttemptAt"
    private static let lastSuccessKey = "mobileSnapshotLastSuccessAt"
    private static let lastErrorKey = "mobileSnapshotLastError"
    private var pendingTask: Task<Void, Never>?

    func schedule(_ snapshot: MobileQuotaSnapshot) {
        pendingTask?.cancel()
        pendingTask = Task {
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            await publish(snapshot)
        }
    }

    private func publish(_ snapshot: MobileQuotaSnapshot) async {
        UserDefaults.standard.set(Date(), forKey: Self.lastAttemptKey)
        guard Self.hasICloudEntitlement else {
            recordFailure("The installed Mac app is missing its iCloud entitlement.")
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let payload = try? encoder.encode(snapshot) else {
            recordFailure("The phone snapshot could not be encoded.")
            return
        }

        let keyValueStore = NSUbiquitousKeyValueStore.default
        keyValueStore.set(payload, forKey: Self.keyValueSnapshotKey)
        keyValueStore.synchronize()

        do {
            let container = CKContainer(identifier: Self.containerIdentifier)
            let database = container.privateCloudDatabase
            let record: CKRecord
            do {
                let current = try await database.record(for: Self.recordID)
                record = current
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: Self.recordType, recordID: Self.recordID)
            }
            record["payload"] = payload as CKRecordValue
            record["updatedAt"] = snapshot.capturedAt as CKRecordValue
            _ = try await database.save(record)
            UserDefaults.standard.set(Date(), forKey: Self.lastSuccessKey)
            UserDefaults.standard.removeObject(forKey: Self.lastErrorKey)
            Self.logger.notice("Phone snapshot saved to private CloudKit")
            await PrivateLiveActivityRelay.shared.sync(snapshot)
        } catch {
            recordFailure(error.localizedDescription)
        }
    }

    private func recordFailure(_ message: String) {
        UserDefaults.standard.set(message, forKey: Self.lastErrorKey)
        Self.logger.error("Phone snapshot failed: \(message, privacy: .public)")
    }

    private static var hasICloudEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-container-identifiers" as CFString,
                nil
              ) as? [String]
        else { return false }
        return value.contains(containerIdentifier)
    }
}
