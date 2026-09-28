import Combine
import Foundation
import UIKit
import WebKit

extension Notification.Name {
    static let directProviderUsageChanged = Notification.Name("QuotaGlance.directProviderUsageChanged")
}

@MainActor
final class ProviderConnectionService: ObservableObject {
    static let shared = ProviderConnectionService()
    var onUsage: ((DirectProviderUsage) -> Void)?
    private var sessions: [DirectUsageProvider: ProviderWebSession] = [:]
    private var refreshing: Set<DirectUsageProvider> = []
    private var generations: [DirectUsageProvider: UUID] = [:]
    private var failures: [DirectUsageProvider: Int] = [:]

    func session(for provider: DirectUsageProvider) -> ProviderWebSession {
        if let existing = sessions[provider] { return existing }
        let session = ProviderWebSession(provider: provider)
        session.onCheck = { [weak self] userInitiated in
            Task { await self?.refresh(provider: provider, userInitiated: userInitiated) }
        }
        session.onWorkspaceChanged = { [weak self] in
            guard let self else { return }
            self.generations[provider] = UUID()
            ProviderConnectionKeychain.clear(provider)
            DirectProviderUsageStore.clearMeasurement(for: provider)
            self.setForegroundRequired(false, provider: provider)
            self.setRetryAt(nil, provider: provider)
            self.publishChange()
            Task { await self.refresh(provider: provider) }
        }
        sessions[provider] = session
        return session
    }

    func hasConnection(_ provider: DirectUsageProvider) -> Bool { DirectProviderUsageStore.hasConnection(provider) }
    func isConnected(_ provider: DirectUsageProvider) -> Bool { DirectProviderUsageStore.isAuthenticated(provider) }
    func needsSignIn(_ provider: DirectUsageProvider) -> Bool { DirectProviderUsageStore.needsSignIn(provider) }
    func latestUsage(for provider: DirectUsageProvider) -> DirectProviderUsage? {
        DirectProviderUsageStore.latestUsage(for: provider)
    }

    func refreshAll(inBackground: Bool = false) async -> [DirectProviderUsage] {
        async let codex = refresh(provider: .codex, inBackground: inBackground)
        async let claude = refresh(provider: .claude, inBackground: inBackground)
        return await [codex, claude].compactMap { $0 }
    }

