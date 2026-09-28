import XCTest
import WebKit
@testable import QuotaGlanceMobile

final class DirectProviderDecoderTests: XCTestCase {
    private let measuredAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let workspaceID = "933F35D2-44F6-4DC9-BDF0-271190960EE0"

    func testCodexUsesDeclaredDurationInEitherWindowPosition() throws {
        let fiveHour: [String: Any] = ["used_percent": 21, "limit_window_seconds": 18_000, "reset_at": 1_800_010_000]
        let weekly: [String: Any] = ["used_percent": 73, "limit_window_seconds": 604_800, "reset_at": 1_800_500_000]
        for (primary, secondary) in [(fiveHour, weekly), (weekly, fiveHour)] {
            let reading = try DirectProviderUsageDecoder.codex([
                "plan_type": "pro", "rate_limit": ["primary_window": primary, "secondary_window": secondary]
            ], accountID: "test-account", userID: "test-user", now: measuredAt)
            XCTAssertEqual(reading.weekly?.usedPercent, 73)
            XCTAssertEqual(reading.weekly?.durationMinutes, 10_080)
            XCTAssertEqual(reading.fiveHour?.usedPercent, 21)
            XCTAssertEqual(reading.fiveHour?.durationMinutes, 300)
            XCTAssertEqual(reading.measuredAt, measuredAt)
            XCTAssertEqual(reading.planName, "pro")
            XCTAssertNotEqual(reading.accountID, "test-account")
        }
    }

    func testMissingCodexWeekStaysMissing() throws {
        let reading = try DirectProviderUsageDecoder.codex([
            "rate_limit": ["primary_window": ["used_percent": 42, "limit_window_seconds": 18_000], "secondary_window": NSNull()]
        ], accountID: "test-account", userID: nil)
        XCTAssertNil(reading.weekly)
        XCTAssertEqual(reading.fiveHour?.usedPercent, 42)
        XCTAssertNil(reading.fiveHour?.resetAt)
    }

    func testUnknownCodexDurationIsNotInferredFromWindowPosition() throws {
        let reading = try DirectProviderUsageDecoder.codex([
            "rate_limit": ["primary_window": ["used_percent": 42], "secondary_window": ["used_percent": 55, "limit_window_seconds": 86_400]]
        ], accountID: "test-account", userID: nil)
        XCTAssertNil(reading.weekly)
        XCTAssertNil(reading.fiveHour)
    }

    func testCodexRejectsMalformedAndNonfiniteNumbers() {
        for value: Any in [true, "21", Double.nan, Double.infinity, -1, 101] {
            XCTAssertThrowsError(try DirectProviderUsageDecoder.codex([
                "rate_limit": ["primary_window": ["used_percent": value, "limit_window_seconds": 18_000]]
            ], accountID: "test-account", userID: nil))
        }
        for key in ["limit_window_seconds", "reset_at"] {
            for value: Any in [true, "123", Double.infinity, -1, 0] {
                XCTAssertThrowsError(try DirectProviderUsageDecoder.codex([
                    "rate_limit": ["primary_window": ["used_percent": 10, key: value]]
                ], accountID: "test-account", userID: nil))
            }
        }
        XCTAssertThrowsError(try DirectProviderUsageDecoder.codex(["rate_limit": "unknown"], accountID: "account", userID: nil))
        XCTAssertThrowsError(try DirectProviderUsageDecoder.codex([:], accountID: "account", userID: nil))
    }

    func testClaudeNullAndEmptyWindowsPreserveMissingValues() throws {
        let nulls = try DirectProviderUsageDecoder.claude([
            "seven_day": NSNull(), "five_hour": NSNull()
        ], workspaceID: workspaceID, now: measuredAt)
        XCTAssertNil(nulls.weekly)
        XCTAssertNil(nulls.fiveHour)
        let empty = try DirectProviderUsageDecoder.claude([
            "seven_day": [String: Any](), "five_hour": ["utilization": NSNull(), "resets_at": NSNull()]
        ], workspaceID: workspaceID)
        XCTAssertNotNil(empty.weekly)
        XCTAssertNil(empty.weekly?.usedPercent)
        XCTAssertNil(empty.weekly?.resetAt)
        XCTAssertNil(empty.fiveHour?.usedPercent)
        XCTAssertNil(empty.fiveHour?.resetAt)
    }

    func testClaudeWindowsAndMalformedValues() throws {
        let reading = try DirectProviderUsageDecoder.claude([
            "seven_day": ["utilization": 12.5, "resets_at": "2027-01-17T00:00:00.000Z"],
            "five_hour": ["utilization": 0, "resets_at": "2027-01-11T12:00:00Z"]
        ], workspaceID: workspaceID)
        XCTAssertEqual(reading.weekly?.usedPercent, 12.5)
        XCTAssertNotNil(reading.weekly?.resetAt)
        XCTAssertEqual(reading.fiveHour?.usedPercent, 0)
        XCTAssertEqual(reading.fiveHour?.durationMinutes, 300)
        for value: Any in [true, "12.5", Double.nan, Double.infinity, -1, 101] {
            XCTAssertThrowsError(try DirectProviderUsageDecoder.claude([
                "seven_day": ["utilization": value]
            ], workspaceID: workspaceID))
        }
        XCTAssertThrowsError(try DirectProviderUsageDecoder.claude([
            "seven_day": ["resets_at": "not a date"]
        ], workspaceID: workspaceID))
    }

