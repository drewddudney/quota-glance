import Foundation
import Security
import WebKit

extension DirectUsageProvider {
    var origin: String { self == .codex ? "https://chatgpt.com" : "https://claude.ai" }
    var host: String { self == .codex ? "chatgpt.com" : "claude.ai" }
    var usagePage: URL {
        URL(string: origin + (self == .codex ? "/codex/settings/usage" : "/settings/usage"))!
    }
    var websiteDataID: UUID {
        UUID(uuidString: self == .codex
            ? "BB10E150-3157-4BB3-9486-1AFC8A037A60"
            : "DB5E8B17-E41E-43CD-948D-2C53E1CF1AE4")!
    }
}

enum ProviderConnectionError: Error {
    case signInRequired, verificationRequired, workspaceRequired, invalidResponse
    case rateLimited(Date), server(Int), offline, timedOut, keychainUnavailable

    var requiresConnection: Bool {
        switch self {
        case .signInRequired, .verificationRequired, .workspaceRequired: true
        default: false
        }
    }

    func message(for provider: DirectUsageProvider) -> String {
        switch self {
        case .signInRequired: "Sign in to \(provider.title) on this iPhone, then check the connection."
        case .verificationRequired: "Open \(provider.title) here to finish its browser verification."
        case .workspaceRequired: "Choose the workspace whose usage you want to see."
        case .invalidResponse: "\(provider.title) returned usage in a format this app could not read."
        case .rateLimited(let date): "\(provider.title) asked us to wait. Try again after \(date.formatted(date: .omitted, time: .shortened))."
        case .server(let status): "\(provider.title) usage is temporarily unavailable (HTTP \(status))."
        case .offline: "Couldn’t reach \(provider.title). Check your internet connection."
        case .timedOut: "\(provider.title) took too long to respond. Try again shortly."
        case .keychainUnavailable: "Unlock this iPhone to access its saved sign-in."
        }
    }

    static func safe(_ error: Error) -> Self {
        if let known = error as? Self { return known }
        if error is DirectUsageDecodeError { return .invalidResponse }
        if (error as? URLError)?.code == .timedOut { return .timedOut }
        return .offline
    }
}

/// Only created from this app's own provider WebKit store after a successful
/// usage read. Secrets are never saved in defaults, app groups, CloudKit or logs.
struct ProviderConnectionCredential: Codable {
    struct Cookie: Codable {
        let name: String
        let value: String
        let expiresAt: Date?
    }
    let provider: DirectUsageProvider
    let origin: String
    let workspaceID: String
    let userID: String?
    var accessToken: String?
    var tokenExpiresAt: Date?
    var cookies: [Cookie]
    var webSessionUserID: String? = nil

    var validOrigin: Bool { origin == provider.origin }

    func cookieHeader(now: Date = Date()) -> String? {
        let values = cookies.filter { cookie in
            (cookie.expiresAt.map { $0 > now } ?? true)
                && Self.allowedCookie(cookie.name, for: provider)
                && !cookie.value.contains(where: { $0 == ";" || $0 == "\r" || $0 == "\n" })
        }.map { "\($0.name)=\($0.value)" }
        return values.isEmpty ? nil : values.joined(separator: "; ")
    }

    static func allowedCookie(_ name: String, for provider: DirectUsageProvider) -> Bool {
        if provider == .claude { return name == "sessionKey" }
        return ["__Secure-next-auth.session-token", "__Secure-authjs.session-token"].contains { prefix in
            name == prefix || (name.hasPrefix(prefix + ".") && Int(name.dropFirst(prefix.count + 1)) != nil)
        }
    }

    @MainActor
    static func cookies(in store: WKWebsiteDataStore, provider: DirectUsageProvider) async -> [Cookie] {
        let all = await store.httpCookieStore.allCookies()
        return all.filter {
            ($0.domain == provider.host || $0.domain == "." + provider.host)
                && $0.isSecure && allowedCookie($0.name, for: provider)
                && ($0.expiresDate.map { $0 > Date() } ?? true)
        }.sorted { $0.name < $1.name }.map {
            Cookie(name: $0.name, value: $0.value, expiresAt: $0.expiresDate)
        }
    }

    // The JWT expiry is a scheduling hint only; the provider validates the token.
    static func tokenExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var text = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        guard let data = Data(base64Encoded: text),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object["exp"] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return Date(timeIntervalSince1970: value.doubleValue)
    }
}

enum ProviderConnectionKeychain {
    private static let service = "com.example.quotaglance.mobile.provider-session.v1"

    static func load(_ provider: DirectUsageProvider) throws -> ProviderConnectionCredential? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw ProviderConnectionError.keychainUnavailable }
        guard let value = try? JSONDecoder().decode(ProviderConnectionCredential.self, from: data),
              value.provider == provider, value.validOrigin else { throw ProviderConnectionError.signInRequired }
        return value
    }

    static func save(_ credential: ProviderConnectionCredential) throws {
        guard credential.validOrigin else { throw ProviderConnectionError.invalidResponse }
        let data = try JSONEncoder().encode(credential)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let query = baseQuery(credential.provider)
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let insertion = query.merging(attributes) { _, value in value }
            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else {
                throw ProviderConnectionError.keychainUnavailable
            }
        } else if status != errSecSuccess { throw ProviderConnectionError.keychainUnavailable }
    }

    static func clear(_ provider: DirectUsageProvider) {
        SecItemDelete(baseQuery(provider) as CFDictionary)
    }

    private static func baseQuery(_ provider: DirectUsageProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: provider.rawValue,
         kSecAttrSynchronizable as String: false]
    }
}

