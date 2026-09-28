import Charts
import SwiftUI

struct PhoneActivityView: View {
    let snapshot: QuotaSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                ProviderBrandMark(provider: .codex).frame(width: 15, height: 15)
                Text("Codex").font(.subheadline.weight(.semibold))
                Spacer()
                Text("Usage & pace").font(.caption).foregroundStyle(PhoneStyle.secondary)
            }.foregroundStyle(PhoneStyle.tint(.codex))
            if let start = snapshot.usageWindowStart, let end = snapshot.resetAt, end > start {
                PhoneHistoryChart(snapshot: snapshot, current: .init(start: start, end: end,
                    points: QuotaChartHistory.currentPoints(from: snapshot, now: min(.now, snapshot.usageMeasurementDate))
                        .map { .init(date: $0.date, used: $0.usedPercent) },
                    used: snapshot.usagePercent, tokens: snapshot.bestTokenTotal, apiValue: snapshot.usageIntelligence?.apiEquivalentUSD),
                    archives: (snapshot.weeklyArchives ?? []).map {
                        .init(start: $0.windowStart, end: $0.resetAt, points: $0.points.map { .init(date: $0.date, used: $0.usedPercent) },
                              used: $0.finalUsedPercent, tokens: $0.totalTokens, apiValue: $0.apiEquivalentUSD)
                    })
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "calendar").font(.title2)
                    Text("Your week, as it happens.").font(.headline)
                    Text("Connect Codex in Settings. Your iPhone will record usage and build your calendar and pace chart.")
                        .font(.subheadline).foregroundStyle(PhoneStyle.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
            }
        }.foregroundStyle(PhoneStyle.ink)
    }
}

