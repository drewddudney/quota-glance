import SwiftUI
import WidgetKit

/// The extension and the native debug gallery render this same view.
/// Selection and snapshot loading stay with the existing WidgetKit provider.
struct CompanionWidgetContent: View {
    let snapshot: QuotaSnapshot
    let date: Date
    let family: WidgetFamily
    var selection: MobileProviderSelection = .current

    private var readings: [MobileProviderReading] {
        selection.providers.map { .init(provider: $0, snapshot: snapshot, at: date) }
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemSmall: small.padding(14)
            default: medium.padding(16)
            }
        }
        .foregroundStyle(CompanionStyle.ink)
    }

    private var small: some View {
        Group {
            if readings.count == 2 {
                VStack(spacing: 10) {
                    ForEach(readings, id: \.provider) { reading in
                        HStack(spacing: 8) {
                            CompanionPetDial(reading: reading, lineWidth: 4).frame(width: 45, height: 45)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Text(reading.provider.name).font(.system(size: 11, weight: .semibold))
                                    Spacer(minLength: 0)
                                    Text(MobileProviderReading.percent(reading.usage))
                                        .font(.system(size: 19, weight: .medium, design: .rounded)).tracking(-0.7).monospacedDigit()
                                }
                                HStack(spacing: 8) {
                                    metric("Week", value: reading.week, tint: CompanionStyle.tint(reading.provider).opacity(0.7), small: true)
                                    metric(reading.provider == .codex ? "Reset" : sessionCountdown(reading), value: reading.third, tint: thirdTint(reading), small: true)
                                }
                                Text(footer(reading)).font(.system(size: 8, weight: .medium)).foregroundStyle(CompanionStyle.secondary)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                        }.accessibilityElement(children: .combine)
                    }
                }
            } else if let reading = readings.first {
                VStack(alignment: .leading, spacing: 8) {
                    brand(reading, size: 12)
                    HStack(spacing: 7) {
                        CompanionPetDial(reading: reading, lineWidth: 5).frame(width: 65, height: 65)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(MobileProviderReading.percent(reading.usage))
                                .font(.system(size: 33, weight: .medium, design: .rounded)).tracking(-1.5).monospacedDigit()
                            Text("weekly used").font(.system(size: 9)).foregroundStyle(CompanionStyle.secondary)
                        }
                    }.frame(maxWidth: .infinity)
                    HStack(spacing: 12) {
                        metric("Week", value: reading.week, tint: CompanionStyle.tint(reading.provider).opacity(0.7), small: true)
                        metric(reading.provider == .codex ? "Reset" : sessionCountdown(reading), value: reading.third, tint: thirdTint(reading), small: true)
                    }
                    Text(footer(reading)).font(.system(size: 9, weight: .medium)).foregroundStyle(CompanionStyle.secondary).lineLimit(1)
                }
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 20) {
            ForEach(readings, id: \.provider) { reading in
                if readings.count == 1 {
                    CompanionPetDial(reading: reading, lineWidth: 7).frame(width: 115, height: 115)
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .firstTextBaseline) {
                            brand(reading, size: 13)
                            Spacer(minLength: 5)
                            Text(MobileProviderReading.percent(reading.usage))
                                .font(.system(size: 34, weight: .medium, design: .rounded)).tracking(-1).monospacedDigit()
                        }
                        Text("used this week").font(.system(size: 10)).foregroundStyle(CompanionStyle.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing).padding(.top, -9)
                        metric("Week elapsed", value: reading.week, tint: CompanionStyle.tint(reading.provider).opacity(0.7))
                        metric(reading.provider == .codex ? "Reset chance" : (MobileProviderReading.remaining(until: reading.sessionDeadline, at: date).map { "\($0) left" } ?? "Session"), value: reading.third, tint: thirdTint(reading))
                        Text(footer(reading)).font(.system(size: 10)).foregroundStyle(CompanionStyle.secondary).lineLimit(1)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            brand(reading, size: 12)
                            Spacer(minLength: 0)
                            Text(MobileProviderReading.percent(reading.usage))
                                .font(.system(size: 25, weight: .medium, design: .rounded)).tracking(-0.8).monospacedDigit()
                        }
                        HStack(spacing: 10) {
                            CompanionPetDial(reading: reading, lineWidth: 5).frame(width: 65, height: 65)
                            VStack(spacing: 13) {
                                metric("Week", value: reading.week, tint: CompanionStyle.tint(reading.provider).opacity(0.7), small: true)
                                metric(reading.provider == .codex ? "Reset" : sessionCountdown(reading), value: reading.third, tint: thirdTint(reading), small: true)
                            }
                        }
                        HStack(spacing: 4) {
                            Circle().fill(CompanionStyle.tint(reading.provider)).frame(width: 3, height: 3)
                            Text(footer(reading)).font(.system(size: 9, weight: .medium)).foregroundStyle(CompanionStyle.secondary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: readings.count == 2 ? 6 : 0) {
            ForEach(readings, id: \.provider) { reading in
                HStack(spacing: 7) {
                    CompanionPetDial(reading: reading, lineWidth: readings.count == 2 ? 3 : 4)
                        .frame(width: readings.count == 2 ? 29 : 45, height: readings.count == 2 ? 29 : 45)
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(reading.provider.name).font(.system(size: readings.count == 2 ? 10 : 12, weight: .semibold))
                            Spacer(minLength: 0)
                            Text(MobileProviderReading.percent(reading.usage))
                                .font(.system(size: readings.count == 2 ? 15 : 21, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                        HStack(spacing: 8) {
                            lockMetric("Week", value: reading.week)
                            lockMetric(reading.provider == .codex ? "Reset" : (MobileProviderReading.remaining(until: reading.sessionDeadline, at: date) ?? "5h"), value: reading.third)
                        }
                        if readings.count == 1 {
                            Text(footer(reading)).font(.system(size: 9, weight: .medium)).lineLimit(1)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibility(reading))
            }
        }.foregroundStyle(.primary)
    }

    private var circular: some View {
        ZStack {
            if readings.count == 2 {
                CompanionDial(value: readings[0].usage, tint: .primary, tickCount: 28, lineWidth: 3)
                CompanionDial(value: readings[1].usage, tint: .primary.opacity(0.6), tickCount: 28, lineWidth: 3).padding(6)
                VStack(spacing: 1) {
                    HStack(spacing: 3) {
                        QuotaPetImage(provider: .codex).frame(width: 16, height: 18)
                        QuotaPetImage(provider: .claude).frame(width: 16, height: 15)
                    }
                    Text(readings.map { MobileProviderReading.percent($0.usage) }.joined(separator: "·"))
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded)).tracking(-0.2).monospacedDigit()
                }
            } else if let reading = readings.first {
                CompanionPetDial(reading: reading, lineWidth: 4)
                    .overlay(alignment: .bottom) {
                        Text(MobileProviderReading.percent(reading.usage))
                            .font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit().offset(y: 2)
                    }
            }
        }
        .foregroundStyle(.primary).widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readings.map { "\($0.provider.name), \(MobileProviderReading.percent($0.usage)) used this week" }.joined(separator: ". "))
    }

    private var inline: some View {
        Text(readings.map { reading in
            if readings.count == 1 && reading.provider == .claude {
                return "Claude \(MobileProviderReading.percent(reading.usage)) · 5h \(MobileProviderReading.percent(reading.third))"
            }
            return "\(reading.provider.name) \(MobileProviderReading.percent(reading.usage)) used"
        }.joined(separator: " · "))
        .foregroundStyle(.primary)
    }

    private func brand(_ reading: MobileProviderReading, size: CGFloat) -> some View {
        HStack(spacing: 5) {
            ProviderBrandMark(provider: reading.provider).frame(width: size, height: size)
            Text(reading.provider.name).font(.system(size: size, weight: .semibold))
        }.foregroundStyle(CompanionStyle.tint(reading.provider))
    }

    private func metric(_ title: String, value: Double?, tint: Color, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text(title).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text(MobileProviderReading.percent(value)).monospacedDigit().fixedSize()
            }.font(.system(size: small ? 8 : 10, weight: .medium))
            CompanionMeter(value: value, tint: tint, segments: small ? 12 : 24, height: 3)
        }.accessibilityElement(children: .combine)
    }

    private func lockMetric(_ title: String, value: Double?) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text(title)
                Spacer(minLength: 0)
                Text(MobileProviderReading.percent(value)).monospacedDigit()
            }.font(.system(size: 8, weight: .medium))
            GeometryReader { geometry in
                Capsule().fill(.primary.opacity(0.18))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.primary).frame(width: geometry.size.width * (MobileProviderReading.valid(value) ?? 0) / 100)
                    }
            }.frame(height: 2)
        }.widgetAccentable()
    }

    private func footer(_ reading: MobileProviderReading) -> String {
        if let status = reading.status(at: date) { return status }
        if reading.provider == .claude {
            return MobileProviderReading.remaining(until: reading.sessionDeadline, at: date).map { "5h session · \($0) left" } ?? "Session update pending"
        }
        if reading.resetAnnounced { return "Reset announced" }
        return MobileProviderReading.remaining(until: reading.deadline, at: date, days: true).map { "Week · \($0) left" } ?? "Week update pending"
    }
    private func sessionCountdown(_ reading: MobileProviderReading) -> String {
        MobileProviderReading.remaining(until: reading.sessionDeadline, at: date) ?? "Session"
    }
    private func thirdTint(_ reading: MobileProviderReading) -> Color {
        reading.provider == .codex ? CompanionStyle.reset : CompanionStyle.session
    }
    private func accessibility(_ reading: MobileProviderReading) -> String {
        "\(reading.provider.name), \(MobileProviderReading.percent(reading.usage)) weekly used. Week elapsed \(MobileProviderReading.percent(reading.week)). \(reading.provider == .codex ? "Reset chance" : "Five hour session") \(MobileProviderReading.percent(reading.third)). \(footer(reading))"
    }
}
