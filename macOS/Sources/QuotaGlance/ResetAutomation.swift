import Foundation
import OSLog

struct ResetAutomationEvent: Codable, Sendable {
    let event: String
    let observedAt: Date
    let usedPercent: Double
    let resetAt: Date?
    let planName: String
}

enum ResetAutomationSettings {
    static let soundEnabledKey = "QuotaGlance.resetActions.soundEnabled"
    static let shortcutNameKey = "QuotaGlance.resetActions.shortcutName"
    static let executablePathKey = "QuotaGlance.resetActions.executablePath"
    static let lastResultKey = "QuotaGlance.resetActions.lastResult"
    static let lastRunAtKey = "QuotaGlance.resetActions.lastRunAt"

    static var soundEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: soundEnabledKey) != nil else { return true }
        return defaults.bool(forKey: soundEnabledKey)
    }

    static var shortcutName: String? {
        normalized(UserDefaults.standard.string(forKey: shortcutNameKey))
    }

    static var executablePath: String? {
        normalized(UserDefaults.standard.string(forKey: executablePathKey))
    }

    static var hasExternalAction: Bool {
        shortcutName != nil || executablePath != nil
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ResetAutomationRunner {
    private static let logger = Logger(
        subsystem: "com.example.quotaglance",
        category: "ResetAutomation"
    )

    static func dispatch(_ event: ResetAutomationEvent) {
        guard ResetAutomationSettings.hasExternalAction else { return }
        Task.detached(priority: .utility) {
            var results: [String] = []
            if let shortcut = ResetAutomationSettings.shortcutName {
                let result = run(
                    executable: "/usr/bin/shortcuts",
                    arguments: ["run", shortcut],
                    event: event
                )
                results.append("Shortcut \(shortcut): \(result)")
            }
            if let executable = ResetAutomationSettings.executablePath {
                let result = run(executable: executable, arguments: [], event: event)
                results.append("Hook \((executable as NSString).lastPathComponent): \(result)")
            }
            let summary = results.joined(separator: " · ")
            UserDefaults.standard.set(Date(), forKey: ResetAutomationSettings.lastRunAtKey)
            UserDefaults.standard.set(summary, forKey: ResetAutomationSettings.lastResultKey)
            logger.notice("Reset actions finished: \(summary, privacy: .public)")
        }
    }

    private static func run(
        executable: String,
        arguments: [String],
        event: ResetAutomationEvent
    ) -> String {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return "not executable"
        }

        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["QUOTA_GLANCE_EVENT"] = event.event
        environment["QUOTA_GLANCE_USED_PERCENT"] = String(format: "%.2f", event.usedPercent)
        environment["QUOTA_GLANCE_PLAN"] = event.planName
        environment["QUOTA_GLANCE_OBSERVED_AT"] = ISO8601DateFormatter().string(from: event.observedAt)
        if let resetAt = event.resetAt {
            environment["QUOTA_GLANCE_RESET_AT"] = ISO8601DateFormatter().string(from: resetAt)
        }
        process.environment = environment

        do {
            try process.run()
            if let payload = try? JSONEncoder().encode(event) {
                input.fileHandleForWriting.write(payload)
                input.fileHandleForWriting.write(Data("\n".utf8))
            }
            try? input.fileHandleForWriting.close()

            let deadline = Date().addingTimeInterval(15)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
                return "timed out"
            }
            return process.terminationStatus == 0 ? "completed" : "exit \(process.terminationStatus)"
        } catch {
            return "failed to launch"
        }
    }
}
