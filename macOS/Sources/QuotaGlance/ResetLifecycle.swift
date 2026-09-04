import Foundation

struct ResetLifecycleSnapshot: Codable, Equatable, Sendable {
    static let delayedExpiry: TimeInterval = 24 * 60 * 60

    var announcementID: String?
    var announcementDetectedAt: Date?
    var hasExactAnnouncementTime: Bool?
    var expectedAt: Date?
    var completedAt: Date?
    var lastUsageWindowStart: Date?
    var lastUsedPercent: Double?
    var lastPlanName: String?
    var lastPostedResetBoundary: Date?
    var pendingResetCandidateAt: Date?
    var pendingResetWindowStart: Date?

    static let empty = ResetLifecycleSnapshot()

    func isRecentlyCompleted(
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let completedAt, date >= completedAt else { return false }
        return calendar.isDate(date, inSameDayAs: completedAt)
    }

    func isDelayed(at date: Date = Date()) -> Bool {
        guard hasExactAnnouncementTime == true,
              let expectedAt,
              !isRecentlyCompleted(at: date) else { return false }
        return date >= expectedAt && date.timeIntervalSince(expectedAt) < Self.delayedExpiry
    }

    func activeExpectedAt(at date: Date = Date()) -> Date? {
        guard hasExactAnnouncementTime == true,
              let expectedAt,
              !isRecentlyCompleted(at: date) else { return nil }
        guard date.timeIntervalSince(expectedAt) < Self.delayedExpiry else { return nil }
        return expectedAt
    }

    var hasPendingResetCandidate: Bool {
        pendingResetCandidateAt != nil
    }
}

enum ResetLifecycleStore {
    private static let defaultsKey = "QuotaGlance.resetLifecycle.v1"

    static func load(at date: Date = Date()) -> ResetLifecycleSnapshot {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              var value = try? decoder.decode(ResetLifecycleSnapshot.self, from: data)
        else { return .empty }
        if let expectedAt = value.expectedAt,
           date.timeIntervalSince(expectedAt) >= ResetLifecycleSnapshot.delayedExpiry {
            value.announcementID = nil
            value.announcementDetectedAt = nil
            value.hasExactAnnouncementTime = nil
            value.expectedAt = nil
            save(value)
        }
        return value
    }

    /// Pins the first concrete time for an announcement. A mirror or provider
    /// correcting its scrape later cannot move the clock. Only a genuinely
    /// newer announcement may replace it.
    @discardableResult
    static func observeAnnouncement(
        _ announcement: ResetAnnouncement?,
        observedAt: Date = Date()
    ) -> ResetLifecycleSnapshot {
        var state = load(at: observedAt)
        guard let announcement,
              let expectedAt = announcement.expectedAt,
              ResetAnnouncementTimeParser.expectedDate(
                in: announcement.text,
                postedAt: announcement.detectedAt
              ) != nil else { return state }

        // Mirrors can rediscover an old post after the reset and stamp it with
        // a fresh detection time. The scheduled instant is authoritative: an
        // announcement for a reset that already completed must never reopen.
        if let completedAt = state.completedAt, expectedAt <= completedAt {
            return state
        }
        guard observedAt.timeIntervalSince(expectedAt) < ResetLifecycleSnapshot.delayedExpiry else {
            return state
        }

        if let completedAt = state.completedAt, announcement.detectedAt <= completedAt {
            return state
        }

        let isNewerAnnouncement: Bool
        if let pinnedDetectedAt = state.announcementDetectedAt {
            isNewerAnnouncement = announcement.detectedAt > pinnedDetectedAt.addingTimeInterval(10 * 60)
        } else {
            isNewerAnnouncement = true
        }

        let correctsSameAnnouncementEarlier = state.expectedAt.map {
            expectedAt < $0 && announcement.detectedAt <= (state.announcementDetectedAt ?? announcement.detectedAt).addingTimeInterval(10 * 60)
        } ?? false
        if state.expectedAt == nil
            || state.hasExactAnnouncementTime != true
            || isNewerAnnouncement
            || correctsSameAnnouncementEarlier
        {
            state.announcementID = announcement.id
            state.announcementDetectedAt = announcement.detectedAt
            state.hasExactAnnouncementTime = true
            state.expectedAt = expectedAt
            save(state)
        }
        return state
    }

    /// The authoritative reset signal is a new Codex usage window. A large
    /// drop to effectively zero is retained as a fallback for older payloads.
    @discardableResult
    static func observeUsage(
        windowStart: Date,
        usedPercent: Double,
        planName: String? = nil,
        observedAt: Date = Date()
    ) -> ResetLifecycleSnapshot {
        var state = load(at: observedAt)
        let previousWindowStart = state.lastUsageWindowStart
        let previousUsedPercent = state.lastUsedPercent
        let planChanged = state.lastPlanName != nil
            && planName != nil
            && state.lastPlanName != planName
        let windowAdvanced = previousWindowStart.map {
            windowStart.timeIntervalSince($0) > 30 * 60
        } ?? false
        let boundaryAlreadyPosted = state.lastPostedResetBoundary.map {
            abs(windowStart.timeIntervalSince($0)) <= 30 * 60
        } ?? false
        let strongBoundaryReset = windowAdvanced
            && usedPercent <= 5
            && !boundaryAlreadyPosted

        // A percentage can transiently read as zero while app-server is
        // switching accounts or rebuilding a rate-limit payload. Without an
        // advanced reset boundary, require a second low observation at least
        // one minute later before treating the drop as a real reset.
        let candidateMinimumAge: TimeInterval = 60
        let candidateMaximumAge: TimeInterval = 30 * 60
        let candidateAge = state.pendingResetCandidateAt.map {
            observedAt.timeIntervalSince($0)
        }
        let candidateMatchesWindow = state.pendingResetWindowStart.map {
            windowStart.timeIntervalSince($0) >= -30 * 60
        } ?? false
        let confirmsLowCandidate = !planChanged
            && usedPercent <= 5
            && candidateMatchesWindow
            && candidateAge.map { $0 >= candidateMinimumAge && $0 <= candidateMaximumAge } == true
        let shouldStartLowCandidate = !planChanged
            && (previousUsedPercent ?? 0) > 0
            && usedPercent <= 0.5
            && state.pendingResetCandidateAt == nil

        if strongBoundaryReset || confirmsLowCandidate {
            state.completedAt = observedAt
            state.lastPostedResetBoundary = windowStart
            state.announcementID = nil
            state.announcementDetectedAt = nil
            state.hasExactAnnouncementTime = nil
            state.expectedAt = nil
            state.pendingResetCandidateAt = nil
            state.pendingResetWindowStart = nil
        } else if shouldStartLowCandidate {
            state.pendingResetCandidateAt = observedAt
            state.pendingResetWindowStart = windowStart
        } else if planChanged
            || usedPercent > 5
            || candidateAge.map({ $0 > candidateMaximumAge }) == true
        {
            state.pendingResetCandidateAt = nil
            state.pendingResetWindowStart = nil
        }
        state.lastUsageWindowStart = windowStart
        state.lastUsedPercent = usedPercent
        if let planName { state.lastPlanName = planName }
        save(state)
        return state
    }

    static func resetForTests() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private static func save(_ value: ResetLifecycleSnapshot) {
        guard let data = try? encoder.encode(value) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

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
}