private final class ProviderConnectionNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) { completionHandler(nil) }
}

enum ProviderConnectionNativeClient {
    struct Reading {
        let usage: DirectProviderUsage
        let credential: ProviderConnectionCredential
    }

    /// Fixed GET routes only. WebKit verification cookies are deliberately not
    /// copied; a verification response returns the user to the provider page.
    static func fetch(_ saved: ProviderConnectionCredential) async throws -> Reading {
        guard saved.validOrigin else { throw ProviderConnectionError.signInRequired }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 22
        let session = URLSession(configuration: configuration, delegate: ProviderConnectionNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var credential = saved

        func get(_ path: String, headers: [String: String]) async throws -> [String: Any] {
            guard path.hasPrefix("/"), !path.hasPrefix("//"),
                  let url = URL(string: saved.origin + path), url.scheme == "https", url.host == saved.provider.host else {
                throw ProviderConnectionError.invalidResponse
            }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("QuotaGlanceMobile/1.0", forHTTPHeaderField: "User-Agent")
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            let (data, rawResponse) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = rawResponse as? HTTPURLResponse, response.url == url else {
                throw ProviderConnectionError.invalidResponse
            }
            switch response.statusCode {
            case 200: break
            case 301...399, 401: throw ProviderConnectionError.signInRequired
            case 403: throw ProviderConnectionError.verificationRequired
            case 429:
                throw ProviderConnectionError.rateLimited(DirectProviderUsageDecoder.retryDate(response.value(forHTTPHeaderField: "Retry-After")))
            default: throw ProviderConnectionError.server(response.statusCode)
            }
            guard response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("application/json") == true else {
                throw ProviderConnectionError.verificationRequired
            }
            guard data.count <= 1_048_576,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ProviderConnectionError.invalidResponse
            }
            // Retain only provider session-cookie rotations from the fixed
            // original host. Verification cookies never enter the Keychain.
            let responseHeaders = response.allHeaderFields.reduce(into: [String: String]()) { headers, pair in
                if let key = pair.key as? String, let value = pair.value as? String { headers[key] = value }
            }
            let rotations = HTTPCookie.cookies(withResponseHeaderFields: responseHeaders, for: url).filter {
                ($0.domain == saved.provider.host || $0.domain == "." + saved.provider.host)
                    && $0.isSecure && ProviderConnectionCredential.allowedCookie($0.name, for: saved.provider)
            }
            for cookie in rotations {
                credential.cookies.removeAll { $0.name == cookie.name }
                if !cookie.value.isEmpty, cookie.expiresDate.map({ $0 > Date() }) ?? true {
                    credential.cookies.append(.init(name: cookie.name, value: cookie.value, expiresAt: cookie.expiresDate))
                }
            }
            return object
        }

        if saved.provider == .claude {
            guard UUID(uuidString: saved.workspaceID) != nil, let cookie = saved.cookieHeader() else {
                throw ProviderConnectionError.signInRequired
            }
            let usage = try await get("/api/organizations/\(saved.workspaceID)/usage", headers: ["Cookie": cookie])
            return Reading(usage: try DirectProviderUsageDecoder.claude(usage, workspaceID: saved.workspaceID), credential: credential)
        }

        var refreshedToken = false
        func refreshToken() async throws {
            guard !refreshedToken else { throw ProviderConnectionError.signInRequired }
            refreshedToken = true
            guard let cookie = credential.cookieHeader() else { throw ProviderConnectionError.signInRequired }
            let auth = try await get("/api/auth/session", headers: ["Cookie": cookie])
            guard let token = auth["accessToken"] as? String, !token.isEmpty,
                  !token.contains(where: { $0.isWhitespace }) else { throw ProviderConnectionError.signInRequired }
            if let expected = saved.webSessionUserID, let user = auth["user"] as? [String: Any],
               let actual = user["id"] as? String, actual != expected {
                throw ProviderConnectionError.signInRequired
            }
            if let expected = saved.userID, let actual = CodexSessionIdentity.claims(in: token).userID,
               actual != expected { throw ProviderConnectionError.signInRequired }
            credential.accessToken = token
            credential.tokenExpiresAt = ProviderConnectionCredential.tokenExpiry(token)
        }

        if credential.accessToken == nil || (credential.tokenExpiresAt.map { $0 <= Date().addingTimeInterval(60) } ?? false) {
            try await refreshToken()
        }
        func getUsage() async throws -> [String: Any] {
            guard let token = credential.accessToken, !token.isEmpty,
                  !token.contains(where: { $0.isWhitespace }), !saved.workspaceID.isEmpty else {
                throw ProviderConnectionError.signInRequired
            }
            return try await get("/backend-api/wham/usage", headers: [
                "Authorization": "Bearer " + token, "ChatGPT-Account-Id": saved.workspaceID
            ])
        }
        let usage: [String: Any]
        do { usage = try await getUsage() }
        catch ProviderConnectionError.signInRequired {
            try await refreshToken()
            usage = try await getUsage()
        }
        let identity = try CodexSessionIdentity.resolve(usage: usage, selectedAccountID: saved.workspaceID,
                                                       claims: CodexSessionIdentity.claims(in: credential.accessToken ?? ""))
        if let expected = saved.userID, let actual = identity.userID, actual != expected {
            throw ProviderConnectionError.signInRequired
        }
        return Reading(usage: try DirectProviderUsageDecoder.codex(
            usage, accountID: saved.workspaceID, userID: identity.userID ?? saved.userID
        ), credential: credential)
    }
}
