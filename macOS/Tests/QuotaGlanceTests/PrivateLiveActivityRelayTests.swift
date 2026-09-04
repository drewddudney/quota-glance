import XCTest
@testable import QuotaGlance

final class PrivateLiveActivityRelayTests: XCTestCase {
    func testResidualTokenPaceProducesAnEndEventWithoutARunningTask() throws {
        let json = """
        {
          "capturedAt": 1800000000,
          "selectedSource": "average",
          "providers": [],
          "resetAnnounced": false,
          "usagePercent": 22,
          "tokenPace": {
            "fiveMinutes": 3350000,
            "oneHour": 12000000,
            "twelveHours": 12000000,
            "twentyFourHours": 12000000,
            "sinceReset": 12000000
          },
          "activeTasks": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(MobileQuotaSnapshot.self, from: Data(json.utf8))
        let update = PrivateLiveActivityUpdate(
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: 1_800_000_001)
        )

        XCTAssertFalse(update.isActive)
        let data = try JSONEncoder().encode(update.payload)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let aps = try XCTUnwrap(root["aps"] as? [String: Any])
        XCTAssertEqual(aps["event"] as? String, "end")
        XCTAssertNotNil(aps["dismissal-date"])
    }

    func testForcedEndPayloadEndsAnOldSessionWhenTheNewSnapshotIsActive() throws {
        let json = """
        {
          "capturedAt": 1800000000,
          "selectedSource": "average",
          "providers": [],
          "resetAnnounced": false,
          "usagePercent": 23,
          "activeTasks": [{
            "id": "new-task",
            "name": "New task",
            "state": "running",
            "source": "codex",
            "updatedAt": 1800000000
          }]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(MobileQuotaSnapshot.self, from: Data(json.utf8))
        let update = PrivateLiveActivityUpdate(
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let data = try JSONEncoder().encode(update.endPayload)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let aps = try XCTUnwrap(root["aps"] as? [String: Any])
        XCTAssertEqual(aps["event"] as? String, "end")
        XCTAssertEqual(aps["dismissal-date"] as? Int, 1_800_000_000)
    }

    func testRemoteStartPayloadIncludesActivityKitBootstrapFields() throws {
        let payload = APNsLiveActivityPayload(aps: .init(
            timestamp: 1_788_106_000,
            event: "start",
            contentState: APNsCodexContentState(
                taskName: "Codex is working",
                usedPercent: 22.125,
                totalTokens: 123_000_000,
                tokensPerMinute: 670_000,
                percentPerMinute: 0.125,
                updatedAt: Date(timeIntervalSince1970: 1_788_106_000)
            ),
            staleDate: 1_788_106_600,
            dismissalDate: nil,
            attributesType: "CodexSessionActivityAttributes",
            attributes: .init(sessionID: "session-1"),
            alert: .init(title: "Codex is working", body: "Live token usage is now updating."),
            inputPushToken: 1
        ))

        let data = try JSONEncoder().encode(payload)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let aps = try XCTUnwrap(root["aps"] as? [String: Any])
        XCTAssertEqual(aps["event"] as? String, "start")
        XCTAssertEqual(aps["attributes-type"] as? String, "CodexSessionActivityAttributes")
        XCTAssertEqual((aps["attributes"] as? [String: Any])?["sessionID"] as? String, "session-1")
        XCTAssertEqual(aps["input-push-token"] as? Int, 1)
        XCTAssertNotNil(aps["alert"])
        XCTAssertNotNil(aps["content-state"])
    }

    func testSessionIdentityStaysStableWhenTheActiveTaskChanges() throws {
        func snapshot(taskID: String) throws -> MobileQuotaSnapshot {
            let json = """
            {
              "capturedAt": 1800000300,
              "usageWindowStart": 1799990000,
              "selectedSource": "average",
              "providers": [],
              "resetAnnounced": false,
              "usagePercent": 23,
              "activeTasks": [{
                "id": "\(taskID)",
                "name": "Task \(taskID)",
                "state": "active",
                "source": "codex",
                "updatedAt": 1800000300
              }]
            }
            """
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode(MobileQuotaSnapshot.self, from: Data(json.utf8))
        }

        let first = PrivateLiveActivityUpdate(
            snapshot: try snapshot(taskID: "first"),
            now: Date(timeIntervalSince1970: 1_800_000_300)
        )
        let second = PrivateLiveActivityUpdate(
            snapshot: try snapshot(taskID: "second"),
            now: Date(timeIntervalSince1970: 1_800_000_301)
        )

        XCTAssertEqual(first.sessionID, second.sessionID)
        XCTAssertEqual(first.sessionID, "usage-1799990000")
    }
}