    @discardableResult
    func refresh(provider: DirectUsageProvider, inBackground: Bool = false, userInitiated: Bool = false) async -> DirectProviderUsage? {
        let presenting = sessions[provider]?.isPresenting == true
        let attempted = UserDefaults.standard.bool(forKey: stateKey(provider, "attempted"))
            || DirectProviderUsageStore.hasPendingConnection(provider)
        guard hasConnection(provider) || (!inBackground && (presenting || userInitiated || attempted)), !Task.isCancelled else { return nil }
        guard !refreshing.contains(provider) else {
            if userInitiated { sessions[provider]?.queueCheck() }
            return nil
        }
        if let retry = retryAt(provider), retry > Date() {
            // A deliberate check may retry an ordinary transport failure after
            // login. Provider rate limits always retain their full Retry-After.
            if !userInitiated || UserDefaults.standard.bool(forKey: stateKey(provider, "rateLimited")) {
                sessions[provider]?.reportWaiting(until: retry)
                return nil
            }
        }
        if inBackground && (foregroundRequired(provider) || needsSignIn(provider)) { return nil }

        refreshing.insert(provider)
        let generation = generations[provider] ?? UUID()
        generations[provider] = generation
        sessions[provider]?.checking = true
        defer {
            refreshing.remove(provider)
            sessions[provider]?.checking = false
            sessions[provider]?.finishCheck()
        }
        do {
            let result: DirectProviderUsage
            let credential: ProviderConnectionCredential?
            let saved: ProviderConnectionCredential?
            if presenting {
                saved = nil
            } else {
                do { saved = try ProviderConnectionKeychain.load(provider) }
                catch {
                    guard !inBackground else { throw error }
                    // A broken or temporarily inaccessible native credential
                    // must not prevent reconnecting in the provider's own page.
                    saved = nil
                }
            }
            if let saved, !presenting, !foregroundRequired(provider) {
                do {
                    let reading = try await ProviderConnectionNativeClient.fetch(saved)
                    result = reading.usage
                    credential = reading.credential
                } catch {
                    let error = ProviderConnectionError.safe(error)
                    guard !inBackground, error.requiresConnection,
                          UIApplication.shared.applicationState == .active else { throw error }
                    let reading = try await session(for: provider).fetch()
                    result = reading.usage
                    credential = reading.credential
                }
            } else {
                // A background refresh must never initialize or drive WebKit.
                guard !inBackground, UIApplication.shared.applicationState == .active else { return nil }
                let reading = try await session(for: provider).fetch()
                result = reading.usage
                credential = reading.credential
            }
            try Task.checkCancellation()
            guard generations[provider] == generation else { return nil }
            var backgroundAvailable = false
            if let credential {
                do {
                    try ProviderConnectionKeychain.save(credential)
                    backgroundAvailable = true
                } catch {
                    // The successful foreground measurement is still useful.
                    // Never leave an old account's credential behind on failure.
                    ProviderConnectionKeychain.clear(provider)
                }
            } else {
                // A new web account can be readable without an exportable
                // session. Never let its next native check use the old account.
                ProviderConnectionKeychain.clear(provider)
            }
            DirectProviderUsageStore.save(result)
            UserDefaults.standard.removeObject(forKey: stateKey(provider, "diagnostic"))
            setForegroundRequired(false, provider: provider)
            setRetryAt(nil, provider: provider)
            failures[provider] = 0
            sessions[provider]?.reportSuccess(backgroundAvailable: backgroundAvailable)
            onUsage?(result)
            publishChange()
            return result
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), generations[provider] == generation else { return nil }
            let safeError = ProviderConnectionError.safe(error)
            let previousNeedsSignIn = needsSignIn(provider)
            if case .signInRequired = safeError {
                DirectProviderUsageStore.setNeedsSignIn(true, for: provider)
                DirectProviderUsageStore.setAuthenticated(false, for: provider)
            }
            if case .verificationRequired = safeError { setForegroundRequired(true, provider: provider) }
            if case .rateLimited(let until) = safeError {
                UserDefaults.standard.set(true, forKey: stateKey(provider, "rateLimited"))
                setRetryAt(until, provider: provider)
            } else if !safeError.requiresConnection {
                UserDefaults.standard.set(false, forKey: stateKey(provider, "rateLimited"))
                let count = min(7, (failures[provider] ?? 0) + 1)
                failures[provider] = count
                setRetryAt(Date().addingTimeInterval(min(1_800, 15 * pow(2, Double(count)))), provider: provider)
            }
            sessions[provider]?.report(safeError)
            if previousNeedsSignIn != needsSignIn(provider) { publishChange() }
            return nil
        }
    }

    func disconnect(_ provider: DirectUsageProvider) async {
        generations[provider] = UUID()
        ProviderConnectionKeychain.clear(provider)
        DirectProviderUsageStore.disconnect(provider)
        UserDefaults.standard.removeObject(forKey: stateKey(provider, "attempted"))
        setRetryAt(nil, provider: provider)
        setForegroundRequired(false, provider: provider)
        failures[provider] = 0
        sessions[provider]?.reset()
        let store = WKWebsiteDataStore(forIdentifier: provider.websiteDataID)
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        publishChange()
    }

    private func publishChange() {
        objectWillChange.send()
        NotificationCenter.default.post(name: .directProviderUsageChanged, object: nil)
    }

    private func retryAt(_ provider: DirectUsageProvider) -> Date? {
        UserDefaults.standard.object(forKey: stateKey(provider, "retryAt")) as? Date
    }
    private func setRetryAt(_ value: Date?, provider: DirectUsageProvider) {
        UserDefaults.standard.set(value, forKey: stateKey(provider, "retryAt"))
        if value == nil { UserDefaults.standard.removeObject(forKey: stateKey(provider, "rateLimited")) }
        sessions[provider]?.retryAt = value
    }
    private func foregroundRequired(_ provider: DirectUsageProvider) -> Bool {
        UserDefaults.standard.bool(forKey: stateKey(provider, "foregroundRequired"))
    }
    private func setForegroundRequired(_ value: Bool, provider: DirectUsageProvider) {
        UserDefaults.standard.set(value, forKey: stateKey(provider, "foregroundRequired"))
    }
    private func stateKey(_ provider: DirectUsageProvider, _ suffix: String) -> String {
        "QuotaGlance.mobile.connection.\(provider.rawValue).\(suffix)"
    }
}

