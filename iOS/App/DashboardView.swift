import SwiftUI
import WidgetKit

struct DashboardView: View {
    @ObservedObject var store: DashboardStore
    @AppStorage(MobileProviderSelection.key, store: MobileProviderSelection.defaults)
    private var selection: MobileProviderSelection = .both
    @State private var destination: Destination = .glance
    @State private var sheet: DashboardSheet?
    @ObservedObject private var liveActivity = ProviderUsageActivityManager.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Destination: Hashable { case glance, activity, updates }
    private enum DashboardSheet: String, Identifiable {
        case settings, reset, codex, claude
        var id: String { rawValue }
    }

    private var presentedSnapshot: QuotaSnapshot {
#if DEBUG
        if DashboardStore.isPreview && ProcessInfo.processInfo.arguments.contains("--quota-preview-empty") { return .empty }
#endif
        return store.snapshot
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $destination) {
                page(title: "Quota Glance", subtitle: Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
                    glance
                }
                .tabItem { Label("Glance", systemImage: "circle.hexagongrid") }.tag(Destination.glance)

                page(title: "Activity", subtitle: selection == .claude ? "Your allowance windows" : "Your week, in detail") {
                    VStack(alignment: .leading, spacing: 30) {
                        if selection.providers.contains(.codex) {
                            PhoneActivityView(snapshot: presentedSnapshot)
                            resetLink
                        }
                        if selection.providers.contains(.claude) {
                            if selection == .both { PhoneRule() }
                            PhoneClaudeWindows(snapshot: presentedSnapshot.claude).id("claude-windows")
                        }
                    }
                }
                .tabItem { Label("Activity", systemImage: "chart.xyaxis.line") }.tag(Destination.activity)

                if selection.providers.contains(.codex) {
                    page(title: "Updates", subtitle: "Tibo’s posts & reset news") {
                        PhonePostsView(posts: presentedSnapshot.displayPosts, initiallyExpanded: true, standalone: true)
                    }
                    .tabItem { Label("Updates", systemImage: "text.bubble") }.tag(Destination.updates)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $sheet) { value in
                Group {
                    switch value {
                    case .settings: SettingsView(store: store)
                    case .reset: ResetDetailView(store: store)
                    case .codex: PhonePetDetails(provider: .codex, store: store)
                    case .claude: PhonePetDetails(provider: .claude, store: store)
                    }
                }
                .presentationDragIndicator(.visible)
            }
            .alert("Does this Codex reset apply to you?", isPresented: Binding(
                get: { selection.providers.contains(.codex) && presentedSnapshot.needsResetApplicabilityAnswer },
                set: { _ in }
            )) {
                Button("Yes") { Task { await store.answerResetApplicability(true) } }
                Button("No") { Task { await store.answerResetApplicability(false) } }
            } message: {
                Text(presentedSnapshot.announcementText ?? "The reset announcement may apply to only some accounts.")
            }
        }
        .tint(PhoneStyle.ink)
        .overlay { PhonePetCelebrationOverlay() }
        .onChange(of: selection) {
            if selection == .claude && destination == .updates { destination = .glance }
            WidgetCenter.shared.reloadAllTimelines()
            Task { await liveActivity.sync(snapshot: store.snapshot) }
        }
        .task {
#if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--quota-preview-settings") { sheet = .settings }
            if args.contains("--quota-preview-reset") { sheet = .reset }
            if args.contains("--quota-preview-codex-details") { sheet = .codex }
            if args.contains("--quota-preview-claude-details") { sheet = .claude }
            if args.contains("--quota-preview-codex") { selection = .codex }
            if args.contains("--quota-preview-claude") { selection = .claude }
            if args.contains("--quota-preview-both") { selection = .both }
            if args.contains("--quota-preview-posts") { destination = .updates }
            if ["--quota-preview-activity", "--quota-preview-archive", "--quota-preview-hour", "--quota-preview-five-minutes", "--quota-preview-totals", "--quota-preview-claude-windows"].contains(where: args.contains) { destination = .activity }
#endif
        }
    }

    private func page<Content: View>(title: String, subtitle: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            content()
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(PhoneStyle.paper.ignoresSafeArea())
        .foregroundStyle(PhoneStyle.ink)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(.title2, weight: .semibold)).tracking(-0.6)
                    Text(subtitle).font(.caption).foregroundStyle(PhoneStyle.secondary)
                }
                Spacer(minLength: 12)
                Button { sheet = .settings } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(PhoneStyle.field, in: Circle())
                }.buttonStyle(PhonePressStyle()).accessibilityLabel("Settings")
            }
            .padding(.horizontal, 24).padding(.top, 5).padding(.bottom, 16)
            .background(PhoneStyle.paper)
        }
        .refreshable { await store.refresh() }
        .task {
#if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--quota-preview-totals") || args.contains("--quota-preview-claude-windows") {
                try? await Task.sleep(for: .milliseconds(200))
                proxy.scrollTo(args.contains("--quota-preview-totals") ? "usage-details" : "claude-windows", anchor: .top)
            }
