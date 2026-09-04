import Foundation
import OSLog

enum ResetClockStarterSettings {
    static let enabledKey = "QuotaGlance.resetClockStarter.enabled"
    static let lastAttemptResetKey = "QuotaGlance.resetClockStarter.lastAttemptReset"
    static let lastAttemptAtKey = "QuotaGlance.resetClockStarter.lastAttemptAt"
    static let attemptCountKey = "QuotaGlance.resetClockStarter.attemptCount"
    static let lastSuccessResetKey = "QuotaGlance.resetClockStarter.lastSuccessReset"
    static let lastRunAtKey = "QuotaGlance.resetClockStarter.lastRunAt"
    static let lastResultKey = "QuotaGlance.resetClockStarter.lastResult"

    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: enabledKey) != nil else { return true }
        return defaults.bool(forKey: enabledKey)
    }

    static var lastResult: String? {
        UserDefaults.standard.string(forKey: lastResultKey)
    }
}

struct ResetClockStarterCommand {
    static let model = "gpt-5.6-luna"
    static let reasoningEffort = "low"

    static func arguments(workDirectory: URL, ephemeral: Bool = true) -> [String] {
        var values = ["exec"]
        if ephemeral { values.append("--ephemeral") }
        values += [
            "--ignore-user-config",
            "--ignore-rules",
            "--skip-git-repo-check",
            "--sandbox", "read-only",
            "-C", workDirectory.path,
            "--model", model,
            "-c", "model_reasoning_effort=\"\(reasoningEffort)\"",
            "-c", "service_tier=\"default\"",
            "--color", "never",
            "Hello. Reply with exactly: hello"
        ]
        return values
    }
}

enum ResetClockStarter {
    private static let logger = Logger(
        subsystem: "com.drewdudney.quotaglance",
        category: "ResetClockStarter"
    )
    private static let retryInterval: TimeInterval = 15 * 60
    private static let maximumAttempts = 12

    static func startIfNeeded(for resetAt: Date, now: Date = Date()) {
        guard ResetClockStarterSettings.isEnabled,
              claimAttempt(for: resetAt, now: now)
        else { return }

        Task.detached(priority: .utility) {
            let result = runHello()
            let defaults = UserDefaults.standard
            defaults.set(Date(), forKey: ResetClockStarterSettings.lastRunAtKey)
            defaults.set(result.message, forKey: ResetClockStarterSettings.lastResultKey)
            if result.succeeded {
                defaults.set(resetAt, forKey: ResetClockStarterSettings.lastSuccessResetKey)
                logger.notice("Weekly clock primed successfully")
            } else {
                logger.error("Weekly clock primer failed: \(result.message, privacy: .public)")
            }
        }
    }

    static func forceTest() {
        Task.detached(priority: .utility) {
            let result = runHello()
            UserDefaults.standard.set(Date(), forKey: ResetClockStarterSettings.lastRunAtKey)
            UserDefaults.standard.set("Test: \(result.message)", forKey: ResetClockStarterSettings.lastResultKey)
        }
    }

    static func claimAttempt(
        for resetAt: Date,
        now: Date,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if let succeededReset = defaults.object(forKey: ResetClockStarterSettings.lastSuccessResetKey) as? Date,
           sameReset(succeededReset, resetAt) {
            return false
        }

        let previousReset = defaults.object(forKey: ResetClockStarterSettings.lastAttemptResetKey) as? Date
        let isRetry = previousReset.map { sameReset($0, resetAt) } ?? false
        let previousAttemptAt = defaults.object(forKey: ResetClockStarterSettings.lastAttemptAtKey) as? Date
        if isRetry,
           let previousAttemptAt,
           now.timeIntervalSince(previousAttemptAt) < retryInterval {
            return false
        }

        let attempts = isRetry ? defaults.integer(forKey: ResetClockStarterSettings.attemptCountKey) : 0
        guard attempts < maximumAttempts else { return false }
        defaults.set(resetAt, forKey: ResetClockStarterSettings.lastAttemptResetKey)
        defaults.set(now, forKey: ResetClockStarterSettings.lastAttemptAtKey)
        defaults.set(attempts + 1, forKey: ResetClockStarterSettings.attemptCountKey)
        return true
    }

    private static func sameReset(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 30 * 60
    }

    private static func runHello() -> (succeeded: Bool, message: String) {
        guard let executable = codexExecutable() else {
            return (false, "Codex CLI not found")
        }
        guard let workDirectory = workingDirectory() else {
            return (false, "Could not create private working folder")
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ResetClockStarterCommand.arguments(workDirectory: workDirectory)
        process.currentDirectoryURL = workDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(90)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if process.isRunning {
                process.terminate()
                return (false, "Timed out; will retry")
            }
            if process.terminationStatus == 0 {
                return (true, "Clock started with Luna low")
            }
            return (false, "Codex exited \(process.terminationStatus); will retry")
        } catch {
            return (false, "Could not launch Codex; will retry")
        }
    }

    private static func codexExecutable() -> URL? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }

    private static func workingDirectory() -> URL? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = applicationSupport
            .appendingPathComponent("QuotaGlance", isDirectory: true)
            .appendingPathComponent("ClockStarter", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory
        } catch {
            return nil
        }
    }
}
