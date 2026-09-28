import AppKit
import CryptoKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum UsageSpeedMode: String, Codable, CaseIterable, Sendable {
    case standard
    case fast
    case unknown

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .fast: return "Fast"
        case .unknown: return "Unknown"
        }
    }
}

enum UsageSpeedProvenance: String, Codable, Sendable {
    case observed
    case declaredConfiguration
    case unknown
}

struct UsageTokenBreakdown: Codable, Equatable, Sendable {
    var uncachedInput: Int64 = 0
    var cachedInput: Int64 = 0
    var cacheWriteInput: Int64 = 0
    var outputText: Int64 = 0
    var reasoningOutput: Int64 = 0

    var total: Int64 {
        uncachedInput + cachedInput + cacheWriteInput + outputText + reasoningOutput
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            uncachedInput: lhs.uncachedInput + rhs.uncachedInput,
            cachedInput: lhs.cachedInput + rhs.cachedInput,
            cacheWriteInput: lhs.cacheWriteInput + rhs.cacheWriteInput,
            outputText: lhs.outputText + rhs.outputText,
            reasoningOutput: lhs.reasoningOutput + rhs.reasoningOutput
        )
    }
}

struct UsageModelSummary: Codable, Identifiable, Equatable, Sendable {
    let model: String
    let tokens: Int64
    let apiEquivalentUSD: Double
    let gpt6CodexCredits: Double?

    var id: String { model }
}

struct UsageCostPoint: Codable, Identifiable, Equatable, Sendable {
    let date: Date
    let apiEquivalentUSD: Double
    let quotaWeightedUSD: Double?

    var id: Date { date }
}

struct SecondaryQuotaSnapshot: Codable, Equatable, Sendable {
    let usedPercent: Double
    let resetAt: Date
    let windowDurationMinutes: Double
}

struct UsageIntelligenceSnapshot: Codable, Equatable, Sendable {
    let capturedAt: Date
    let windowStart: Date
    let tokens: UsageTokenBreakdown
    let apiEquivalentUSD: Double
    let quotaWeightedUSD: Double
    let gpt6CodexCredits: Double?
    let pricingCoverage: Double
    let speedCoverage: Double
    let fastShare: Double
    let standardShare: Double
    let unknownSpeedShare: Double
    let modelSummaries: [UsageModelSummary]
    let costTimeline: [UsageCostPoint]
    let eventCount: Int
    let sourceFileCount: Int
    let backfillComplete: Bool
    let pendingBackfillSourceCount: Int
    let ledgerBytes: Int64
    let oldestEventAt: Date?
    let newestEventAt: Date?
    let pricingRegistryVersion: String
    let pricingSourceURL: String
    let pricingReviewedAt: Date
    let recentTokenPace: LocalTokenPaceSnapshot?

    static func empty(windowStart: Date) -> Self {
        Self(
            capturedAt: Date(),
            windowStart: windowStart,
            tokens: UsageTokenBreakdown(),
            apiEquivalentUSD: 0,
            quotaWeightedUSD: 0,
            gpt6CodexCredits: nil,
            pricingCoverage: 0,
            speedCoverage: 0,
            fastShare: 0,
            standardShare: 0,
            unknownSpeedShare: 1,
            modelSummaries: [],
            costTimeline: [],
            eventCount: 0,
            sourceFileCount: 0,
            backfillComplete: false,
            pendingBackfillSourceCount: 0,
            ledgerBytes: 0,
            oldestEventAt: nil,
            newestEventAt: nil,
            pricingRegistryVersion: UsagePriceCatalog.version,
            pricingSourceURL: UsagePriceCatalog.sourceURL,
            pricingReviewedAt: UsagePriceCatalog.reviewedAt,
            recentTokenPace: nil
        )
    }
}

struct UsagePriceCard: Equatable, Sendable {
    let model: String
    let contextBand: ContextBand
    let validFrom: Date?
    let validThrough: Date?
    let inputPerMillion: Double
    let cachedInputPerMillion: Double?
    let cacheWritePerMillion: Double?
    let outputPerMillion: Double

    enum ContextBand: String, Sendable {
        case any
        case short
        case long
    }
}

struct GPT6CodexCreditRate: Sendable {
    let inputPerMillion: Double
    let cachedInputPerMillion: Double
    let outputPerMillion: Double
}

enum GPT6CodexCreditCatalog {
    // Standard-speed Codex credits per million tokens. Codex does not charge a
    // separate cache-write rate, so cache-write input uses the normal input rate.
    static let rates: [String: GPT6CodexCreditRate] = [
        "gpt-6-astra": .init(inputPerMillion: 250, cachedInputPerMillion: 25, outputPerMillion: 1_250),
        "gpt-6-sol": .init(inputPerMillion: 50, cachedInputPerMillion: 5, outputPerMillion: 250),
        "gpt-6-luna": .init(inputPerMillion: 2.5, cachedInputPerMillion: 0.25, outputPerMillion: 12.5)
    ]
    static let fastMultiplier = 2.5

