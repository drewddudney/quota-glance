import Charts
import SwiftUI

enum MobileTheme: String, CaseIterable, Identifiable {
    case instrument = "Instrument", oled = "OLED", marine = "Marine"
    case retro = "Retro", radar = "Radar", eInk = "E-Ink"

    var id: String { rawValue }
    var calendarColor: Color {
        switch self {
        case .instrument, .oled, .retro: Color(hex: QuotaColors.calendar)
        case .marine: Color(hex: 0xF1B84B)
        case .radar: Color(hex: 0xFFC34D)
        case .eInk: Color(hex: 0xA85D00)
        }
    }
    var usageColor: Color {
        switch self {
        case .instrument, .oled: Color(hex: QuotaColors.usage)
        case .marine: Color(hex: 0x3B8FEA)
        case .retro: Color(hex: 0x3182E8)
        case .radar: Color(hex: 0x2685E5)
        case .eInk: Color(hex: 0x2868B2)
        }
    }
    var resetColor: Color {
        switch self {
        case .instrument, .oled: Color(hex: QuotaColors.reset)
        case .marine: Color(hex: 0x83E2AE)
        case .retro: Color(hex: 0x63E18A)
        case .radar: Color(hex: 0x6FE0AC)
        case .eInk: Color(hex: 0x3A8B62)
        }
    }
    var fontDesign: Font.Design {
        switch self { case .retro, .eInk: .monospaced; default: .rounded }
    }
    var cornerRadius: CGFloat {
        switch self { case .retro: 8; case .eInk: 5; case .marine: 14; default: 16 }
    }
    var palette: ThemePalette {
        switch self {
        case .instrument: .init(0x0B0D0F, 0x15181B, 0x202429, 0xF5F3EE, 0x92989C, 0x34393E)
        case .oled: .init(0x000000, 0x070909, 0x101313, 0xF7FAF9, 0x727C78, 0x202725)
        case .marine: .init(0x06111C, 0x0C1B28, 0x14293A, 0xF1E9D9, 0x8EA2B0, 0x294458)
        case .retro: .init(0x070A07, 0x0E160E, 0x172217, 0xB6FFBF, 0x6E9672, 0x29402B)
        case .radar: .init(0x010708, 0x041112, 0x092022, 0xCFFFE9, 0x629B87, 0x123C35)
        case .eInk: .init(0xE7E5DE, 0xD8D7D1, 0xF0EEE8, 0x292B2B, 0x666967, 0xB9BBB6, true)
        }
    }
}

struct ThemePalette {
    let background, surface, raised, text, secondary, grid: Color
    let isLight: Bool
    init(_ background: UInt32, _ surface: UInt32, _ raised: UInt32, _ text: UInt32, _ secondary: UInt32, _ grid: UInt32, _ isLight: Bool = false) {
        self.background = Color(hex: background); self.surface = Color(hex: surface)
        self.raised = Color(hex: raised); self.text = Color(hex: text)
        self.secondary = Color(hex: secondary); self.grid = Color(hex: grid); self.isLight = isLight
    }
}

enum MobilePaceRange: String, CaseIterable, Identifiable {
    case fiveMinutes = "5M", oneHour = "1H", twelveHours = "12H", twentyFourHours = "24H", total = "TOTAL"
    var id: String { rawValue }
    var seconds: TimeInterval? {
        switch self {
        case .fiveMinutes: 300
        case .oneHour: 3_600
        case .twelveHours: 43_200
        case .twentyFourHours: 86_400
        case .total: nil
        }
    }
}

private enum DashboardTab: Hashable { case glance, posts, pace, settings }

struct DashboardView: View {
    @ObservedObject var store: DashboardStore
    @AppStorage("QuotaGlance.mobile.theme") private var theme: MobileTheme = .instrument
    @State private var selectedTab: DashboardTab = {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--quota-preview-settings") { return .settings }
        if ProcessInfo.processInfo.arguments.contains("--quota-preview-pace") { return .pace }
        return .glance
#else
        .glance
#endif
    }()
    @State private var paceRange: MobilePaceRange = .twelveHours
    @State private var paceWeekIndex: Int = {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--quota-preview-previous-week") ? 1 : 0
#else
        0
#endif
    }()
    @State private var postFilterReset = true

