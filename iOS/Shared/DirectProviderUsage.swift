import CryptoKit
import Foundation

enum DirectUsageProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex, claude

    var id: String { rawValue }
    var title: String { self == .codex ? "Codex" : "Claude" }
}

struct DirectUsageWindow: Codable, Equatable, Sendable {
    let usedPercent: Double?
    let resetAt: Date?
    var durationMinutes: Double? = nil
}

/// Contains measurements and a one-way account identifier, never session data.
struct DirectProviderUsage: Codable, Equatable, Sendable {
    let provider: DirectUsageProvider
    let measuredAt: Date
    let accountID: String
    let weekly: DirectUsageWindow?
    let fiveHour: DirectUsageWindow?
    let planName: String?
}

enum DirectProviderUsageStore {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.example.quotaglance") ?? .standard
    }

    static func latestUsage(for provider: DirectUsageProvider) -> DirectProviderUsage? {
        guard let data = defaults.data(forKey: key(provider, "usage")),
              let value = try? JSONDecoder().decode(DirectProviderUsage.self, from: data),
              value.provider == provider else { return nil }
        return value
    }

    static func hasConnection(_ provider: DirectUsageProvider) -> Bool {
        defaults.bool(forKey: key(provider, "enabled"))
    }

    static func isAuthenticated(_ provider: DirectUsageProvider) -> Bool {
        defaults.bool(forKey: key(provider, "authenticated"))
    }

    static func needsSignIn(_ provider: DirectUsageProvider) -> Bool {
        hasConnection(provider) && defaults.bool(forKey: key(provider, "needsSignIn"))
    }

    static func hasPendingConnection(_ provider: DirectUsageProvider) -> Bool {
        !hasConnection(provider) && defaults.bool(forKey: key(provider, "needsSignIn"))
    }

    static func setNeedsSignIn(_ needed: Bool, for provider: DirectUsageProvider) {
        defaults.set(needed, forKey: key(provider, "needsSignIn"))
    }

    static func save(_ usage: DirectProviderUsage) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        defaults.set(data, forKey: key(usage.provider, "usage"))
        defaults.set(true, forKey: key(usage.provider, "enabled"))
        setAuthenticated(true, for: usage.provider)
        setNeedsSignIn(false, for: usage.provider)
    }

    static func setAuthenticated(_ authenticated: Bool, for provider: DirectUsageProvider) {
        defaults.set(authenticated, forKey: key(provider, "authenticated"))
    }

    static func clearMeasurement(for provider: DirectUsageProvider) {
        defaults.removeObject(forKey: key(provider, "usage"))
        setAuthenticated(false, for: provider)
    }

    static func disconnect(_ provider: DirectUsageProvider) {
        clearMeasurement(for: provider)
        defaults.removeObject(forKey: key(provider, "enabled"))
        defaults.removeObject(forKey: key(provider, "needsSignIn"))
    }

    private static func key(_ provider: DirectUsageProvider, _ suffix: String) -> String {
        "QuotaGlance.mobile.direct.\(provider.rawValue).\(suffix).v1"
    }
}

enum DirectUsageDecodeError: Error { case invalidResponse }

/// OpenAI distinguishes the login/session subject from ChatGPT's quota user.
/// These claims only select a request/account; the usage server must validate
/// the access token before this identity may be used for a measurement.
struct CodexSessionIdentity: Equatable, Sendable {
    let accountID: String?
    let userID: String?

    static func claims(in token: String) -> Self {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return .init(accountID: nil, userID: nil) }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = object["https://api.openai.com/auth"] as? [String: Any] else {
            return .init(accountID: nil, userID: nil)
        }
        return .init(accountID: identifier(auth["chatgpt_account_id"]),
                     userID: identifier(auth["chatgpt_user_id"]) ?? identifier(auth["user_id"]))
    }

    static func resolve(usage: [String: Any], selectedAccountID: String?, claims: Self) throws -> Self {
        let returnedAccount = identifier(usage["account_id"])
        let returnedUser = identifier(usage["user_id"])
        let selected = identifier(selectedAccountID) ?? claims.accountID
        if let returnedAccount, let selected, returnedAccount != selected { throw DirectUsageDecodeError.invalidResponse }
        if let returnedUser, let claimedUser = claims.userID, returnedUser != claimedUser { throw DirectUsageDecodeError.invalidResponse }
        guard let account = returnedAccount ?? selected else { throw DirectUsageDecodeError.invalidResponse }
        return .init(accountID: account, userID: returnedUser ?? claims.userID)
    }

    private static func identifier(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty, value.count <= 200,
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else { return nil }
        return value
    }
}