    func testRetryAfterNeverRetriesEarlierThanProviderRequested() {
        XCTAssertEqual(DirectProviderUsageDecoder.retryDate("900", now: measuredAt), measuredAt.addingTimeInterval(900))
        XCTAssertGreaterThanOrEqual(DirectProviderUsageDecoder.retryDate("0", now: measuredAt), measuredAt)
        XCTAssertEqual(DirectProviderUsageDecoder.retryDate(nil, now: measuredAt), measuredAt.addingTimeInterval(300))
        let later = Date(timeIntervalSince1970: 1_800_001_800)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        XCTAssertEqual(DirectProviderUsageDecoder.retryDate(formatter.string(from: later), now: measuredAt), later)
    }

    func testCodexUsesQuotaClaimsInsteadOfTheLoginSubject() throws {
        let token = try testToken([
            "sub": "auth0|login-subject", "https://api.openai.com/auth": [
                "chatgpt_account_id": "workspace-a", "chatgpt_user_id": "quota-user-a"
            ]
        ])
        let claims = CodexSessionIdentity.claims(in: token)
        let resolved = try CodexSessionIdentity.resolve(
            usage: ["account_id": "workspace-a", "user_id": "quota-user-a"],
            selectedAccountID: nil, claims: claims
        )
        XCTAssertEqual(resolved.accountID, "workspace-a")
        XCTAssertEqual(resolved.userID, "quota-user-a")
        let subjectOnly = CodexSessionIdentity.claims(in: try testToken(["sub": "auth0|login-subject"]))
        XCTAssertNil(subjectOnly.userID)
        XCTAssertNil(subjectOnly.accountID)
    }

    func testCodexAccountAndUserMismatchAreRejected() {
        let claims = CodexSessionIdentity(accountID: "personal", userID: "quota-user-a")
        XCTAssertThrowsError(try CodexSessionIdentity.resolve(
            usage: ["account_id": "another-workspace", "user_id": "quota-user-a"],
            selectedAccountID: "personal", claims: claims
        ))
        XCTAssertThrowsError(try CodexSessionIdentity.resolve(
            usage: ["account_id": "personal", "user_id": "another-user"],
            selectedAccountID: "personal", claims: claims
        ))
    }

    func testCodexExplicitWorkspaceAndAuthoritativeUsageIdentity() throws {
        let selected = try CodexSessionIdentity.resolve(
            usage: ["account_id": "team", "user_id": "quota-user-a"],
            selectedAccountID: "team",
            claims: .init(accountID: "personal", userID: "quota-user-a")
        )
        XCTAssertEqual(selected.accountID, "team")
        let responseOnly = try CodexSessionIdentity.resolve(
            usage: ["account_id": "personal", "user_id": "quota-user-a"],
            selectedAccountID: nil, claims: .init(accountID: nil, userID: nil)
        )
        XCTAssertEqual(responseOnly.accountID, "personal")
        XCTAssertEqual(responseOnly.userID, "quota-user-a")
    }

    func testCodexLegacyCanonicalUserClaim() throws {
        let token = try testToken(["https://api.openai.com/auth": ["user_id": "quota-user-a"]])
        XCTAssertEqual(CodexSessionIdentity.claims(in: token).userID, "quota-user-a")
        XCTAssertNil(CodexSessionIdentity.claims(in: "not-a-token").userID)
    }

    func testFailedInitialSignInRemainsRetryableWithoutOwningProvider() {
        let defaults = UserDefaults(suiteName: "group.com.example.quotaglance")!
        let enabled = "QuotaGlance.mobile.direct.codex.enabled.v1"
        let signIn = "QuotaGlance.mobile.direct.codex.needsSignIn.v1"
        let oldEnabled = defaults.object(forKey: enabled)
        let oldSignIn = defaults.object(forKey: signIn)
        defer {
            defaults.set(oldEnabled, forKey: enabled)
            defaults.set(oldSignIn, forKey: signIn)
        }
        defaults.set(false, forKey: enabled)
        defaults.set(true, forKey: signIn)
        XCTAssertTrue(DirectProviderUsageStore.hasPendingConnection(.codex))
        XCTAssertFalse(DirectProviderUsageStore.hasConnection(.codex))
    }

    @MainActor
    func testExplicitCheckRestoresPresentationAndRequestsRefresh() {
        let session = ProviderWebSession(provider: .codex)
        session.isPresenting = false
        var userInitiated: Bool?
        session.onCheck = { userInitiated = $0 }
        session.checkConnection()
        XCTAssertEqual(userInitiated, true)
        XCTAssertTrue(session.isPresenting)
        XCTAssertTrue(session.connectionMessage.contains("Checking"))
        session.dismiss()
    }

    @MainActor
    func testWebKitPromiseHasNativeDeadline() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let loaded = expectation(description: "Local web document loaded")
        let observer = LocalPageObserver(loaded: loaded)
        webView.navigationDelegate = observer
        webView.loadHTMLString("<html><body>Connection check</body></html>", baseURL: nil)
        await fulfillment(of: [loaded], timeout: 5)

        let success = try await ProviderConnectionJavaScript.evaluate("return 42;", arguments: [:], in: webView, timeout: 3)
        XCTAssertEqual(success as? Int, 42)
        let started = Date()
        do {
            _ = try await ProviderConnectionJavaScript.evaluate(
                "await new Promise(() => {});", arguments: [:], in: webView, timeout: 0.1
            )
            XCTFail("A pending web promise must time out")
        } catch ProviderConnectionError.timedOut {
            XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        }
        webView.stopLoading()
    }

    private func testToken(_ payload: [String: Any]) throws -> String {
        let encoded = try JSONSerialization.data(withJSONObject: payload).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }
}

@MainActor
private final class LocalPageObserver: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation
    init(loaded: XCTestExpectation) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
}
