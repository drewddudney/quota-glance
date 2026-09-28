import AppKit
import CryptoKit
import SwiftUI
import WebKit

struct ClaudeWebWorkspace: Identifiable, Equatable {
    let id: String
    let name: String
}

/// An app-owned Claude web session. WebKit keeps its cookies; they never enter
/// the usage cache, logs, or another provider's requests.
@MainActor
final class ClaudeWebSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver, NSWindowDelegate {
    static let shared = ClaudeWebSession()
    private static let workspaceKey = "QuotaGlance.Claude.webWorkspace"
    @Published private(set) var workspaces: [ClaudeWebWorkspace] = []
    @Published var workspaceID = UserDefaults.standard.string(forKey: workspaceKey) ?? ""
    @Published var connectionMessage = "Sign in below, then check the connection."
    @Published var checking = false
    @Published var connected = false
    let webView: WKWebView
    var onReady: (() -> Void)?
    var onWorkspaceChanged: (() -> Void)?
    private var window: NSWindow?
    private var authWindows: [ObjectIdentifier: NSWindow] = [:]
    private var navigationWaiter: CheckedContinuation<Void, Error>?
    private var navigationID = UUID()
    private var cookieCheckScheduled = false

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 780, height: 650), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        configuration.websiteDataStore.httpCookieStore.add(self)
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 760),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Connect Claude · Quota Glance"
            window.identifier = NSUserInterfaceItemIdentifier("QuotaGlance.ClaudeConnection")
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 600, height: 540)
            window.contentView = NSHostingView(rootView: ClaudeConnectionView(session: self))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if webView.url == nil || webView.url?.host != "claude.ai" {
            webView.load(URLRequest(url: URL(string: "https://claude.ai/settings/usage")!))
        }
        onReady?()
    }

    func selectWorkspace(_ id: String) {
        workspaceID = id
        UserDefaults.standard.set(id, forKey: Self.workspaceKey)
        connected = false
        onWorkspaceChanged?()
    }

    func checkConnection() { onReady?() }
    func close() { window?.orderOut(nil) }

    func report(_ result: Result<ClaudeUsageSnapshot, Error>) {
        checking = false
        switch result {
        case .success:
            connected = true
            connectionMessage = "Connected. Your Claude usage is updating in Quota Glance."
        case .failure(let error):
            connected = false
            connectionMessage = error.localizedDescription
        }
    }

    func fetch() async throws -> ClaudeUsageSnapshot {
        checking = true
        defer { checking = false }
        // A fresh installation doesn't launch a hidden login page during every poll.
        if webView.url == nil {
            let hasSession = await withCheckedContinuation { continuation in
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    continuation.resume(returning: cookies.contains {
                        ($0.domain == "claude.ai" || $0.domain == ".claude.ai") && $0.name == "sessionKey"
                    })
                }
            }
            guard hasSession else { throw ClaudeUsageError.webSignInRequired }
            try await loadUsagePage()
        } else if webView.isLoading {
            throw ClaudeUsageError.webSignInRequired
        }
        guard webView.url?.scheme == "https", webView.url?.host == "claude.ai" else {
            throw ClaudeUsageError.webSignInRequired
        }
        if ["/login", "/logout", "/signup"].contains(where: { webView.url?.path.hasPrefix($0) == true }) {
            throw ClaudeUsageError.webSignInRequired
        }
        let result = try await webView.callAsyncJavaScript(Self.usageScript, arguments: ["workspaceID": workspaceID],
                                                           in: nil, contentWorld: .defaultClient)
        try Task.checkCancellation()
        guard let result = result as? [String: Any], let status = result["status"] as? Int else {
            throw ClaudeUsageError.invalidResponse
        }
        workspaces = (result["workspaces"] as? [[String: String]] ?? []).compactMap {
            guard let id = $0["id"], let name = $0["name"], UUID(uuidString: id) != nil else { return nil }
            return ClaudeWebWorkspace(id: id, name: name)
        }
        switch status {
        case 200: break
        case 401: throw ClaudeUsageError.webSignInRequired
        case 403: throw ClaudeUsageError.webVerificationRequired
        case 409: throw ClaudeUsageError.organizationRequired
        case 429: throw ClaudeUsageError.rateLimited(ClaudeUsageClient.retryDate(result["retryAfter"] as? String))
        default: throw ClaudeUsageError.server(status)
        }
        guard let id = result["workspaceID"] as? String, UUID(uuidString: id) != nil,
              let usage = result["usage"] as? [String: Any] else { throw ClaudeUsageError.invalidResponse }
        workspaceID = id
        UserDefaults.standard.set(id, forKey: Self.workspaceKey)
        let identity = SHA256.hash(data: Data(("claude-web:" + id).utf8)).map { String(format: "%02x", $0) }.joined()
        var snapshot = try ClaudeUsageClient.decode(JSONSerialization.data(withJSONObject: usage),
                                                    credentialID: identity, plan: nil)
        snapshot.source = .web
        return snapshot
    }

    private func loadUsagePage() async throws {
        let id = UUID()
        navigationID = id
        try await withCheckedThrowingContinuation { continuation in
            navigationWaiter?.resume(throwing: CancellationError())
            navigationWaiter = continuation
            webView.load(URLRequest(url: URL(string: "https://claude.ai/settings/usage")!))
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(25))
                guard let self, self.navigationID == id, self.navigationWaiter != nil else { return }
                self.finishNavigation(.failure(URLError(.timedOut)))
            }
        }
    }

    private func finishNavigation(_ result: Result<Void, Error>) {
        let waiter = navigationWaiter
        navigationWaiter = nil
        waiter?.resume(with: result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        finishNavigation(.success(()))
        if window?.isVisible == true, webView.url?.host == "claude.ai" { onReady?() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }
        finishNavigation(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }
        finishNavigation(.failure(error))
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        guard window?.isVisible == true, !connected, !cookieCheckScheduled else { return }
        cookieCheckScheduled = true
        // Cookie writes can precede the completed sign-in navigation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.cookieCheckScheduled = false
            if self.window?.isVisible == true, !self.connected { self.onReady?() }
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        // Google/Apple complete sign-in through window.opener. Loading a popup's
        // request into the parent destroys that channel and strands the login.
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 560, height: 680), configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        let authWindow = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        authWindow.title = "Claude sign-in"
        authWindow.identifier = NSUserInterfaceItemIdentifier("QuotaGlance.ClaudeAuth")
        authWindow.contentView = popup
        authWindow.isReleasedWhenClosed = false
        authWindow.delegate = self
        authWindow.center()
        authWindows[ObjectIdentifier(popup)] = authWindow
        authWindow.makeKeyAndOrderFront(nil)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        authWindows.removeValue(forKey: ObjectIdentifier(webView))?.close()
        window?.makeKeyAndOrderFront(nil)
        onReady?()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        authWindows = authWindows.filter { $0.value !== closing }
    }

    // Runs in an isolated WebKit content world, so the page cannot replace fetch.
    // Only the two documented, same-origin usage reads are issued. No cookie is exported.
    private static let usageScript = #"""
    if (location.origin !== 'https://claude.ai') return {status: 401};
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 20000);
    const get = path => fetch(path, {credentials: 'same-origin', cache: 'no-store', signal: controller.signal});
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
        return {status: 200, workspaces, workspaceID: selected.id, usage: {seven_day: usage.seven_day, five_hour: usage.five_hour}};
    } finally { clearTimeout(timeout); }
    """#
}

private struct ClaudeConnectionView: View {
    @ObservedObject var session: ClaudeWebSession

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect Claude").font(.system(size: 18, weight: .semibold))
                    Text("Sign in on claude.ai. Your session stays on this Mac.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if session.checking { ProgressView().controlSize(.small) }
            }.padding(18)
            Divider()
            ClaudeSessionWebView(webView: session.webView)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if session.workspaces.count > 1 {
                    Picker("Workspace", selection: Binding(get: { session.workspaceID }, set: session.selectWorkspace)) {
                        Text("Choose a workspace").tag("")
                        ForEach(session.workspaces) { Text($0.name).tag($0.id) }
                    }
                }
                HStack(spacing: 14) {
                    Text(session.connectionMessage).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Check connection", action: session.checkConnection).disabled(session.checking)
                    Button("Done", action: session.close).keyboardShortcut(.defaultAction)
                }
            }.padding(16)
        }
    }
}

private struct ClaudeSessionWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
