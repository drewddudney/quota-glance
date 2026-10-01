import Combine
import Foundation

@MainActor
final class ClaudeUsageModel: ObservableObject {
    @Published private(set) var snapshot = ClaudeUsageCache.load()
    @Published private(set) var isRefreshing = false
    @Published private(set) var problem: String?
    @Published private(set) var needsConnection = false
    @Published private(set) var verified = false
    @Published private(set) var source = ClaudeUsageSource.current
    private var timer: Timer?
    private var request: Task<Void, Never>?
    private var retryAt = Date.distantPast
    private var failures = 0
    private var generation = 0

    /// Publishes usage independently of the Codex polling cadence.
    var onSnapshotChanged: (() -> Void)?

    var mobileSnapshot: ClaudeQuotaSnapshot {
        snapshot?.quotaSnapshot(verified: verified, needsConnection: needsConnection) ??
            ClaudeQuotaSnapshot(capturedAt: nil, usagePercent: nil, resetAt: nil, planName: nil,
                                accountID: nil, verified: verified, needsConnection: needsConnection)
    }

    func connect() {
        selectSource(.web)
        ClaudeWebSession.shared.onReady = { [weak self] in self?.refresh() }
        ClaudeWebSession.shared.onWorkspaceChanged = { [weak self] in
            guard let self else { return }
            self.generation += 1
            self.request?.cancel()
            self.request = nil
            self.isRefreshing = false
            self.snapshot = nil
            ClaudeUsageCache.clear()
            self.verified = false
            self.onSnapshotChanged?()
            self.refresh()
        }
        ClaudeWebSession.shared.show()
    }

    func useClaudeCode() {
        selectSource(.claudeCode)
        refresh(allowPrompt: true)
    }

    private func selectSource(_ newSource: ClaudeUsageSource) {
        guard source != newSource else { return }
        generation += 1
        request?.cancel()
        request = nil
        isRefreshing = false
        source = newSource
        UserDefaults.standard.set(newSource.rawValue, forKey: ClaudeUsageSource.defaultsKey)
        snapshot = nil
        ClaudeUsageCache.clear()
        verified = false
        problem = nil
        needsConnection = false
        failures = 0
        retryAt = .distantPast
        onSnapshotChanged?()
    }

    func start(allowPrompt: Bool = false) {
        guard timer == nil else { return }
        refresh(allowPrompt: allowPrompt)
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        request?.cancel()
        // Keep the request slot occupied until cancellation finishes; a rapid hide/show
        // cannot let an older task overwrite a newer account's measurement.
    }

    func refresh(allowPrompt: Bool = false) {
        guard request == nil, Date() >= retryAt else { return }
        isRefreshing = true
        let currentGeneration = generation
        let currentSource = source
        request = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == currentGeneration {
                    self.isRefreshing = false
                    self.request = nil
                    if Task.isCancelled, self.timer != nil {
                        DispatchQueue.main.async { self.refresh() }
                    }
                }
            }
            do {
                let latest: ClaudeUsageSnapshot
                if currentSource == .web {
                    latest = try await ClaudeWebSession.shared.fetch()
                } else {
                    let credential = try await ClaudeCredentialReader.readAsync(allowPrompt: allowPrompt)
                    try Task.checkCancellation()
                    if let previous = self.snapshot, previous.credentialID != credential.identifier {
                        self.snapshot = nil
                        ClaudeUsageCache.clear()
                    }
                    latest = try await ClaudeUsageClient.fetch(credential: credential)
                }
                try Task.checkCancellation()
                guard self.generation == currentGeneration else { return }
                let recorded = latest.recordingHistory(previous: self.snapshot)
                self.snapshot = recorded
                self.problem = nil
                self.needsConnection = false
                self.verified = true
                self.failures = 0
                self.retryAt = .distantPast
                ClaudeUsageCache.save(recorded)
                if currentSource == .web { ClaudeWebSession.shared.report(.success(latest)) }
                self.onSnapshotChanged?()
            } catch {
                guard !Task.isCancelled, self.generation == currentGeneration else { return }
                self.verified = false
                self.problem = error.localizedDescription
                self.needsConnection = (error as? ClaudeUsageError)?.requiresConnection ?? false
                if let authError = error as? ClaudeUsageError {
                    switch authError {
                    case .signInRequired, .unauthorized, .missingUsageScope, .webSignInRequired, .organizationRequired:
                        self.snapshot = nil
                        ClaudeUsageCache.clear()
                    default: break
                    }
                }
                if currentSource == .web { ClaudeWebSession.shared.report(.failure(error)) }
                self.failures = min(5, self.failures + 1)
                if case let ClaudeUsageError.rateLimited(until) = error {
                    self.retryAt = until
                } else if self.needsConnection {
                    self.retryAt = .distantPast
                } else {
                    self.retryAt = Date().addingTimeInterval(min(900, 120 * pow(2, Double(self.failures - 1))))
                }
                self.onSnapshotChanged?()
            }
        }
    }

    func isLive(at now: Date) -> Bool {
        verified && problem == nil && snapshot.map {
            now.timeIntervalSince($0.capturedAt) < 300 && $0.weekly?.hasEnded(at: now) != true
        } == true
    }

    func status(at now: Date) -> String {
        if isRefreshing { return "Updating…" }
        if needsConnection { return snapshot == nil ? "Connect Claude to show usage" : "Saved · reconnect Claude" }
        guard let snapshot else { return problem == nil ? "Connecting to Claude…" : "Usage unavailable" }
        if snapshot.weekly?.hasEnded(at: now) == true { return "Waiting for the next weekly window" }
        let minutes = max(0, Int(now.timeIntervalSince(snapshot.capturedAt) / 60))
        let age = minutes == 0 ? "just now" : minutes < 60 ? "\(minutes)m ago" : "\(minutes / 60)h ago"
        if problem != nil { return "Saved \(age) · retrying" }
        if snapshot.weekly?.usedPercent == nil { return "Weekly usage not available" }
        return "\(isLive(at: now) ? "Updated" : "Saved") \(age)"
    }
}


/// Claude's usage model remains alive for the shared companion layouts.
/// The retired standalone Claude bar and its theme controls are gone.
@MainActor
final class ClaudeBarController {
    static let shared = ClaudeBarController()
    let model = ClaudeUsageModel()

    func suspendForCombinedDisplay() { model.start() }
    func stop() { model.stop() }
    func refresh() { model.refresh() }
}
