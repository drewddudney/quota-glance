import XCTest
@testable import QuotaGlance

final class ResetClockStarterTests: XCTestCase {
    func testCommandUsesEphemeralLunaLowAndAPrivateWorkingDirectory() {
        let directory = URL(fileURLWithPath: "/tmp/quota-glance-clock-test")
        let arguments = ResetClockStarterCommand.arguments(workDirectory: directory)

        XCTAssertEqual(arguments.first, "exec")
        XCTAssertTrue(arguments.contains("--ephemeral"))
        XCTAssertTrue(arguments.contains("--ignore-user-config"))
        XCTAssertTrue(arguments.contains("read-only"))
        XCTAssertTrue(arguments.contains(directory.path))
        XCTAssertTrue(arguments.contains("gpt-5.6-luna"))
        XCTAssertTrue(arguments.contains("model_reasoning_effort=\"low\""))
        XCTAssertTrue(arguments.contains("service_tier=\"default\""))
    }

    func testAttemptIsDeduplicatedAndCanRetryAfterFifteenMinutes() {
        let suite = "ResetClockStarterTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let reset = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertTrue(ResetClockStarter.claimAttempt(for: reset, now: reset, defaults: defaults))
        XCTAssertFalse(
            ResetClockStarter.claimAttempt(
                for: reset,
                now: reset.addingTimeInterval(14 * 60),
                defaults: defaults
            )
        )
        XCTAssertTrue(
            ResetClockStarter.claimAttempt(
                for: reset,
                now: reset.addingTimeInterval(15 * 60),
                defaults: defaults
            )
        )
    }

    func testSuccessfulResetNeverRunsAgain() {
        let suite = "ResetClockStarterTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let reset = Date(timeIntervalSince1970: 2_000_000_000)
        defaults.set(reset, forKey: ResetClockStarterSettings.lastSuccessResetKey)

        XCTAssertFalse(
            ResetClockStarter.claimAttempt(
                for: reset,
                now: reset.addingTimeInterval(86_400),
                defaults: defaults
            )
        )
    }
}
