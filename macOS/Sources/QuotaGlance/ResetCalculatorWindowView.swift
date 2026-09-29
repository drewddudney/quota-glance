import AppKit
import SwiftUI

/// A live calculator window shared by the menu command and the Codex pet.
/// Source selection and source navigation are separate controls so either
/// action remains available while the forecast refreshes.
@MainActor
struct ResetCalculatorWindowView: View {
    @ObservedObject var model: DashboardModel
    @State private var selectedSources = ForecastSourceSelection.load()

    private let accent = Color(red: 0.32, green: 0.68, blue: 0.49)

    private var isAnnounced: Bool { model.resetAnnouncement != nil }
    private var chance: Double? {
        if isAnnounced { return 100 }
        return model.forecastPercent
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CODEX")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(accent)
                        Text("Reset calculator")
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                    }
                    Spacer()
                    Button { model.refreshResetForecast() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh reset estimates")
                    .accessibilityLabel("Refresh reset estimates")
                }

                forecastCard

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Calculator sources")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Spacer()
                        Text("\(selectedSources.count) selected")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 0) {
                        ForEach(ForecastSource.calculatorCases) { source in
                            sourceRow(source)
                            if source != ForecastSource.calculatorCases.last { Divider().padding(.leading, 42) }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.045)))

                    Text("The forecast uses your selected sources. A high percentage is an estimate, not a confirmed reset.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let posts = model.forecastSnapshot?.intel?.tweets, !posts.isEmpty {
                    Divider()
                    QuotaPostsView(posts: posts.map {
                        QuotaPost(id: $0.id, date: $0.date, text: $0.text,
                                  reply: $0.inReplyTo, url: $0.url, isReset: $0.isResetOriented)
                    })
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 450, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .quotaGlanceResetCalculatorChanged)) { _ in
            selectedSources = ForecastSourceSelection.load()
        }
        .onChange(of: model.forecastSnapshot?.selectedSources) { newValue in
            if let newValue { selectedSources = newValue }
        }
    }

    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isAnnounced ? "RESET ANNOUNCED" : "CHANCE OF A RESET")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(accent)
                    Text(chance.map { "\(Int($0.rounded()))%" } ?? "—")
                        .font(.system(size: 58, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Text(isAnnounced ? "Confirmed announcement" : "An estimate from your sources")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isAnnounced ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 42, weight: .ultraLight))
                    .foregroundStyle(accent)
                    .frame(width: 90)
            }
            if let expectedAt = model.resetAnnouncement?.expectedAt {
                Text(expectedAt > .now
                     ? "Expected \(expectedAt.formatted(date: .abbreviated, time: .shortened))"
                     : "Awaiting reset confirmation")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accent)
            }
            if let text = model.resetAnnouncement?.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(model.forecastStatus)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(accent.opacity(0.09)))
    }

    private func sourceRow(_ source: ForecastSource) -> some View {
        let provider = model.forecastSnapshot?.providers.first { $0.source == source }
        let score = provider?.score
        let destination = source == .polymarket
            ? provider?.polymarketForecast?.url ?? URL(string: "https://polymarket.com")
            : source.url

        return HStack(spacing: 12) {
            Toggle(source.displayName, isOn: binding(for: source))
                .labelsHidden()
                .tint(accent)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let destination {
                        Link(source.displayName, destination: destination)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                    } else {
                        Text(source.displayName).font(.system(size: 13, weight: .medium))
                    }
                    Spacer(minLength: 4)
                    Text(score.map { "\(Int($0.rounded()))%" } ?? "—")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(score == nil ? .secondary : .primary)
                    if let destination {
                        Link(destination: destination) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 24, height: 24)
                        }
                        .help("Open \(source.hostLabel) in your browser")
                        .accessibilityLabel("Open \(source.displayName) in your browser")
                    }
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.09))
                        Capsule().fill(selectedSources.contains(source) ? accent : accent.opacity(0.4))
                            .frame(width: geometry.size.width * max(0, min(1, (score ?? 0) / 100)))
                    }
                }
                .frame(height: 5)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private func binding(for source: ForecastSource) -> Binding<Bool> {
        Binding(
            get: { selectedSources.contains(source) },
            set: { enabled in
                var next = selectedSources
                if enabled {
                    next.insert(source)
                } else if next.count > 1 {
                    next.remove(source)
                } else {
                    NSSound.beep()
                    return
                }
                selectedSources = next
                ForecastSourceSelection.save(next)
                model.selectForecastSources(ForecastSource.calculatorCases.filter(next.contains).map(\.rawValue))
            }
        )
    }
}