    private var palette: ThemePalette { theme.palette }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { glancePage }
                .tag(DashboardTab.glance)
                .tabItem { Label("Glance", systemImage: "circle.grid.3x3.fill") }
            NavigationStack { postsPage }
                .tag(DashboardTab.posts)
                .tabItem { Label("Posts", systemImage: "bubble.left.and.bubble.right") }
            NavigationStack { pacePage }
                .tag(DashboardTab.pace)
                .tabItem { Label("Pace", systemImage: "chart.xyaxis.line") }
            NavigationStack {
                SettingsView(store: store, selectedTheme: $theme)
            }
            .tag(DashboardTab.settings)
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(theme.usageColor)
        .preferredColorScheme(palette.isLight ? .light : .dark)
        .alert(
            "Does this reset apply to your account?",
            isPresented: Binding(
                get: { store.snapshot.needsResetApplicabilityAnswer },
                set: { _ in }
            )
        ) {
            Button("Yes, it applies") {
                Task { await store.answerResetApplicability(true) }
            }
            Button("No, not eligible") {
                Task { await store.answerResetApplicability(false) }
            }
        } message: {
            Text(store.snapshot.announcementText ?? "This reset has account-specific eligibility requirements.")
        }
    }

    private var glancePage: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                dashboardHeader
                overview
                if let expectedAt = activeScheduledResetAt { scheduledResetCard(expectedAt) }
                if let post = store.snapshot.tiboPosts?.first { latestPost(post) }
                PacePanel(snapshot: store.snapshot, theme: theme, range: $paceRange, weekIndex: .constant(0), compact: true)
                    .onTapGesture { selectedTab = .pace }
                detailRows
            }
            .padding(.horizontal, 14).padding(.bottom, 10)
        }
        .background(palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await store.refresh() }
    }

    private var dashboardHeader: some View {
        HStack {
            Button { selectedTab = .pace } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 38, height: 38)
                    .background(palette.raised, in: Circle())
                    .overlay(Circle().stroke(palette.grid, lineWidth: 1))
            }
            Spacer()
            Text("Quota Glance")
                    .font(.system(size: 24, weight: .semibold, design: theme.fontDesign))
                .tracking(-0.7)
                .foregroundStyle(palette.text)
            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .frame(height: 38)
    }

    private var overview: some View {
        HStack(spacing: 22) {
                ActivityRingCluster(snapshot: store.snapshot, theme: theme).frame(width: 138, height: 138)
                VStack(spacing: 10) {
                    overviewMetric("WEEK", store.snapshot.weekElapsedPercent, theme.calendarColor)
                    overviewMetric("CODEX", store.snapshot.usagePercent, theme.usageColor)
                    overviewMetric("RESET", store.snapshot.effectiveResetChance, theme.resetColor)
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private func overviewMetric(_ label: String, _ value: Double?, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).font(.system(size: 12, weight: .medium, design: theme.fontDesign)).foregroundStyle(color)
            Spacer(minLength: 4)
            Text(value.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(.system(size: 30, weight: .light, design: theme.fontDesign)).monospacedDigit().foregroundStyle(color)
        }
    }

    private func latestPost(_ post: QuotaTiboPost) -> some View {
        Button { selectedTab = .posts } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: post.isResetOriented ? "bubble.left.fill" : "bubble.left")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.resetColor)
                    .frame(width: 34, height: 34).background(theme.resetColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(post.isResetOriented ? "TIBO · RESET SIGNAL" : "TIBO · NEW POST")
                            .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.9)
                        Spacer()
                        if let date = post.date { Text(date, style: .relative).font(.caption2.monospaced()) }
                    }.foregroundStyle(theme.resetColor)
                    Text(post.text).font(.system(size: 15, weight: .medium, design: theme.fontDesign)).foregroundStyle(palette.text)
                        .lineLimit(3).multilineTextAlignment(.leading)
                    if let reply = post.inReplyTo, !reply.isEmpty {
                        Text("↳ \(reply)").font(.caption).foregroundStyle(palette.secondary).lineLimit(1)
                    }
                }
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(palette.secondary).padding(.top, 9)
            }
            .padding(.horizontal, 10).padding(.vertical, 5).dashboardSurface(palette, radius: theme.cornerRadius)
        }.buttonStyle(.plain)
    }

    private var activeScheduledResetAt: Date? {
        store.snapshot.activeAnnouncementExpectedAt
    }

    private func scheduledResetCard(_ expectedAt: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(expectedAt <= context.date ? "RESET ANNOUNCEMENT ACTIVE" : "CODEX RESET INCOMING")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(Color.black.opacity(0.72))
                    if expectedAt <= context.date {
                        Text("AWAITING CONFIRMATION")
                            .font(.system(size: 18, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(Color.black)
                    } else {
                        Text(expectedAt, style: .timer)
                            .font(.system(size: 25, weight: .semibold, design: theme.fontDesign))
                            .monospacedDigit()
                            .foregroundStyle(Color.black)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(expectedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(Color.black)
                    Text("YOUR TIME · \(Self.timeZoneLabel(expectedAt))")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.62))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(theme.calendarColor, in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.24), lineWidth: 1)
            }
        }
    }

    private static func timeZoneLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "z"
        return formatter.string(from: date).uppercased()
    }

    private var detailRows: some View {
        VStack(spacing: 0) {
            dashboardRow("terminal.fill", "SESSION", sessionLabel,
                         store.snapshot.resetAt.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Waiting for Mac sync",
                         theme.usageColor) { selectedTab = .pace }
            Divider().overlay(palette.grid).padding(.leading, 50)
            dashboardRow("creditcard.fill", "PLAN", store.snapshot.planName?.uppercased() ?? "NOT SYNCED",
                         store.snapshot.renewalDate.map { "Renews \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Open Mac app to sync billing",
                         theme.calendarColor) { selectedTab = .settings }
        }.dashboardSurface(palette, radius: theme.cornerRadius)
    }

    private func dashboardRow(_ icon: String, _ title: String, _ value: String, _ detail: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(color)
                    .frame(width: 34, height: 34).background(color.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.2).foregroundStyle(palette.secondary)
                    Text(value).font(.system(size: 15, weight: .semibold, design: theme.fontDesign)).foregroundStyle(palette.text)
                    Text(detail).font(.system(size: 11, design: theme.fontDesign)).foregroundStyle(palette.secondary).lineLimit(1)
                }
                Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(palette.secondary)
            }.padding(.horizontal, 10).padding(.vertical, 5)
        }.buttonStyle(.plain)
    }

    private var sessionLabel: String {
        let duration: String
        if let minutes = store.snapshot.windowDurationMinutes, minutes >= 1_440 { duration = "\(Int((minutes / 1_440).rounded()))-DAY WINDOW" }
        else if let minutes = store.snapshot.windowDurationMinutes { duration = "\(Int((minutes / 60).rounded()))-HOUR WINDOW" }
        else { duration = "CODEX WINDOW" }
        return "\(Int((store.snapshot.usagePercent ?? 0).rounded()))% · \(duration)"
    }

    private var postsPage: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Picker("Post filter", selection: $postFilterReset) {
                    Text("Reset signals").tag(true); Text("All posts").tag(false)
                }.pickerStyle(.segmented).padding(.bottom, 4)
                if filteredPosts.isEmpty {
                    ContentUnavailableView("No recent posts", systemImage: "bubble.left", description: Text("Posts from the last seven days will appear here."))
                        .foregroundStyle(palette.secondary).padding(.top, 70)
                } else { ForEach(filteredPosts) { PostRow(post: $0, palette: palette) } }
            }.padding(16)
        }
        .background(palette.background.ignoresSafeArea()).navigationTitle("Tibo Posts").navigationBarTitleDisplayMode(.large)
        .toolbarBackground(palette.background, for: .navigationBar).refreshable { await store.refresh() }
    }

    private var filteredPosts: [QuotaTiboPost] {
        let posts = store.snapshot.tiboPosts ?? []; return postFilterReset ? posts.filter(\.isResetOriented) : posts
    }

    private var pacePage: some View {
        ScrollView {
            VStack(spacing: 16) {
                PacePanel(snapshot: store.snapshot, theme: theme, range: $paceRange, weekIndex: $paceWeekIndex, compact: false)
                paceStats
                UsageRhythmPanel(snapshot: store.snapshot, theme: theme)
                providerSection
            }.padding(16)
        }
        .background(palette.background.ignoresSafeArea()).navigationTitle("Codex Pace").navigationBarTitleDisplayMode(.large)
        .toolbarBackground(palette.background, for: .navigationBar)
    }

    private var paceStats: some View {
        let archives = (store.snapshot.weeklyArchives ?? []).sorted { $0.windowStart > $1.windowStart }
        let archive = paceWeekIndex > 0 && paceWeekIndex <= archives.count ? archives[paceWeekIndex - 1] : nil
        return HStack(spacing: 0) {
            if let archive {
                paceStatText("TOKENS", archive.totalTokens.map(Self.tokens))
                paceStatText("API VALUE", archive.apiEquivalentUSD.map { String(format: "$%.2f", $0) })
                paceStatText("CACHE", archive.cacheHitRate.map { "\(Int(($0 * 100).rounded()))%" })
                paceStatText("FAST", archive.fastShare.map { "\(Int(($0 * 100).rounded()))%" })
            } else {
                paceStat("5M", tokenBurn(store.snapshot.tokenPace?.fiveMinutes, over: 5 * 60))
                paceStat("1H", tokenBurn(store.snapshot.tokenPace?.oneHour, over: 60 * 60))
                paceStat("12H", tokenBurn(store.snapshot.tokenPace?.twelveHours, over: 12 * 60 * 60))
                paceStat("24H", tokenBurn(store.snapshot.tokenPace?.twentyFourHours, over: 24 * 60 * 60))
            }
        }.padding(.vertical, 15).dashboardSurface(palette)
    }
    private func tokenBurn(_ reported: Int64?, over interval: TimeInterval) -> Int64? {
        let derived = store.snapshot.tokenBurnSample(over: interval)?.tokens
        return [reported, derived].compactMap { $0 }.max()
    }
    private func paceStat(_ label: String, _ tokens: Int64?) -> some View {
        paceStatText(label, tokens.map(Self.tokens))
    }
    private func paceStatText(_ label: String, _ value: String?) -> some View {
        VStack(spacing: 5) {
            Text(label).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(palette.secondary)
            Text(value ?? "—").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(palette.text).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity)
    }

    private func archivedWeeks(_ archives: [QuotaWeeklyArchive]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("PREVIOUS WEEKS", systemImage: "clock.arrow.circlepath")
                Spacer()
                Text("HOURLY · \(archives.count) SAVED")
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(palette.secondary)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(archives) { archive in
                        MobileArchivedWeekCard(archive: archive, theme: theme)
                            .containerRelativeFrame(.horizontal, count: 1, spacing: 12)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    private var usageIntelligenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("USAGE INTELLIGENCE", systemImage: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(palette.secondary)
                Spacer()
                if let coverage = store.snapshot.usageIntelligence?.pricingCoverage {
                    Text("\(Int((coverage * 100).rounded()))% PRICED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(coverage >= 0.8 ? theme.usageColor : theme.calendarColor)
                }
            }

            if let intelligence = store.snapshot.usageIntelligence {
                HStack(spacing: 0) {
                    intelligenceMetric("API VALUE", String(format: "$%.2f", intelligence.apiEquivalentUSD))
                    intelligenceMetric("QUOTA VALUE", String(format: "$%.2f", intelligence.quotaWeightedUSD))
                    intelligenceMetric("FAST", "\(Int((intelligence.fastShare * 100).rounded()))%")
                }
                Text("\(intelligence.topModel ?? "Unknown model") · \(intelligence.eventCount.formatted()) metered events · speed confidence \(Int((intelligence.speedCoverage * 100).rounded()))%")
                    .font(.system(size: 10, design: theme.fontDesign))
                    .foregroundStyle(palette.secondary)
            }

            if let secondary = store.snapshot.secondaryQuota {
                Divider().overlay(palette.grid)
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(palette.grid, lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: max(0, min(1, secondary.usedPercent / 100)))
                            .stroke(theme.resetColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(secondary.usedPercent.rounded()))%")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SECONDARY WINDOW")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.resetColor)
                        Text("Resets \(secondary.resetAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(palette.text)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .dashboardSurface(palette)
    }

    private func intelligenceMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(palette.secondary)
            Text(value).font(.system(size: 18, weight: .semibold, design: theme.fontDesign)).foregroundStyle(palette.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RESET SOURCES").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.2).foregroundStyle(palette.secondary)
                Spacer()
                Menu {
                    ForEach(ResetSource.calculatorCases) { source in
                        Toggle(source.name, isOn: store.binding(for: source))
                    }
                } label: {
                    Text(ResetSource.selectionLabel(store.selectedSources))
                        .font(.caption.bold())
                        .foregroundStyle(Color(hex: QuotaColors.reset))
                }
            }
            ForEach(store.snapshot.providers) { provider in
                HStack {
                    Circle().fill(provider.percent == nil ? palette.grid : Color(hex: QuotaColors.reset)).frame(width: 6, height: 6)
                    Text(provider.source.name).font(.subheadline).foregroundStyle(palette.text); Spacer()
                    Text(provider.percent.map { "\(Int($0.rounded()))%" } ?? "—").font(.subheadline.bold().monospacedDigit()).foregroundStyle(palette.text)
                }
            }
        }.padding(16).dashboardSurface(palette)
    }

    private var statusColor: Color {
        switch store.state { case .current: Color(hex: QuotaColors.usage); case .syncing: Color(hex: QuotaColors.calendar); case .idle, .partial: palette.secondary }
    }
    fileprivate static func tokens(_ value: Int64) -> String {
        if value >= 1_000_000_000 { return String(format: "%.2fB", Double(value) / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fK", Double(value) / 1_000) }
        return "\(value)"
    }
}

private struct ActivityRingCluster: View {
    let snapshot: QuotaSnapshot
    let theme: MobileTheme
    private var palette: ThemePalette { theme.palette }
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            Group {
                switch theme {
                case .oled: oledFace(side)
                case .instrument: instrumentFace(side, marine: false)
                case .marine: instrumentFace(side, marine: true)
                case .retro: retroFace
                case .radar: radarFace(side)
                case .eInk: eInkFace(side)
                }
            }
        }.accessibilityElement(children: .ignore)
    }

    private func oledFace(_ side: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color.black)
            ring(snapshot.weekElapsedPercent ?? 0, theme.calendarColor, side * 0.05, side * 0.070)
            ring(snapshot.usagePercent ?? 0, theme.usageColor, side * 0.20, side * 0.070)
            ring(snapshot.effectiveResetChance, theme.resetColor, side * 0.35, side * 0.070)
        }
    }

    private func instrumentFace(_ side: CGFloat, marine: Bool) -> some View {
        ZStack {
            Circle().fill(marine ? Color(hex: 0x071A2B) : palette.surface)
            Circle().stroke(marine ? Color(hex: 0xB88C47) : palette.grid, lineWidth: 2)
            ForEach(0..<36) { tick in
                Capsule()
                    .fill(tick.isMultiple(of: 3) ? palette.text.opacity(0.72) : palette.secondary.opacity(0.4))
                    .frame(width: tick.isMultiple(of: 3) ? 1.5 : 0.8, height: tick.isMultiple(of: 3) ? 7 : 4)
                    .offset(y: -side * 0.43)
                    .rotationEffect(.degrees(Double(tick) * 10))
            }
            ring(snapshot.weekElapsedPercent ?? 0, theme.calendarColor, side * 0.10, side * 0.045)
            ring(snapshot.usagePercent ?? 0, theme.usageColor, side * 0.23, side * 0.045)
            ring(snapshot.effectiveResetChance, theme.resetColor, side * 0.36, side * 0.045)
            Circle().fill(marine ? Color(hex: 0xB88C47) : palette.text).frame(width: 5, height: 5)
        }
        .shadow(color: Color.black.opacity(0.38), radius: 6, y: 3)
    }

    private var retroFace: some View {
        VStack(spacing: 7) {
            retroRow("WEEK", snapshot.weekElapsedPercent ?? 0, theme.calendarColor)
            retroRow("CODEX", snapshot.usagePercent ?? 0, theme.usageColor)
            retroRow("RESET", snapshot.effectiveResetChance, theme.resetColor)
        }
        .padding(11)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.grid, lineWidth: 1))
    }

    private func retroRow(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 2) {
            HStack { Text(label); Spacer(); Text("\(Int(value.rounded()))%") }
                .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(color)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(palette.grid)
                    Rectangle().fill(color).frame(width: geo.size.width * max(0, min(1, value / 100)))
                }
            }.frame(height: 5)
        }
    }

    private func radarFace(_ side: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(hex: 0x020B0A)); Circle().stroke(theme.usageColor.opacity(0.55), lineWidth: 1)
            Circle().stroke(theme.usageColor.opacity(0.23), lineWidth: 1).padding(side * 0.15)
            Circle().stroke(theme.usageColor.opacity(0.18), lineWidth: 1).padding(side * 0.30)
            Rectangle().fill(theme.usageColor.opacity(0.18)).frame(width: 1)
            Rectangle().fill(theme.usageColor.opacity(0.18)).frame(height: 1)
            ring(snapshot.weekElapsedPercent ?? 0, theme.calendarColor, side * 0.08, side * 0.025)
            ring(snapshot.usagePercent ?? 0, theme.usageColor, side * 0.22, side * 0.025)
            ring(snapshot.effectiveResetChance, theme.resetColor, side * 0.36, side * 0.025)
            Circle().fill(theme.usageColor).frame(width: 8, height: 8).offset(x: side * 0.28, y: -side * 0.17)
                .shadow(color: theme.usageColor, radius: 7)
        }
    }

    private func eInkFace(_ side: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(palette.surface)
            RoundedRectangle(cornerRadius: 8).stroke(palette.secondary.opacity(0.75), lineWidth: 1)
            ring(snapshot.weekElapsedPercent ?? 0, theme.calendarColor, side * 0.08, side * 0.035)
            ring(snapshot.usagePercent ?? 0, theme.usageColor, side * 0.22, side * 0.035)
            ring(snapshot.effectiveResetChance, theme.resetColor, side * 0.36, side * 0.035)
            Text("\(Int((snapshot.usagePercent ?? 0).rounded()))")
                .font(.system(size: 16, weight: .medium, design: .monospaced)).foregroundStyle(palette.text)
        }
    }
    private func ring(_ value: Double, _ color: Color, _ padding: CGFloat, _ width: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.13), lineWidth: width)
            Circle().trim(from: 0, to: max(0, min(1, value / 100))).stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round)).rotationEffect(.degrees(-90))
        }.padding(padding)
    }
}

