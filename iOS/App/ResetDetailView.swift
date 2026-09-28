import SwiftUI

struct ResetDetailView: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    forecast
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Calculator sources").font(.headline)
                            Spacer()
                            Text("\(store.selectedSources.count) sources").font(.system(size: 11)).foregroundStyle(PhoneStyle.secondary)
                        }
                        ForEach(ResetSource.calculatorCases) { source in
                            let value = store.snapshot.providers.first { $0.source == source }?.percent
                            Toggle(isOn: store.binding(for: source)) {
                                VStack(alignment: .leading, spacing: 9) {
                                    HStack {
                                        Text(source.name).font(.system(size: 14, weight: .medium))
                                        Spacer()
                                        Text(MobileProviderReading.percent(value))
                                            .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                                            .foregroundStyle(PhoneStyle.secondary)
                                    }
                                    QuotaRail(value: value, tint: store.selectedSources.contains(source) ? PhoneStyle.reset : PhoneStyle.secondary.opacity(0.5))
                                }.padding(.trailing, 12)
                            }
                            .tint(PhoneStyle.reset)
                            .padding(.vertical, 4)
                            if source != ResetSource.calculatorCases.last { PhoneRule() }
                        }
                        Text("The forecast averages your selected sources. A high percentage is an estimate, not a confirmed reset.")
                            .font(.system(size: 12)).foregroundStyle(PhoneStyle.secondary).lineSpacing(3)
                    }
                    PhoneRule()
                    PhonePostsView(posts: store.snapshot.displayPosts, initiallyExpanded: true)
                }
                .padding(24)
            }
            .background(PhoneStyle.paper).foregroundStyle(PhoneStyle.ink)
            .tint(PhoneStyle.reset)
            .navigationTitle("Codex reset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .refreshable { await store.refresh() }
        }
    }

    private var forecast: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.snapshot.effectiveResetAnnounced ? "Reset announced" : "Chance of a reset")
                        .font(.subheadline.weight(.medium)).foregroundStyle(PhoneStyle.reset)
                    Text(MobileProviderReading.percent(chance))
                        .font(.system(size: 64, weight: .medium, design: .rounded)).monospacedDigit().tracking(-3)
                    Text(store.snapshot.effectiveResetAnnounced ? "Confirmed announcement" : "An estimate from your sources")
                        .font(.caption).foregroundStyle(PhoneStyle.secondary)
                }
                Spacer(minLength: 0)
                ZStack {
                    CompanionDial(value: chance, tint: PhoneStyle.reset, tickCount: 32, lineWidth: 6)
                    QuotaPetImage(provider: .codex).frame(width: 54, height: 64)
                }.frame(width: 112, height: 112)
            }
            if let date = store.snapshot.activeAnnouncementExpectedAt {
                Text(date > .now ? "Expected \(date.formatted(date: .abbreviated, time: .shortened))" : "Awaiting reset confirmation")
                    .font(.subheadline.weight(.medium)).foregroundStyle(PhoneStyle.reset)
            }
            if let text = store.snapshot.announcementText, store.snapshot.effectiveResetAnnounced {
                Text(text).font(.subheadline).foregroundStyle(PhoneStyle.secondary).lineSpacing(3)
            }
            PhoneRule()
        }
        .padding(.vertical, 10)
    }

    private var chance: Double? { store.snapshot.effectiveResetAnnounced ? 100 : MobileProviderReading.valid(store.snapshot.resetChancePercent) }
}