/// Phone-specific composition of the same recorded samples used on the Mac.
/// Quota percentages stay authoritative; the pace is shown as an estimate.
private struct PhoneHistoryChart: View {
    var snapshot: QuotaSnapshot? = nil
    let current: QuotaHistoryWeek
    let archives: [QuotaHistoryWeek]
    var provider: DisplayProvider = .codex
    var measuredAt: Date? = nil
    var fallbackRunout: Date? = nil
    @State private var weekIndex = 0
    @State private var range = QuotaHistoryRange.week
    @State private var selectedDay: Date?
    @State private var selectedDate: Date?
    @State private var showTotals = false
    private var blue: Color { PhoneStyle.tint(provider) }
    private var weeks: [QuotaHistoryWeek] { [current] + archives.sorted { $0.start > $1.start } }
    private var week: QuotaHistoryWeek { weeks[min(weekIndex, weeks.count - 1)] }
    private var history: [QuotaHistoryPoint] {
        week.points.filter { $0.used.isFinite && (0...100).contains($0.used) && $0.date >= week.start && $0.date <= week.end }
            .sorted { $0.date < $1.date }
    }
    private var bounds: ClosedRange<Date> {
        if let selectedDay {
            let start = max(week.start, selectedDay)
            let end = min(week.end, Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay.addingTimeInterval(86_400))
            return start...max(start.addingTimeInterval(60), end)
        }
        if let seconds = range.seconds, weekIndex == 0 {
            let end = max(week.start.addingTimeInterval(60), min(.now, week.end))
            return max(week.start, end.addingTimeInterval(-seconds))...end
        }
        return week.start...max(week.start.addingTimeInterval(60), week.end)
    }
    private var visible: [QuotaHistoryPoint] {
        let inside = history.filter { bounds.contains($0.date) }
        if let previous = history.last(where: { $0.date < bounds.lowerBound }) { return [previous] + inside }
        return inside
    }
    private var nearest: QuotaHistoryPoint? {
        guard let selectedDate else { return nil }
        return visible.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private var pacePoints: [QuotaHistoryPoint] {
        let end = min(Date(), week.end)
        let start = range.seconds.map { end.addingTimeInterval(-$0) } ?? week.start
        return history.filter { $0.date >= start && $0.date <= end }
    }
    private var hourlyRate: Double? {
        if provider == .claude {
            guard weekIndex == 0 else { return nil }
            return ClaudeUsageHistory.hourlyRate(points: history.map { .init(date: $0.date, usedPercent: $0.used) },
                resetAt: week.end, measuredAt: measuredAt, lookback: range.seconds)
        }
        guard weekIndex == 0, let first = pacePoints.first, let last = pacePoints.last,
              last.date.timeIntervalSince(first.date) >= 60 else { return nil }
        return max(0, last.used - first.used) / last.date.timeIntervalSince(first.date) * 3_600
    }
    private var runout: Date? {
        guard weekIndex == 0 else { return nil }
        if let hourlyRate, hourlyRate > 0, let last = pacePoints.last, last.used < 100 {
            return last.date.addingTimeInterval((100 - last.used) / hourlyRate * 3_600)
        }
        return range == .hour ? (snapshot?.estimatedRunoutAt ?? fallbackRunout) : nil
    }
    private var days: [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: week.start)
        return (0..<8).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.filter { $0 < week.end }
    }
    private var yDomain: ClosedRange<Double> {
        if (range == .week || weekIndex > 0) && selectedDay == nil { return 0...100 }
        let values = visible.map(\.used) + [ideal(bounds.lowerBound), ideal(bounds.upperBound)]
        let low = max(0, floor(((values.min() ?? 0) - 5) / 5) * 5)
        return low...min(100, max(low + 10, ceil(((values.max() ?? 0) + 5) / 5) * 5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            weekNavigation
            calendar
            chartCaption
            if history.isEmpty {
                Text("Your recorded usage will appear here after the next account refresh.")
                    .font(.subheadline).foregroundStyle(PhoneStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: 155)
            } else {
                usageChart
                if provider == .claude, history.count == 1 {
                    Text("First reading recorded. Your graph and pace will build as Claude refreshes.")
                        .font(.caption).foregroundStyle(PhoneStyle.secondary)
                }
            }
            if weekIndex == 0 {
                rangePicker
                PhoneRule()
                timing
                if let hourlyRate {
                    HStack {
                        Text("\(hourlyRate, specifier: "%.2f")% / hour")
                        Spacer()
                        Text(range == .week ? "Recorded weekly pace" : "Last \(range.rawValue) pace")
                    }.font(.caption).foregroundStyle(PhoneStyle.secondary)
                }
            }
            if week.tokens != nil || week.apiValue != nil || tokenBurn != nil { totals }
        }
        .tint(blue)
        .task {
#if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--quota-preview-archive"), weeks.count > 1 { weekIndex = 1 }
            if arguments.contains("--quota-preview-hour") { range = .hour }
            if arguments.contains("--quota-preview-five-minutes") { range = .fiveMinutes }
            if arguments.contains("--quota-preview-totals") { showTotals = true }
#endif
        }
    }

    private var weekNavigation: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                Text(week.start.formatted(.dateTime.month(.abbreviated).day()) + " – " + week.end.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(.headline, weight: .medium))
                Text(weekIndex == 0 ? "This quota week" : "Previous quota week")
                    .font(.caption).foregroundStyle(PhoneStyle.secondary)
            }
            Spacer()
            Button { changeWeek(1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .disabled(weekIndex >= weeks.count - 1).accessibilityLabel("Previous week")
            Button { changeWeek(-1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(weekIndex == 0).accessibilityLabel("Next week")
        }
        .font(.system(size: 13, weight: .semibold))
        .buttonStyle(PhonePressStyle())
    }

    private var calendar: some View {
        HStack(spacing: 3) {
            ForEach(days, id: \.self) { day in
                let selected = selectedDay == day
                let today = Calendar.current.isDateInToday(day)
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedDay = selected ? nil : day; selectedDate = nil }
                } label: {
                    VStack(spacing: 7) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 10, weight: .medium))
                            .foregroundStyle(selected ? PhoneStyle.paper.opacity(0.65) : PhoneStyle.secondary)
                        Text(day.formatted(.dateTime.day())).font(.system(size: 18, weight: today ? .semibold : .regular, design: .rounded))
                        Circle().fill(hasReading(on: day) ? (selected ? PhoneStyle.paper : blue) : .clear).frame(width: 3, height: 3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 65)
                    .background(selected ? PhoneStyle.ink : (today ? PhoneStyle.field : .clear), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(selected ? PhoneStyle.paper : PhoneStyle.ink)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityHint("Show this day’s usage")
            }
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(QuotaHistoryRange.allCases) { period in
                Button {
                    range = period; selectedDay = nil; selectedDate = nil
                } label: {
                    Text(period.rawValue).font(.subheadline.weight(range == period && selectedDay == nil ? .semibold : .medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(range == period && selectedDay == nil ? blue : PhoneStyle.secondary)
                        .overlay(alignment: .bottom) {
                            if range == period && selectedDay == nil { Capsule().fill(blue).frame(width: 22, height: 3) }
                        }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(period.rawValue) pace period")
                    .accessibilityAddTraits(range == period && selectedDay == nil ? [.isSelected] : [])
            }
        }
    }

    private var chartCaption: some View {
        HStack(spacing: 6) {
            if let nearest {
                Text(nearest.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                Spacer()
                Text("\(nearest.used, specifier: "%.1f")% used").fontWeight(.semibold)
            } else {
                Capsule().fill(blue).frame(width: 13, height: 2)
                Text("Used")
                Spacer()
                Text("– –").tracking(1)
                Text("Even pace")
            }
        }.font(.system(size: 10)).foregroundStyle(nearest == nil ? PhoneStyle.secondary : blue)
    }

    private var usageChart: some View {
        Chart {
            ForEach(visible) { point in
                AreaMark(x: .value("Date", point.date), yStart: .value("Base", yDomain.lowerBound), yEnd: .value("Used", point.used))
                    .foregroundStyle(blue.opacity(0.07)).interpolationMethod(.stepEnd)
                LineMark(x: .value("Date", point.date), y: .value("Used", point.used), series: .value("Series", "Used"))
                    .foregroundStyle(blue).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round)).interpolationMethod(.stepEnd)
            }
            if visible.count == 1, let point = visible.first {
                PointMark(x: .value("Date", point.date), y: .value("Used", point.used))
                    .foregroundStyle(blue).symbolSize(24)
            }
            ForEach([bounds.lowerBound, bounds.upperBound], id: \.self) { date in
                LineMark(x: .value("Date", date), y: .value("Even pace", ideal(date)), series: .value("Series", "Even pace"))
                    .foregroundStyle(PhoneStyle.secondary.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            if let nearest {
                RuleMark(x: .value("Selected", nearest.date)).foregroundStyle(PhoneStyle.secondary.opacity(0.3))
                PointMark(x: .value("Date", nearest.date), y: .value("Used", nearest.used)).foregroundStyle(blue)
            }
        }
        .chartPlotStyle { $0.clipped() }
        .chartXScale(domain: bounds).chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(PhoneStyle.line.opacity(0.7))
                AxisValueLabel { if let percent = value.as(Double.self) { Text("\(Int(percent))%").font(.system(size: 9)).foregroundStyle(PhoneStyle.secondary) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text((range == .week || weekIndex > 0) && selectedDay == nil ? date.formatted(.dateTime.weekday(.abbreviated)) : date.formatted(.dateTime.hour().minute()))
                            .font(.system(size: 9)).foregroundStyle(PhoneStyle.secondary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        if let plot = proxy.plotFrame {
                            selectedDate = proxy.value(atX: value.location.x - geometry[plot].minX, as: Date.self)
                        }
                    })
            }
        }
        .frame(height: 200)
        .accessibilityLabel("Recorded \(provider.name) quota usage and even pace")
    }

    private var timing: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Week renews").font(.caption).foregroundStyle(PhoneStyle.secondary)
                Text(QuotaHistoryView.duration(week.end)).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(week.end.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .font(.system(size: 10)).foregroundStyle(PhoneStyle.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(PhoneStyle.line).frame(width: 0.5, height: 54)
            VStack(alignment: .leading, spacing: 5) {
                Text("Estimated run-out").font(.caption).foregroundStyle(PhoneStyle.secondary)
                Text(runout.map(QuotaHistoryView.duration) ?? (hourlyRate == 0 ? "No burn" : "Learning"))
                    .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.75).lineLimit(1)
                Text(runout != nil ? "At this pace" : "Needs more recorded usage")
                    .font(.system(size: 10)).foregroundStyle(PhoneStyle.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.top, 3)
    }

    private var tokenBurn: Int64? {
        guard weekIndex == 0, provider == .codex, let snapshot else { return nil }
        if let pace = snapshot.tokenPace {
            switch range {
            case .fiveMinutes: return pace.fiveMinutes
            case .hour: return pace.oneHour
            case .twelveHours: return pace.twelveHours
            case .day: return pace.twentyFourHours
            case .week: return pace.sinceReset
            }
        }
        return snapshot.tokenBurnSample(over: range.seconds)?.tokens
    }

    private var totals: some View {
        DisclosureGroup(isExpanded: $showTotals) {
            VStack(spacing: 13) {
                if let tokens = tokenBurn {
                    LabeledContent(range == .week ? "Tokens since reset" : "Tokens in \(range.rawValue)", value: tokens.formatted())
                }
                if let tokens = week.tokens { LabeledContent("Total recorded tokens", value: tokens.formatted()) }
                if let value = week.apiValue { LabeledContent("API equivalent", value: value.formatted(.currency(code: "USD"))) }
                if weekIndex == 0, let intelligence = snapshot?.usageIntelligence {
                    if let model = intelligence.topModel { LabeledContent("Most used model", value: model) }
                    if let cache = intelligence.cacheHitRate { LabeledContent("Cache hit rate", value: cache.formatted(.percent.precision(.fractionLength(0)))) }
                    LabeledContent("Fast mode share", value: intelligence.fastShare.formatted(.percent.precision(.fractionLength(0))))
                }
            }.font(.system(size: 12)).padding(.top, 13)
        } label: {
            HStack {
                Text("Usage details")
                Spacer()
                if let tokens = tokenBurn { Text("\(tokens.formatted(.number.notation(.compactName))) tokens").foregroundStyle(PhoneStyle.secondary) }
            }.font(.system(size: 12, weight: .medium))
        }
        .tint(PhoneStyle.secondary).foregroundStyle(PhoneStyle.ink)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(PhoneStyle.surface, in: RoundedRectangle(cornerRadius: 14))
        .id("usage-details")
    }

    private var axisDates: [Date] { [0.1, 0.36, 0.62, 0.85].map { bounds.lowerBound.addingTimeInterval(bounds.upperBound.timeIntervalSince(bounds.lowerBound) * $0) } }
    private func changeWeek(_ delta: Int) { weekIndex = max(0, min(weeks.count - 1, weekIndex + delta)); selectedDay = nil; selectedDate = nil }
    private func ideal(_ date: Date) -> Double { min(100, max(0, date.timeIntervalSince(week.start) / max(1, week.end.timeIntervalSince(week.start)) * 100)) }
    private func hasReading(on day: Date) -> Bool { history.contains { Calendar.current.isDate($0.date, inSameDayAs: day) } }
}

extension QuotaSnapshot {
    var displayPosts: [QuotaPost] {
        (tiboPosts ?? []).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.map {
            .init(id: $0.id, date: $0.date, text: $0.text, reply: $0.inReplyTo, url: $0.url, isReset: $0.isResetOriented)
        }
    }
}

struct PhonePostsView: View {
    let posts: [QuotaPost]
    var initiallyExpanded = false
    var standalone = false
    @State private var expanded = false
    @State private var resetOnly = false
    @State private var openPosts: Set<String> = []
    private var filtered: [QuotaPost] { resetOnly ? posts.filter(\.isReset) : posts }

    var body: some View {
        Group {
            if standalone {
                feed
            } else {
                DisclosureGroup(isExpanded: $expanded) {
                    feed.padding(.top, 20)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Tibo’s updates").font(.headline)
                            Text("\(posts.count)").font(.caption).foregroundStyle(PhoneStyle.secondary)
                        }
                        if !expanded {
                            Text(posts.first?.text ?? "New posts and replies will appear here.")
                                .font(.subheadline).foregroundStyle(PhoneStyle.secondary).lineLimit(2)
                        }
                    }
                }
            }
        }
        .foregroundStyle(PhoneStyle.ink).tint(PhoneStyle.secondary)
        .task {
            if initiallyExpanded { expanded = true }
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--quota-preview-posts") {
                expanded = true
                openPosts = Set(posts.map(\.id))
            }
#endif
        }
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: 24) {
            Picker("Posts", selection: $resetOnly) {
                Text("All posts · \(posts.count)").tag(false)
                Text("Reset updates").tag(true)
            }.pickerStyle(.segmented)
            if filtered.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "text.bubble").font(.title2)
                    Text(resetOnly ? "No recent reset updates" : "You’re all caught up").font(.headline)
                    Text("New posts and replies appear here after the next refresh.").font(.subheadline).foregroundStyle(PhoneStyle.secondary)
                }.padding(.vertical, 28)
            }
            ForEach(filtered) { post in
                DisclosureGroup(isExpanded: Binding(
                    get: { openPosts.contains(post.id) },
                    set: { if $0 { openPosts.insert(post.id) } else { openPosts.remove(post.id) } }
                )) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(post.text).font(.body).fixedSize(horizontal: false, vertical: true).lineSpacing(4)
                        if let reply = post.reply, !reply.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Replying to", systemImage: "arrow.turn.up.left").font(.caption.weight(.medium))
                                Text(reply).font(.subheadline).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                            }
                            .foregroundStyle(PhoneStyle.secondary)
                            .padding(.leading, 15)
                            .overlay(alignment: .leading) { Rectangle().fill(PhoneStyle.line).frame(width: 2) }
                        }
                        if let url = post.url {
                            Link(destination: url) {
                                HStack {
                                    Text("Read on X")
                                    Image(systemName: "arrow.up.right")
                                }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                            }.foregroundStyle(PhoneStyle.tint(.codex))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 18)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 7) {
                            Text("Tibo").font(.subheadline.weight(.semibold))
                            if let date = post.date {
                                Text(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                    .font(.caption).foregroundStyle(PhoneStyle.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        if post.isReset {
                            Label("Reset update", systemImage: "arrow.counterclockwise")
                                .font(.caption.weight(.medium)).foregroundStyle(PhoneStyle.reset)
                        }
                        if !openPosts.contains(post.id) {
                            Text(post.text).font(.body).lineLimit(3).lineSpacing(3)
                        }
                    }
                }
                PhoneRule()
            }
        }
    }
}