private struct MobileAllowancePanel: View {
    let snapshot: QuotaSnapshot
    let theme: MobileTheme
    private var palette: ThemePalette { theme.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("ALLOWANCES", systemImage: "gauge.with.dots.needle.67percent")
                Spacer()
                if let credits = snapshot.creditSummary {
                    Text(credits.unlimited ? "UNLIMITED" : credits.balance ?? (credits.hasCredits ? "CREDITS" : "NO CREDITS"))
                }
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(palette.secondary)

            ForEach(snapshot.quotaInventory ?? []) { window in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(window.label).font(.system(size: 13, weight: .semibold, design: theme.fontDesign)).foregroundStyle(palette.text)
                            Text(window.scope + " · " + window.resetAt.formatted(.relative(presentation: .named)))
                                .font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(palette.secondary)
                        }
                        Spacer()
                        Text("\(Int(window.usedPercent.rounded()))%")
                            .font(.system(size: 17, weight: .semibold, design: theme.fontDesign)).foregroundStyle(theme.usageColor)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.grid)
                            Capsule().fill(theme.usageColor)
                                .frame(width: geometry.size.width * max(0, min(1, window.usedPercent / 100)))
                        }
                    }.frame(height: 5)
                }
            }

            if let task = snapshot.activeTasks?.first {
                Divider().overlay(palette.grid)
                HStack(spacing: 9) {
                    Circle().fill(theme.usageColor).frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.name).font(.system(size: 12, weight: .semibold, design: theme.fontDesign)).foregroundStyle(palette.text).lineLimit(1)
                        Text(task.state.uppercased()).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(palette.secondary)
                    }
                    Spacer()
                    Text(task.updatedAt, style: .relative).font(.caption2).foregroundStyle(palette.secondary)
                }
            }
        }
        .padding(16)
        .dashboardSurface(palette)
    }
}