enum DirectProviderUsageDecoder {
    // Wire contract: OpenAI's codex-rs/codex-backend-openapi-models/src/models/
    // rate_limit_status_payload.rs and rate_limit_window_snapshot.rs.
    // Windows are classified by their declared duration, never by position.
    static func codex(
        _ object: [String: Any], accountID: String, userID: String?, now: Date = Date()
    ) throws -> DirectProviderUsage {
        guard object.keys.contains("rate_limit"), !accountID.isEmpty else {
            throw DirectUsageDecodeError.invalidResponse
        }
        let rateLimit = try dictionary(object["rate_limit"])
        let windows = try ["primary_window", "secondary_window"].compactMap { key -> DirectUsageWindow? in
            guard let value = try dictionary(rateLimit?[key]) else { return nil }
            let seconds = try number(value["limit_window_seconds"])
            if let seconds, seconds <= 0 { throw DirectUsageDecodeError.invalidResponse }
            let reset = try number(value["reset_at"])
            if let reset, reset <= 0 { throw DirectUsageDecodeError.invalidResponse }
            return DirectUsageWindow(
                usedPercent: try percent(value["used_percent"]),
                resetAt: reset.map(Date.init(timeIntervalSince1970:)),
                durationMinutes: seconds.map { $0 / 60 }
            )
        }
        let weekly = windows.first { $0.durationMinutes == 7 * 24 * 60 }
        let fiveHour = windows.first { $0.durationMinutes == 5 * 60 }
        return DirectProviderUsage(
            provider: .codex, measuredAt: now,
            accountID: identity("codex-web:\(accountID):\(userID ?? "")"),
            weekly: weekly, fiveHour: fiveHour,
            planName: safeText(object["plan_type"], limit: 60)
        )
    }

    static func claude(
        _ object: [String: Any], workspaceID: String, now: Date = Date()
    ) throws -> DirectProviderUsage {
        guard object.keys.contains("seven_day"), UUID(uuidString: workspaceID) != nil else {
            throw DirectUsageDecodeError.invalidResponse
        }
        func window(_ key: String, minutes: Double) throws -> DirectUsageWindow? {
            guard let value = try dictionary(object[key]) else { return nil }
            let reset: Date?
            if let raw = value["resets_at"], !(raw is NSNull) {
                guard let text = raw as? String, let parsed = date(text) else {
                    throw DirectUsageDecodeError.invalidResponse
                }
                reset = parsed
            } else { reset = nil }
            return DirectUsageWindow(
                usedPercent: try percent(value["utilization"]),
                resetAt: reset, durationMinutes: minutes
            )
        }
        return DirectProviderUsage(
            provider: .claude, measuredAt: now,
            accountID: identity("claude-web:" + workspaceID),
            weekly: try window("seven_day", minutes: 7 * 24 * 60),
            fiveHour: try window("five_hour", minutes: 5 * 60), planName: nil
        )
    }

    static func retryDate(_ header: String?, now: Date = Date()) -> Date {
        let minimum = now.addingTimeInterval(60)
        guard let header else { return now.addingTimeInterval(300) }
        if let seconds = TimeInterval(header), seconds.isFinite, seconds >= 0 {
            return max(minimum, now.addingTimeInterval(seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return max(minimum, formatter.date(from: header) ?? now.addingTimeInterval(300))
    }

    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func dictionary(_ value: Any?) throws -> [String: Any]? {
        guard let value, !(value is NSNull) else { return nil }
        guard let object = value as? [String: Any] else { throw DirectUsageDecodeError.invalidResponse }
        return object
    }

    private static func number(_ value: Any?) throws -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else {
            throw DirectUsageDecodeError.invalidResponse
        }
        return number.doubleValue
    }

    private static func percent(_ value: Any?) throws -> Double? {
        let result = try number(value)
        if let result, !(0...100).contains(result) { throw DirectUsageDecodeError.invalidResponse }
        return result
    }

    private static func safeText(_ value: Any?, limit: Int) -> String? {
        guard let text = value as? String else { return nil }
        let cleaned = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let result = String(String.UnicodeScalarView(cleaned)).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : String(result.prefix(limit))
    }

    private static func identity(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
