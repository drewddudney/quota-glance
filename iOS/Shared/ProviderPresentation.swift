import Foundation
import SwiftUI

enum MobileProviderSelection: String, CaseIterable, Identifiable {
    case codex, claude, both
    static let key = "QuotaGlance.mobile.providers"
    static let defaults = UserDefaults(suiteName: SharedSnapshotStore.appGroup) ?? .standard
    var id: String { rawValue }
    var title: String { self == .both ? "Both" : rawValue.capitalized }
    var providers: [DisplayProvider] {
        switch self { case .codex: [.codex]; case .claude: [.claude]; case .both: [.codex, .claude] }
    }
    static var current: Self { Self(rawValue: defaults.string(forKey: key) ?? "") ?? .both }
}

enum QuotaStyle {
    static let background = Color(red: 0.035, green: 0.043, blue: 0.047)
    static let surface = Color(red: 0.075, green: 0.086, blue: 0.09)
    static let text = Color(red: 0.94, green: 0.95, blue: 0.93)
    static let quiet = Color(red: 0.59, green: 0.63, blue: 0.64)
    static let reset = Color(red: 0.57, green: 0.88, blue: 0.68)
    static let session = Color(red: 0.91, green: 0.75, blue: 0.49)
    static func tint(_ provider: DisplayProvider) -> Color {
        provider == .codex ? Color(red: 0.56, green: 0.76, blue: 0.98) : Color(red: 0.88, green: 0.59, blue: 0.45)
    }
}

/// Display policy shared by the app and widgets. Expired windows never imply
/// that an account has received a fresh allowance until the provider confirms it.
struct MobileProviderReading {
    let provider: DisplayProvider
    let usage: Double?
    let week: Double?
    let third: Double?
    let deadline: Date?
    let sessionDeadline: Date?
    let capturedAt: Date?
    let needsConnection: Bool
    let isVerified: Bool
    let resetAnnounced: Bool

    init(provider: DisplayProvider, snapshot: QuotaSnapshot, at now: Date) {
        self.provider = provider
        if provider == .codex {
            deadline = snapshot.resetAt
            let ended = snapshot.resetAt.map { $0 <= now } ?? false
            usage = ended ? nil : Self.valid(snapshot.usagePercent)
            if let deadline {
                week = min(100, max(0, (1 - deadline.timeIntervalSince(now) / (7 * 86_400)) * 100))
            } else { week = Self.valid(snapshot.weekElapsedPercent) }
            resetAnnounced = snapshot.hasActiveResetAnnouncement(at: now)
            third = resetAnnounced ? 100 : Self.valid(snapshot.resetChancePercent)
            capturedAt = snapshot.usagePercent == nil && snapshot.secondaryQuota == nil ? nil : snapshot.usageMeasurementDate
            sessionDeadline = nil
            needsConnection = snapshot.codexNeedsConnection == true
            isVerified = snapshot.codexNeedsConnection != true
        } else {
            let claude = snapshot.claude
            usage = claude?.displayedUsage(at: now)
            week = claude?.weekElapsedPercent(at: now)
            third = claude?.displayedFiveHourUsage(at: now)
            deadline = claude?.resetAt
            sessionDeadline = claude?.fiveHourResetAt
            capturedAt = claude?.capturedAt
            needsConnection = claude?.needsConnection == true
            isVerified = claude?.verified == true
            resetAnnounced = false
        }
    }

    func status(at now: Date) -> String? {
        if needsConnection { return "Reconnect \(provider.name) in Settings" }
        guard let capturedAt else { return "Connect \(provider.name) in Settings" }
        if deadline.map({ $0 <= now }) == true { return "Waiting for the new week" }
        if now.timeIntervalSince(capturedAt) > 15 * 60 {
            return "Saved \(Self.age(capturedAt, at: now)) ago"
        }
        if !isVerified { return "Waiting for verified usage" }
        return nil
    }

    static func valid(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }
    static func percent(_ value: Double?) -> String { valid(value).map { "\(Int($0.rounded()))%" } ?? "—" }
    static func remaining(until date: Date?, at now: Date, days: Bool = false) -> String? {
        guard let date, date > now else { return nil }
        let minutes = Int(ceil(date.timeIntervalSince(now) / 60))
        if days, minutes >= 1_440 { return "\(minutes / 1_440)d \((minutes % 1_440) / 60)h" }
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
    static func age(_ date: Date, at now: Date) -> String {
        let minutes = max(1, Int(now.timeIntervalSince(date) / 60))
        return minutes < 60 ? "\(minutes)m" : minutes < 1_440 ? "\(minutes / 60)h" : "\(minutes / 1_440)d"
    }
}

struct QuotaRail: View {
    let value: Double?
    let tint: Color
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(tint.opacity(0.13))
                .overlay(alignment: .leading) {
                    Capsule().fill(tint)
                        .frame(width: geometry.size.width * (MobileProviderReading.valid(value) ?? 0) / 100)
                }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

struct QuotaPetImage: View {
    let provider: DisplayProvider
    var frame = 0
    var waving = false
    var body: some View {
        let name = provider == .codex
            ? (waving ? "CodexWave\(frame % 4)" : "CodexIdle\(frame % 2)")
            : (waving ? ["ClawdIdle", "ClawdWave", "ClawdWink", "ClawdWave"][frame % 4] : ["ClawdIdle", "ClawdWink"][frame % 2])
        Image(name).resizable().interpolation(.high).scaledToFit()
            .accessibilityHidden(true)
    }
}