private struct UsageRhythmPanel: View {
    private struct Cell: Identifiable { let date: Date; let burn: Double; var id: Date { date } }
    let snapshot: QuotaSnapshot
    let theme: MobileTheme
    private var palette: ThemePalette { theme.palette }

    private var cells: [Cell] {
        let calendar = Calendar.current
        var output: [Cell] = []
        for archive in snapshot.weeklyArchives ?? [] {
            let values = [(archive.windowStart, 0.0)] + archive.points.map { ($0.date, $0.usedPercent) }
            var first: [Date: Double] = [:], last: [Date: Double] = [:]
            for (date, value) in values.sorted(by: { $0.0 < $1.0 }) {
                let day = calendar.startOfDay(for: date)
                if first[day] == nil { first[day] = value }
                last[day] = value
            }
            output += last.map { Cell(date: $0.key, burn: max(0, $0.value - (first[$0.key] ?? $0.value))) }
        }
        if let start = snapshot.usageWindowStart {
            let values = [(start, 0.0)] + (snapshot.usageHistory ?? []).map { ($0.date, $0.usedPercent) }
            var first: [Date: Double] = [:], last: [Date: Double] = [:]
            for (date, value) in values.sorted(by: { $0.0 < $1.0 }) {
                let day = calendar.startOfDay(for: date)
                if first[day] == nil { first[day] = value }
                last[day] = value
            }
            output += last.map { Cell(date: $0.key, burn: max(0, $0.value - (first[$0.key] ?? $0.value))) }
        }
        var merged: [Date: Double] = [:]
        for cell in output { merged[cell.date] = max(merged[cell.date] ?? 0, cell.burn) }
        return merged.map { Cell(date: $0.key, burn: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("USAGE RHYTHM", systemImage: "square.grid.3x3.fill")
                Spacer()
                Text("26 WEEKS")
            }.font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(palette.secondary)

            Canvas { context, size in
                let calendar = Calendar.current
                let end = calendar.startOfDay(for: Date())
                let start = calendar.date(byAdding: .day, value: -(26 * 7 - 1), to: end) ?? end
                let gap: CGFloat = 3
                let side = min(11, (size.width - 25 * gap) / 26)
                let lookup = Dictionary(uniqueKeysWithValues: cells.map { (calendar.startOfDay(for: $0.date), $0.burn) })
                let peak = max(1, cells.map(\.burn).max() ?? 1)
                for offset in 0..<(26 * 7) {
                    guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                    let row = (calendar.component(.weekday, from: date) + 5) % 7
                    let column = offset / 7
                    let intensity = min(1, (lookup[date] ?? 0) / peak)
                    let rect = CGRect(x: CGFloat(column) * (side + gap), y: CGFloat(row) * (side + gap), width: side, height: side)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(intensity > 0 ? theme.usageColor.opacity(0.18 + intensity * 0.82) : palette.grid.opacity(0.7)))
                }
            }.frame(height: 7 * 14)

            HStack {
                Text("\(cells.filter { $0.burn > 0.05 }.count) active days")
                Spacer()
                Text(cells.max(by: { $0.burn < $1.burn }).map { "Peak \(Int($0.burn.rounded()))%" } ?? "Building history")
            }.font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(palette.secondary)
        }
        .padding(16)
        .dashboardSurface(palette)
    }
}

