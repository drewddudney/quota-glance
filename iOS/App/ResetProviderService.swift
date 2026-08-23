import Foundation

struct PublicForecast: Sendable {
    let providers: [ProviderReading]
    let selectedPercent: Double?
    let resetAnnounced: Bool
    let announcementID: String?
    let announcementText: String?
    let announcementDate: Date?
    let announcementExpectedAt: Date?
    let announcementURL: URL?
    let lastBlessingAt: Date?
    let tiboPosts: [QuotaTiboPost]
}

enum ResetProviderService {
    static func fetch(selected: ResetSource) async throws -> PublicForecast {
        async let lunar = optional { try await fetchLunar() }
        async let codexResets = optional { try await fetchCodexResets() }
        async let will = optional { try await fetchWill() }
        async let gussuri = optional { try await fetchGussuri() }

        let results = await [lunar, codexResets, will, gussuri].compactMap { $0 }
        guard !results.isEmpty else { throw URLError(.cannotLoadFromNetwork) }
        let readings = results.map(\.reading)
        let scored = readings.compactMap(\.percent)
        let mean = scored.isEmpty ? nil : scored.reduce(0, +) / Double(scored.count)
        let selectedPercent = selected == .average
            ? mean
            : readings.first(where: { $0.source == selected })?.percent ?? mean
        let providerAnnouncement = results
            .compactMap(\.announcement)
            .filter { $0.detectedAt > Date().addingTimeInterval(-36 * 3_600) }
            .max { $0.detectedAt < $1.detectedAt }
        var postsByID: [String: QuotaTiboPost] = [:]
        for post in results.flatMap(\.posts) {
            let previous = postsByID[post.id]
            let oldDetail = (previous?.text.count ?? 0) + (previous?.inReplyTo?.count ?? 0)
            let newDetail = post.text.count + (post.inReplyTo?.count ?? 0)
            if previous == nil || newDetail > oldDetail { postsByID[post.id] = post }
        }
        let recentCutoff = Date().addingTimeInterval(-7 * 86_400)
        let tiboPosts = postsByID.values
            .filter { ($0.date ?? .distantPast) >= recentCutoff }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        let scheduledPost = tiboPosts.compactMap { post -> Announcement? in
            guard
                post.isResetOriented,
                let postedAt = post.date,
                let expectedAt = ResetAnnouncementTimeParser.expectedDate(in: post.text, postedAt: postedAt),
                expectedAt > Date().addingTimeInterval(-5 * 60)
            else { return nil }
            return Announcement(
                id: "scheduled:\(post.id)",
                detectedAt: postedAt,
                expectedAt: expectedAt,
                text: post.text,
                url: post.url
            )
        }.min { ($0.expectedAt ?? .distantFuture) < ($1.expectedAt ?? .distantFuture) }
        let announcement: Announcement? = {
            if let providerAnnouncement {
                guard let scheduledPost else { return providerAnnouncement }
                return Announcement(
                    id: providerAnnouncement.id,
                    detectedAt: providerAnnouncement.detectedAt,
                    expectedAt: resolvedExpectedAt(
                        providerExpectedAt: providerAnnouncement.expectedAt,
                        tweetExpectedAt: scheduledPost.expectedAt
                    ),
                    text: providerAnnouncement.text,
                    url: providerAnnouncement.url
                )
            }
            return scheduledPost
        }()

        return PublicForecast(
            providers: readings,
            selectedPercent: announcement == nil ? selectedPercent : 100,
            resetAnnounced: announcement != nil,
            announcementID: announcement?.id,
            announcementText: announcement?.text,
            announcementDate: announcement?.detectedAt,
            announcementExpectedAt: announcement?.expectedAt,
            announcementURL: announcement?.url,
            lastBlessingAt: results.compactMap(\.lastBlessingAt).max(),
            tiboPosts: tiboPosts
        )
    }

    private struct Result: Sendable {
        let reading: ProviderReading
        let announcement: Announcement?
        let lastBlessingAt: Date?
        let posts: [QuotaTiboPost]
    }

    private struct Announcement: Sendable {
        let id: String
        let detectedAt: Date
        let expectedAt: Date?
        let text: String
        let url: URL?
    }

    private static func optional(_ operation: @escaping @Sendable () async throws -> Result) async -> Result? {
        try? await operation()
    }

