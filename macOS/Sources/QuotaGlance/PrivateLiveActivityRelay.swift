import CryptoKit
import Foundation
import OSLog
import Security

struct PrivateLiveActivityRegistration: Codable, Equatable, Sendable {
    let token: String
    let activityID: String
    let sessionID: String
    let environment: String
    let updatedAt: Date
}

struct PrivateLiveActivityPushToStartRegistration: Codable, Equatable, Sendable {
    let token: String
    let environment: String
    let updatedAt: Date
}

enum PrivateLiveActivitySettings {
    static let enabledKey = "QuotaGlance.privateLiveActivity.enabled"
    static let keyIDKey = "QuotaGlance.privateLiveActivity.keyID"
    static let teamIDKey = "QuotaGlance.privateLiveActivity.teamID"
    static let lastStatusKey = "QuotaGlance.privateLiveActivity.lastStatus"
    static let lastSuccessKey = "QuotaGlance.privateLiveActivity.lastSuccessAt"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var keyID: String? { nonempty(UserDefaults.standard.string(forKey: keyIDKey)) }
    static var teamID: String? { nonempty(UserDefaults.standard.string(forKey: teamIDKey)) }
    static var isConfigured: Bool { keyID != nil && teamID != nil && PrivateAPNsKeychain.load() != nil }

    static var statusText: String {
        if !isConfigured { return "Not configured" }
        if !isEnabled { return "Configured · Off" }
        return UserDefaults.standard.string(forKey: lastStatusKey) ?? "Configured · Waiting for iPhone"
    }

    private static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum PrivateAPNsKeychain {
    private static let service = "com.drewdudney.quotaglance.private-apns"
    private static let account = "live-activity-signing-key"

    static func save(_ pem: String) throws {
        guard (try? P256.Signing.PrivateKey(pemRepresentation: pem)) != nil else {
            throw PrivateAPNsError.invalidKey
        }
        let data = Data(pem.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            let result = SecItemAdd(insert as CFDictionary, nil)
            guard result == errSecSuccess else { throw PrivateAPNsError.keychain(result) }
        } else if update != errSecSuccess {
            throw PrivateAPNsError.keychain(update)
        }
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)
    }
}

enum PrivateAPNsError: LocalizedError {
    case invalidKey
    case keychain(OSStatus)
    case missingConfiguration
    case rejected(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "The selected file is not a valid APNs .p8 signing key."
        case .keychain(let status): return "Keychain could not save the APNs key (\(status))."
        case .missingConfiguration: return "The private APNs feed is not configured."
        case .rejected(let status, let reason): return "APNs rejected the update (\(status): \(reason))."
        }
    }
}