private struct PacePanel: View {
    let snapshot: QuotaSnapshot
    let theme: MobileTheme
    @Binding var range: MobilePaceRange
    @Binding var weekIndex: Int
    let compact: Bool
    @State private var selectedDate: Date?
    private var palette: ThemePalette { theme.palette }
    private var archives: [QuotaWeeklyArchive] {
        (snapshot.weeklyArchives ?? []).sorted { $0.windowStart > $1.windowStart }
    }
    private var selectedArchive: QuotaWeeklyArchive? {
        guard !compact, weekIndex > 0, weekIndex <= archives.count else { return nil }
        return archives[weekIndex - 1]
    }
    private var currentPoints: [QuotaUsagePoint] {
        QuotaChartHistory.currentPoints(from: snapshot)
    }
    private var archivePoints: [QuotaUsagePoint] {
        guard let archive = selectedArchive else { return [] }
        let start = QuotaUsagePoint(date: archive.windowStart, usedPercent: 0, tokens: 0)
        let converted = archive.points.map { point in
            let tokens = archive.totalTokens.flatMap { total -> Int64? in
                guard archive.finalUsedPercent > 0 else { return nil }
                return Int64((Double(total) * point.usedPercent / archive.finalUsedPercent).rounded())
            }
            return QuotaUsagePoint(date: point.date, usedPercent: point.usedPercent, tokens: tokens)
        }
        return [start] + converted
    }
    private var points: [QuotaUsagePoint] {
        if selectedArchive != nil { return archivePoints }
        let all = currentPoints
        let now = Date()
        guard let seconds = range.seconds else { return all }
        let cutoff = now.addingTimeInterval(-seconds), inside = all.filter { $0.date >= cutoff }
        if let previous = all.last(where: { $0.date < cutoff }) {
            return [.init(date: cutoff, usedPercent: previous.usedPercent, tokens: previous.tokens)] + inside
        }
        return inside
    }
    private var activeWindowStart: Date? { selectedArchive?.windowStart ?? snapshot.usageWindowStart }
    private var activeResetAt: Date? { selectedArchive?.resetAt ?? snapshot.resetAt }
    private var activeUsedPercent: Double? { selectedArchive?.finalUsedPercent ?? snapshot.usagePercent }
    private var activeTokenTotal: Int64? { selectedArchive?.totalTokens ?? snapshot.bestTokenTotal }
    private var visibleStart: Date {
        points.first?.date ?? activeWindowStart ?? Date().addingTimeInterval(-(range.seconds ?? 3_600))
    }
    private var visibleEnd: Date {
        let candidate = points.last?.date ?? Date()
        return candidate > visibleStart ? candidate : visibleStart.addingTimeInterval(60)
    }
    private func graphValue(_ point: QuotaUsagePoint) -> Double { point.usedPercent }
    private func idealPercent(at date: Date) -> Double {
        guard let start = activeWindowStart, let reset = activeResetAt, reset > start else { return 0 }
        return max(0, min(100, date.timeIntervalSince(start) / reset.timeIntervalSince(start) * 100))
    }
    private func idealValue(at date: Date) -> Double { idealPercent(at: date) }
    private var nearestPoint: QuotaUsagePoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private var costPoints: [QuotaCostPoint] {
        guard selectedArchive == nil else { return [] }
        let all = (snapshot.usageIntelligence?.costTimeline ?? []).sorted { $0.date < $1.date }
        guard let seconds = range.seconds else { return all }
        let cutoff = Date().addingTimeInterval(-seconds)
        let inside = all.filter { $0.date >= cutoff }
        if let previous = all.last(where: { $0.date < cutoff }) {
            return [.init(date: cutoff, apiEquivalentUSD: previous.apiEquivalentUSD)] + inside
        }
        return inside
    }
    private func normalizedCost(_ point: QuotaCostPoint) -> Double {
        guard let intelligence = snapshot.usageIntelligence,
              intelligence.apiEquivalentUSD > 0,
              let used = activeUsedPercent else { return 0 }
        return max(0, min(100, point.apiEquivalentUSD / intelligence.apiEquivalentUSD * used))
    }
    private var nearestCost: QuotaCostPoint? {
        guard let selectedDate else { return nil }
        return costPoints.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.usedPercent)
            + costPoints.map(normalizedCost)
            + [idealPercent(at: visibleStart), idealPercent(at: visibleEnd)]
        guard let minimum = values.min(), let maximum = values.max() else { return 0...10 }
        let span = max(5, maximum - minimum)
        var lower = floor(max(0, minimum - span * 0.18) / 5) * 5
        var upper = ceil(min(100, maximum + span * 0.18) / 5) * 5
        if upper - lower < 10 {
            lower = max(0, lower - 5)
            upper = min(100, upper + 5)
        }
        return lower...max(lower + 5, upper)
    }
    private var xAxisDates: [Date] {
        let duration = visibleEnd.timeIntervalSince(visibleStart)
        guard duration > 0 else { return [visibleStart] }
        // Keep labels comfortably inside the plot. Axis labels at the exact
        // trailing boundary are truncated by Swift Charts on narrow phones.
        let fractions: [Double] = compact ? [0.14, 0.50, 0.82] : [0.10, 0.35, 0.60, 0.84]
        return fractions.map { visibleStart.addingTimeInterval(duration * $0) }
    }
    private var projectedRunoutAt: Date? {
        guard selectedArchive == nil,
              let used = snapshot.usagePercent,
              used > 0, used < 100,
              let latest = points.last,
              let first = points.first,
              latest.date > first.date
        else { return selectedArchive == nil ? snapshot.estimatedRunoutAt : nil }

        let duration = latest.date.timeIntervalSince(first.date)
        var percentBurn = latest.usedPercent - first.usedPercent
        if percentBurn <= 0,
           let firstTokens = first.tokens,
           let lastTokens = latest.tokens,
           lastTokens > firstTokens,
           let total = activeTokenTotal,
           total > 0 {
            percentBurn = Double(lastTokens - firstTokens) / Double(total) * used
        }
        guard percentBurn > 0 else { return snapshot.estimatedRunoutAt }
        let seconds = (100 - used) / (percentBurn / duration)
        guard seconds.isFinite, seconds > 0 else { return snapshot.estimatedRunoutAt }
        return latest.date.addingTimeInterval(seconds)
    }
    private var weekLabel: String {
        guard let archive = selectedArchive else { return "THIS WEEK" }
        return archive.windowStart.formatted(.dateTime.month(.abbreviated).day())
            + " – " + archive.resetAt.formatted(.dateTime.month(.abbreviated).day())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if !compact {
                HStack {
                    Button {
                        guard weekIndex < archives.count else { return }
                        weekIndex += 1
                        selectedDate = nil
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 34, height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(weekIndex >= archives.count)
                    .opacity(weekIndex >= archives.count ? 0.22 : 1)

                    Spacer()
                    Text(weekLabel.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(palette.secondary)
                    Spacer()

                    Button {
                        guard weekIndex > 0 else { return }
                        weekIndex -= 1
                        selectedDate = nil
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 34, height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(weekIndex == 0)
                    .opacity(weekIndex == 0 ? 0.22 : 1)
                }
                .foregroundStyle(theme.usageColor)
            }
            HStack(alignment: .center) {
                Label("PACE", systemImage: "chart.xyaxis.line")
                    .font(.system(size: compact ? 12 : 14, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.secondary)
                Spacer()
                if let runout = projectedRunoutAt {
                    Text("Run-out in").font(.system(size: 11, design: .rounded)).foregroundStyle(palette.secondary)
                    Text(Self.relative(runout)).font(.system(size: 16, weight: .semibold, design: theme.fontDesign)).foregroundStyle(theme.usageColor)
                } else if let archive = selectedArchive {
                    Text("Finished").font(.system(size: 11, design: .rounded)).foregroundStyle(palette.secondary)
                    Text("\(Int(archive.finalUsedPercent.rounded()))%")
                        .font(.system(size: 16, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.usageColor)
                } else {
                    Text("Calculating pace")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.secondary)
                }
            }
            if selectedArchive == nil {
                HStack(spacing: 6) {
                    ForEach(MobilePaceRange.allCases) { option in
                        Button { range = option; selectedDate = nil } label: {
                            Text(option.rawValue).font(.system(size: 9, weight: .medium, design: .rounded)).frame(maxWidth: .infinity).padding(.vertical, 6)
                                .background(range == option ? theme.usageColor : palette.raised, in: theme == .retro || theme == .eInk ? AnyShape(RoundedRectangle(cornerRadius: 3)) : AnyShape(Capsule()))
                                .foregroundStyle(range == option ? Color.white : palette.secondary)
                        }.buttonStyle(.plain)
                    }
                }
            }
            if !compact, selectedArchive == nil, let intelligence = snapshot.usageIntelligence {
                HStack(alignment: .bottom, spacing: 0) {
                    intelligenceValue("API VALUE", String(format: "$%.2f", intelligence.apiEquivalentUSD), theme.resetColor)
                    intelligenceValue("TOKENS", snapshot.bestTokenTotal.map(DashboardView.tokens) ?? "—", palette.text)
                    intelligenceValue("CACHE", intelligence.cacheHitRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", palette.text)
                    intelligenceValue("FAST", "\(Int((intelligence.fastShare * 100).rounded()))%", palette.text)
                }
                HStack(spacing: 7) {
                    Text(intelligence.topModel?.replacingOccurrences(of: "gpt-", with: "") ?? "Unknown model")
                    Circle().frame(width: 2, height: 2)
                    Text("\(Int((intelligence.pricingCoverage * 100).rounded()))% priced")
                    if let secondary = snapshot.secondaryQuota {
                        Circle().frame(width: 2, height: 2)
                        Text("secondary \(Int(secondary.usedPercent.rounded()))%")
                    }
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.secondary)
            }
            if let point = nearestPoint {
                HStack {
                    Text(point.date.formatted(date: .omitted, time: .shortened)); Spacer(); Text("\(Int(point.usedPercent.rounded()))%")
                    if let tokens = point.tokens { Text("· \(DashboardView.tokens(tokens)) tokens") }
                    if let cost = nearestCost { Text("· \(cost.apiEquivalentUSD, format: .currency(code: "USD"))") }
                }.font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(palette.text)
                    .padding(.horizontal, 10).padding(.vertical, 7).background(palette.raised, in: Capsule())
            }
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Used", graphValue(point)), series: .value("Series", "Actual"))
                        .foregroundStyle(theme.usageColor).lineStyle(StrokeStyle(lineWidth: theme == .radar ? 1.4 : 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(theme == .marine ? .catmullRom : .stepEnd)
                    AreaMark(x: .value("Time", point.date), y: .value("Used", graphValue(point)), series: .value("Series", "Actual fill"))
                        .foregroundStyle(LinearGradient(colors: [theme.usageColor.opacity(theme == .eInk ? 0.05 : 0.18), .clear], startPoint: .top, endPoint: .bottom))
                }
                ForEach(costPoints) { point in
                    LineMark(x: .value("Time", point.date), y: .value("API cost", normalizedCost(point)), series: .value("Series", "API cost"))
                        .foregroundStyle(theme.resetColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
                if activeWindowStart != nil, activeResetAt != nil {
                    LineMark(x: .value("Time", visibleStart), y: .value("Ideal", idealValue(at: visibleStart)), series: .value("Series", "Ideal")).foregroundStyle(palette.secondary).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                    LineMark(x: .value("Time", visibleEnd), y: .value("Ideal", idealValue(at: visibleEnd)), series: .value("Series", "Ideal")).foregroundStyle(palette.secondary).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                }
                if let point = nearestPoint {
                    RuleMark(x: .value("Selected", point.date)).foregroundStyle(palette.secondary.opacity(0.65))
                    PointMark(x: .value("Selected", point.date), y: .value("Used", graphValue(point))).foregroundStyle(theme.usageColor).symbolSize(38)
                }
            }
            .chartXScale(domain: visibleStart...visibleEnd)
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(palette.grid.opacity(0.75))
                    AxisValueLabel {
                        if let n = value.as(Double.self) { Text("\(Int(n))%") }
                    }.foregroundStyle(palette.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisDates) { value in
                    AxisGridLine().foregroundStyle(palette.grid.opacity(0.35))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(date))
                        }
                    }
                    .foregroundStyle(palette.secondary)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        guard let frame = proxy.plotFrame else { return }; let origin = geo[frame].origin
                        selectedDate = proxy.value(atX: value.location.x - origin.x, as: Date.self)
                    })
                }
            }
            .frame(height: compact ? 102 : 270)
            HStack {
                Label("USAGE PATH", systemImage: "line.diagonal").foregroundStyle(theme.usageColor)
                if !costPoints.isEmpty { Label("API COST", systemImage: "line.diagonal").foregroundStyle(theme.resetColor) }
                Label("IDEAL", systemImage: "line.diagonal").foregroundStyle(palette.secondary); Spacer()
                if let used = activeUsedPercent { Text("\(Int(used.rounded()))% USED") }
            }.font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(palette.secondary)
        }.padding(compact ? 8 : 16).dashboardSurface(palette, radius: compact ? theme.cornerRadius : theme.cornerRadius + 2)
    }
    private func intelligenceValue(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundStyle(palette.secondary)
            Text(value).font(.system(size: 14, weight: .semibold, design: theme.fontDesign)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var paceHeadline: String {
        guard let runout = snapshot.estimatedRunoutAt, let reset = snapshot.resetAt else { return "Building your pace" }
        if abs(runout.timeIntervalSince(reset)) < 3_600 { return "On pace" }; return runout < reset ? "Running hot" : "Room to spare"
    }
    private static func relative(_ date: Date) -> String {
        let seconds = max(0, date.timeIntervalSinceNow), days = Int(seconds / 86_400)
        let hours = Int(seconds.truncatingRemainder(dividingBy: 86_400) / 3_600), minutes = Int(seconds.truncatingRemainder(dividingBy: 3_600) / 60)
        if days > 0 { return "\(days)d \(hours)h" }; if hours > 0 { return "\(hours)h \(minutes)m" }; return "\(minutes)m"
    }
    private func axisLabel(_ date: Date) -> String {
        if selectedArchive != nil || visibleEnd.timeIntervalSince(visibleStart) > 36 * 3_600 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.hour())
    }
}

