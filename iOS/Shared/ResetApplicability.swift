import Foundation

struct ResetApplicabilityResponse: Codable, Equatable, Sendable {
    let announcementID: String
    let applies: Bool
    let answeredAt: Date
}

enum ResetApplicability {
    static let cloudKey = "QuotaGlance.resetApplicability.v1"
    private static let localKey = "QuotaGlance.resetApplicability.local.v1"

    static func requiresConfirmation(_ text: String) -> Bool {
        let value = text.lowercased()
        let conditionalPhrases = [
            "some plus", "some business", "some users", "selected users",
            "eligible", "eligibility", "if you ", "if your ", "if you've ",
            "if you have ", "don't have access", "do not have access",
            "won't yet get access", "without access", "accounts that"
        ]
        return conditionalPhrases.contains { value.contains($0) }
    }

    static func load() -> ResetApplicabilityResponse? {
        let local = UserDefaults.standard.data(forKey: localKey).flatMap(decode)
        let cloud = NSUbiquitousKeyValueStore.default.data(forKey: cloudKey).flatMap(decode)
        let latest = [local, cloud].compactMap { $0 }.max { $0.answeredAt < $1.answeredAt }
        if let latest, latest != local, let data = try? encoder.encode(latest) {
            UserDefaults.standard.set(data, forKey: localKey)
        }
        return latest
    }

    static func save(announcementID: String, applies: Bool, at date: Date = Date()) {
        let response = ResetApplicabilityResponse(
            announcementID: announcementID,
            applies: applies,
            answeredAt: date
        )
        guard let data = try? encoder.encode(response) else { return }
        UserDefaults.standard.set(data, forKey: localKey)
        let cloud = NSUbiquitousKeyValueStore.default
        cloud.set(data, forKey: cloudKey)
        cloud.synchronize()
    }

    private static func decode(_ data: Data) -> ResetApplicabilityResponse? {
        try? decoder.decode(ResetApplicabilityResponse.self, from: data)
    }

    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .secondsSince1970
        return value
    }()

    private static let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .secondsSince1970
        return value
    }()
}