    static func normalizedModel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.lowercased()
        for model in rates.keys where value == model || value == "\(model)-wm" {
            return model
        }
        return nil
    }

    static func credits(tokens: UsageTokenBreakdown, model rawModel: String?, speed: UsageSpeedMode) -> Double? {
        guard let model = normalizedModel(rawModel), let rate = rates[model] else { return nil }
        let uncachedAndWritten = tokens.uncachedInput + tokens.cacheWriteInput
        let input = Double(uncachedAndWritten) * rate.inputPerMillion
            + Double(tokens.cachedInput) * rate.cachedInputPerMillion
        let output = Double(tokens.outputText + tokens.reasoningOutput) * rate.outputPerMillion
        let standardCredits = (input + output) / 1_000_000
        return speed == .fast ? standardCredits * fastMultiplier : standardCredits
    }
}

enum UsagePriceCatalog {
    static let version = "openai-api-and-codex-rates-reviewed-2026-09-22-v3"
    static let sourceURL = "https://developers.openai.com/api/docs/pricing"
    static let codexSourceURL = "https://developers.openai.com/codex/pricing"
    static let reviewedAt = ISO8601DateFormatter().date(from: "2026-09-22T00:00:00Z")!
    static let longContextBoundary = 272_000

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func date(_ value: String) -> Date { formatter.date(from: value)! }

    // Standard API prices in USD per million tokens. Fast-mode quota weighting
    // is applied separately because it is a subscription-credit multiplier,
    // not API billing. Unknown cards remain explicitly unpriced.
    static let cards: [UsagePriceCard] = [
        .init(model: "gpt-6-astra", contextBand: .short, validFrom: date("2026-09-04"), validThrough: nil, inputPerMillion: 10, cachedInputPerMillion: 1, cacheWritePerMillion: 12.5, outputPerMillion: 50),
        .init(model: "gpt-6-astra", contextBand: .long, validFrom: date("2026-09-04"), validThrough: nil, inputPerMillion: 20, cachedInputPerMillion: 2, cacheWritePerMillion: 25, outputPerMillion: 75),
        .init(model: "gpt-5.6-sol", contextBand: .short, validFrom: nil, validThrough: nil, inputPerMillion: 5, cachedInputPerMillion: 0.5, cacheWritePerMillion: 6.25, outputPerMillion: 30),
        .init(model: "gpt-5.6-sol", contextBand: .long, validFrom: nil, validThrough: nil, inputPerMillion: 10, cachedInputPerMillion: 1, cacheWritePerMillion: 12.5, outputPerMillion: 45),
        .init(model: "gpt-5.6-terra", contextBand: .short, validFrom: date("2026-07-30"), validThrough: nil, inputPerMillion: 2, cachedInputPerMillion: 0.2, cacheWritePerMillion: 2.5, outputPerMillion: 12),
        .init(model: "gpt-5.6-terra", contextBand: .long, validFrom: date("2026-07-30"), validThrough: nil, inputPerMillion: 4, cachedInputPerMillion: 0.4, cacheWritePerMillion: 5, outputPerMillion: 18),
        .init(model: "gpt-5.6-luna", contextBand: .short, validFrom: date("2026-07-30"), validThrough: nil, inputPerMillion: 0.2, cachedInputPerMillion: 0.02, cacheWritePerMillion: 0.25, outputPerMillion: 1.2),
        .init(model: "gpt-5.6-luna", contextBand: .long, validFrom: date("2026-07-30"), validThrough: nil, inputPerMillion: 0.4, cachedInputPerMillion: 0.04, cacheWritePerMillion: 0.5, outputPerMillion: 1.8),
        .init(model: "gpt-5.5", contextBand: .short, validFrom: nil, validThrough: nil, inputPerMillion: 5, cachedInputPerMillion: 0.5, cacheWritePerMillion: nil, outputPerMillion: 30),
        .init(model: "gpt-5.5", contextBand: .long, validFrom: nil, validThrough: nil, inputPerMillion: 10, cachedInputPerMillion: 1, cacheWritePerMillion: nil, outputPerMillion: 45),
        .init(model: "gpt-5.4", contextBand: .short, validFrom: nil, validThrough: nil, inputPerMillion: 2.5, cachedInputPerMillion: 0.25, cacheWritePerMillion: nil, outputPerMillion: 15),
        .init(model: "gpt-5.4", contextBand: .long, validFrom: nil, validThrough: nil, inputPerMillion: 5, cachedInputPerMillion: 0.5, cacheWritePerMillion: nil, outputPerMillion: 22.5),
        .init(model: "gpt-5.4-mini", contextBand: .any, validFrom: nil, validThrough: nil, inputPerMillion: 0.75, cachedInputPerMillion: 0.075, cacheWritePerMillion: nil, outputPerMillion: 4.5),
        .init(model: "gpt-5", contextBand: .any, validFrom: nil, validThrough: nil, inputPerMillion: 1.25, cachedInputPerMillion: 0.125, cacheWritePerMillion: nil, outputPerMillion: 10),
        .init(model: "gpt-4.1", contextBand: .any, validFrom: nil, validThrough: nil, inputPerMillion: 2, cachedInputPerMillion: 0.5, cacheWritePerMillion: nil, outputPerMillion: 8)
    ]

