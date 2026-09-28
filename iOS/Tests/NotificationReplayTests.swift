import UserNotifications
import XCTest
@testable import QuotaGlanceMobile

final class NotificationReplayTests: XCTestCase {
    private var preferences: NotificationPreferences {
        .init(resetAnnounced: true, resetCompleted: true, prominentResetAlert: false,
              usageApproachingLimit: false, usageThreshold: 90, renewalSoon: false,
              resetCreditExpiring: false, paceRisk: false, staleSync: false,
              tiboPosts: true, codexTasks: false, sessionLiveActivity: false,
              claudeUsage: false, claudeWeek: false)
    }

    private func post(_ id: String, at date: Date, reset: Bool = false) -> QuotaTiboPost {
        .init(id: id, date: date, text: reset ? "Usage limits reset tomorrow." : "A new update from Tibo.",
              inReplyTo: nil, url: URL(string: "https://x.com/thsottiaux/status/\(id)"), isResetOriented: reset)
    }

    private func snapshot(_ post: QuotaTiboPost, source: String? = nil) -> QuotaSnapshot {
        var value = QuotaSnapshot.empty
        value.capturedAt = .now
        value.tiboPosts = [post]
        if let source {
            value.resetAnnounced = true
            value.announcementID = "\(source):\(post.id)"
            value.announcementURL = post.url
            value.announcementDate = post.date
            value.announcementExpectedAt = Date().addingTimeInterval(3_600)
            value.announcementText = post.text
        }
        return value
    }

    @MainActor
    func testOpeningAgainAndSwitchingAnnouncementMirrorsDoesNotReplaySavedEvents() async throws {
        let suite = "NotificationReplayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let savedPost = post("2100000000000000002", at: Date().addingTimeInterval(-3_600), reset: true)
        let saved = snapshot(savedPost, source: "gussuri")
        defaults.set("gussuri:\(savedPost.url!.absoluteString)", forKey: "QuotaGlance.notifiedAnnouncementID")
        NotificationManager.saveTiboNotificationState(
            NotificationManager.tiboNotificationState(posts: [savedPost], defaults: defaults), defaults: defaults)

        var requests: [String] = []
        for source in ["lunar", "will", "gussuri", "scheduled", "lunar"] {
            // A new delivery object models process memory being discarded.
            let delivery = NotificationDelivery(defaults: defaults) { requests.append($0.identifier) }
            await NotificationManager.evaluate(snapshot(savedPost, source: source), previous: saved,
                                               preferences: preferences, delivery: delivery)
        }
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue((defaults.stringArray(forKey: NotificationDelivery.eventKey) ?? [])
            .contains("reset-announced-x:\(savedPost.id)"))
    }

    @MainActor
    func testNewResetIsOneAlertAndLaterNewTweetStillNotifies() async throws {
        let suite = "NotificationReplayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var requests: [String] = []
        let delivery = NotificationDelivery(defaults: defaults) { requests.append($0.identifier) }
        let baselinePost = post("2100000000000000001", at: Date().addingTimeInterval(-7_200))
        let baseline = snapshot(baselinePost)
        await NotificationManager.evaluate(baseline, previous: baseline, preferences: preferences, delivery: delivery)

        let resetPost = post("2100000000000000002", at: Date().addingTimeInterval(-60), reset: true)
        let reset = snapshot(resetPost, source: "lunar")
        await NotificationManager.evaluate(reset, previous: baseline, preferences: preferences, delivery: delivery)
        await NotificationManager.evaluate(snapshot(resetPost, source: "will"), previous: reset,
                                           preferences: preferences, delivery: delivery)
        XCTAssertEqual(requests, ["reset-announced-x:\(resetPost.id)"])

        let laterPost = post("2100000000000000003", at: Date())
        let later = snapshot(laterPost)
        await NotificationManager.evaluate(later, previous: reset, preferences: preferences, delivery: delivery)
        let relaunched = NotificationDelivery(defaults: defaults) { requests.append($0.identifier) }
        await NotificationManager.evaluate(later, previous: later, preferences: preferences, delivery: relaunched)
        XCTAssertEqual(requests, ["reset-announced-x:\(resetPost.id)", "tibo-post-x:\(laterPost.id)"])
    }

    @MainActor
    func testOverlappingForegroundAndBackgroundRefreshesQueueTweetOnce() async throws {
        let suite = "NotificationReplayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let baseline = snapshot(post("2100000000000000001", at: Date().addingTimeInterval(-3_600)))
        NotificationManager.saveTiboNotificationState(
            NotificationManager.tiboNotificationState(posts: baseline.tiboPosts!, defaults: defaults), defaults: defaults)
        let current = snapshot(post("2100000000000000002", at: Date()))
        let queued = expectation(description: "First notification is awaiting iOS")
        var resume: CheckedContinuation<Void, Never>?
        var requests: [String] = []
        let delivery = NotificationDelivery(defaults: defaults) { request in
            requests.append(request.identifier)
            await withCheckedContinuation { continuation in
                resume = continuation
                queued.fulfill()
            }
        }
        let first = Task { await NotificationManager.evaluate(current, previous: baseline,
                                                              preferences: preferences, delivery: delivery) }
        await fulfillment(of: [queued], timeout: 3)
        await NotificationManager.evaluate(current, previous: baseline, preferences: preferences, delivery: delivery)
        XCTAssertEqual(requests.count, 1)
        resume?.resume()
        await first.value
        XCTAssertEqual(defaults.stringArray(forKey: NotificationDelivery.eventKey)?.count, 2)
    }

    @MainActor
    func testDeliveredResetCannotReplayAfterOldSixHourCooldown() async throws {
        let suite = "NotificationReplayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        var previous = QuotaSnapshot.empty
        previous.capturedAt = now.addingTimeInterval(-60)
        previous.usagePercent = 60
        previous.usageWindowStart = now.addingTimeInterval(-86_400)
        var current = previous
        current.capturedAt = now
        current.usagePercent = 0
        current.usageWindowStart = now
        defaults.set("usage-\(Int(now.timeIntervalSince1970))", forKey: "QuotaGlance.notifiedResetCompletionID")
        defaults.set(now.addingTimeInterval(-7 * 3_600).timeIntervalSince1970, forKey: "QuotaGlance.notifiedResetCompletionAt")
        var requests: [String] = []
        let delivery = NotificationDelivery(defaults: defaults) { requests.append($0.identifier) }
        await NotificationManager.evaluate(current, previous: previous, preferences: preferences, delivery: delivery)
        XCTAssertTrue(requests.isEmpty)
    }

    @MainActor
    func testFailedSubmissionCanRetryButDeliveredIdentifierSurvivesRelaunch() async throws {
        let suite = "NotificationReplayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var attempts = 0
        let delivery = NotificationDelivery(defaults: defaults) { _ in
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
        }
        let content = UNMutableNotificationContent()
        let failed = await delivery.add(content, identifier: "reset-announced-x:2100000000000000002")
        let retried = await delivery.add(content, identifier: "reset-announced-x:2100000000000000002")
        let relaunched = NotificationDelivery(defaults: defaults) { _ in attempts += 1 }
        let duplicate = await relaunched.add(content, identifier: "reset-announced-x:2100000000000000002")
        XCTAssertFalse(failed)
        XCTAssertTrue(retried)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(attempts, 2)
    }
}