actor PrivateLiveActivityRelay {
    static let shared = PrivateLiveActivityRelay()

    private static let registrationKey = "QuotaGlance.liveActivity.codex.registration.v1"
    private static let pushToStartKey = "QuotaGlance.liveActivity.codex.pushToStart.v1"
    private static let topic = "com.drewdudney.quotaglance.mobile.push-type.liveactivity"
    private static let logger = Logger(subsystem: "com.drewdudney.quotaglance", category: "PrivateLiveFeed")
    private var cachedJWT: (value: String, createdAt: Date)?
    private var lastSentFingerprint: String?
    private var projectionTask: Task<Void, Never>?
    private var lastStartAttempt: (sessionID: String, date: Date)?

    func forceNextUpdate() {
        lastSentFingerprint = nil
    }

    func sync(_ snapshot: MobileQuotaSnapshot, force: Bool = false) async {
        guard PrivateLiveActivitySettings.isEnabled else { return }
        projectionTask?.cancel()
        projectionTask = nil
        await push(snapshot, force: force)

        guard PrivateLiveActivityUpdate(snapshot: snapshot, now: Date()).isActive else { return }
        projectionTask = Task { [weak self] in
            let expiresAt = snapshot.capturedAt.addingTimeInterval(10 * 60)
            while !Task.isCancelled, Date() < expiresAt {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, Date() < expiresAt else { return }
                await self?.push(snapshot, force: true)
            }
        }
    }

    private func push(_ snapshot: MobileQuotaSnapshot, force: Bool) async {
        do {
            let update = PrivateLiveActivityUpdate(snapshot: snapshot, now: Date())
            if let registration = Self.registration(),
               Date().timeIntervalSince(registration.updatedAt) < 12 * 60 * 60 {
                let sessionMatches = registration.sessionID == update.sessionID
                let payload = sessionMatches ? update.payload : update.endPayload
                let fingerprint = (sessionMatches ? update.fingerprint : "end-old|\(registration.sessionID)") + registration.token
                guard force || fingerprint != lastSentFingerprint else { return }
                try await send(payload, token: registration.token, environment: registration.environment)
                lastSentFingerprint = fingerprint
                UserDefaults.standard.set(Date(), forKey: PrivateLiveActivitySettings.lastSuccessKey)
                if !update.isActive || !sessionMatches {
                    Self.clearRegistration()
                }
                if !update.isActive {
                    recordStatus("Waiting for active Codex work")
                    return
                }
                if sessionMatches {
                    recordStatus("Live · updated just now")
                    return
                }
            }

            guard update.isActive else {
                recordStatus("Waiting for active Codex work")
                return
            }
            guard let startRegistration = Self.pushToStartRegistration(),
                  Date().timeIntervalSince(startRegistration.updatedAt) < 30 * 86_400
            else {
                recordStatus("Waiting for iPhone start token · open build 21 once")
                return
            }
            if let lastStartAttempt,
               lastStartAttempt.sessionID == update.sessionID,
               Date().timeIntervalSince(lastStartAttempt.date) < 2 * 60 {
                recordStatus("Starting Live Activity…")
                return
            }
            try await send(
                update.startPayload,
                token: startRegistration.token,
                environment: startRegistration.environment
            )
            lastStartAttempt = (update.sessionID, Date())
            UserDefaults.standard.set(Date(), forKey: PrivateLiveActivitySettings.lastSuccessKey)
            recordStatus("Starting Live Activity…")
        } catch {
            recordStatus("Error · \(error.localizedDescription)")
            Self.logger.error("Private APNs update failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func send(
        _ payload: APNsLiveActivityPayload,
        token: String,
        environment: String
    ) async throws {
        guard let keyID = PrivateLiveActivitySettings.keyID,
              let teamID = PrivateLiveActivitySettings.teamID,
              let pem = PrivateAPNsKeychain.load()
        else { throw PrivateAPNsError.missingConfiguration }
        let host = environment == "development" ? "api.sandbox.push.apple.com" : "api.push.apple.com"
        guard let url = URL(string: "https://\(host)/3/device/\(token)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder.apns.encode(payload)
        request.setValue("bearer \(try jwt(keyID: keyID, teamID: teamID, pem: pem))", forHTTPHeaderField: "authorization")
        request.setValue(Self.topic, forHTTPHeaderField: "apns-topic")
        request.setValue("liveactivity", forHTTPHeaderField: "apns-push-type")
        request.setValue("10", forHTTPHeaderField: "apns-priority")
        request.setValue("0", forHTTPHeaderField: "apns-expiration")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else {
            let reason = (try? JSONDecoder().decode(APNsFailure.self, from: data).reason)
                ?? String(data: data, encoding: .utf8) ?? "Unknown"
            if http.statusCode == 410 { NSUbiquitousKeyValueStore.default.removeObject(forKey: Self.registrationKey) }
            throw PrivateAPNsError.rejected(http.statusCode, reason)
        }
    }

    private func jwt(keyID: String, teamID: String, pem: String) throws -> String {
        let now = Date()
        if let cachedJWT, now.timeIntervalSince(cachedJWT.createdAt) < 50 * 60 { return cachedJWT.value }
        guard let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else { throw PrivateAPNsError.invalidKey }
        let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID])
        let claims = try JSONSerialization.data(withJSONObject: ["iss": teamID, "iat": Int(now.timeIntervalSince1970)])
        let unsigned = "\(header.base64URL).\(claims.base64URL)"
        let signature = try key.signature(for: Data(unsigned.utf8)).rawRepresentation.base64URL
        let value = "\(unsigned).\(signature)"
        cachedJWT = (value, now)
        return value
    }

    private func recordStatus(_ value: String) {
        UserDefaults.standard.set(value, forKey: PrivateLiveActivitySettings.lastStatusKey)
    }

    private static func registration() -> PrivateLiveActivityRegistration? {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        guard let data = store.data(forKey: registrationKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(PrivateLiveActivityRegistration.self, from: data)
    }

    private static func clearRegistration() {
        let store = NSUbiquitousKeyValueStore.default
        store.removeObject(forKey: registrationKey)
        store.synchronize()
    }

    private static func pushToStartRegistration() -> PrivateLiveActivityPushToStartRegistration? {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        guard let data = store.data(forKey: pushToStartKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(PrivateLiveActivityPushToStartRegistration.self, from: data)
    }
}

struct PrivateLiveActivityUpdate {
    let payload: APNsLiveActivityPayload
    let fingerprint: String
    let isActive: Bool
    let sessionID: String

    init(snapshot: MobileQuotaSnapshot, now: Date) {
        let authoritative = max(0, min(100, snapshot.usagePercent ?? 0))
        let tokensPerMinute = max(0, (snapshot.tokenPace?.fiveMinutes ?? 0) / 5)
        let percentPerMinute = Self.percentPerMinute(snapshot: snapshot, tokensPerMinute: tokensPerMinute)
        let estimated = Self.estimatedPercent(snapshot: snapshot, authoritative: authoritative, percentPerMinute: percentPerMinute, now: now)
        let anchor = snapshot.usageWindowStart ?? snapshot.capturedAt
        // Keep one Live Activity for the whole quota window. Task ordering can change
        // while several Codex turns run, but that must not restart the activity.
        sessionID = "usage-\(Int(anchor.timeIntervalSince1970))"
        let task = snapshot.activeTasks?.first
        // A recent burn rate can remain non-zero for several minutes after the last
        // Codex turn ends. Only an actual running task should keep the activity alive.
        isActive = now.timeIntervalSince(snapshot.capturedAt) <= 10 * 60 && task != nil
        let state = APNsCodexContentState(
            taskName: (snapshot.activeTasks?.count ?? 0) > 1
                ? "\(snapshot.activeTasks?.count ?? 0) Codex sessions active"
                : task?.name ?? "Codex is working",
            usedPercent: estimated,
            totalTokens: snapshot.usageIntelligence?.totalTokens ?? snapshot.weeklyTokens ?? 0,
            tokensPerMinute: tokensPerMinute,
            percentPerMinute: percentPerMinute,
            updatedAt: now
        )
        payload = APNsLiveActivityPayload(aps: .init(
            timestamp: Int(now.timeIntervalSince1970), event: isActive ? "update" : "end",
            contentState: state, staleDate: Int(now.addingTimeInterval(10 * 60).timeIntervalSince1970),
            dismissalDate: isActive ? nil : Int(now.timeIntervalSince1970)
        ))
        fingerprint = [isActive ? "update" : "end", task?.id ?? "none", String(format: "%.3f", estimated), String(tokensPerMinute), String(state.totalTokens)].joined(separator: "|")
    }

    var startPayload: APNsLiveActivityPayload {
        var aps = payload.aps
        aps.event = "start"
        aps.dismissalDate = nil
        aps.attributesType = "CodexSessionActivityAttributes"
        aps.attributes = APNsCodexAttributes(sessionID: sessionID)
        aps.alert = APNsLiveActivityAlert(
            title: "Codex is working",
            body: "Live token usage is now updating."
        )
        aps.inputPushToken = 1
        return APNsLiveActivityPayload(aps: aps)
    }

    var endPayload: APNsLiveActivityPayload {
        var aps = payload.aps
        aps.event = "end"
        aps.dismissalDate = aps.timestamp
        aps.attributesType = nil
        aps.attributes = nil
        aps.alert = nil
        aps.inputPushToken = nil
        return APNsLiveActivityPayload(aps: aps)
    }

    private static func percentPerMinute(snapshot: MobileQuotaSnapshot, tokensPerMinute: Int64) -> Double {
        guard tokensPerMinute > 0, let current = snapshot.usagePercent, current > 0 else { return 0 }
        let points = (snapshot.usageHistory ?? []).compactMap { point -> (Double, Int64)? in
            guard let tokens = point.tokens else { return nil }
            return (point.usedPercent, tokens)
        }
        var anchors: [(Double, Int64)] = []
        var highWater = -Double.infinity
        for point in points where point.0 > highWater + 0.001 { anchors.append(point); highWater = point.0 }
        var ratios: [Double] = []
        for pair in zip(anchors, anchors.dropFirst()) {
            let percentDelta = pair.1.0 - pair.0.0
            let tokenDelta = pair.1.1 - pair.0.1
            guard percentDelta > 0, percentDelta <= 20, tokenDelta > 0 else { continue }
            ratios.append(Double(tokenDelta) / percentDelta)
        }
        let calibrated: Double? = {
            let recent = Array(ratios.suffix(8)).sorted()
            guard !recent.isEmpty else { return nil }
            let middle = recent.count / 2
            return recent.count.isMultiple(of: 2) ? (recent[middle - 1] + recent[middle]) / 2 : recent[middle]
        }()
        let baseline = points.first?.1 ?? 0
        let observed = max(0, (snapshot.usageIntelligence?.totalTokens ?? snapshot.weeklyTokens ?? 0) - baseline)
        let wholeWindow = observed > 0 ? Double(observed) / current : nil
        guard let denominator = calibrated ?? wholeWindow, denominator > 0 else { return 0 }
        return min(5, max(0, Double(tokensPerMinute) / denominator))
    }

    private static func estimatedPercent(snapshot: MobileQuotaSnapshot, authoritative: Double, percentPerMinute: Double, now: Date) -> Double {
        guard percentPerMinute > 0 else { return authoritative }
        let points = (snapshot.usageHistory ?? []).filter { $0.date <= snapshot.capturedAt }.sorted { $0.date < $1.date }
        guard let latest = points.last, abs(latest.usedPercent - authoritative) < 0.001 else { return authoritative }
        var threshold = latest.date
        for point in points.dropLast().reversed() {
            guard abs(point.usedPercent - authoritative) < 0.001 else { break }
            threshold = point.date
        }
        let projectionDate = min(now, snapshot.capturedAt.addingTimeInterval(10 * 60))
        let elapsedMinutes = max(0, projectionDate.timeIntervalSince(threshold) / 60)
        return min(authoritative + 0.999, authoritative + percentPerMinute * elapsedMinutes)
    }
}

struct APNsLiveActivityPayload: Encodable {
    struct APS: Encodable {
        let timestamp: Int
        var event: String
        let contentState: APNsCodexContentState
        let staleDate: Int
        var dismissalDate: Int?
        var attributesType: String? = nil
        var attributes: APNsCodexAttributes? = nil
        var alert: APNsLiveActivityAlert? = nil
        var inputPushToken: Int? = nil
        enum CodingKeys: String, CodingKey {
            case timestamp, event
            case contentState = "content-state"
            case staleDate = "stale-date"
            case dismissalDate = "dismissal-date"
            case attributesType = "attributes-type"
            case attributes, alert
            case inputPushToken = "input-push-token"
        }
    }
    let aps: APS
}

struct APNsCodexAttributes: Encodable { let sessionID: String }
struct APNsLiveActivityAlert: Encodable { let title: String; let body: String }

struct APNsCodexContentState: Encodable {
    let taskName: String
    let usedPercent: Double
    let totalTokens: Int64
    let tokensPerMinute: Int64
    let percentPerMinute: Double?
    let updatedAt: Date
}

private struct APNsFailure: Decodable { let reason: String }

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private extension JSONEncoder {
    // ActivityKit decodes content-state with Codable's defaults. In
    // particular, Date must use the default reference-date representation.
    static let apns = JSONEncoder()
}