    static func normalizedModel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.lowercased()
        if value == "gpt-5.6-sol-wm" { return "gpt-5.6-sol" }
        if value == "gpt-6-astra-wm" { return "gpt-6-astra" }
        if value == "gpt-6-sol-wm" { return "gpt-6-sol" }
        if value == "gpt-6-luna-wm" { return "gpt-6-luna" }
        if value == "gpt-5.5-codex" { return "gpt-5.5" }
        if value == "codex-auto-review" { return "gpt-5.4" }
        return value
    }

    static func card(model rawModel: String?, contextWindow: Int?, at date: Date) -> UsagePriceCard? {
        guard let model = normalizedModel(rawModel) else { return nil }
        let band: UsagePriceCard.ContextBand = (contextWindow ?? 0) >= longContextBoundary ? .long : .short
        return cards.first {
            $0.model == model
                && ($0.contextBand == .any || $0.contextBand == band)
                && ($0.validFrom == nil || date >= $0.validFrom!)
                && ($0.validThrough == nil || date <= $0.validThrough!)
        }
    }

    static func fastMultiplier(model rawModel: String?) -> Double? {
        guard let model = normalizedModel(rawModel) else { return nil }
        if model == "gpt-6-astra" { return 2 }
        if model == "gpt-5.6" || model.hasPrefix("gpt-5.6-") { return 2.5 }
        if model == "gpt-5.5" || model.hasPrefix("gpt-5.5-") { return 2.5 }
        if model == "gpt-5.4" || model.hasPrefix("gpt-5.4-") { return 2 }
        return nil
    }

    static func price(
        tokens: UsageTokenBreakdown,
        model: String?,
        contextWindow: Int?,
        at date: Date
    ) -> (usd: Double?, pricedTokens: Int64) {
        guard let card = card(model: model, contextWindow: contextWindow, at: date) else {
            return (nil, 0)
        }
        var pricedTokens: Int64 = tokens.uncachedInput + tokens.outputText + tokens.reasoningOutput
        var dollars = Double(tokens.uncachedInput) * card.inputPerMillion
            + Double(tokens.outputText + tokens.reasoningOutput) * card.outputPerMillion
        if let cached = card.cachedInputPerMillion {
            dollars += Double(tokens.cachedInput) * cached
            pricedTokens += tokens.cachedInput
        }
        if let write = card.cacheWritePerMillion {
            dollars += Double(tokens.cacheWriteInput) * write
            pricedTokens += tokens.cacheWriteInput
        }
        return (dollars / 1_000_000, pricedTokens)
    }
}

private struct UsageLedgerEvent: Codable, Sendable {
    let sourceKey: String
    let sourceOffset: UInt64
    let timestamp: Date
    let model: String?
    let contextWindow: Int?
    let speed: UsageSpeedMode
    let speedProvenance: UsageSpeedProvenance
    let tokens: UsageTokenBreakdown
    let apiEquivalentUSD: Double?
    let quotaWeightedUSD: Double?
    let gpt6CodexCredits: Double?
    let pricedTokens: Int64
}

private struct UsageRolloutCursor: Codable, Sendable {
    var sourceKey: String
    var offset: UInt64
    var backfillOffset: UInt64?
    var backfillLimit: UInt64?
    var model: String?
    var contextWindow: Int?
    var observedSpeed: UsageSpeedMode
    var modifiedAt: Date
}

private struct UsageLedgerDocument: Codable, Sendable {
    var schemaVersion = 1
    var pricingRegistryVersion: String?
    var cursors: [String: UsageRolloutCursor] = [:]
    var events: [UsageLedgerEvent] = []
    var lastRefreshAt: Date?
}