    /// The announcement's own wording is authoritative for its clock time.
    /// Some aggregators serialize colloquial "PST" as a fixed UTC−8 offset,
    /// which is one hour late while Los Angeles is observing daylight time.
    static func resolvedExpectedAt(providerExpectedAt: Date?, tweetExpectedAt: Date?) -> Date? {
        tweetExpectedAt ?? providerExpectedAt
    }

    private static func fetchLunar() async throws -> Result {
        let data = try await data(from: URL(string: "https://codex.lunarwerx.com/cnx/aireset/summary/t/5957183")!)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let chance = (root["chanceToday"] as? NSNumber)?.doubleValue
        else { throw URLError(.cannotParseResponse) }
        let generatedAt = (root["generatedAt"] as? String).flatMap(date(_:))
        let tibo = root["tibo"] as? [String: Any]
        let posts = ((tibo?["tweets"] as? [[String: Any]]) ?? []) + ((tibo?["more"] as? [[String: Any]]) ?? [])
        let tiboPosts = posts.compactMap { post -> QuotaTiboPost? in
            guard let text = post["text"] as? String else { return nil }
            let context = post["context"] as? String
            let url = (post["url"] as? String).flatMap(URL.init(string:))
            return QuotaTiboPost(
                id: canonicalPostID(rawID: post["id"] as? String ?? text, url: url, text: text),
                date: (post["at"] as? String).flatMap(date(_:)),
                text: text,
                inReplyTo: context,
                url: url,
                isResetOriented: isResetPost(text: text, context: context)
            )
        }
        let pending = posts
            .filter { ($0["pendingReset"] as? Bool) == true }
            .max {
                (($0["at"] as? String).flatMap(date(_:)) ?? .distantPast)
                    < (($1["at"] as? String).flatMap(date(_:)) ?? .distantPast)
            }
        let announcement = pending.flatMap { post -> Announcement? in
            guard
                let id = post["id"] as? String,
                let text = post["text"] as? String,
                let detectedAt = (post["at"] as? String).flatMap(date(_:))
            else { return nil }
            return Announcement(
                id: "lunar:\(id)",
                detectedAt: detectedAt,
                expectedAt: ResetAnnouncementTimeParser.expectedDate(in: text, postedAt: detectedAt),
                text: text,
                url: (post["url"] as? String).flatMap(URL.init(string:))
            )
        }
        return Result(
            reading: ProviderReading(source: .lunarWerx, percent: chance * 100, updatedAt: generatedAt),
            announcement: announcement,
            lastBlessingAt: (root["lastReset"] as? String).flatMap(date(_:)),
            posts: tiboPosts
        )
    }

