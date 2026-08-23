import Charts
import SwiftUI

enum MobileTheme: String, CaseIterable, Identifiable {
    case instrument = "Instrument", oled = "OLED", marine = "Marine"
    case retro = "Retro", radar = "Radar", eInk = "E-Ink"

    var id: String { rawValue }
    var calendarColor: Color {
        switch self {
        case .instrument, .oled, .retro: Color(hex: QuotaColors.calendar)
        case .marine: Color(hex: 0xE3B459)
        case .radar: Color(hex: 0x82C98E)
        case .eInk: Color(hex: 0x8C7240)
        }
    }
    var usageColor: Color {
        switch self {
        case .instrument, .oled, .marine: Color(hex: QuotaColors.usage)
        case .retro: Color(hex: 0x79F19B)
        case .radar: Color(hex: 0x58E5A5)
        case .eInk: Color(hex: 0x557A67)
        }
    }
    var resetColor: Color {
        switch self {
        case .instrument, .oled, .marine: Color(hex: QuotaColors.reset)
        case .retro: Color(hex: 0x5CD5FF)
        case .radar: Color(hex: 0x45BFCB)
        case .eInk: Color(hex: 0x536A76)
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
    @State private var selectedTab: DashboardTab = .glance
    @State private var paceRange: MobilePaceRange = .twelveHours
    @State private var postFilterReset = true

    private var palette: ThemePalette { theme.palette }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { glancePage }
                .tag(DashboardTab.glance)
            NavigationStack { postsPage }
                .tag(DashboardTab.posts)
            NavigationStack { pacePage }
                .tag(DashboardTab.pace)
            NavigationStack {
                SettingsView(selectedSource: $store.selectedSource, selectedTheme: $theme)
            }
            .tag(DashboardTab.settings)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DashboardTabBar(selection: $selectedTab, theme: theme)
        }
        .tint(theme.usageColor)
        .preferredColorScheme(palette.isLight ? .light : .dark)
        .onAppear {
#if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--quota-tab-posts") { selectedTab = .posts }
            if arguments.contains("--quota-tab-pace") { selectedTab = .pace }
            if arguments.contains("--quota-tab-settings") { selectedTab = .settings }
#endif
        }
    }

    private var glancePage: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                dashboardHeader
                overview
                if let expectedAt = activeScheduledResetAt { scheduledResetCard(expectedAt) }
                if let post = store.snapshot.tiboPosts?.first { latestPost(post) }
                PacePanel(snapshot: store.snapshot, theme: theme, range: $paceRange, compact: true)
                    .onTapGesture { selectedTab = .pace }
                detailRows
                themeRail
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
            Menu {
                    Picker("Theme", selection: $theme) {
                    ForEach(MobileTheme.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Label("THEMES", systemImage: "paintpalette")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 78, alignment: .trailing)
            }
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
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(palette.secondary)
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
        guard let expectedAt = store.snapshot.announcementExpectedAt,
              expectedAt > Date().addingTimeInterval(-5 * 60)
        else { return nil }
        return expectedAt
    }

