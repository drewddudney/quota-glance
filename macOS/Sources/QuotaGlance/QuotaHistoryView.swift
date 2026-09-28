import Charts
import SwiftUI

struct QuotaHistoryPoint: Identifiable {
    let date: Date
    let used: Double
    var id: Date { date }
}

struct QuotaHistoryWeek: Identifiable {
    let start: Date
    let end: Date
    let points: [QuotaHistoryPoint]
    let used: Double?
    var tokens: Int64? = nil
    var apiValue: Double? = nil
    var id: Date { start }
}

enum QuotaHistoryRange: String, CaseIterable, Identifiable {
    case fiveMinutes = "5m", hour = "1h", twelveHours = "12h", day = "24h", week = "Week"
    var id: String { rawValue }
    var seconds: Double? {
        switch self { case .fiveMinutes: 300; case .hour: 3_600; case .twelveHours: 43_200; case .day: 86_400; case .week: nil }
    }
}

/// The chart and calendar show recorded quota percentages. The dashed line is
/// an even allowance through the window; the pace estimate is labelled separately.
struct QuotaHistoryView: View {
    let current: QuotaHistoryWeek
    var archives: [QuotaHistoryWeek] = []
    var fallbackRunout: Date?
    var tint = Color(red: 0.56, green: 0.76, blue: 0.98)
    var recordedMeasurementAt: Date? = nil
    @State private var weekIndex = 0
    @State private var range = QuotaHistoryRange.week
    @State private var selectedDay: Date?
    @State private var selectedDate: Date?
    private var blue: Color { tint }
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
        // A predecessor preserves the real step into a selected time interval.
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
        if let recordedMeasurementAt {
            guard weekIndex == 0 else { return nil }
            return ClaudeUsageHistory.hourlyRate(
                points: history.map { .init(date: $0.date, usedPercent: $0.used) },
                resetAt: week.end, measuredAt: recordedMeasurementAt, lookback: range.seconds)
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
        return range == .hour ? fallbackRunout : nil
    }
    private var days: [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: week.start)
        return (0..<8).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.filter { $0 < week.end }
    }
    private var yDomain: ClosedRange<Double> {
        if range == .week && selectedDay == nil { return 0...100 }
        let values = visible.map(\.used) + [ideal(bounds.lowerBound), ideal(bounds.upperBound)]
        let low = max(0, floor(((values.min() ?? 0) - 5) / 5) * 5)
        return low...min(100, max(low + 10, ceil(((values.max() ?? 0) + 5) / 5) * 5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { changeWeek(1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
                    .disabled(weekIndex >= weeks.count - 1).accessibilityLabel("Previous week")
                Spacer(minLength: 4)
                VStack(spacing: 3) {
                    Text(weekIndex == 0 ? "This week" : "Previous week").font(.system(size: 13, weight: .semibold))
                    Text(week.start.formatted(.dateTime.month(.abbreviated).day()) + " – " + week.end.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button { changeWeek(-1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
                    .disabled(weekIndex == 0).accessibilityLabel("Next week")
            }.buttonStyle(.plain)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(days, id: \.self) { day in
                        Button { selectedDay = selectedDay == day ? nil : day; selectedDate = nil } label: {
                            VStack(spacing: 6) {
                                Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 9)).foregroundStyle(.secondary)
                                Text(day.formatted(.dateTime.day())).font(.system(size: 15, weight: .medium, design: .rounded))
                                Capsule().fill(blue.opacity(hasReading(on: day) ? 0.8 : 0.1)).frame(width: 16, height: 3)
                            }
                            .frame(width: 35, height: 60)
                            .background(RoundedRectangle(cornerRadius: 10).fill(selectedDay == day ? blue.opacity(0.17) : Color.white.opacity(0.035)))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                    }
                }
            }
            if weekIndex == 0 {
                Picker("Pace period", selection: $range) {
                    ForEach(QuotaHistoryRange.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                .onChange(of: range) { _ in selectedDay = nil; selectedDate = nil }
            }
            if let nearest {
                HStack {
                    Text(nearest.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    Spacer()
                    Text("\(nearest.used, specifier: "%.1f")%")
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(blue)
            }
            if history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line").font(.title2)
                    Text("Usage history will appear after your Mac syncs.").font(.subheadline)
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart {
                    ForEach(visible) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Used", point.used), series: .value("Series", "Used"))
                            .foregroundStyle(blue).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.stepEnd)
                    }
                    if visible.count == 1, let point = visible.first {
                        PointMark(x: .value("Date", point.date), y: .value("Used", point.used))
                            .foregroundStyle(blue)
                    }
                    ForEach([bounds.lowerBound, bounds.upperBound], id: \.self) { date in
                        LineMark(x: .value("Date", date), y: .value("Even pace", ideal(date)), series: .value("Series", "Even pace"))
                            .foregroundStyle(Color.white.opacity(0.3)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    if let nearest {
                        RuleMark(x: .value("Selected", nearest.date)).foregroundStyle(Color.white.opacity(0.2))
                        PointMark(x: .value("Date", nearest.date), y: .value("Used", nearest.used)).foregroundStyle(blue)
                    }
                }
                .chartPlotStyle { $0.clipped() }
                .chartXScale(domain: bounds).chartYScale(domain: yDomain)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.07))
                        AxisValueLabel { if let percent = value.as(Double.self) { Text("\(Int(percent))%") } }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: axisDates) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(range == .week && selectedDay == nil ? date.formatted(.dateTime.weekday(.abbreviated)) : date.formatted(.dateTime.hour().minute()))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                selectedDate = proxy.value(atX: value.location.x - geometry[proxy.plotAreaFrame].minX, as: Date.self)
                            })
                    }
                }
                .frame(height: 180)
            }
            HStack(spacing: 12) {
                Label("Used", systemImage: "line.diagonal").foregroundStyle(blue)
                Label("Even pace", systemImage: "line.diagonal").foregroundStyle(.secondary)
                Spacer()
            }.font(.system(size: 10))
            if weekIndex == 0 {
                HStack(alignment: .top, spacing: 24) {
                    timing("Week renews", date: week.end)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Estimated run-out").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(runout.map(Self.duration) ?? (hourlyRate == 0 ? "No recent burn" : "Learning pace"))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text(range == .week ? "From recorded week usage" : "At the last \(range.rawValue) pace")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if let hourlyRate {
                    Text("\(hourlyRate, specifier: "%.2f")% per hour · estimate changes with usage")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            if week.tokens != nil || week.apiValue != nil {
                DisclosureGroup("Usage totals") {
                    HStack {
                        if let tokens = week.tokens { Text("\(tokens.formatted()) tokens") }
                        Spacer()
                        if let value = week.apiValue { Text(value, format: .currency(code: "USD")); Text("API value").foregroundStyle(.secondary) }
                    }.font(.system(size: 11)).padding(.top, 8)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .tint(blue)
    }

    private var axisDates: [Date] { [0.08, 0.36, 0.64, 0.9].map { bounds.lowerBound.addingTimeInterval(bounds.upperBound.timeIntervalSince(bounds.lowerBound) * $0) } }
    private func changeWeek(_ delta: Int) { weekIndex = max(0, min(weeks.count - 1, weekIndex + delta)); selectedDay = nil; selectedDate = nil }
    private func ideal(_ date: Date) -> Double { min(100, max(0, date.timeIntervalSince(week.start) / max(1, week.end.timeIntervalSince(week.start)) * 100)) }
    private func hasReading(on day: Date) -> Bool { history.contains { Calendar.current.isDate($0.date, inSameDayAs: day) } }
    private func timing(_ title: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(Self.duration(date)).font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(date.formatted(.dateTime.month(.abbreviated).day().hour().minute())).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    static func duration(_ date: Date) -> String {
        guard date > .now else { return "Awaiting update" }
        let minutes = Int(ceil(date.timeIntervalSinceNow / 60))
        if minutes >= 1_440 { return "\(minutes / 1_440)d \((minutes % 1_440) / 60)h" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
