import Foundation
import SwiftUI

struct WeeklyUsageArchivePoint: Codable, Equatable, Sendable {
    let date: Date
    let usedPercent: Double
    let apiEquivalentUSD: Double?
    let localTokensTotal: Int64?
}

struct WeeklyUsageArchive: Codable, Identifiable, Equatable, Sendable {
    let windowStart: Date
    let resetAt: Date
    let capturedAt: Date
    let finalUsedPercent: Double
    let totalTokens: Int64?
    let apiEquivalentUSD: Double?
    let quotaWeightedUSD: Double?
    let cacheHitRate: Double?
    let fastShare: Double?
    let pricingCoverage: Double?
    let modelSummaries: [UsageModelSummary]
    let peakFiveMinuteTokens: Int64?
    let points: [WeeklyUsageArchivePoint]

    var id: TimeInterval { windowStart.timeIntervalSince1970 }
}

enum WeeklyUsageArchiveStore {
    private static let maximumWeeks = 26
    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quota Glance", isDirectory: true)
            .appendingPathComponent("weekly-usage-archives-v1.json")
    }

    static func load() -> [WeeklyUsageArchive] {
        guard let data = try? Data(contentsOf: fileURL),
              let values = try? JSONDecoder().decode([WeeklyUsageArchive].self, from: data)
        else { return [] }
        return values.sorted { $0.windowStart > $1.windowStart }
    }

    @discardableResult
    static func capture(
        windowStart: Date,
        resetAt: Date,
        finalUsedPercent: Double,
        intelligence: UsageIntelligenceSnapshot?,
        checkpoints: [UsageCheckpoint],
        capturedAt: Date = Date()
    ) -> [WeeklyUsageArchive] {
        guard resetAt > windowStart else { return load() }
        let windowPoints = checkpoints
            .filter {
                abs($0.windowStart.timeIntervalSince(windowStart)) < UsageHistoryStore.windowTolerance
                    && $0.recordedAt >= windowStart
                    && $0.recordedAt <= resetAt.addingTimeInterval(30 * 60)
            }
            .sorted { $0.recordedAt < $1.recordedAt }
        let compactPoints = hourlyPoints(windowPoints, windowStart: windowStart)
        let input = (intelligence?.tokens.uncachedInput ?? 0)
            + (intelligence?.tokens.cachedInput ?? 0)
            + (intelligence?.tokens.cacheWriteInput ?? 0)
        let cacheHit = input > 0
            ? Double(intelligence?.tokens.cachedInput ?? 0) / Double(input)
            : nil
        let fallbackAPI = windowPoints.compactMap(\.apiEquivalentUSD).last
        let fallbackWeighted = windowPoints.compactMap(\.quotaWeightedUSD).last
        let archive = WeeklyUsageArchive(
            windowStart: windowStart,
            resetAt: resetAt,
            capturedAt: capturedAt,
            finalUsedPercent: max(0, min(100, finalUsedPercent)),
            totalTokens: intelligence?.tokens.total,
            apiEquivalentUSD: intelligence?.apiEquivalentUSD ?? fallbackAPI,
            quotaWeightedUSD: intelligence?.quotaWeightedUSD ?? fallbackWeighted,
            cacheHitRate: cacheHit,
            fastShare: intelligence?.fastShare,
            pricingCoverage: intelligence?.pricingCoverage,
            modelSummaries: Array(intelligence?.modelSummaries.prefix(4) ?? []),
            peakFiveMinuteTokens: windowPoints.compactMap(\.rollingFiveMinuteTokens).max(),
            points: compactPoints
        )
        var archives = load().filter {
            abs($0.windowStart.timeIntervalSince(windowStart)) >= UsageHistoryStore.windowTolerance
        }
        archives.append(archive)
        archives.sort { $0.windowStart > $1.windowStart }
        archives = Array(archives.prefix(maximumWeeks))
        save(archives)
        return archives
    }

    static func hourlyPoints(
        _ checkpoints: [UsageCheckpoint],
        windowStart: Date
    ) -> [WeeklyUsageArchivePoint] {
        var buckets: [Int: UsageCheckpoint] = [:]
        for checkpoint in checkpoints {
            let hour = max(0, Int(checkpoint.recordedAt.timeIntervalSince(windowStart) / 3_600))
            buckets[hour] = checkpoint
        }
        return buckets.keys.sorted().compactMap { key in
            guard let value = buckets[key] else { return nil }
            return WeeklyUsageArchivePoint(
                date: value.recordedAt,
                usedPercent: value.usedPercent,
                apiEquivalentUSD: value.apiEquivalentUSD,
                localTokensTotal: value.localTokensTotal
            )
        }
    }

    private static func save(_ archives: [WeeklyUsageArchive]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(archives)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Quota Glance could not save weekly usage archives: %@", error.localizedDescription)
        }
    }
}