#endif
        }
        }
    }

    private var glance: some View {
        VStack(alignment: .leading, spacing: 24) {
            providerPicker
            if !DashboardStore.isPreview,
               selection.providers.contains(where: { !ProviderConnectionService.shared.hasConnection($0 == .codex ? .codex : .claude) }) {
                Button { sheet = .settings } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.plus")
                        Text("Connect accounts on this iPhone").font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }.foregroundStyle(PhoneStyle.ink)
                }.buttonStyle(.plain)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 24) {
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: 28))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                    layout {
                        ForEach(selection.providers) { provider in
                            PhoneProviderInstrument(
                                reading: .init(provider: provider, snapshot: presentedSnapshot, at: context.date),
                                now: context.date,
                                paired: selection == .both && !typeSize.isAccessibilitySize,
                                showReset: { sheet = .reset },
                                showActivity: { sheet = provider == .codex ? .codex : .claude }
                            )
                        }
                    }
                    if selection.providers.contains(.codex), let expected = presentedSnapshot.activeAnnouncementExpectedAt {
                        resetAnnouncement(expected, now: context.date)
                    }
                    PhoneRule()
                    renewalSchedule(now: context.date)
                }
            }
            syncStatus
            if presentedSnapshot.usagePercent != nil || presentedSnapshot.claude?.usagePercent != nil {
                Button {
                    Task {
                        await liveActivity.setEnabled(!liveActivity.isEnabled, snapshot: store.snapshot)
                    }
                } label: {
                    Label(liveActivity.isEnabled ? (liveActivity.isRunning ? "Live Activity · Following usage" : "Live Activity · Watching for usage") : "Enable automatic Live Activity", systemImage: "platter.filled.top.iphone")
                        .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain)
                if let message = liveActivity.message {
                    Text(message).font(.caption).foregroundStyle(PhoneStyle.secondary)
                }
            }
        }
    }

    private var providerPicker: some View {
        HStack(spacing: 4) {
            ForEach(MobileProviderSelection.allCases) { option in
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = option }
                } label: {
                    HStack(spacing: 6) {
                        if option != .both { ProviderBrandMark(provider: option == .codex ? .codex : .claude).frame(width: 13, height: 13) }
                        Text(option.title).font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(selection == option ? PhoneStyle.paper : PhoneStyle.secondary)
                    .background(selection == option ? PhoneStyle.ink : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(PhoneStyle.field.opacity(0.65), in: Capsule())
        .accessibilityIdentifier("provider-selection")
    }

    private func renewalSchedule(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Coming up").font(.subheadline.weight(.semibold))
            ForEach(selection.providers) { provider in
                let reading = MobileProviderReading(provider: provider, snapshot: presentedSnapshot, at: now)
                let date = provider == .claude ? reading.sessionDeadline : reading.deadline
                Button { sheet = provider == .codex ? .codex : .claude } label: {
                    HStack(spacing: 12) {
                        Image(systemName: provider == .codex ? "calendar" : "clock")
                            .font(.system(size: 16, weight: .regular)).foregroundStyle(PhoneStyle.tint(provider))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider == .codex ? "Codex week renews" : "Claude session renews")
                                .font(.subheadline.weight(.medium))
                            Text(date.map { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) } ?? "Connect your account")
                                .font(.caption).foregroundStyle(PhoneStyle.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(MobileProviderReading.remaining(until: date, at: now, days: true) ?? "Pending")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold)).monospacedDigit()
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(PhoneStyle.secondary)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(PhonePressStyle())
            }
        }
    }

    private var syncStatus: some View {
        Button { Task { await store.refresh() } } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10, weight: .medium))
                Text(syncLabel)
                    .font(.caption2)
            }
            .foregroundStyle(PhoneStyle.secondary)
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.plain).disabled(store.state == .syncing)
        .accessibilityLabel("Refresh provider usage")
    }

    private var syncLabel: String {
        if store.state == .syncing { return "Checking accounts…" }
        if presentedSnapshot.capturedAt == .distantPast { return "Connect accounts in Settings" }
        if case .partial(let message) = store.state { return "\(message) · Refresh" }
        return "Updated \(presentedSnapshot.capturedAt.formatted(.dateTime.hour().minute())) · Refresh"
    }

    private var resetLink: some View {
        Button { sheet = .reset } label: {
            HStack(spacing: 14) {
                Image(systemName: "arrow.counterclockwise").font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Codex reset forecast").font(.subheadline.weight(.semibold))
                    Text("Calculator & source estimates").font(.caption).foregroundStyle(PhoneStyle.secondary)
                }
                Spacer()
                Text(MobileProviderReading.percent(presentedSnapshot.effectiveResetAnnounced ? 100 : presentedSnapshot.resetChancePercent))
                    .font(.system(.title2, design: .rounded, weight: .medium)).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption2)
            }.foregroundStyle(PhoneStyle.reset).padding(.vertical, 8)
        }.buttonStyle(PhonePressStyle())
    }

    private func resetAnnouncement(_ date: Date, now: Date) -> some View {
        Button { sheet = .reset } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.counterclockwise.circle.fill").font(.title3)
                Text("Codex reset announced").font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if date > now { Text(timerInterval: now...date, countsDown: true).font(.caption.monospacedDigit()).fixedSize() }
                else { Text("Pending").font(.caption) }
                Image(systemName: "chevron.right").font(.caption2)
            }
            .foregroundStyle(PhoneStyle.reset).padding(16)
            .background(PhoneStyle.reset.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(PhonePressStyle())
    }
}

