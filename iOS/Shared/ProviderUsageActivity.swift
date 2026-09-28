import ActivityKit
import SwiftUI

struct ProviderUsageActivityAttributes: ActivityAttributes {
    struct Reading: Codable, Hashable, Identifiable {
        var id: String { provider }
        let provider: String
        let usedPercent: Double?
        let weeklyResetAt: Date?
        let sessionUsedPercent: Double?
        let sessionResetAt: Date?
        let resetChance: Double?
        let measuredAt: Date
        var estimatedRunoutAt: Date? = nil
        var displayProvider: DisplayProvider { DisplayProvider(rawValue: provider) ?? .codex }
    }
    struct ContentState: Codable, Hashable {
        let readings: [Reading]
    }
    let startedAt: Date

    static func state(snapshot: QuotaSnapshot, providers: [DisplayProvider], now: Date = Date()) -> ContentState {
        let readings = providers.compactMap { provider -> Reading? in
            let value = MobileProviderReading(provider: provider, snapshot: snapshot, at: now)
            let sessionPercent = provider == .claude ? value.third : snapshot.secondaryQuota?.usedPercent
            let sessionEnd = provider == .claude ? value.sessionDeadline : snapshot.secondaryQuota?.resetAt
            guard let measuredAt = value.capturedAt, !value.needsConnection,
                  value.usage != nil || sessionPercent != nil else { return nil }
            return Reading(provider: provider.rawValue, usedPercent: value.usage, weeklyResetAt: value.deadline,
                           sessionUsedPercent: sessionPercent, sessionResetAt: sessionEnd,
                           resetChance: provider == .codex ? value.third : nil, measuredAt: measuredAt,
                           estimatedRunoutAt: provider == .codex ? snapshot.estimatedRunoutAt : snapshot.claude?.estimatedRunoutAt)
        }
        return ContentState(readings: readings)
    }
}

/// A compact estimate alongside a single active pet. The percentage belongs
/// to the weekly meter, so this uses that same window's recorded usage pace.
struct ProviderRunoutEstimate: View {
    let reading: ProviderUsageActivityAttributes.Reading
    var isStale = false

    private var duration: String? {
        guard !isStale, let deadline = reading.estimatedRunoutAt else { return nil }
        return MobileProviderReading.remaining(until: deadline, at: .now, days: true) ?? "0m"
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "hourglass").font(.system(size: 9, weight: .medium))
            Text(duration.map { "~\($0)" } ?? "Pace —")
                .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .foregroundStyle(QuotaStyle.tint(reading.displayProvider))
        .lineLimit(1).minimumScaleFactor(0.85)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(duration.map { "Estimated weekly quota remaining: \($0) at the current pace" }
                            ?? (isStale ? "Open to refresh the pace estimate" : "Recording usage to estimate pace"))
    }
}

/// Shared with the native preview so the Lock Screen composition is reviewed
/// at its actual size, using the same assets and typography as the extension.
struct ProviderUsageActivityContent: View {
    let readings: [ProviderUsageActivityAttributes.Reading]
    let startedAt: Date
    var isStale = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(readings) { reading in
                    if reading.id != readings.first?.id { Rectangle().fill(.white.opacity(0.12)).frame(width: 1) }
                    instrument(reading).frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.move(edge: reading.displayProvider == .codex ? .leading : .trailing).combined(with: .opacity))
                }
            }
            HStack(spacing: 4) {
                Image(systemName: isStale ? "clock" : "arrow.triangle.2.circlepath").font(.system(size: 9))
                Text(isStale ? "Open to refresh" : "Checked")
                if !isStale, let oldest = readings.map(\.measuredAt).min() { Text(oldest, style: .time) }
                Spacer()
                Text("Quota Glance")
            }
            .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.52))
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .foregroundStyle(.white)
        .animation(reduceMotion || luminanceReduced ? nil : .easeInOut(duration: 0.6), value: readings.map(\.provider))
    }

    private func instrument(_ reading: ProviderUsageActivityAttributes.Reading) -> some View {
        let provider = reading.displayProvider
        let tint = QuotaStyle.tint(provider)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                LiveCompanionPet(reading: reading).frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(MobileProviderReading.percent(reading.usedPercent))
                            .font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText(value: reading.usedPercent ?? 0))
                        Text("used").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                    }.lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            QuotaRail(value: reading.usedPercent, tint: tint)
            if provider == .claude {
                HStack(spacing: 4) {
                    Text(MobileProviderReading.percent(reading.sessionUsedPercent)).foregroundStyle(QuotaStyle.session)
                    Spacer(minLength: 3)
                    if let deadline = reading.sessionResetAt, deadline > startedAt {
                        Text(timerInterval: startedAt...deadline, countsDown: true, showsHours: true)
                            .multilineTextAlignment(.trailing).monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                    } else { Text("Session —") }
                }
            } else {
                HStack {
                    Text("Reset chance")
                    Spacer(minLength: 3)
                    Text(MobileProviderReading.percent(reading.resetChance)).foregroundStyle(QuotaStyle.reset)
                }
            }
        }
        .font(.system(size: 10, weight: .medium))
        .animation(reduceMotion || luminanceReduced ? nil : .spring(duration: 0.7, bounce: 0.25), value: reading.usedPercent)
    }
}

struct LiveCompanionPet: View {
    let reading: ProviderUsageActivityAttributes.Reading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    var body: some View {
        ZStack {
            if reading.displayProvider == .codex {
                Capsule().fill(QuotaStyle.tint(.codex).opacity(0.35)).frame(width: 29, height: 5).offset(y: 11)
            } else {
                Ellipse().fill(Color.cyan.opacity(0.3)).frame(width: 28, height: 7).offset(y: 12)
            }
            QuotaPetImage(provider: reading.displayProvider, frame: Int((reading.usedPercent ?? 0).rounded()) % 4,
                          waving: !reduceMotion && !luminanceReduced)
                .id(reduceMotion || luminanceReduced ? "still" : "\(reading.measuredAt.timeIntervalSince1970)")
                .transition(.asymmetric(
                    insertion: .move(edge: reading.displayProvider == .codex ? .leading : .bottom).combined(with: .scale(scale: 0.4)),
                    removal: .scale(scale: 0.7).combined(with: .opacity)
                ))
        }
        .animation(reduceMotion || luminanceReduced ? nil : .spring(duration: 0.8, bounce: 0.4), value: reading.measuredAt)
    }
}