    private static func fetchWill() async throws -> Result {
        let data = try await data(from: URL(string: "https://www.willcodexquotareset.com/api/forecast")!)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let forecast = root["forecast"] as? [String: Any],
            let score = (forecast["score"] as? NSNumber)?.doubleValue
        else { throw URLError(.cannotParseResponse) }
        let posts = root["tiboPosts"] as? [[String: Any]] ?? []
        let tiboPosts = posts.compactMap { post -> QuotaTiboPost? in
            guard let text = post["title"] as? String else { return nil }
            let context = post["context"] as? String
            let url = (post["link"] as? String).flatMap(URL.init(string:))
            return QuotaTiboPost(
                id: canonicalPostID(rawID: post["guid"] as? String ?? text, url: url, text: text),
                date: (post["pubDate"] as? String).flatMap(date(_:)),
                text: text,
                inReplyTo: context,
                url: url,
                isResetOriented: isResetPost(text: text, context: context)
            )
        }
        let resetPost = posts.first { post in
            guard (forecast["resetAnnounced"] as? Bool) == true else { return false }
            let combined = "\(post["title"] as? String ?? "") \(post["context"] as? String ?? "")"
            return combined.range(of: #"\b(reset|usage limits|banked)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        let announcement = resetPost.flatMap { post -> Announcement? in
            guard
                let id = post["guid"] as? String,
                let text = post["title"] as? String,
                let detectedAt = (post["pubDate"] as? String).flatMap(date(_:))
            else { return nil }
            return Announcement(
                id: "will:\(id)",
                detectedAt: detectedAt,
                expectedAt: ResetAnnouncementTimeParser.expectedDate(in: text, postedAt: detectedAt),
                text: text,
                url: (post["link"] as? String).flatMap(URL.init(string:))
            )
        }
        return Result(
            reading: ProviderReading(
                source: .willCodexQuotaReset,
                percent: score,
                updatedAt: (root["fetchedAt"] as? String).flatMap(date(_:))
            ),
            announcement: announcement,
            lastBlessingAt: (forecast["latestResetAt"] as? String).flatMap(date(_:)),
            posts: tiboPosts
        )
    }

    private static func fetchCodexResets() async throws -> Result {
        let html = try await string(from: URL(string: "https://codex-resets.com")!)
        let watch = capture(#"(<section\s+class="[^"]*\bwatch-card\b[^"]*"[\s\S]*?</section>)"#, in: html)
        let percent = watch.flatMap { section -> Double? in
            guard let raw = capture(#"aria-label="(?:Greater than )?([0-9.]+) percent""#, in: section) else { return nil }
            return Double(raw)
        }
        return Result(
            reading: ProviderReading(source: .codexResets, percent: percent, updatedAt: Date()),
            announcement: nil,
            lastBlessingAt: capture(#"class="hero-figure"[^>]*data-datetime="([^"]+)""#, in: html).flatMap(date(_:)),
            posts: []
        )
    }

    private static func fetchGussuri() async throws -> Result {
        let raw = try await string(from: URL(string: "https://codex.gussuriworks.com/en")!)
        let html = raw
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
        guard let probability = capture(#""probability24h":\s*([0-9.]+)"#, in: html).flatMap(Double.init) else {
            throw URLError(.cannotParseResponse)
        }
        let active = capture(#""activeWindow":\{([\s\S]*?)\},"displayReasoningSummary""#, in: html)
        let isOfficial = active?.contains(#""active":true"#) == true
            && capture(#""kind":"([^"]+)""#, in: active ?? "")?.lowercased() == "official"
        let announcement: Announcement? = {
            guard
                isOfficial,
                let openedAt = capture(#""openedAt":"([^"]+)""#, in: active ?? "").flatMap(date(_:))
            else { return nil }
            let url = capture(#""source":"([^"]+)""#, in: active ?? "").flatMap(URL.init(string:))
            return Announcement(
                id: "gussuri:\(url?.absoluteString ?? openedAt.ISO8601Format())",
                detectedAt: openedAt,
                expectedAt: capture(#""expectedAt":"([^"]+)""#, in: active ?? "").flatMap(date(_:)),
                text: capture(#""summary":"([^"]+)""#, in: active ?? "") ?? "An official Codex reset was announced.",
                url: url
            )
        }()
        return Result(
            reading: ProviderReading(
                source: .gussuri,
                percent: probability * 100,
                updatedAt: capture(#""checkedAt":"([^"]+)""#, in: html).flatMap(date(_:))
            ),
            announcement: announcement,
            lastBlessingAt: capture(#""latestWindow":\{[\s\S]*?"closedAt":"([^"]+)""#, in: html).flatMap(date(_:)),
            posts: []
        )
    }

    private static func canonicalPostID(rawID: String, url: URL?, text: String) -> String {
        for value in [url?.absoluteString, rawID].compactMap({ $0 }) {
            if let status = capture(#"(?:/status/|^)([0-9]{12,})(?:\D|$)"#, in: value) {
                return "x:\(status)"
            }
        }
        let normalized = text.lowercased()
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "text:\(normalized.prefix(160))"
    }

    private static func isResetPost(text: String, context: String?) -> Bool {
        let combined = [text, context].compactMap { $0 }.joined(separator: " ")
        return combined.range(
            of: #"\b(reset(?:s|ting)?|quota|rate[ -]?limit|usage limit|token limit|weekly limit|replenish(?:ed|ment)?|restore(?:d|ation)?|refresh(?:ed)?|bless(?:ed|ing)?|banked|reset button|circle back)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Quota Glance iOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func string(from url: URL) async throws -> String {
        let payload = try await data(from: url)
        guard let value = String(data: payload, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
        return value
    }

    private static func capture(_ pattern: String, in value: String) -> String? {
        guard
            let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: value)
        else { return nil }
        return String(value[range])
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