    private func scheduledResetCard(_ expectedAt: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(spacing: 12) {
                Image(systemName: "hourglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.resetColor)
                    .frame(width: 34, height: 34)
                    .background(theme.resetColor.opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("RESET COUNTDOWN")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(theme.resetColor)
                    Text(expectedAt, style: .timer)
                        .font(.system(size: 25, weight: .semibold, design: theme.fontDesign))
                        .monospacedDigit()
                        .foregroundStyle(palette.text)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(expectedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(palette.text)
                    Text("YOUR TIME · \(Self.timeZoneLabel(expectedAt))")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .dashboardSurface(palette, radius: theme.cornerRadius)
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

    private var themeRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("THEMES").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.4).foregroundStyle(palette.secondary)
                Spacer(); Text(theme.rawValue).font(.caption.bold()).foregroundStyle(palette.text)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(MobileTheme.allCases) { option in
                        Button { theme = option } label: { ThemeSwatch(theme: option, selected: option == theme) }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(.vertical, 2)
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
                PacePanel(snapshot: store.snapshot, theme: theme, range: $paceRange, compact: false)
                paceStats; providerSection
            }.padding(16)
        }
        .background(palette.background.ignoresSafeArea()).navigationTitle("Codex Pace").navigationBarTitleDisplayMode(.large)
        .toolbarBackground(palette.background, for: .navigationBar)
    }

    private var paceStats: some View {
        HStack(spacing: 0) {
            paceStat("5M", store.snapshot.tokenPace?.fiveMinutes); paceStat("1H", store.snapshot.tokenPace?.oneHour)
            paceStat("12H", store.snapshot.tokenPace?.twelveHours); paceStat("24H", store.snapshot.tokenPace?.twentyFourHours)
        }.padding(.vertical, 15).dashboardSurface(palette)
    }
    private func paceStat(_ label: String, _ tokens: Int64?) -> some View {
        VStack(spacing: 5) {
            Text(label).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(palette.secondary)
            Text(tokens.map(Self.tokens) ?? "—").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(palette.text).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity)
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RESET SOURCES").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.2).foregroundStyle(palette.secondary)
                Spacer()
                Menu {
                    Picker("Reset calculator", selection: $store.selectedSource) { ForEach(ResetSource.allCases) { Text($0.name).tag($0) } }
                } label: { Text(store.selectedSource.name).font(.caption.bold()).foregroundStyle(Color(hex: QuotaColors.reset)) }
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

private struct PacePanel: View {
    let snapshot: QuotaSnapshot
    let theme: MobileTheme
    @Binding var range: MobilePaceRange
    let compact: Bool
    @State private var selectedDate: Date?
    private var palette: ThemePalette { theme.palette }
    private var points: [QuotaUsagePoint] {
        var all = (snapshot.usageHistory ?? []).sorted { $0.date < $1.date }
        let now = Date()
        if let current = snapshot.usagePercent, all.last.map({ now.timeIntervalSince($0.date) > 30 }) ?? true {
            all.append(.init(date: now, usedPercent: current, tokens: snapshot.weeklyTokens))
        }
        let reportedTokens = snapshot.weeklyTokens ?? 0
        let tokenAnchor = reportedTokens > 0 ? reportedTokens : (all.compactMap(\.tokens).max() ?? 0)
        all = all.map { point in
            guard let tokenAtPoint = point.tokens,
                  tokenAnchor > 0,
                  let currentPercent = snapshot.usagePercent, currentPercent > 0 else { return point }
            let tokenInterpolated = Double(tokenAtPoint) / Double(tokenAnchor) * currentPercent
            return .init(date: point.date, usedPercent: max(point.usedPercent, min(currentPercent, tokenInterpolated)), tokens: tokenAtPoint)
        }
        guard let seconds = range.seconds else { return all }
        let cutoff = now.addingTimeInterval(-seconds), inside = all.filter { $0.date >= cutoff }
        if let previous = all.last(where: { $0.date < cutoff }) {
            return [.init(date: cutoff, usedPercent: previous.usedPercent, tokens: previous.tokens)] + inside
        }
        return inside
    }
    private var visibleStart: Date { points.first?.date ?? snapshot.usageWindowStart ?? Date().addingTimeInterval(-3_600) }
    private var visibleEnd: Date { points.last?.date ?? Date() }
    private func graphValue(_ point: QuotaUsagePoint) -> Double { point.usedPercent }
    private func idealPercent(at date: Date) -> Double {
        guard let start = snapshot.usageWindowStart, let reset = snapshot.resetAt, reset > start else { return 0 }
        return max(0, min(100, date.timeIntervalSince(start) / reset.timeIntervalSince(start) * 100))
    }
    private func idealValue(at date: Date) -> Double { idealPercent(at: date) }
    private var nearestPoint: QuotaUsagePoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center) {
                Label("PACE", systemImage: "chart.xyaxis.line")
                    .font(.system(size: compact ? 12 : 14, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.secondary)
                Spacer()
                if let runout = snapshot.estimatedRunoutAt {
                    Text("Run-out in").font(.system(size: 11, design: .rounded)).foregroundStyle(palette.secondary)
                    Text(Self.relative(runout)).font(.system(size: 16, weight: .semibold, design: theme.fontDesign)).foregroundStyle(theme.usageColor)
                }
            }
            HStack(spacing: 6) {
                ForEach(MobilePaceRange.allCases) { option in
                    Button { range = option; selectedDate = nil } label: {
                        Text(option.rawValue).font(.system(size: 9, weight: .medium, design: .rounded)).frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(range == option ? theme.usageColor : palette.raised, in: theme == .retro || theme == .eInk ? AnyShape(RoundedRectangle(cornerRadius: 3)) : AnyShape(Capsule()))
                            .foregroundStyle(range == option ? (palette.isLight ? Color.white : Color.black) : palette.secondary)
                    }.buttonStyle(.plain)
                }
            }
            if let point = nearestPoint {
                HStack {
                    Text(point.date.formatted(date: .omitted, time: .shortened)); Spacer(); Text("\(Int(point.usedPercent.rounded()))%")
                    if let tokens = point.tokens { Text("· \(DashboardView.tokens(tokens)) tokens") }
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
                if snapshot.usageWindowStart != nil, snapshot.resetAt != nil {
                    LineMark(x: .value("Time", visibleStart), y: .value("Ideal", idealValue(at: visibleStart)), series: .value("Series", "Ideal")).foregroundStyle(palette.secondary).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                    LineMark(x: .value("Time", visibleEnd), y: .value("Ideal", idealValue(at: visibleEnd)), series: .value("Series", "Ideal")).foregroundStyle(palette.secondary).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                }
                if let point = nearestPoint {
                    RuleMark(x: .value("Selected", point.date)).foregroundStyle(palette.secondary.opacity(0.65))
                    PointMark(x: .value("Selected", point.date), y: .value("Used", graphValue(point))).foregroundStyle(theme.usageColor).symbolSize(38)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(palette.grid.opacity(0.75))
                    AxisValueLabel {
                        if let n = value.as(Double.self) { Text("\(Int(n))%") }
                    }.foregroundStyle(palette.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: compact ? 3 : 5)) {
                    AxisGridLine().foregroundStyle(palette.grid.opacity(0.35)); AxisValueLabel(format: .dateTime.hour().minute()).foregroundStyle(palette.secondary)
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
                Label("IDEAL", systemImage: "line.diagonal").foregroundStyle(palette.secondary); Spacer()
                if let used = snapshot.usagePercent { Text("\(Int(used.rounded()))% USED") }
            }.font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(palette.secondary)
        }.padding(compact ? 8 : 16).dashboardSurface(palette, radius: compact ? theme.cornerRadius : theme.cornerRadius + 2)
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

private struct DashboardTabBar: View {
    @Binding var selection: DashboardTab
    let theme: MobileTheme
    private var palette: ThemePalette { theme.palette }
    private let items: [(DashboardTab, String, String)] = [
        (.glance, "circle.grid.3x3.fill", "Glance"),
        (.posts, "bubble.left.and.bubble.right", "Posts"),
        (.pace, "chart.xyaxis.line", "Pace"),
        (.settings, "gearshape", "Settings")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { tab, icon, label in
                Button { selection = tab } label: {
                    VStack(spacing: 3) {
                        Image(systemName: icon).font(.system(size: 20, weight: .medium))
                        Text(label).font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(selection == tab ? theme.usageColor : palette.secondary)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .background(palette.background.opacity(0.97))
        .overlay(alignment: .top) { Rectangle().fill(palette.grid.opacity(0.6)).frame(height: 0.5) }
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
