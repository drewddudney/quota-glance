import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum ClaudeUsageSource: String, Codable, CaseIterable {
    case claudeCode, web

    static let defaultsKey = "QuotaGlance.Claude.source"
    static var current: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .claudeCode
    }
}

struct ClaudeWeeklyUsage: Codable, Equatable, Sendable {
    let usedPercent: Double?
    let resetAt: Date?

    func calendarPercent(at now: Date) -> Double? {
        guard let resetAt else { return nil }
        let week: TimeInterval = 7 * 24 * 60 * 60
        return min(100, max(0, (now.timeIntervalSince(resetAt) + week) / week * 100))
    }

    func hasEnded(at now: Date) -> Bool {
        resetAt.map { now >= $0 } ?? false
    }
}

struct ClaudeUsageSnapshot: Codable, Equatable, Sendable {
    let capturedAt: Date
    let weekly: ClaudeWeeklyUsage?
    let credentialID: String
    let plan: String?
    var source: ClaudeUsageSource? = nil
    var fiveHour: ClaudeFiveHourUsage? = nil
    var usageHistory: [ClaudeUsagePoint]? = nil
    var weeklyArchives: [ClaudeUsageArchive]? = nil
    var estimatedRunoutAt: Date? = nil
    var paceWindowLabel: String? = nil

    func quotaSnapshot(verified: Bool, needsConnection: Bool) -> ClaudeQuotaSnapshot {
        ClaudeQuotaSnapshot(capturedAt: capturedAt, usagePercent: weekly?.usedPercent,
            resetAt: weekly?.resetAt, planName: plan,
            accountID: SHA256.hash(data: Data(credentialID.utf8)).map { String(format: "%02x", $0) }.joined(),
            verified: verified, needsConnection: needsConnection,
            fiveHourUsagePercent: fiveHour?.usedPercent, fiveHourResetAt: fiveHour?.resetAt,
            usageHistory: usageHistory, weeklyArchives: weeklyArchives,
            estimatedRunoutAt: estimatedRunoutAt, paceWindowLabel: paceWindowLabel)
    }

    func recordingHistory(previous: ClaudeUsageSnapshot?, now: Date = Date()) -> ClaudeUsageSnapshot {
        if let previous, previous.credentialID == credentialID, previous.capturedAt > capturedAt { return previous }
        let recorded = ClaudeUsageHistory.record(quotaSnapshot(verified: true, needsConnection: false),
            previous: previous?.quotaSnapshot(verified: true, needsConnection: false), now: now)
        var result = self
        result.usageHistory = recorded.usageHistory
        result.weeklyArchives = recorded.weeklyArchives
        result.estimatedRunoutAt = recorded.estimatedRunoutAt
        result.paceWindowLabel = recorded.paceWindowLabel
        return result
    }
}

struct ClaudeFiveHourUsage: Codable, Equatable, Sendable {
    let usedPercent: Double?
    let resetAt: Date?
    func hasEnded(at now: Date) -> Bool { resetAt.map { $0 <= now } ?? false }
}

enum ClaudeUsageError: LocalizedError {
    case signInRequired
    case keychainAccessRequired
    case expiredSignIn
    case missingUsageScope
    case unauthorized
    case invalidResponse
    case server(Int)
    case rateLimited(Date)
    case webSignInRequired
    case webVerificationRequired
    case organizationRequired

    var requiresConnection: Bool {
        switch self {
        case .signInRequired, .keychainAccessRequired, .expiredSignIn, .missingUsageScope, .unauthorized,
             .webSignInRequired, .webVerificationRequired, .organizationRequired: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .signInRequired: return "Sign in to Claude Code, then connect."
        case .keychainAccessRequired: return "Connect to allow access to your Claude Code sign-in."
        case .expiredSignIn: return "Open Claude Code to refresh your sign-in, then connect."
        case .missingUsageScope: return "Use Claude Code /login; this token cannot read usage."
        case .unauthorized: return "Claude sign-in was rejected. Use Claude Code /login."
        case .invalidResponse: return "Claude returned an unreadable usage response."
        case .server(let code): return "Claude usage is unavailable (HTTP \(code))."
        case .rateLimited: return "Claude is limiting usage checks. Retrying shortly."
        case .webSignInRequired: return "Sign in to Claude in the connection window."
        case .webVerificationRequired: return "Open the Claude connection window to finish browser verification."
        case .organizationRequired: return "Choose your Claude workspace in the connection window."
        }
    }
}

