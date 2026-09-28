import AppKit
import CryptoKit
import SwiftUI

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

enum ClaudeBarLayout: String, CaseIterable {
    case horizontal, vertical

    var size: NSSize {
        self == .horizontal ? NSSize(width: 340, height: 150) : NSSize(width: 176, height: 274)
    }
}

enum ClaudeBarGeometry {
    static func frame(size: NSSize, origin: NSPoint, dock: DockPosition, in visible: NSRect) -> NSRect {
        let size = NSSize(width: min(size.width, visible.width), height: min(size.height, visible.height))
        var point = NSPoint(
            x: min(max(origin.x, visible.minX), visible.maxX - size.width),
            y: min(max(origin.y, visible.minY), visible.maxY - size.height)
        )
        switch dock {
        case .left, .topLeft, .bottomLeft: point.x = visible.minX
        case .right, .topRight, .bottomRight: point.x = visible.maxX - size.width
        default: break
        }
        switch dock {
        case .top, .topLeft, .topRight: point.y = visible.maxY - size.height
        case .bottom, .bottomLeft, .bottomRight: point.y = visible.minY
        default: break
        }
        return NSRect(origin: point, size: size)
    }
}

private final class ClaudePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ClaudeBarController: NSObject, ObservableObject {
    static let shared = ClaudeBarController()
    static let enabledKey = "QuotaGlance.Claude.enabled"
    private static let frameKey = "QuotaGlance.Claude.frame"
    private static let layoutKey = "QuotaGlance.Claude.layout"
    private static let scaleKey = "QuotaGlance.Claude.scale"
    private static let dockKey = "QuotaGlance.Claude.dock"
    let model = ClaudeUsageModel()
    @Published private(set) var layout: ClaudeBarLayout
    @Published private(set) var scale: Double
    private var panel: ClaudePanel?
    private var dock: DockPosition

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    override init() {
        let defaults = UserDefaults.standard
        layout = ClaudeBarLayout(rawValue: defaults.string(forKey: Self.layoutKey) ?? "") ?? .horizontal
        scale = min(1.5, max(0.8, defaults.object(forKey: Self.scaleKey) as? Double ?? 1))
        dock = DockPosition(rawValue: defaults.string(forKey: Self.dockKey) ?? "") ?? .floating
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wokeUp), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func restoreIfEnabled() { if isEnabled { show() } }

    func toggle() {
        if isEnabled { hide() } else { show(allowPrompt: true) }
    }

    func show(allowPrompt: Bool = false) {
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        if panel == nil {
            let window = ClaudePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = "Claude · Quota Glance"
            window.identifier = NSUserInterfaceItemIdentifier("QuotaGlance.Claude")
            window.level = .floating
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
            window.tabbingMode = .disallowed
            window.isRestorable = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.contentView = NSHostingView(rootView: ClaudeBarView(model: model, controller: self))
            panel = window
            restoreFrame()
        }
        panel?.orderFrontRegardless()
        model.start(allowPrompt: allowPrompt)
    }

    func hide() {
        saveFrame()
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        panel?.orderOut(nil)
        model.stop()
    }

    func stop() { saveFrame(); model.stop() }

    func suspendForCombinedDisplay() {
        saveFrame()
        panel?.orderOut(nil)
        model.start()
    }

    func refresh() { if isEnabled { model.refresh(allowPrompt: true) } }

    func rotate() {
        layout = layout == .horizontal ? .vertical : .horizontal
        dock = .floating
        resize()
    }

    func setScale(_ value: Double) {
        scale = value
        resize()
    }

    func place(_ position: DockPosition) {
        dock = position
        if position == .left || position == .right { layout = .vertical }
        if position == .top || position == .bottom { layout = .horizontal }
        resize()
    }

    func didDrag() {
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? panel.screen ?? NSScreen.main
        guard let screen else { return }
        dock = DockingGeometry.candidate(for: NSEvent.mouseLocation, in: screen.frame)
        if dock == .left || dock == .right { layout = .vertical }
        if dock == .top || dock == .bottom { layout = .horizontal }
        applyFrame(origin: panel.frame.origin, screen: screen)
    }

    private var scaledSize: NSSize { NSSize(width: layout.size.width * scale, height: layout.size.height * scale) }

    private func restoreFrame() {
        let saved = UserDefaults.standard.string(forKey: Self.frameKey).map(NSRectFromString)
        let screen = saved.flatMap { rect in NSScreen.screens.first { $0.visibleFrame.intersects(rect) } } ?? NSScreen.main
        guard let screen else { return }
        let origin = saved?.origin ?? NSPoint(x: screen.visibleFrame.maxX - scaledSize.width - 24, y: screen.visibleFrame.minY + 36)
        applyFrame(origin: origin, screen: screen)
    }