struct PhonePetDetails: View {
    let provider: DisplayProvider
    @ObservedObject var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @State private var showReset = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if provider == .codex {
                        PhoneActivityView(snapshot: store.snapshot)
                        PhoneRule()
                        Button { showReset = true } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Reset forecast").font(.system(size: 16, weight: .semibold, design: .rounded))
                                    Text("Calculator & source estimates").font(.system(size: 12)).foregroundStyle(PhoneStyle.secondary)
                                }
                                Spacer()
                                Text(MobileProviderReading.percent(store.snapshot.effectiveResetAnnounced ? 100 : store.snapshot.resetChancePercent))
                                    .font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit()
                                Image(systemName: "chevron.right").font(.caption)
                            }.foregroundStyle(PhoneStyle.reset).padding(.vertical, 5)
                        }.buttonStyle(.plain)
                        PhoneRule()
                        PhonePostsView(posts: store.snapshot.displayPosts)
                    } else {
                        PhoneClaudeWindows(snapshot: store.snapshot.claude)
                    }
                }.padding(24)
            }
            .background(PhoneStyle.paper).foregroundStyle(PhoneStyle.ink)
            .navigationTitle(provider.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .refreshable { await store.refresh() }
            .sheet(isPresented: $showReset) { ResetDetailView(store: store).presentationDragIndicator(.visible) }
        }.tint(PhoneStyle.reset)
    }
}