struct ClaudeUsageCredential: Sendable {
    let accessToken: String
    let plan: String?

    // A rotated token requires a new measurement before reusing a cached account's values.
    var identifier: String {
        SHA256.hash(data: Data(accessToken.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private final class ClaudeCredentialReadCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ClaudeUsageCredential, Error>?
    let context: LAContext

    init(_ continuation: CheckedContinuation<ClaudeUsageCredential, Error>, context: LAContext) {
        self.continuation = continuation
        self.context = context
    }

    func finish(_ result: Result<ClaudeUsageCredential, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

enum ClaudeCredentialReader {
    private static let readLock = NSLock()
    private static var reading = false

    // Foreign Keychain items can stall even a no-UI read. Bound the wait and allow
    // only one underlying Security request, so polling cannot accumulate workers.
    static func readAsync(allowPrompt: Bool) async throws -> ClaudeUsageCredential {
        let context = LAContext()
        context.interactionNotAllowed = !allowPrompt
        return try await withCheckedThrowingContinuation { continuation in
            readLock.lock()
            let wasReading = reading
            if !wasReading { reading = true }
            readLock.unlock()
            guard !wasReading else {
                continuation.resume(throwing: ClaudeUsageError.keychainAccessRequired)
                return
            }
            let completion = ClaudeCredentialReadCompletion(continuation, context: context)
            DispatchQueue.global(qos: .utility).async {
                let result = Result { try read(allowPrompt: allowPrompt, context: completion.context) }
                readLock.lock()
                reading = false
                readLock.unlock()
                completion.finish(result)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + (allowPrompt ? 60 : 8)) {
                completion.finish(.failure(ClaudeUsageError.keychainAccessRequired))
                completion.context.invalidate()
            }
        }
    }

    // Protocol reference: github.com/steipete/CodexBar/blob/main/docs/claude.md.
    // Claude Code owns these credentials. Read them afresh; never rotate or rewrite them.
    private static func read(allowPrompt: Bool, context: LAContext) throws -> ClaudeUsageCredential {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let customDirectory = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCustomDirectory = customDirectory?.isEmpty == false
        let root = hasCustomDirectory
            ? URL(fileURLWithPath: (customDirectory! as NSString).expandingTildeInPath, isDirectory: true)
            : home.appendingPathComponent(".claude", isDirectory: true)
        let file = root.appendingPathComponent(".credentials.json")
        var fileError: Error?
        if FileManager.default.fileExists(atPath: file.path) {
            do { return try decode(Data(contentsOf: file)) }
            catch { fileError = error }
        }
        // A custom profile must never silently switch to the default account.
        if hasCustomDirectory { throw fileError ?? ClaudeUsageError.signInRequired }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecAttrAccount as String: NSUserName(),
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]
        // Legacy Keychain ACLs also need this flag; LAContext alone can show an access dialog.
        if !allowPrompt { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        // Legacy login-keychain ACLs can ignore per-query flags. Deny interaction
        // for this brief, serialized read and restore the previous process policy.
        var previousInteraction = DarwinBoolean(true)
        if !allowPrompt {
            guard SecKeychainGetUserInteractionAllowed(&previousInteraction) == errSecSuccess,
                  SecKeychainSetUserInteractionAllowed(false) == errSecSuccess
            else { throw ClaudeUsageError.keychainAccessRequired }
        }
        defer {
            if !allowPrompt { _ = SecKeychainSetUserInteractionAllowed(previousInteraction.boolValue) }
        }
        var item: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &item)
        if result == errSecItemNotFound { throw fileError ?? ClaudeUsageError.signInRequired }
        guard result == errSecSuccess, let data = item as? Data else {
            throw ClaudeUsageError.keychainAccessRequired
        }
        return try decode(data)
    }

    static func decode(_ data: Data, now: Date = Date()) throws -> ClaudeUsageCredential {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let rawToken = oauth["accessToken"] as? String,
              !rawToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw ClaudeUsageError.signInRequired }
        if let expiry = oauth["expiresAt"] as? Double, expiry.isFinite,
           Date(timeIntervalSince1970: expiry / 1_000) <= now {
            throw ClaudeUsageError.expiredSignIn
        }
        if let scopes = oauth["scopes"] as? [String], !scopes.contains("user:profile") {
            throw ClaudeUsageError.missingUsageScope
        }
        return ClaudeUsageCredential(
            accessToken: rawToken.trimmingCharacters(in: .whitespacesAndNewlines),
            plan: (oauth["subscriptionType"] as? String).map { String($0.prefix(40)) }
        )
    }
}

private final class ClaudeNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum ClaudeUsageClient {
    static func fetch(credential: ClaudeUsageCredential) async throws -> ClaudeUsageSnapshot {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration, delegate: ClaudeNoRedirectDelegate(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("QuotaGlance/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ClaudeUsageError.invalidResponse }
        switch response.statusCode {
        case 200:
            return try decode(data, credentialID: credential.identifier, plan: credential.plan)
        case 401, 403:
            throw ClaudeUsageError.unauthorized
        case 429:
            throw ClaudeUsageError.rateLimited(retryDate(response.value(forHTTPHeaderField: "Retry-After")))
        default:
            throw ClaudeUsageError.server(response.statusCode)
        }
    }

    static func decode(_ data: Data, credentialID: String, plan: String?, now: Date = Date()) throws -> ClaudeUsageSnapshot {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object.keys.contains("seven_day") else { throw ClaudeUsageError.invalidResponse }
        func window(_ key: String) throws -> ClaudeWeeklyUsage? {
            guard let value = object[key], !(value is NSNull) else { return nil }
            guard let window = value as? [String: Any] else { throw ClaudeUsageError.invalidResponse }
            let number = window["utilization"] as? NSNumber
            if let number, CFGetTypeID(number) == CFBooleanGetTypeID() { throw ClaudeUsageError.invalidResponse }
            let percent = number?.doubleValue
            if let percent, !percent.isFinite || !(0...100).contains(percent) {
                throw ClaudeUsageError.invalidResponse
            }
            if let value = window["utilization"], !(value is NSNull), percent == nil {
                throw ClaudeUsageError.invalidResponse
            }
            return ClaudeWeeklyUsage(usedPercent: percent, resetAt: parseDate(window["resets_at"] as? String))
        }
        let weekly = try window("seven_day")
        let fiveHour = try window("five_hour").map { ClaudeFiveHourUsage(usedPercent: $0.usedPercent, resetAt: $0.resetAt) }
        return ClaudeUsageSnapshot(capturedAt: now, weekly: weekly, credentialID: credentialID, plan: plan, fiveHour: fiveHour)
    }

    static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func retryDate(_ header: String?, now: Date = Date()) -> Date {
        let minimum = now.addingTimeInterval(300)
        guard let header else { return minimum }
        if let seconds = TimeInterval(header), seconds.isFinite, seconds >= 0 {
            return max(minimum, now.addingTimeInterval(seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return max(minimum, formatter.date(from: header) ?? minimum)
    }
}

enum ClaudeUsageCache {
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quota Glance/claude-usage-v1.json")
    }

    static func load() -> ClaudeUsageSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ClaudeUsageSnapshot.self, from: data)
    }

    static func save(_ snapshot: ClaudeUsageSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(snapshot).write(to: url, options: .atomic)
        } catch { NSLog("Quota Glance could not save its Claude usage snapshot.") }
    }

    static func clear() { try? FileManager.default.removeItem(at: url) }
}
