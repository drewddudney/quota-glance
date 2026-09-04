import XCTest
@testable import QuotaGlance

final class CodexActivityProbeTests: XCTestCase {
    func testFindsLatestRolloutModificationInTodayDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy/MM/dd"
        let day = root.appendingPathComponent(formatter.string(from: now), isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let rollout = day.appendingPathComponent("rollout-test.jsonl")
        try Data("{}\n".utf8).write(to: rollout)
        let expected = now.addingTimeInterval(-20)
        try FileManager.default.setAttributes([.modificationDate: expected], ofItemAtPath: rollout.path)

        let result = CodexActivityProbe.latestActivity(
            sessionsRoot: root,
            now: now,
            calendar: calendar
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.01)
    }

    func testDetectsRunningTurnWhenNewestLifecycleEventIsStarted() throws {
        let file = try rollout([
            event("task_started", at: "2026-08-30T16:00:00Z"),
            event("agent_message", at: "2026-08-30T16:00:01Z")
        ])
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        XCTAssertTrue(CodexActivityProbe.isTurnActive(rolloutURL: file))
    }

    func testDetectsCompletedTurnWhenNewestLifecycleEventIsComplete() throws {
        let file = try rollout([
            event("task_started", at: "2026-08-30T16:00:00Z"),
            event("task_complete", at: "2026-08-30T16:00:10Z")
        ])
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        XCTAssertFalse(CodexActivityProbe.isTurnActive(rolloutURL: file))
    }

    private func rollout(_ lines: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("rollout.jsonl")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
        return file
    }

    private func event(_ type: String, at timestamp: String) -> String {
        #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"\#(type)"}}"#
    }
}