struct PhoneClaudeWindows: View {
    let snapshot: ClaudeQuotaSnapshot?
    var showsUsage = true
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(showsUsage ? "Claude" : "Renewal schedule").font(.headline)
                        if showsUsage { Text("Usage & pace").font(.system(size: 12)).foregroundStyle(PhoneStyle.secondary) }
                    }
                    Spacer()
                    if showsUsage { QuotaPetImage(provider: .claude).frame(width: 72, height: 70) }
                }
                if let snapshot {
                    if showsUsage {
                        window("Weekly allowance", usage: snapshot.displayedUsage(at: context.date), date: snapshot.resetAt, now: context.date)
                        if let end = snapshot.resetAt {
                            PhoneHistoryChart(current: .init(start: end.addingTimeInterval(-ClaudeUsageHistory.week), end: end,
                                points: (snapshot.usageHistory ?? []).map { .init(date: $0.date, used: $0.usedPercent) },
                                used: snapshot.usagePercent),
                                archives: (snapshot.weeklyArchives ?? []).map {
                                    .init(start: $0.windowStart, end: $0.resetAt,
                                          points: $0.points.map { .init(date: $0.date, used: $0.usedPercent) }, used: $0.finalUsedPercent)
                                }, provider: .claude, measuredAt: snapshot.isFresh(at: context.date) ? snapshot.capturedAt : nil,
                                fallbackRunout: snapshot.isFresh(at: context.date) ? snapshot.estimatedRunoutAt : nil)
                                .id(snapshot.accountID)
                        }
                        PhoneRule()
                        window("Current session", usage: snapshot.displayedFiveHourUsage(at: context.date), date: snapshot.fiveHourResetAt, now: context.date)
                    } else {
                        renewal("Weekly allowance", date: snapshot.resetAt, now: context.date)
                        PhoneRule()
                        renewal("Current session", date: snapshot.fiveHourResetAt, now: context.date)
                    }
                    PhoneRule()
                    if let plan = snapshot.planName { LabeledContent("Plan", value: plan).font(.system(size: 13)) }
                    Text(snapshot.status(at: context.date)).font(.caption).foregroundStyle(PhoneStyle.secondary)
                } else {
                    Text("Connect Claude in Settings to fetch its weekly and session usage on this iPhone.")
                        .font(.subheadline).foregroundStyle(PhoneStyle.secondary)
                }
            }.foregroundStyle(PhoneStyle.ink)
        }
    }

    private func renewal(_ title: String, date: Date?, now: Date) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(date.map { $0.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()) } ?? "Waiting for fresh usage")
                    .font(.caption).foregroundStyle(PhoneStyle.secondary)
            }
            Spacer(minLength: 10)
            Text(MobileProviderReading.remaining(until: date, at: now, days: true) ?? "Pending")
                .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }

    private func window(_ title: String, usage: Double?, date: Date?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(MobileProviderReading.percent(usage)).font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
            }
            QuotaRail(value: usage, tint: PhoneStyle.tint(.claude))
            HStack {
                if let remaining = MobileProviderReading.remaining(until: date, at: now, days: true) {
                    Text("\(remaining) left").fontWeight(.medium)
                } else { Text("Awaiting fresh allowance") }
                Spacer()
                if let date { Text(date.formatted(.dateTime.weekday(.abbreviated).hour().minute())) }
            }.font(.system(size: 12)).foregroundStyle(PhoneStyle.secondary)
        }
    }
}