struct ProviderWebWorkspace: Identifiable, Equatable {
    let id: String
    let name: String
}

struct ProviderAuthPopup: Identifiable {
    let id = UUID()
    let webView: WKWebView
}

/// WebKit's promise can remain pending when its process is suspended. Bound
/// the native wait as well as the JavaScript fetch, without printing its value.
@MainActor
enum ProviderConnectionJavaScript {
    private final class Pending {
        var continuation: CheckedContinuation<Any?, Error>?
        var timer: Task<Void, Never>?

        func finish(_ result: Result<Any?, Error>) {
            let waiting = continuation
            continuation = nil
            timer?.cancel()
            timer = nil
            waiting?.resume(with: result)
        }
    }

    static func evaluate(
        _ script: String, arguments: [String: Any], in webView: WKWebView,
        timeout: TimeInterval = 24
    ) async throws -> Any? {
        let pending = Pending()
        return try await withTaskCancellationHandler { () async throws -> Any? in
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
                pending.continuation = continuation
                guard !Task.isCancelled else { pending.finish(.failure(CancellationError())); return }
                pending.timer = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(max(0.01, timeout)))
                    guard !Task.isCancelled else { return }
                    pending.finish(.failure(ProviderConnectionError.timedOut))
                }
                webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .defaultClient) { result in
                    switch result {
                    case .success(let value): pending.finish(.success(value))
                    case .failure(let error): pending.finish(.failure(error))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in pending.finish(.failure(CancellationError())) }
        }
    }
}