enum UsageIntelligenceStore {
    private static let retention: TimeInterval = 9 * 86_400
    private static let maximumEvents = 60_000
    // Initial reconstruction is a single streaming pass over recent rollouts.
    // A typical large history is ~1–2 GB but only produces a few thousand tiny
    // ledger events, so this remains memory-bounded while avoiding hours of
    // misleading partial totals. Later refreshes read only appended bytes.
    private static let maximumReadPerRefresh = 6 * 1_024 * 1_024 * 1_024
    private static let initialTailBytesPerFile = 2 * 1_024 * 1_024
    private static let liveReadBytesPerFile = 8 * 1_024 * 1_024
    private static let backfillReadBytesPerFile = 6 * 1_024 * 1_024 * 1_024
    private static let relevantNeedles = [
        Data("\"token_count\"".utf8),
        Data("\"turn_context\"".utf8),
        Data("\"thread_settings_applied\"".utf8)
    ]
    private static let newline = Data([0x0A])
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
    private static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quota Glance", isDirectory: true)
    }
    private static var ledgerURL: URL { supportDirectory.appendingPathComponent("usage-intelligence-v1.json") }
    private static var backupURL: URL { supportDirectory.appendingPathComponent("usage-intelligence-v1.backup.json") }

    static func refresh(windowStart: Date, now: Date = Date()) -> UsageIntelligenceSnapshot {
        var document = load()
        if document.pricingRegistryVersion != UsagePriceCatalog.version {
            document.events = document.events.map(repriced)
            document.pricingRegistryVersion = UsagePriceCatalog.version
        }
        let isInitialBuild = document.lastRefreshAt == nil
        let declaredSpeed = readDeclaredSpeedMode()
        let files = rolloutFiles(modifiedAfter: windowStart.addingTimeInterval(-86_400))
        var budget = maximumReadPerRefresh
        let liveKeys = Set(files.map(sourceKey(for:)))

        for file in files where budget > 0 {
            let key = sourceKey(for: file)
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modifiedAt = values?.contentModificationDate ?? now
            let fileSize = UInt64(max(0, values?.fileSize ?? 0))
            let initialOffset = fileSize > UInt64(initialTailBytesPerFile)
                ? fileSize - UInt64(initialTailBytesPerFile)
                : 0
            var cursor = document.cursors[key] ?? UsageRolloutCursor(
                sourceKey: key,
                offset: initialOffset,
                backfillOffset: initialOffset > 0 ? 0 : nil,
                backfillLimit: initialOffset > 0 ? initialOffset : nil,
                model: nil,
                contextWindow: nil,
                observedSpeed: .unknown,
                modifiedAt: modifiedAt
            )
            if fileSize < cursor.offset {
                document.events.removeAll { $0.sourceKey == key }
                cursor.offset = 0
                cursor.backfillOffset = nil
                cursor.backfillLimit = nil
                cursor.model = nil
                cursor.contextWindow = nil
                cursor.observedSpeed = .unknown
            }
            if let tailStart = liveTailCatchUpStart(
                fileSize: fileSize,
                cursorOffset: cursor.offset,
                liveReadLimit: UInt64(liveReadBytesPerFile)
            ) {
                // A very chatty turn can append hundreds of MB between scans.
                // Always ingest the live tail now so pace and API value remain
                // current, then fill the skipped middle without blocking it.
                cursor.backfillOffset = cursor.backfillOffset ?? cursor.offset
                cursor.backfillLimit = max(cursor.backfillLimit ?? 0, tailStart)
                cursor.offset = tailStart
            }
            let wasKnown = document.cursors[key] != nil
            scan(
                file: file,
                cursor: &cursor,
                events: &document.events,
                budget: &budget,
                maximumBytes: liveReadBytesPerFile,
                endOffset: nil,
                declaredSpeed: (!isInitialBuild && wasKnown) ? declaredSpeed : .unknown
            )
            cursor.modifiedAt = modifiedAt
            document.cursors[key] = cursor
        }

        // Newest data is deliberately ingested first so the panel is useful on its
        // first refresh. Older bytes are then filled in a few MB at a time. This
        // prevents a single multi-hundred-MB rollout from starving every other
        // active session while still converging on the full current-window ledger.
        for file in files where budget > 0 {
            let key = sourceKey(for: file)
            guard var cursor = document.cursors[key],
                  let start = cursor.backfillOffset,
                  let limit = cursor.backfillLimit,
                  start < limit
            else { continue }
            var backfillCursor = UsageRolloutCursor(
                sourceKey: key,
                offset: start,
                backfillOffset: nil,
                backfillLimit: nil,
                model: nil,
                contextWindow: nil,
                observedSpeed: .unknown,
                modifiedAt: cursor.modifiedAt
            )
            scan(
                file: file,
                cursor: &backfillCursor,
                events: &document.events,
                budget: &budget,
                maximumBytes: backfillReadBytesPerFile,
                endOffset: limit,
                declaredSpeed: .unknown
            )
            if backfillCursor.offset >= limit {
                // The initial tail pass may begin between a turn_context line
                // and its token_count lines. Once the prefix is available we
                // know the carried model/tier, so replace that provisional tail
                // instead of leaving valid tokens unpriced or unattributed.
                let liveEnd = cursor.offset
                document.events.removeAll {
                    $0.sourceKey == key && $0.sourceOffset >= limit
                }
                var repairedTail = backfillCursor
                repairedTail.offset = limit
                scan(
                    file: file,
                    cursor: &repairedTail,
                    events: &document.events,
                    budget: &budget,
                    maximumBytes: max(initialTailBytesPerFile, Int(liveEnd - limit)),
                    endOffset: liveEnd,
                    declaredSpeed: .unknown
                )
                cursor.model = repairedTail.model
                cursor.contextWindow = repairedTail.contextWindow
                cursor.observedSpeed = repairedTail.observedSpeed
                cursor.backfillOffset = nil
                cursor.backfillLimit = nil
            } else {
                cursor.backfillOffset = backfillCursor.offset
            }
            document.cursors[key] = cursor
        }

        let cutoff = now.addingTimeInterval(-retention)
        document.events.removeAll { $0.timestamp < cutoff }
        if document.events.count > maximumEvents {
            document.events.sort { $0.timestamp < $1.timestamp }
            document.events = Array(document.events.suffix(maximumEvents))
        }
        document.cursors = document.cursors.filter {
            liveKeys.contains($0.key) && $0.value.modifiedAt >= cutoff
        }
        document.lastRefreshAt = now
        save(document)
        return summarize(document: document, windowStart: windowStart, now: now)
    }

    private static func repriced(_ event: UsageLedgerEvent) -> UsageLedgerEvent {
        let price = UsagePriceCatalog.price(
            tokens: event.tokens,
            model: event.model,
            contextWindow: event.contextWindow,
            at: event.timestamp
        )
        let weighted: Double? = {
            guard let usd = price.usd else { return nil }
            switch event.speed {
            case .standard: return usd
            case .fast:
                guard let multiplier = UsagePriceCatalog.fastMultiplier(model: event.model) else { return nil }
                return usd * multiplier
            case .unknown: return nil
            }
        }()
        return UsageLedgerEvent(
            sourceKey: event.sourceKey,
            sourceOffset: event.sourceOffset,
            timestamp: event.timestamp,
            model: event.model,
            contextWindow: event.contextWindow,
            speed: event.speed,
            speedProvenance: event.speedProvenance,
            tokens: event.tokens,
            apiEquivalentUSD: price.usd,
            quotaWeightedUSD: weighted,
            gpt6CodexCredits: GPT6CodexCreditCatalog.credits(tokens: event.tokens, model: event.model, speed: event.speed),
            pricedTokens: price.pricedTokens
        )
    }

    static func liveTailCatchUpStart(
        fileSize: UInt64,
        cursorOffset: UInt64,
        liveReadLimit: UInt64
    ) -> UInt64? {
        guard liveReadLimit > 0, fileSize > cursorOffset + liveReadLimit else { return nil }
        return fileSize - liveReadLimit
    }

    static func cachedSnapshot(windowStart: Date, now: Date = Date()) -> UsageIntelligenceSnapshot {
        summarize(document: load(), windowStart: windowStart, now: now)
    }

    static func purge() throws {
        for url in [ledgerURL, backupURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func rebuild(windowStart: Date) throws -> UsageIntelligenceSnapshot {
        try purge()
        return refresh(windowStart: windowStart)
    }

    static func exportSanitizedSummary(_ snapshot: UsageIntelligenceSnapshot, to url: URL) throws {
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    static func ledgerSize() -> Int64 {
        let values = try? ledgerURL.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private static func load() -> UsageLedgerDocument {
        for url in [ledgerURL, backupURL] {
            guard let data = try? Data(contentsOf: url),
                  let document = try? decoder.decode(UsageLedgerDocument.self, from: data),
                  document.schemaVersion == 1
            else { continue }
            return document
        }
        return UsageLedgerDocument()
    }

    private static func save(_ document: UsageLedgerDocument) {
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            let data = try encoder.encode(document)
            let temporary = supportDirectory.appendingPathComponent("usage-intelligence-v1.tmp")
            try data.write(to: temporary, options: .atomic)
            if FileManager.default.fileExists(atPath: ledgerURL.path) {
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: ledgerURL, to: backupURL)
                try FileManager.default.removeItem(at: ledgerURL)
            }
            try FileManager.default.moveItem(at: temporary, to: ledgerURL)
        } catch {
            NSLog("Quota Glance could not save usage intelligence: %@", error.localizedDescription)
        }
    }

    private static func rolloutFiles(modifiedAfter cutoff: Date) -> [URL] {
        var files: [URL] = []
        let codexHome = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        for folder in ["sessions", "archived_sessions"] {
            let root = codexHome.appendingPathComponent(folder, isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                      values.isRegularFile == true,
                      (values.contentModificationDate ?? .distantPast) >= cutoff
                else { continue }
                files.append(url)
            }
        }
        return files.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs == rhs ? $0.path > $1.path : lhs > rhs
        }
    }

    private static func sourceKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.lastPathComponent.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func scan(
        file: URL,
        cursor: inout UsageRolloutCursor,
        events: inout [UsageLedgerEvent],
        budget: inout Int,
        maximumBytes: Int,
        endOffset: UInt64?,
        declaredSpeed: UsageSpeedMode
    ) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: cursor.offset) } catch { return }

        var buffer = Data()
        var bufferStart = cursor.offset
        var totalRead = 0
        while budget > 0, totalRead < maximumBytes, endOffset.map({ bufferStart < $0 }) ?? true {
            let remainingToLimit = endOffset.map { max(0, Int($0 - min($0, bufferStart))) } ?? Int.max
            let request = min(512 * 1_024, budget, maximumBytes - totalRead, remainingToLimit)
            guard request > 0 else { break }
            guard let chunk = try? handle.read(upToCount: request), !chunk.isEmpty else { break }
            budget -= chunk.count
            totalRead += chunk.count
            buffer.append(chunk)

            while let range = buffer.range(of: newline) {
                let line = Data(buffer[..<range.lowerBound])
                processLine(
                    line,
                    sourceKey: cursor.sourceKey,
                    sourceOffset: bufferStart,
                    cursor: &cursor,
                    events: &events,
                    declaredSpeed: declaredSpeed
                )
                let consumed = buffer.distance(from: buffer.startIndex, to: range.upperBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                bufferStart += UInt64(consumed)
            }
        }
        if totalRead > 0 { cursor.offset = bufferStart }
    }

    private static func processLine(
        _ line: Data,
        sourceKey: String,
        sourceOffset: UInt64,
        cursor: inout UsageRolloutCursor,
        events: inout [UsageLedgerEvent],
        declaredSpeed: UsageSpeedMode
    ) {
        guard relevantNeedles.contains(where: { line.range(of: $0) != nil }),
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String,
              let payload = object["payload"] as? [String: Any]
        else { return }

        if type == "turn_context" {
            if let model = payload["model"] as? String { cursor.model = model }
            return
        }
        guard type == "event_msg", let payloadType = payload["type"] as? String else { return }
        if payloadType == "thread_settings_applied" {
            let settings = payload["thread_settings"] as? [String: Any]
            switch (settings?["service_tier"] as? String)?.lowercased() {
            case "priority": cursor.observedSpeed = .fast
            case "default", "standard": cursor.observedSpeed = .standard
            default: cursor.observedSpeed = .unknown
            }
            return
        }
        guard payloadType == "token_count",
              let timestamp = parseDate(object["timestamp"]),
              let info = payload["info"] as? [String: Any]
        else { return }
        if let context = integer(info["model_context_window"]) { cursor.contextWindow = Int(context) }
        guard let raw = (info["last_token_usage"] as? [String: Any])
                ?? (info["total_token_usage"] as? [String: Any]),
              let tokens = normalizedTokens(raw), tokens.total > 0
        else { return }

        let effectiveSpeed: UsageSpeedMode
        let provenance: UsageSpeedProvenance
        if cursor.observedSpeed != .unknown {
            effectiveSpeed = cursor.observedSpeed
            provenance = .observed
        } else if declaredSpeed != .unknown {
            effectiveSpeed = declaredSpeed
            provenance = .declaredConfiguration
        } else {
            effectiveSpeed = .unknown
            provenance = .unknown
        }
        let price = UsagePriceCatalog.price(
            tokens: tokens,
            model: cursor.model,
            contextWindow: cursor.contextWindow,
            at: timestamp
        )
        let weighted: Double? = {
            guard let usd = price.usd else { return nil }
            switch effectiveSpeed {
            case .standard: return usd
            case .fast:
                guard let multiplier = UsagePriceCatalog.fastMultiplier(model: cursor.model) else { return nil }
                return usd * multiplier
            case .unknown: return nil
            }
        }()
        events.append(
            UsageLedgerEvent(
                sourceKey: sourceKey,
                sourceOffset: sourceOffset,
                timestamp: timestamp,
                model: UsagePriceCatalog.normalizedModel(cursor.model),
                contextWindow: cursor.contextWindow,
                speed: effectiveSpeed,
                speedProvenance: provenance,
                tokens: tokens,
                apiEquivalentUSD: price.usd,
                quotaWeightedUSD: weighted,
                gpt6CodexCredits: GPT6CodexCreditCatalog.credits(tokens: tokens, model: cursor.model, speed: effectiveSpeed),
                pricedTokens: price.pricedTokens
            )
        )
    }

    static func normalizedTokens(_ raw: [String: Any]) -> UsageTokenBreakdown? {
        guard let input = integer(raw["input_tokens"]),
              let output = integer(raw["output_tokens"]),
              input >= 0, output >= 0
        else { return nil }
        let cached = min(input, max(0, integer(raw["cached_input_tokens"]) ?? 0))
        let write = min(max(0, input - cached), max(0, integer(raw["cache_write_input_tokens"]) ?? 0))
        let reasoning = min(output, max(0, integer(raw["reasoning_output_tokens"]) ?? 0))
        return UsageTokenBreakdown(
            uncachedInput: max(0, input - cached - write),
            cachedInput: cached,
            cacheWriteInput: write,
            outputText: max(0, output - reasoning),
            reasoningOutput: reasoning
        )
    }

    static func rollingTokenPace(
        samples: [(date: Date, tokens: Int64)],
        windowStart: Date,
        now: Date
    ) -> LocalTokenPaceSnapshot {
        func total(since date: Date) -> Int64 {
            samples.reduce(Int64(0)) { partial, sample in
                sample.date >= date && sample.date <= now
                    ? partial + max(0, sample.tokens)
                    : partial
            }
        }
        return LocalTokenPaceSnapshot(
            fiveMinutes: total(since: now.addingTimeInterval(-5 * 60)),
            oneHour: total(since: now.addingTimeInterval(-60 * 60)),
            twelveHours: total(since: now.addingTimeInterval(-12 * 60 * 60)),
            twentyFourHours: total(since: now.addingTimeInterval(-24 * 60 * 60)),
            sinceReset: total(since: windowStart)
        )
    }

    private static func summarize(
        document: UsageLedgerDocument,
        windowStart: Date,
        now: Date
    ) -> UsageIntelligenceSnapshot {
        let events = document.events.filter { $0.timestamp >= windowStart && $0.timestamp <= now }
        guard !events.isEmpty else { return .empty(windowStart: windowStart) }
        let totalTokens = events.reduce(UsageTokenBreakdown()) { $0 + $1.tokens }
        let rawTokenCount = max(1, totalTokens.total)
        let pricedTokens = events.reduce(Int64(0)) { $0 + $1.pricedTokens }
        let knownSpeedTokens = events.filter { $0.speed != .unknown }.reduce(Int64(0)) { $0 + $1.tokens.total }
        let fastTokens = events.filter { $0.speed == .fast }.reduce(Int64(0)) { $0 + $1.tokens.total }
        let standardTokens = events.filter { $0.speed == .standard }.reduce(Int64(0)) { $0 + $1.tokens.total }
        let apiTotal = events.compactMap(\.apiEquivalentUSD).reduce(0, +)
        let weightedTotal = events.compactMap(\.quotaWeightedUSD).reduce(0, +)
        let recentTokenPace = rollingTokenPace(
            samples: events.map { ($0.timestamp, $0.tokens.total) },
            windowStart: windowStart,
            now: now
        )

        let gpt6Credits = events.compactMap(\.gpt6CodexCredits).reduce(0, +)
        var modelBuckets: [String: (tokens: Int64, usd: Double, credits: Double)] = [:]
        for event in events {
            let model = event.model ?? "Unknown model"
            var bucket = modelBuckets[model] ?? (0, 0, 0)
            bucket.tokens += event.tokens.total
            bucket.usd += event.apiEquivalentUSD ?? 0
            bucket.credits += event.gpt6CodexCredits ?? 0
            modelBuckets[model] = bucket
        }
        var modelSummaries: [UsageModelSummary] = []
        for (model, bucket) in modelBuckets {
            let codexCredits: Double?
            if GPT6CodexCreditCatalog.normalizedModel(model) != nil {
                codexCredits = bucket.credits
            } else {
                codexCredits = nil
            }
            modelSummaries.append(UsageModelSummary(
                model: model,
                tokens: bucket.tokens,
                apiEquivalentUSD: bucket.usd,
                gpt6CodexCredits: codexCredits
            ))
        }
        let models = modelSummaries.sorted { lhs, rhs in
            if lhs.tokens == rhs.tokens {
                return lhs.apiEquivalentUSD > rhs.apiEquivalentUSD
            }
            return lhs.tokens > rhs.tokens
        }

        let calendar = Calendar(identifier: .gregorian)
        var cumulativeAPI = 0.0
        var cumulativeWeighted = 0.0
        var weightedCoverageComplete = true
        var timeline: [UsageCostPoint] = [
            UsageCostPoint(date: windowStart, apiEquivalentUSD: 0, quotaWeightedUSD: 0)
        ]
        let grouped = Dictionary(grouping: events) { event -> Date in
            let interval = floor(event.timestamp.timeIntervalSince1970 / 300) * 300
            return Date(timeIntervalSince1970: interval)
        }
        for bucket in grouped.keys.sorted() {
            let values = grouped[bucket] ?? []
            cumulativeAPI += values.compactMap(\.apiEquivalentUSD).reduce(0, +)
            cumulativeWeighted += values.compactMap(\.quotaWeightedUSD).reduce(0, +)
            weightedCoverageComplete = weightedCoverageComplete
                && values.allSatisfy { $0.quotaWeightedUSD != nil }
            timeline.append(
                UsageCostPoint(
                    date: calendar.date(byAdding: .minute, value: 5, to: bucket) ?? bucket,
                    apiEquivalentUSD: cumulativeAPI,
                    quotaWeightedUSD: weightedCoverageComplete ? cumulativeWeighted : nil
                )
            )
        }

        return UsageIntelligenceSnapshot(
            capturedAt: now,
            windowStart: windowStart,
            tokens: totalTokens,
            apiEquivalentUSD: apiTotal,
            quotaWeightedUSD: weightedTotal,
            gpt6CodexCredits: events.contains(where: { $0.gpt6CodexCredits != nil }) ? gpt6Credits : nil,
            pricingCoverage: min(1, Double(pricedTokens) / Double(rawTokenCount)),
            speedCoverage: min(1, Double(knownSpeedTokens) / Double(rawTokenCount)),
            fastShare: Double(fastTokens) / Double(rawTokenCount),
            standardShare: Double(standardTokens) / Double(rawTokenCount),
            unknownSpeedShare: Double(max(0, rawTokenCount - fastTokens - standardTokens)) / Double(rawTokenCount),
            modelSummaries: models,
            costTimeline: timeline,
            eventCount: events.count,
            sourceFileCount: Set(events.map(\.sourceKey)).count,
            backfillComplete: !document.cursors.values.contains { $0.backfillOffset != nil },
            pendingBackfillSourceCount: document.cursors.values.filter { $0.backfillOffset != nil }.count,
            ledgerBytes: ledgerSize(),
            oldestEventAt: events.map(\.timestamp).min(),
            newestEventAt: events.map(\.timestamp).max(),
            pricingRegistryVersion: UsagePriceCatalog.version,
            pricingSourceURL: UsagePriceCatalog.sourceURL,
            pricingReviewedAt: UsagePriceCatalog.reviewedAt,
            recentTokenPace: recentTokenPace
        )
    }

    private static func readDeclaredSpeedMode() -> UsageSpeedMode {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return .unknown }
        let pattern = #"(?m)^\s*service_tier\s*=\s*[\"']([A-Za-z0-9._-]{1,32})[\"']\s*(?:#.*)?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return .unknown }
        switch text[range].lowercased() {
        case "priority": return .fast
        case "default", "standard": return .standard
        default: return .unknown
        }
    }

    private static func integer(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

struct UsageIntelligencePanel: View {
    let snapshot: UsageIntelligenceSnapshot
    let secondaryQuota: SecondaryQuotaSnapshot?
    let onRebuild: () -> Void
    let onPurge: () -> Void
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("USAGE INTELLIGENCE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(Color.white.opacity(0.45))
                    Text(currency(snapshot.apiEquivalentUSD) + (snapshot.backfillComplete ? " API equivalent" : "+ indexing"))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.94))
                }
                Spacer()
                confidenceBadge
            }

            HStack {
                Text("QUOTA-WEIGHTED VALUE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.35))
                Spacer()
                Text(currency(snapshot.quotaWeightedUSD))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x7EE6AE))
            }

            if let credits = snapshot.gpt6CodexCredits {
                HStack {
                    Text("GPT-6 CODEX CREDITS · STANDARD RATE CARD")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.35))
                    Spacer()
                    Text(String(format: "%.2f cr", credits))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x7EE6AE))
                }
                Text("Sol and Luna have Codex credit estimates; no public API dollar rate is listed yet.")
                    .font(.system(size: 8, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.35))
            }

            HStack(spacing: 8) {
                metric("CACHE", percent(cacheShare))
                metric("PRICED", percent(snapshot.pricingCoverage))
                metric("SPEED", percent(snapshot.speedCoverage))
                metric("FAST", percent(snapshot.fastShare))
            }

            HStack(spacing: 6) {
                speedChip("STANDARD", snapshot.standardShare)
                speedChip("FAST", snapshot.fastShare)
                speedChip("UNKNOWN", snapshot.unknownSpeedShare)
            }

            if !snapshot.modelSummaries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MODEL MIX")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.35))
                    ForEach(snapshot.modelSummaries.prefix(3)) { model in
                        HStack {
                            Text(model.model)
                            Spacer()
                            Text(shortTokens(model.tokens))
                            Text(model.apiEquivalentUSD > 0 || model.gpt6CodexCredits == nil
                                 ? currency(model.apiEquivalentUSD) : "API —")
                                .frame(width: 54, alignment: .trailing)
                            if let credits = model.gpt6CodexCredits {
                                Text(String(format: "%.2f cr", credits))
                                    .frame(width: 62, alignment: .trailing)
                            }
                        }
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.62))
                    }
                }
            }

            if let secondaryQuota {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("SHORT WINDOW")
                        Spacer()
                        Text("\(Int(secondaryQuota.usedPercent.rounded()))% · " + relative(secondaryQuota.resetAt))
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(Color(hex: 0x7EE6AE))
                                .frame(width: geometry.size.width * min(1, secondaryQuota.usedPercent / 100))
                        }
                    }
                    .frame(height: 5)
                }
            }

            Divider().overlay(Color.white.opacity(0.1))

            HStack(spacing: 8) {
                action("EXPORT", icon: "square.and.arrow.up") { export() }
                action("REBUILD", icon: "arrow.clockwise") {
                    onRebuild()
                    message = "Ledger rebuild started"
                }
                action("PURGE", icon: "trash") {
                    onPurge()
                    message = "Local usage ledger cleared"
                }
            }
            if let message {
                Text(message)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: 0x7EE6AE).opacity(0.8))
            }
            Text("\(snapshot.eventCount) events · \(snapshot.sourceFileCount) sessions · \(byteCount(snapshot.ledgerBytes)) on disk")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .padding(16)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: 0x101419))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(hex: 0x7EE6AE).opacity(0.2), lineWidth: 1)
                )
        )
        .preferredColorScheme(.dark)
    }

    private var cacheShare: Double {
        let input = snapshot.tokens.uncachedInput + snapshot.tokens.cachedInput + snapshot.tokens.cacheWriteInput
        guard input > 0 else { return 0 }
        return Double(snapshot.tokens.cachedInput) / Double(input)
    }

    private var confidenceBadge: some View {
        let confidence = min(snapshot.pricingCoverage, snapshot.speedCoverage)
        let label = snapshot.backfillComplete
            ? (confidence >= 0.8 ? "HIGH" : confidence >= 0.45 ? "MED" : "CALIBRATING")
            : "INDEXING"
        return Text(label)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(confidence >= 0.8 ? Color(hex: 0x7EE6AE) : Color(hex: 0xF2AD3E))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundStyle(Color.white.opacity(0.3))
            Text(value).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Color.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.045)))
    }

    private func speedChip(_ title: String, _ share: Double) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Text(percent(share)).foregroundStyle(Color.white.opacity(0.88))
        }
        .font(.system(size: 7, weight: .bold, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.34))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.04)))
    }

    private func action(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "quota-glance-usage-summary.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try UsageIntelligenceStore.exportSanitizedSummary(snapshot, to: url)
            message = "Sanitized summary exported"
        } catch {
            message = "Export failed"
        }
    }

    private func currency(_ value: Double) -> String { String(format: "$%.2f", value) }
    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    private func shortTokens(_ value: Int64) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fK", Double(value) / 1_000) }
        return "\(value)"
    }
    private func relative(_ date: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSinceNow / 60))
        return "\(minutes / 60)h \(minutes % 60)m"
    }
    private func byteCount(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
}