struct ArchivedUsageWeekView: View {
    let archive: WeeklyUsageArchive

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("COMPLETED WEEK")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Color.white.opacity(0.36))
                    Text(dateRange)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.94))
                }
                Spacer()
                Text("\(Int(archive.finalUsedPercent.rounded()))% USED")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x7EE6AE))
            }

            HStack(spacing: 0) {
                archiveMetric("API VALUE", archive.apiEquivalentUSD.map { String(format: "$%.2f", $0) } ?? "—")
                archiveMetric("TOKENS", archive.totalTokens.map(compactTokens) ?? "—")
                archiveMetric("CACHE", archive.cacheHitRate.map(percent) ?? "—")
                archiveMetric("FAST", archive.fastShare.map(percent) ?? "—")
            }

            ArchivedUsageChart(archive: archive)
                .frame(height: 176)

            if !archive.modelSummaries.isEmpty {
                HStack(spacing: 12) {
                    ForEach(archive.modelSummaries.prefix(3)) { model in
                        HStack(spacing: 5) {
                            Circle().fill(Color(hex: 0x58B9F3).opacity(0.7)).frame(width: 4, height: 4)
                            Text(model.model.replacingOccurrences(of: "gpt-", with: ""))
                            Text(String(format: "$%.0f", model.apiEquivalentUSD))
                                .foregroundStyle(Color.white.opacity(0.44))
                        }
                    }
                }
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.7))
            }
        }
    }

    private var dateRange: String {
        archive.windowStart.formatted(.dateTime.month(.abbreviated).day())
            + " – "
            + archive.resetAt.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func archiveMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundStyle(Color.white.opacity(0.3))
            Text(value).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(Color.white.opacity(0.84))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactTokens(_ tokens: Int64) -> String {
        let value = Double(max(0, tokens))
        if value >= 1_000_000_000 { return String(format: "%.2fB", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        return "\(tokens)"
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}

private struct ArchivedUsageChart: View {
    let archive: WeeklyUsageArchive

    var body: some View {
        Canvas { context, size in
            let plot = CGRect(x: 34, y: 8, width: max(1, size.width - 42), height: max(1, size.height - 25))
            for step in 0...4 {
                let y = plot.maxY - plot.height * CGFloat(step) / 4
                var line = Path(); line.move(to: CGPoint(x: plot.minX, y: y)); line.addLine(to: CGPoint(x: plot.maxX, y: y))
                context.stroke(line, with: .color(Color.white.opacity(step == 0 ? 0.18 : 0.07)), lineWidth: 0.8)
                context.draw(
                    Text("\(step * 25)%").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(Color.white.opacity(0.3)),
                    at: CGPoint(x: plot.minX - 6, y: y), anchor: .trailing
                )
            }
            var ideal = Path(); ideal.move(to: CGPoint(x: plot.minX, y: plot.maxY)); ideal.addLine(to: CGPoint(x: plot.maxX, y: plot.minY))
            context.stroke(ideal, with: .color(Color.white.opacity(0.42)), style: StrokeStyle(lineWidth: 1.1, dash: [3, 3]))
            let values = [WeeklyUsageArchivePoint(date: archive.windowStart, usedPercent: 0, apiEquivalentUSD: 0, localTokensTotal: nil)] + archive.points
            let points = values.map { value -> CGPoint in
                let x = max(0, min(1, value.date.timeIntervalSince(archive.windowStart) / max(1, archive.resetAt.timeIntervalSince(archive.windowStart))))
                let y = max(0, min(1, value.usedPercent / 100))
                return CGPoint(x: plot.minX + plot.width * x, y: plot.maxY - plot.height * y)
            }
            if points.count > 1 {
                var path = Path(); path.move(to: points[0]); for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(Color(hex: 0x7EE6AE)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
            context.draw(Text("START").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(Color.white.opacity(0.3)), at: CGPoint(x: plot.minX, y: plot.maxY + 12), anchor: .leading)
            context.draw(Text("RESET").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(Color.white.opacity(0.3)), at: CGPoint(x: plot.maxX, y: plot.maxY + 12), anchor: .trailing)
        }
        .accessibilityLabel("Archived weekly usage chart ending at \(Int(archive.finalUsedPercent.rounded())) percent")
    }
}