@MainActor
final class ProviderWebSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    struct Reading {
        let usage: DirectProviderUsage
        let credential: ProviderConnectionCredential?
    }
    let provider: DirectUsageProvider
    @Published private(set) var workspaces: [ProviderWebWorkspace] = []
    @Published private(set) var workspaceID: String
    @Published private(set) var connectionMessage: String
    @Published private(set) var connected: Bool
    @Published var checking = false
    @Published var retryAt: Date?
    @Published private(set) var displayedHost: String
    @Published var popup: ProviderAuthPopup?
    var status: String { connectionMessage }
    var isPresenting = false
    var onCheck: ((Bool) -> Void)?
    var onWorkspaceChanged: (() -> Void)?
    private var storedWebView: WKWebView?
    private var navigationWaiter: CheckedContinuation<Void, Error>?
    private var navigationID = UUID()
    private var cookieCheckTask: Task<Void, Never>?
    private var checkPending = false
    private var deferredCookieCheckAvailable = true
    @Published private(set) var diagnosticText: String?

    var webView: WKWebView {
        if let storedWebView { return storedWebView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: provider.websiteDataID)
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        configuration.websiteDataStore.httpCookieStore.add(self)
        storedWebView = view
        return view
    }

    init(provider: DirectUsageProvider) {
        let wasAuthenticated = DirectProviderUsageStore.isAuthenticated(provider)
        self.provider = provider
        workspaceID = UserDefaults.standard.string(forKey: "QuotaGlance.mobile.\(provider.rawValue).workspace") ?? ""
        connected = wasAuthenticated
        connectionMessage = wasAuthenticated ? "Connected on this iPhone." : "Sign in below, then check the connection."
        displayedHost = provider.host
        retryAt = UserDefaults.standard.object(forKey: "QuotaGlance.mobile.connection.\(provider.rawValue).retryAt") as? Date
        super.init()
    }

    func present() {
        isPresenting = true
        UserDefaults.standard.set(true, forKey: "QuotaGlance.mobile.connection.\(provider.rawValue).attempted")
        if webView.url == nil { webView.load(URLRequest(url: provider.usagePage)) }
    }

    func dismiss() {
        isPresenting = false
        closePopup()
        cookieCheckTask?.cancel()
    }

    func selectWorkspace(_ id: String) {
        guard id != workspaceID, workspaces.contains(where: { $0.id == id }) else { return }
        workspaceID = id
        UserDefaults.standard.set(id, forKey: workspaceKey)
        connected = false
        connectionMessage = "Checking this workspace…"
        onWorkspaceChanged?()
    }

    func checkConnection() {
        // This action is proof that the sheet is visible, even when an OAuth
        // popup temporarily changed SwiftUI's presentation callbacks.
        isPresenting = true
        deferredCookieCheckAvailable = true
        connectionMessage = provider == .codex ? "Checking OpenAI sign-in and usage…" : "Checking Claude usage…"
        diagnosticText = nil
        onCheck?(true)
    }

    func queueCheck() { checkPending = true }

    func finishCheck() {
        guard checkPending else { return }
        checkPending = false
        if !connected { scheduleCheck() }
    }

    func reportSuccess(backgroundAvailable: Bool) {
        connected = true
        diagnosticText = nil
        UserDefaults.standard.removeObject(forKey: diagnosticKey)
        connectionMessage = backgroundAvailable
            ? "Connected. Usage can refresh directly from this iPhone."
            : "Connected. Open Quota Glance to refresh this provider’s usage."
    }

    func report(_ error: ProviderConnectionError) {
        if error.requiresConnection { connected = false }
        connectionMessage = error.message(for: provider)
        UserDefaults.standard.set(diagnosticText ?? connectionMessage, forKey: diagnosticKey)
    }

    func reportWaiting(until date: Date) {
        connectionMessage = "Next usage check after \(date.formatted(date: .omitted, time: .shortened))."
    }

    func reset() {
        storedWebView?.stopLoading()
        finishNavigation(.failure(CancellationError()))
        closePopup()
        storedWebView?.configuration.websiteDataStore.httpCookieStore.remove(self)
        storedWebView = nil
        workspaces = []
        workspaceID = ""
        UserDefaults.standard.removeObject(forKey: workspaceKey)
        connected = false
        connectionMessage = "Sign in below, then check the connection."
        diagnosticText = nil
        checkPending = false
        UserDefaults.standard.removeObject(forKey: diagnosticKey)
    }

    func fetch() async throws -> Reading {
        connectionMessage = provider == .codex ? "Checking OpenAI sign-in and usage…" : "Checking Claude usage…"
        diagnosticText = nil
        UserDefaults.standard.set(provider == .codex ? "OpenAI sign-in · Checking" : "Claude usage · Checking", forKey: diagnosticKey)
        if webView.url == nil { try await loadUsagePage() }
        guard !webView.isLoading, webView.url?.scheme == "https", webView.url?.host == provider.host else {
            throw ProviderConnectionError.signInRequired
        }
        let raw: Any?
        var token: String?
        var webSessionUserID: String?
        if provider == .codex {
            let auth = try await ProviderConnectionJavaScript.evaluate(Self.codexSessionScript, arguments: [:], in: webView)
            if let session = auth as? [String: Any], session["status"] as? Int == 200,
               let accessToken = session["accessToken"] as? String, !accessToken.isEmpty {
                token = accessToken
                webSessionUserID = session["sessionUserID"] as? String
                let claims = CodexSessionIdentity.claims(in: accessToken)
                connectionMessage = "OpenAI sign-in found. Reading Codex usage…"
                UserDefaults.standard.set("Codex usage · Checking", forKey: diagnosticKey)
                raw = try await ProviderConnectionJavaScript.evaluate(Self.codexUsageScript, arguments: [
                    "workspaceID": workspaceID, "accessToken": accessToken,
                    "claimedAccountID": claims.accountID ?? ""
                ], in: webView)
            } else { raw = auth }
        } else {
            raw = try await ProviderConnectionJavaScript.evaluate(Self.claudeScript, arguments: ["workspaceID": workspaceID], in: webView)
        }
        try Task.checkCancellation()
        guard let result = raw as? [String: Any], let status = result["status"] as? Int else {
            throw ProviderConnectionError.invalidResponse
        }
        if provider == .codex, status != 200 {
            // Only an allowlisted stage and numeric code leave the web result.
            let stages = ["session": "OpenAI sign-in", "usage": "Codex usage", "accounts": "Workspace selection", "identity": "Account verification"]
            if let stage = result["stage"] as? String, let label = stages[stage] {
                let reasons = ["sessionMissing": "Session not ready", "format": "Unexpected response format", "workspace": "Choose a workspace", "network": "Request failed", "timeout": "Request timed out", "origin": "Waiting for sign-in to return"]
                let reason = (result["reason"] as? String).flatMap { reasons[$0] }
                diagnosticText = "\(label) · \(reason ?? "HTTP \(status)")"
            }
        }
        if let choices = result["workspaces"] as? [[String: String]] {
            workspaces = choices.compactMap {
                guard let id = $0["id"], !id.isEmpty, id.count <= 200, let name = $0["name"] else { return nil }
                if provider == .claude, UUID(uuidString: id) == nil { return nil }
                return ProviderWebWorkspace(id: id, name: String(name.prefix(80)))
            }
        }
        switch status {
        case 200: break
        case 401: throw ProviderConnectionError.signInRequired
        case 403: throw ProviderConnectionError.verificationRequired
        case 409: throw ProviderConnectionError.workspaceRequired
        case 429: throw ProviderConnectionError.rateLimited(DirectProviderUsageDecoder.retryDate(result["retryAfter"] as? String))
        case 408: throw ProviderConnectionError.timedOut
        default: throw ProviderConnectionError.server(status)
        }
        guard let selectedID = result["workspaceID"] as? String, !selectedID.isEmpty,
              let usage = result["usage"] as? [String: Any] else { throw ProviderConnectionError.invalidResponse }
        workspaceID = selectedID
        UserDefaults.standard.set(selectedID, forKey: workspaceKey)
        let userID: String?
        let reading: DirectProviderUsage
        if provider == .codex {
            let identity: CodexSessionIdentity
            do {
                identity = try CodexSessionIdentity.resolve(usage: usage, selectedAccountID: selectedID,
                                                          claims: CodexSessionIdentity.claims(in: token ?? ""))
            } catch {
                diagnosticText = "Account verification · Usage belongs to a different account"
                throw ProviderConnectionError.signInRequired
            }
            userID = identity.userID
            reading = try DirectProviderUsageDecoder.codex(usage, accountID: selectedID, userID: userID)
        } else {
            userID = nil
            reading = try DirectProviderUsageDecoder.claude(usage, workspaceID: selectedID)
        }
        let cookies = await ProviderConnectionCredential.cookies(in: webView.configuration.websiteDataStore, provider: provider)
        let credential: ProviderConnectionCredential?
        if (provider == .claude && !cookies.isEmpty) || (provider == .codex && token?.isEmpty == false) {
            credential = ProviderConnectionCredential(
                provider: provider, origin: provider.origin, workspaceID: selectedID, userID: userID,
                accessToken: token, tokenExpiresAt: token.flatMap(ProviderConnectionCredential.tokenExpiry), cookies: cookies,
                webSessionUserID: webSessionUserID
            )
        } else { credential = nil }
        return Reading(usage: reading, credential: credential)
    }

    private var workspaceKey: String { "QuotaGlance.mobile.\(provider.rawValue).workspace" }
    private var diagnosticKey: String { "QuotaGlance.mobile.connection.\(provider.rawValue).diagnostic" }

    private func loadUsagePage() async throws {
        let id = UUID()
        navigationID = id
        try await withCheckedThrowingContinuation { continuation in
            finishNavigation(.failure(CancellationError()))
            navigationWaiter = continuation
            webView.load(URLRequest(url: provider.usagePage))
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(22))
                guard let self, self.navigationID == id, self.navigationWaiter != nil else { return }
                self.finishNavigation(.failure(ProviderConnectionError.timedOut))
            }
        }
    }

    private func finishNavigation(_ result: Result<Void, Error>) {
        let waiter = navigationWaiter
        navigationWaiter = nil
        waiter?.resume(with: result)
    }

    private func scheduleCheck() {
        guard isPresenting, popup == nil else { return }
        guard !checking else { checkPending = true; return }
        cookieCheckTask?.cancel()
        cookieCheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, self.isPresenting, !self.checking,
                  self.webView.url?.host == self.provider.host, !self.webView.isLoading else { return }
            self.onCheck?(false)
        }
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        if checking {
            // /api/auth/session can itself rotate cookies. Permit one deferred
            // check per navigation/user action, never an endless polling loop.
            if deferredCookieCheckAvailable {
                deferredCookieCheckAvailable = false
                checkPending = true
            }
            return
        }
        if !connected { scheduleCheck() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === storedWebView else { return }
        displayedHost = webView.url?.host ?? provider.host
        deferredCookieCheckAvailable = true
        finishNavigation(.success(()))
        scheduleCheck()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === storedWebView else { return }
        finishNavigation(.failure(ProviderConnectionError.safe(error)))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === storedWebView else { return }
        finishNavigation(.failure(ProviderConnectionError.offline))
        webView.configuration.websiteDataStore.httpCookieStore.remove(self)
        storedWebView = nil
        connectionMessage = "The sign-in page closed. Open the connection again to continue."
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              url.scheme == "https" || url.absoluteString == "about:blank",
              !navigationAction.shouldPerformDownload else { decisionHandler(.cancel); return }
        if webView === storedWebView, navigationAction.targetFrame?.isMainFrame == true {
            displayedHost = url.host ?? provider.host
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard isPresenting, navigationAction.targetFrame == nil, popup == nil else { return nil }
        // Preserve the supplied configuration and window.opener for Google/Apple.
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        popup = ProviderAuthPopup(webView: view)
        return view
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard popup?.webView === webView else { return }
        closePopup()
        scheduleCheck()
    }

    func closePopup() {
        popup?.webView.stopLoading()
        popup = nil
    }

    // Isolated world: page scripts cannot replace these fetch calls. Requests
    // are read-only, same-origin, and refuse redirects. Challenges stay visible.
    private static let claudeScript = #"""
    if (location.origin !== 'https://claude.ai') return {status: 401};
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 18000);
    const get = path => fetch(path, {method: 'GET', credentials: 'same-origin', mode: 'same-origin',
        redirect: 'error', cache: 'no-store', signal: controller.signal});
    try {
        const response = await get('/api/organizations');
        if (!response.ok) return {status: response.status, retryAfter: response.headers.get('Retry-After')};
        if (!(response.headers.get('content-type') || '').includes('application/json')) return {status: 403};
        const organizations = await response.json();
        if (!Array.isArray(organizations)) return {status: 502};
        const workspaces = organizations.filter(o => typeof o.uuid === 'string' &&
            (!Array.isArray(o.capabilities) || o.capabilities.includes('chat')))
            .map(o => ({id: o.uuid, name: String(o.name || 'Personal workspace').slice(0, 80)}));
        const selected = workspaces.find(o => o.id === workspaceID) || (workspaces.length === 1 ? workspaces[0] : null);
        if (!selected) return {status: 409, workspaces};
        const usageResponse = await get('/api/organizations/' + encodeURIComponent(selected.id) + '/usage');
        if (!usageResponse.ok) return {status: usageResponse.status, workspaces, retryAfter: usageResponse.headers.get('Retry-After')};
        if (!(usageResponse.headers.get('content-type') || '').includes('application/json')) return {status: 403, workspaces};
        const usage = await usageResponse.json();
        return {status: 200, workspaces, workspaceID: selected.id,
            usage: {seven_day: usage.seven_day, five_hour: usage.five_hour}};
    } catch (error) { return {status: error.name === 'AbortError' ? 408 : 503}; }
    finally { clearTimeout(timeout); }
    """#

    // Page: https://developers.openai.com/codex/pricing#where-can-i-see-my-current-usage-limits
    // Account/usage routes and account response layouts: OpenAI's codex-rs/backend-client.
    // These are website endpoints, not a stable public subscription API. Validate
    // every response and ask for a fresh phone sign-in when the session expires.
    // A successful web session and usage response are required before anything
    // is written to the phone's private Keychain. No OAuth client is impersonated.
    private static let codexSessionScript = #"""
    if (location.origin !== 'https://chatgpt.com') return {status: 401, stage: 'session', reason: 'origin'};
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 12000);
    try {
        const response = await fetch('/api/auth/session', {method: 'GET', credentials: 'same-origin',
            mode: 'same-origin', redirect: 'error', cache: 'no-store', signal: controller.signal});
        if (!response.ok) return {status: response.status, stage: 'session', retryAfter: response.headers.get('Retry-After')};
        if (!(response.headers.get('content-type') || '').includes('application/json')) return {status: 403, stage: 'session', reason: 'format'};
        const auth = await response.json();
        if (typeof auth.accessToken !== 'string' || !auth.accessToken || /\s/.test(auth.accessToken)) {
            return {status: 401, stage: 'session', reason: 'sessionMissing'};
        }
        return {status: 200, accessToken: auth.accessToken,
            sessionUserID: auth.user && typeof auth.user.id === 'string' ? auth.user.id : null};
    } catch (error) {
        return {status: error.name === 'AbortError' ? 408 : 503, stage: 'session', reason: error.name === 'AbortError' ? 'timeout' : 'network'};
    } finally { clearTimeout(timeout); }
    """#

    private static let codexUsageScript = #"""
    if (location.origin !== 'https://chatgpt.com') return {status: 401, stage: 'usage', reason: 'origin'};
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 18000);
    let stage = 'usage';
    const get = (path, headers = {}) => fetch(path, {method: 'GET', headers,
        credentials: 'same-origin', mode: 'same-origin', redirect: 'error', cache: 'no-store', signal: controller.signal});
    const failure = response => ({status: response.status, stage, retryAfter: response.headers.get('Retry-After')});
    const isJSON = response => (response.headers.get('content-type') || '').includes('application/json');
    try {
        const headers = {Authorization: 'Bearer ' + accessToken};
        let selectedID = workspaceID || claimedAccountID || '';
        if (selectedID) headers['ChatGPT-Account-Id'] = selectedID;
        let response = await get('/backend-api/wham/usage', headers);
        let usage = null;
        if (response.ok) {
            if (!isJSON(response)) return {status: 403, stage, reason: 'format'};
            usage = await response.json();
            if (!selectedID && typeof usage.account_id === 'string') selectedID = usage.account_id;
        } else if (selectedID || ![400, 401].includes(response.status)) return failure(response);

        let workspaces = [];
        // A usage response (or account-bound token) already identifies the
        // workspace. Do not require an unrelated discovery endpoint to succeed.
        if (!selectedID) {
            stage = 'accounts';
            const accountsResponse = await get('/backend-api/wham/accounts/check', headers);
            if (!accountsResponse.ok) return failure(accountsResponse);
            if (!isJSON(accountsResponse)) return {status: 403, stage, reason: 'format'};
            const accounts = await accountsResponse.json();
            if (Array.isArray(accounts.accounts)) {
                workspaces = accounts.accounts.filter(a => typeof a.id === 'string' && a.id &&
                    (!a.workspace_backend_origin || a.workspace_backend_origin === 'https://chatgpt.com'))
                    .map(a => ({id: a.id, name: String(a.name || a.structure || 'Personal workspace').slice(0, 80)}));
            } else if (accounts.accounts && typeof accounts.accounts === 'object') {
                workspaces = Object.values(accounts.accounts).map(a => a.account).filter(a => a && typeof a.account_id === 'string')
                    .map(a => ({id: a.account_id, name: String(a.name || a.structure || 'Personal workspace').slice(0, 80)}));
            } else return {status: 502, stage, reason: 'format'};
            const selected = workspaces.find(a => a.id === workspaceID)
                || workspaces.find(a => a.id === accounts.default_account_id)
                || (workspaces.length === 1 ? workspaces[0] : null);
            if (!selected) return {status: 409, stage, reason: 'workspace', workspaces};
            selectedID = selected.id;
            headers['ChatGPT-Account-Id'] = selectedID;
            stage = 'usage';
            response = await get('/backend-api/wham/usage', headers);
            if (!response.ok) return {...failure(response), workspaces};
            if (!isJSON(response)) return {status: 403, stage, reason: 'format', workspaces};
            usage = await response.json();
        }
        if (!usage || !Object.prototype.hasOwnProperty.call(usage, 'rate_limit')) return {status: 502, stage, reason: 'format'};
        return {status: 200, workspaces, workspaceID: selectedID, usage: {
            plan_type: usage.plan_type ?? null, rate_limit: usage.rate_limit,
            account_id: usage.account_id ?? null, user_id: usage.user_id ?? null}};
    } catch (error) {
        return {status: error.name === 'AbortError' ? 408 : 503, stage, reason: error.name === 'AbortError' ? 'timeout' : 'network'};
    }
    finally { clearTimeout(timeout); }
    """#
}