private struct PhoneProviderInstrument: View {
    let reading: MobileProviderReading
    let now: Date
    let paired: Bool
    let showReset: () -> Void
    let showActivity: () -> Void
    @State private var greeting: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var tint: Color { PhoneStyle.tint(reading.provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                ProviderBrandMark(provider: reading.provider).frame(width: 14, height: 14)
                Text(reading.provider.name).font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: showActivity) {
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).frame(width: 26, height: 28)
                }.buttonStyle(.plain).accessibilityLabel("\(reading.provider.name) activity")
            }.foregroundStyle(tint)

            Button { greeting = .now } label: {
                TimelineView(.animation(minimumInterval: 0.15, paused: greeting == nil || reduceMotion)) { context in
                    let elapsed = greeting.map { context.date.timeIntervalSince($0) } ?? 10
                    CompanionPetDial(reading: reading, frame: elapsed < 1 ? Int(max(0, elapsed) / 0.15) % 4 : 0, waving: elapsed < 1 && !reduceMotion)
                        .phaseAnimator([false, true], trigger: reading.usage) { content, lifted in
                            content.offset(y: lifted && !reduceMotion ? -7 : 0)
                                .rotationEffect(.degrees(lifted && !reduceMotion ? (reading.provider == .codex ? -5 : 5) : 0))
                        } animation: { _ in .spring(duration: 0.45, bounce: 0.4) }
                        .frame(maxWidth: paired ? 168 : 218)
                        .overlay(alignment: .bottom) {
                            Text(MobileProviderReading.percent(reading.usage))
                                .font(.system(size: paired ? 38 : 48, weight: .medium, design: .rounded))
                                .tracking(-1.8).monospacedDigit().contentTransition(.numericText())
                                .offset(y: paired ? 15 : 17)
                        }
                        .padding(.bottom, 20)
                        .frame(maxWidth: .infinity)
                        .background(CompanionDottedField().mask(LinearGradient(colors: [.clear, .black, .clear], startPoint: .top, endPoint: .bottom)))
                }
            }
            .buttonStyle(PhonePressStyle())
            .accessibilityLabel("\(reading.provider.name), \(MobileProviderReading.percent(reading.usage)) used this week")
            .accessibilityHint("Open usage details")
            .padding(.top, 10)
            Text("used this week").font(.caption).foregroundStyle(PhoneStyle.secondary)
                .frame(maxWidth: .infinity).padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 18) {
                meter("Week elapsed", value: reading.week, color: tint.opacity(0.7))
                if reading.provider == .codex {
                    Button(action: showReset) {
                        VStack(alignment: .leading, spacing: 6) {
                            meter(reading.resetAnnounced ? "Reset announced" : "Reset chance", value: reading.third, color: PhoneStyle.reset, disclosure: true)
                            Text("Open calculator").font(.caption2).foregroundStyle(PhoneStyle.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("reset-details")
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        meter(MobileProviderReading.remaining(until: reading.sessionDeadline, at: now).map { "\($0) left" } ?? "Session pending", value: reading.third, color: PhoneStyle.session)
                        Text("5h session used")
                            .font(.caption2).foregroundStyle(PhoneStyle.secondary).monospacedDigit()
                    }
                }
            }
            if let status = reading.status(at: now) {
                Text(status).font(.caption2).foregroundStyle(PhoneStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: greeting) {
            guard greeting != nil else { return }
            do { try await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 450)) } catch { return }
            greeting = nil
            showActivity()
        }
    }

    private func meter(_ title: String, value: Double?, color: Color, disclosure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 3) {
                Text(title).font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                if disclosure { Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .semibold)) }
                Spacer(minLength: 4)
                Text(MobileProviderReading.percent(value)).font(.system(.subheadline, design: .rounded, weight: .semibold)).monospacedDigit()
            }
            CompanionMeter(value: value, tint: color)
        }
        .foregroundStyle(disclosure ? PhoneStyle.reset : PhoneStyle.ink)
        .accessibilityElement(children: .combine)
    }
}