private struct MobileArchivedWeekCard: View {
    let archive: QuotaWeeklyArchive
    let theme: MobileTheme
    private var palette: ThemePalette { theme.palette }
    private var values: [QuotaWeeklyArchivePoint] {
        [.init(date: archive.windowStart, usedPercent: 0, apiEquivalentUSD: 0)] + archive.points
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateRange).font(.system(size: 15, weight: .semibold, design: theme.fontDesign)).foregroundStyle(palette.text)
                    Text("COMPLETED WEEK").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(palette.secondary)
                }
                Spacer()
                Text("\(Int(archive.finalUsedPercent.rounded()))%")
                    .font(.system(size: 24, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.usageColor)
            }

            HStack(spacing: 0) {
                metric("API", archive.apiEquivalentUSD.map { String(format: "$%.0f", $0) } ?? "—")
                metric("TOKENS", archive.totalTokens.map(DashboardView.tokens) ?? "—")
                metric("CACHE", archive.cacheHitRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                metric("FAST", archive.fastShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
            }

            Chart {
                ForEach(values) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Used", point.usedPercent))
                        .foregroundStyle(theme.usageColor)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    AreaMark(x: .value("Time", point.date), y: .value("Used", point.usedPercent))
                        .foregroundStyle(LinearGradient(colors: [theme.usageColor.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom))
                }
                LineMark(x: .value("Time", archive.windowStart), y: .value("Ideal", 0), series: .value("Series", "Ideal"))
                    .foregroundStyle(palette.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                LineMark(x: .value("Time", archive.resetAt), y: .value("Ideal", 100), series: .value("Series", "Ideal"))
                    .foregroundStyle(palette.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine().foregroundStyle(palette.grid)
                    AxisValueLabel { if let n = value.as(Int.self) { Text("\(n)%") } }.foregroundStyle(palette.secondary)
                }
            }
            .frame(height: 150)

            if let model = archive.topModel {
                Text(model.replacingOccurrences(of: "gpt-", with: ""))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.secondary)
            }
        }
        .padding(16)
        .dashboardSurface(palette)
    }

    private var dateRange: String {
        archive.windowStart.formatted(.dateTime.month(.abbreviated).day()) + " – " + archive.resetAt.formatted(.dateTime.month(.abbreviated).day())
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundStyle(palette.secondary)
            Text(value).font(.system(size: 12, weight: .semibold, design: theme.fontDesign)).foregroundStyle(palette.text).lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PostRow: View {
    let post: QuotaTiboPost; let palette: ThemePalette
    var body: some View {
        Button { if let url = post.url { UIApplication.shared.open(url) } } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: post.isResetOriented ? "arrow.triangle.2.circlepath" : "bubble.left.fill")
                    Text(post.isResetOriented ? "RESET SIGNAL" : "TIBO"); Spacer(); if let date = post.date { Text(date, style: .relative) }
                }.font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(post.isResetOriented ? Color(hex: QuotaColors.calendar) : Color(hex: QuotaColors.reset))
                if let reply = post.inReplyTo, !reply.isEmpty {
                    Text("IN REPLY TO  \(reply)").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(palette.secondary).lineLimit(3)
                }
                Text(post.text).font(.system(size: 16, weight: .medium, design: .rounded)).foregroundStyle(palette.text)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                if post.url != nil { Label("Open on X", systemImage: "arrow.up.right").font(.caption.bold()).foregroundStyle(Color(hex: QuotaColors.reset)) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16).dashboardSurface(palette)
        }.buttonStyle(.plain)
    }
}