    private func resize() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let origin = NSPoint(x: panel.frame.midX - scaledSize.width / 2, y: panel.frame.midY - scaledSize.height / 2)
        applyFrame(origin: origin, screen: screen)
    }

    private func applyFrame(origin: NSPoint, screen: NSScreen) {
        panel?.setFrame(ClaudeBarGeometry.frame(size: scaledSize, origin: origin, dock: dock, in: screen.visibleFrame), display: true)
        saveFrame()
    }

    private func saveFrame() {
        guard let panel else { return }
        let defaults = UserDefaults.standard
        defaults.set(NSStringFromRect(panel.frame), forKey: Self.frameKey)
        defaults.set(layout.rawValue, forKey: Self.layoutKey)
        defaults.set(scale, forKey: Self.scaleKey)
        defaults.set(dock.rawValue, forKey: Self.dockKey)
    }

    @objc private func screenChanged() { if panel != nil { restoreFrame() } }
    @objc private func wokeUp() { if isEnabled { model.refresh() } }
}

private struct ClaudeBarView: View {
    @ObservedObject var model: ClaudeUsageModel
    @ObservedObject var controller: ClaudeBarController
    @AppStorage(WidgetTheme.defaultsKey) private var themeValue = WidgetTheme.current.rawValue
    private var palette: PopoverPalette { (WidgetTheme(rawValue: themeValue) ?? .current).popoverPalette }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let weekly = model.snapshot?.weekly
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(model.isLive(at: now) ? Color(hex: 0xD97757) : palette.tertiary).frame(width: 6, height: 6)
                        Text("CLAUDE").tracking(1.2)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.primary)
                    .overlay(ClaudeBarDragHandle(onDrag: controller.didDrag, onDoubleClick: controller.rotate))
                    .help("Drag to place Claude independently. Double-click to rotate.")
                    controls
                }

                if controller.layout == .horizontal {
                    HStack(spacing: 20) { meters(weekly, now: now) }
                } else {
                    VStack(alignment: .leading, spacing: 20) { meters(weekly, now: now) }
                }

                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text(weekly?.resetAt.map { "Week ends " + $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) } ?? "Weekly window")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                        .help(weekly?.resetAt?.formatted(date: .complete, time: .shortened) ?? "Claude has not provided a weekly end time.")
                    HStack(spacing: 6) {
                        Text(model.status(at: now))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.tertiary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        if model.needsConnection {
                            Button("Connect", action: model.connect)
                                .font(.system(size: 9, weight: .semibold))
                                .buttonStyle(.plain)
                                .foregroundStyle(Color(hex: 0xD97757))
                        }
                    }
                    .help(model.problem ?? "Usage is account-wide. The calendar follows Claude's seven-day window.")
                }
            }
            .padding(14)
            .frame(width: controller.layout.size.width, height: controller.layout.size.height)
            .background(RoundedRectangle(cornerRadius: 14).fill(palette.background))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.rule, lineWidth: 1))
            .scaleEffect(controller.scale, anchor: .topLeading)
            .frame(width: controller.layout.size.width * controller.scale, height: controller.layout.size.height * controller.scale, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func meters(_ weekly: ClaudeWeeklyUsage?, now: Date) -> some View {
        meter("USAGE", value: weekly?.hasEnded(at: now) == true ? nil : weekly?.usedPercent, color: Color(hex: 0xD97757), roundsDown: false)
        meter("CALENDAR", value: weekly?.calendarPercent(at: now), color: palette.billing, roundsDown: true)
    }

    private func meter(_ title: String, value: Double?, color: Color, roundsDown: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(palette.secondary)
                Spacer(minLength: 4)
                Text(value.map { "\(Int($0.rounded(roundsDown ? .down : .toNearestOrAwayFromZero)))%" } ?? "—")
                    .font(.system(size: 25, weight: .medium, design: palette.numberDesign))
                    .monospacedDigit()
                    .foregroundStyle(palette.primary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.rule)
                    if let value { Capsule().fill(color).frame(width: geometry.size.width * min(1, max(0, value / 100))) }
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title == "USAGE" ? "Claude weekly usage" : "Claude week elapsed")
        .accessibilityValue(value.map { String(format: "%.1f percent", $0) } ?? "Unavailable")
    }

    private var controls: some View {
        Menu {
            ProviderDisplayStyleMenu()
            Button("Manage sign-in…", action: model.connect)
            Button("Refresh") { model.refresh() }.disabled(model.isRefreshing)
            Button("Hide") { controller.hide() }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.secondary)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Claude controls")
    }

}

private struct ClaudeBarDragHandle: NSViewRepresentable {
    let onDrag: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> ClaudeDragView { ClaudeDragView() }
    func updateNSView(_ nsView: ClaudeDragView, context: Context) {
        nsView.onDrag = onDrag
        nsView.onDoubleClick = onDoubleClick
    }
}

private final class ClaudeDragView: NSView {
    var onDrag: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?(); return }
        window?.performDrag(with: event)
        onDrag?()
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}