private struct ThemeSwatch: View {
    let theme: MobileTheme; let selected: Bool
    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 10) {
            glyph.frame(width: 48, height: 48)
            Text(theme.rawValue.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(p.text)
        }.padding(8).frame(width: 76, alignment: .leading).background(p.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(selected ? Color(hex: QuotaColors.usage) : p.grid, lineWidth: selected ? 2 : 1))
    }

    @ViewBuilder private var glyph: some View {
        switch theme {
        case .oled:
            ZStack {
                Circle().stroke(Color(hex: QuotaColors.calendar).opacity(0.25), lineWidth: 4)
                Circle().trim(from: 0, to: 0.72).stroke(Color(hex: QuotaColors.calendar), style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                Circle().trim(from: 0, to: 0.58).stroke(Color(hex: QuotaColors.usage), style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90)).padding(8)
                Circle().trim(from: 0, to: 0.44).stroke(Color(hex: QuotaColors.reset), style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90)).padding(16)
            }
        case .instrument:
            ZStack {
                Circle().fill(Color(hex: 0x090B0B)); Circle().stroke(Color.white.opacity(0.28), lineWidth: 2)
                ForEach(0..<12) { tick in
                    Capsule().fill(Color(hex: QuotaColors.calendar)).frame(width: 1.3, height: 5).offset(y: -18).rotationEffect(.degrees(Double(tick) * 30))
                }
                Capsule().fill(Color.white).frame(width: 2, height: 16).offset(y: -7).rotationEffect(.degrees(52), anchor: .bottom)
                Circle().fill(Color(hex: QuotaColors.calendar)).frame(width: 5, height: 5)
            }
        case .marine:
            ZStack {
                Circle().fill(Color(hex: 0x082243)); Circle().stroke(Color(hex: 0xBC8B43), lineWidth: 2)
                ForEach(0..<8) { tick in Capsule().fill(Color.white.opacity(0.8)).frame(width: 1, height: 4).offset(y: -18).rotationEffect(.degrees(Double(tick) * 45)) }
                Capsule().fill(Color.white).frame(width: 2, height: 15).offset(y: -7).rotationEffect(.degrees(118), anchor: .bottom)
                Circle().fill(Color(hex: 0xBC8B43)).frame(width: 5, height: 5)
            }
        case .retro:
            RoundedRectangle(cornerRadius: 7).fill(Color(hex: 0xC4C8B3)).overlay(
                VStack(spacing: 2) { Text("WEEK  86%"); Text("CODEX 71%"); Text("RESET 56%") }
                    .font(.system(size: 5, weight: .bold, design: .monospaced)).foregroundStyle(Color(hex: 0x263229))
            )
        case .radar:
            ZStack {
                Circle().fill(Color(hex: 0x071408)); Circle().stroke(Color.green.opacity(0.55), lineWidth: 1)
                Circle().stroke(Color.green.opacity(0.28), lineWidth: 1).padding(10)
                Rectangle().fill(Color.green.opacity(0.25)).frame(width: 1); Rectangle().fill(Color.green.opacity(0.25)).frame(height: 1)
                Capsule().fill(Color.green.opacity(0.8)).frame(width: 2, height: 21).offset(y: -10).rotationEffect(.degrees(35), anchor: .bottom)
            }
        case .eInk:
            RoundedRectangle(cornerRadius: 7).fill(Color(hex: 0xE2E0D8)).overlay(
                VStack(spacing: 0) { Text("86%").font(.system(size: 14, weight: .medium, design: .monospaced)); Text("71 · 56").font(.system(size: 6, design: .monospaced)) }
                    .foregroundStyle(Color(hex: 0x353636))
            )
        }
    }
}

private extension View {
    func dashboardSurface(_ palette: ThemePalette, radius: CGFloat = 18) -> some View {
        background(palette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(palette.grid.opacity(0.72), lineWidth: 1))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
