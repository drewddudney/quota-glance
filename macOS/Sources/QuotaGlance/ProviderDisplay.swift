import AppKit
import ServiceManagement
import SwiftUI

final class ProviderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ProviderDisplayController: NSObject, ObservableObject, NSPopoverDelegate {
    static let shared = ProviderDisplayController()
    @Published private(set) var selection = ProviderSelection.current
    @Published private(set) var style = ProviderDisplayStyle.current
    @Published private(set) var layoutShuffle = ProviderLayoutShuffle.load()
    @Published private(set) var travelFrequency = ProviderTravelFrequency.current
    @Published private(set) var peekFrequency = ProviderTravelFrequency(rawValue: UserDefaults.standard.string(forKey: "QuotaGlance.peekFrequency") ?? "") ?? .often
    @Published private(set) var displayID = UserDefaults.standard.string(forKey: "QuotaGlance.providers.display") ?? ""
    private var panels: [ProviderPanel] = []
    private var settingsWindow: NSWindow?
    private var tweetPanel: ProviderPanel?
    private var shownTweetID: String?
    private let claude = ClaudeBarController.shared
    private let companions = ProviderCompanionController()
    private var shuffleTimer: Timer?
    private var shuffleRandom = SystemRandomNumberGenerator()
    private var detailInteractions = Set<UUID>()
    private let nativeDetailInteractionID = UUID()
    private var detailPopover: NSPopover?
    private var detailProvider: DisplayProvider?
    private var sleeping = false

    @Published private(set) var isVisible = false
    var screens: [NSScreen] { NSScreen.screens }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(syncTweetBubble), name: .quotaGlanceMenuBarSummaryChanged, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screensChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(pauseShuffleForSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(resumeShuffleAfterWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    static func id(for screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? screen.localizedName
    }

    func restore() {
        UserDefaults.standard.set(style.rawValue, forKey: ProviderDisplayStyle.defaultsKey)
        applyStyle()
        resumeLayoutShuffle()
    }

    func selectStyle(_ newStyle: ProviderDisplayStyle) {
        setLayoutShuffleEnabled(false)
        saveFrame()
        style = newStyle
        UserDefaults.standard.set(style.rawValue, forKey: ProviderDisplayStyle.defaultsKey)
        applyStyle()
    }

    func setLayoutShuffleEnabled(_ enabled: Bool) {
        layoutShuffle.setEnabled(enabled, at: .now)
        layoutShuffle.save()
        resumeLayoutShuffle()
    }

    func selectLayoutShuffleInterval(_ interval: ProviderLayoutShuffleInterval) {
        layoutShuffle.setInterval(interval, at: .now)
        layoutShuffle.save()
        resumeLayoutShuffle()
    }

    func nextShuffledLayout() { advanceLayoutShuffle(automatically: false) }

    func setDetailInteraction(_ id: UUID, active: Bool) {
        if active { detailInteractions.insert(id) } else { detailInteractions.remove(id) }
    }

    private func resumeLayoutShuffle() {
        shuffleTimer?.invalidate(); shuffleTimer = nil
        guard layoutShuffle.isEnabled, isVisible, !sleeping else { return }
        if layoutShuffle.isDue(at: .now) { advanceLayoutShuffle(automatically: true) }
        else if let next = layoutShuffle.nextChangeAt { scheduleLayoutShuffle(at: next) }
    }

    private func advanceLayoutShuffle(automatically: Bool) {
        guard layoutShuffle.isEnabled, isVisible, !sleeping else { return }
        if automatically && (!detailInteractions.isEmpty || companions.isInteracting || NSEvent.pressedMouseButtons != 0 || NSApp.modalWindow != nil) {
            scheduleLayoutShuffle(at: .now.addingTimeInterval(2))
            return
        }
        saveFrame()
        guard let next = layoutShuffle.advance(after: style, at: .now, using: &shuffleRandom) else { return }
        layoutShuffle.save()
        style = next
        UserDefaults.standard.set(next.rawValue, forKey: ProviderDisplayStyle.defaultsKey)
        applyStyle()
        resumeLayoutShuffle()
    }

    private func scheduleLayoutShuffle(at date: Date) {
        shuffleTimer?.invalidate()
        let timer = Timer(fireAt: date, interval: 0, target: self, selector: #selector(layoutShuffleTimerFired), userInfo: nil, repeats: false)
        timer.tolerance = 0.5
        // Default mode leaves context menus and native window drags alone.
        RunLoop.main.add(timer, forMode: .default)
        shuffleTimer = timer
    }

    @objc private func layoutShuffleTimerFired() { resumeLayoutShuffle() }
    @objc private func pauseShuffleForSleep() {
        sleeping = true
        shuffleTimer?.invalidate(); shuffleTimer = nil
    }
    @objc private func resumeShuffleAfterWake() { sleeping = false; resumeLayoutShuffle() }

    func selectProviders(_ value: ProviderSelection) {
        guard selection != value else { return }
        saveFrame()
        selection = value
        UserDefaults.standard.set(value.rawValue, forKey: ProviderSelection.defaultsKey)
        if isVisible { applyStyle() } else { syncTweetBubble() }
        NotificationCenter.default.post(name: .quotaGlanceProvidersChanged, object: nil)
    }

    func selectTravelFrequency(_ value: ProviderTravelFrequency) {
        travelFrequency = value
        UserDefaults.standard.set(value.rawValue, forKey: ProviderTravelFrequency.key)
        companions.setFrequency(value)
    }

    func selectPeekFrequency(_ value: ProviderTravelFrequency) {
        peekFrequency = value
        UserDefaults.standard.set(value.rawValue, forKey: "QuotaGlance.peekFrequency")
        companions.setPeekFrequency(value)
    }

    func selectDisplay(_ id: String) {
        saveFrame()
        displayID = id
        UserDefaults.standard.set(id, forKey: "QuotaGlance.providers.display")
        applyStyle(restoreFrame: false)
    }

    private var selectedScreen: NSScreen? {
        screens.first { Self.id(for: $0) == displayID } ?? panels.first?.screen ?? NSScreen.main ?? screens.first
    }

    private func applyStyle(restoreFrame: Bool = true) {
        guard let screen = selectedScreen else { return }
        detailPopover?.close()
        detailInteractions.removeAll()
        companions.stop()
        isVisible = true
        claude.suspendForCombinedDisplay()
        if style.isCompanion {
            panels.forEach { $0.orderOut(nil); $0.contentView = nil }
            companions.start(style: style, screen: screen, owner: self)
            syncTweetBubble()
            return
        }
        let frames: [NSRect]
        if style == .edgeWings {
            frames = ProviderDisplayGeometry.edgeFrames(screen: screen.frame, safeTop: screen.safeAreaInsets.top,
                                                        leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea, selection: selection)
        } else if style.isCorner {
            frames = ProviderDisplayGeometry.cornerFrames(style: style, screen: screen.frame, selection: selection)
        } else {
            let size = ProviderDisplayGeometry.size(style: style, providerCount: selection.providers.count)
            let visible = screen.visibleFrame
            let saved = restoreFrame ? UserDefaults.standard.string(forKey: frameKey).map(NSRectFromString) : nil
            let initial = ProviderDisplayGeometry.initialOrigin(style: style, in: visible, providerCount: selection.providers.count)
            let origin = saved.map { visible.intersects($0) ? $0.origin : initial } ?? initial
            frames = [ProviderDisplayGeometry.floatingFrame(size: size, origin: origin, in: visible)]
        }
        for index in frames.indices {
            let panel: ProviderPanel
            if index < panels.count { panel = panels[index] }
            else {
                panel = ProviderPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.identifier = NSUserInterfaceItemIdentifier("QuotaGlance.Providers.\(index)")
                panel.isReleasedWhenClosed = false
                panel.isRestorable = false
                panel.isFloatingPanel = true
                panel.hidesOnDeactivate = false
                panel.acceptsMouseMovedEvents = true
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.tabbingMode = .disallowed
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
                panels.append(panel)
            }
            let panelProvider: DisplayProvider? = style.isCorner || frames.count == 2 ? selection.providers[index] : nil
            panel.title = (panelProvider?.name ?? selection.windowTitle) + " · Quota Glance"
            panel.level = style == .edgeWings ? .statusBar : .floating
            panel.hasShadow = false
            panel.contentView = NSHostingView(rootView: ProviderDisplayView(controller: self, codex: .shared, claude: claude.model, panelProvider: panelProvider))
            panel.setFrame(frames[index], display: true)
            panel.orderFrontRegardless()
        }
        for panel in panels.dropFirst(frames.count) { panel.orderOut(nil) }
        syncTweetBubble()
    }

    @objc func toggleVisibility() {
        if isVisible {
            detailPopover?.close()
            saveFrame()
            isVisible = false
            shuffleTimer?.invalidate(); shuffleTimer = nil
            companions.stop()
            panels.forEach { $0.orderOut(nil); $0.contentView = nil }
            tweetPanel?.orderOut(nil)
            // Usage continues syncing to the phone when the desktop face is hidden.
        } else { applyStyle(); resumeLayoutShuffle() }
    }

    func show() { if !isVisible { applyStyle(); resumeLayoutShuffle() } }

    @objc func playNow() {
        guard style.isCompanion else { return }
        if style == .screenBuddies && isVisible { companions.wave() }
        else { applyStyle() }
    }

    func didDrag() {
        guard style.canDrag, let panel = panels.first else { return }
        if let screen = screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? panel.screen {
            displayID = Self.id(for: screen)
            UserDefaults.standard.set(displayID, forKey: "QuotaGlance.providers.display")
            panel.setFrame(ProviderDisplayGeometry.floatingFrame(size: ProviderDisplayGeometry.size(style: style, providerCount: selection.providers.count), origin: panel.frame.origin, in: screen.visibleFrame), display: true)
        }
        saveFrame()
        syncTweetBubble()
    }

    private var frameKey: String { "QuotaGlance.providers.creativeFrame." + style.rawValue + (selection == .both ? "" : "." + selection.rawValue) }
    private func saveFrame() {
        guard style.canDrag, let panel = panels.first, panel.isVisible else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: frameKey)
    }
    func stop() {
        detailPopover?.close()
        saveFrame()
        shuffleTimer?.invalidate(); shuffleTimer = nil
        isVisible = false
        companions.stop(); claude.model.stop()
    }
    @objc private func screensChanged() { objectWillChange.send(); if isVisible { applyStyle() } }

    @objc private func syncTweetBubble() {
        let summary = MenuBarSummaryModel.shared
        guard isVisible, selection.contains(.codex), let screen = selectedScreen,
              let tweet = summary.payload.newTweet else {
            tweetPanel?.orderOut(nil)
            return
        }
        if tweetPanel == nil {
            let panel = ProviderPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "New Tibo post"
            panel.identifier = NSUserInterfaceItemIdentifier("QuotaGlance.TiboBubble")
            panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            tweetPanel = panel
        }
        guard let panel = tweetPanel else { return }
        let anchor = panels.first(where: { $0.isVisible }) ?? companions.anchorPanel
        if shownTweetID != tweet.alertIdentity {
            panel.contentView = NSHostingView(rootView: ProviderTweetBubble(tweet: tweet, summary: summary))
            shownTweetID = tweet.alertIdentity
        }
        let visible = screen.visibleFrame
        let size = NSSize(width: 244, height: 108)
        let anchorFrame = anchor?.frame ?? NSRect(x: visible.midX + 122, y: visible.maxY - 58, width: 0, height: 58)
        let origin = style.isCorner
            ? NSPoint(x: anchorFrame.minX, y: anchorFrame.maxY + 10)
            : NSPoint(x: anchorFrame.minX - size.width - 8,
                      y: min(anchorFrame.maxY, visible.maxY) - size.height - 4)
        panel.level = anchor?.level ?? .floating
        panel.setFrame(ProviderDisplayGeometry.floatingFrame(size: size, origin: origin, in: visible), display: true)
        panel.orderFrontRegardless()
    }

    @objc func refresh() {
        NotificationCenter.default.post(name: .quotaGlanceRefresh, object: nil)
        claude.model.refresh()
    }

    func showDetails(for provider: DisplayProvider) {
        if detailPopover?.isShown == true, detailProvider == provider {
            detailPopover?.close()
            return
        }
        detailPopover?.close()
        let panel = panels.first { $0.isVisible && $0.title == provider.name + " · Quota Glance" }
            ?? panels.first { $0.isVisible }
        guard let panel, let anchor = panel.contentView else { return }
        let size = NSSize(width: 430, height: 647)
        let popover = NSPopover()
        popover.behavior = .transient
        // The pet can wave while the details are already usable. A fixed
        // viewport also avoids SwiftUI's repeated popup sizing at screen edges.
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView:
            ProviderDetailView(provider: provider, codex: .shared, claude: claude.model)
                .frame(width: size.width, height: size.height))
        popover.contentSize = size
        detailPopover = popover
        detailProvider = provider
        setDetailInteraction(nativeDetailInteractionID, active: true)
        popover.show(relativeTo: anchor.bounds, of: anchor,
                     preferredEdge: style.isCorner ? .maxY : style == .cornerBlade ? .minX : .minY)
    }

    func popoverDidClose(_ notification: Notification) {
        detailPopover = nil
        detailProvider = nil
        setDetailInteraction(nativeDetailInteractionID, active: false)
    }

    func contextMenu() -> NSMenu {
        detailPopover?.close()
        let menu = NSMenu()
        menu.addItem(withTitle: "Layout…", action: #selector(showSettings), keyEquivalent: "")
        if style.isCompanion { menu.addItem(withTitle: style == .screenBuddies ? "Wave" : "Show now", action: #selector(playNow), keyEquivalent: "") }
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "")
        menu.addItem(withTitle: "Hide widget", action: #selector(toggleVisibility), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.minSize = NSSize(width: 820, height: 600)
            window.title = "Quota Glance · Layout"
            window.identifier = NSUserInterfaceItemIdentifier("QuotaGlance.DisplayOptions")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ProviderDisplaySettings(controller: self, codex: .shared, claude: claude.model))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// The old standalone Claude view can still be opened by an old window session;
/// its only display control now leads to the shared layout picker.
struct ProviderDisplayStyleMenu: View {
    var body: some View {
        Button("Layout…") { ProviderDisplayController.shared.showSettings() }
    }
}

extension ProviderReading {
    @MainActor static func codex(_ model: MenuBarSummaryModel, at now: Date) -> Self {
        let week = model.weeklyWindow
        let deadline = model.payload.calendarDeadlineAt ?? week?.resetAt
        return Self(provider: .codex, usage: week?.usedPercent,
                    calendar: deadline.map { CodexService.calendarProgress(to: $0, at: now) }, deadline: deadline,
                    status: model.freshness == .live ? "Updated " + age(model.payload.lastSuccessfulAt, at: now) : model.payload.statusMessage,
                    live: model.freshness == .live, resetChance: model.payload.forecastPercent,
                    announcedResetAt: model.payload.expectedResetAt)
    }
    @MainActor static func claude(_ model: ClaudeUsageModel, at now: Date) -> Self {
        let week = model.snapshot?.weekly
        return Self(provider: .claude, usage: week?.hasEnded(at: now) == true ? nil : week?.usedPercent,
                    calendar: week?.calendarPercent(at: now), deadline: week?.resetAt,
                    status: model.status(at: now), live: model.isLive(at: now),
                    fiveHourUsage: model.snapshot?.fiveHour?.hasEnded(at: now) == true ? nil : model.snapshot?.fiveHour?.usedPercent,
                    fiveHourRemaining: remainingTime(until: model.snapshot?.fiveHour?.resetAt, at: now))
    }
    private static func age(_ date: Date?, at now: Date) -> String {
        guard let date else { return "never" }
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        return minutes == 0 ? "just now" : minutes < 60 ? "\(minutes)m ago" : "\(minutes / 60)h ago"
    }
}

private struct ProviderDisplayView: View {
    @ObservedObject var controller: ProviderDisplayController
    @ObservedObject var codex: MenuBarSummaryModel
    @ObservedObject var claude: ClaudeUsageModel
    let panelProvider: DisplayProvider?
    @State private var greetingProvider: DisplayProvider?
    @State private var greetingAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ProviderWidgetFace(style: controller.style,
                               readings: controller.selection.filter([.codex(codex, at: context.date), .claude(claude, at: context.date)]),
                               panelProvider: panelProvider, onSelect: select,
                               onDrag: controller.didDrag, menu: controller.contextMenu,
                               greetingProvider: greetingProvider, greetingAt: greetingAt)
        }
    }

    private func select(_ provider: DisplayProvider) {
        if controller.style != .edgeWings, !reduceMotion {
            greetingProvider = provider
            greetingAt = .now
        }
        controller.showDetails(for: provider)
    }
}

struct ProviderDetailView: View {
    let provider: DisplayProvider
    @ObservedObject var codex: MenuBarSummaryModel
    @ObservedObject var claude: ClaudeUsageModel
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let reading = provider == .codex ? ProviderReading.codex(codex, at: context.date) : ProviderReading.claude(claude, at: context.date)
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    ProviderPet(provider: provider, animated: false).frame(width: 29, height: 31)
                    Text(reading.name).font(.system(size: 18, weight: .semibold, design: .rounded))
                    Spacer()
                    Button { provider == .codex ? ProviderDisplayController.shared.refresh() : claude.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }.buttonStyle(.borderless).accessibilityLabel("Refresh usage")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 17) {
                        if provider == .codex, let announcedResetAt = reading.announcedResetAt {
                            announcedResetNotice(at: announcedResetAt, now: context.date)
                        }
                        HStack(spacing: 28) {
                            detailMetric("Weekly usage", value: ProviderReading.percent(reading.usage))
                            detailMetric("Week elapsed", value: ProviderReading.percent(reading.calendar, calendar: true))
                        }
                        if let date = reading.deadline {
                            Text("Week ends " + date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11))
                        }
                        Text(reading.status).font(.system(size: 11)).foregroundStyle(.secondary)
                        if provider == .claude {
                            Divider()
                            HStack {
                                detailMetric("Session usage", value: ProviderReading.percent(reading.fiveHourUsage))
                                Spacer()
                                detailMetric("Time left", value: reading.fiveHourRemaining ?? "—")
                            }
                            if let end = claude.snapshot?.fiveHour?.resetAt {
                                Text("Session renews " + end.formatted(date: .omitted, time: .shortened)).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            if let problem = claude.problem { Text(problem).font(.system(size: 11)).foregroundStyle(.secondary) }
                            Button(claude.needsConnection ? "Connect Claude…" : "Manage sign-in…", action: claude.connect)
                            Divider()
                            ProviderClaudeActivity(model: claude)
                        } else {
                            HStack {
                                Text("Reset " + ProviderReading.percent(codex.payload.forecastPercent))
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(ProviderPalette.green)
                                Spacer()
                                Button("Calculator…") { NotificationCenter.default.post(name: .quotaGlanceOpenCodexResetCalculator, object: nil) }
                            }
                            Divider()
                            QuotaPostsView(posts: codex.payload.tweets.map {
                                .init(id: $0.id, date: $0.date, text: $0.text, reply: $0.inReplyTo, url: $0.url, isReset: $0.isResetOriented)
                            })
                            Divider()
                            if let model = ProviderAppRuntime.current?.model { ProviderCodexActivity(model: model) }
                        }
                    }.padding(.trailing, 3)
                }.frame(maxHeight: 560)
            }.padding(20).frame(width: 430, alignment: .leading)
                .preferredColorScheme(.dark)
        }
    }
    private func detailMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func announcedResetNotice(at expectedAt: Date, now: Date) -> some View {
        let delayed = expectedAt <= now
        return HStack(alignment: .center, spacing: 11) {
            Image(systemName: delayed ? "clock.badge.exclamationmark" : "clock.arrow.circlepath")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 25)
            VStack(alignment: .leading, spacing: 3) {
                Text(delayed ? "Reset delayed" : "Reset announced")
                    .font(.system(size: 12, weight: .semibold))
                Text("Expected " + expectedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(delayed ? "Waiting" : ProviderReading.remainingTime(until: expectedAt, at: now) ?? "—")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(ProviderPalette.amber)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(ProviderPalette.amber.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ProviderPalette.amber.opacity(0.24), lineWidth: 1))
    }
}

private struct ProviderDisplaySettings: View {
    @ObservedObject var controller: ProviderDisplayController
    @ObservedObject var codex: MenuBarSummaryModel
    @ObservedObject var claude: ClaudeUsageModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var browsingGroup: ProviderLayoutGroup = .floating
    @State private var showingResetOptions = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let readings = controller.selection.filter([.codex(codex, at: context.date), .claude(claude, at: context.date)])
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(showingResetOptions ? "Reset celebrations" : "Layouts").font(.system(size: 23, weight: .semibold, design: .rounded))
                        Text("Active: " + controller.style.title(for: controller.selection)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if controller.style.isCompanion {
                        Button(controller.style == .screenBuddies ? "Wave now" : "Show now", action: controller.playNow)
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
                HStack(spacing: 12) {
                    Text("Show").font(.system(size: 12, weight: .medium))
                    Picker("Providers", selection: Binding(get: { controller.selection }, set: controller.selectProviders)) {
                        ForEach(ProviderSelection.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 252)
                    Spacer()
                }
                if !showingResetOptions { layoutShuffleControls(at: context.date) }
                Divider()
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 6) {
                        ForEach(ProviderLayoutGroup.allCases) { group in
                            Button { browsingGroup = group; showingResetOptions = false } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: group.symbol).frame(width: 18)
                                    Text(group.title)
                                    Spacer(minLength: 3)
                                    Text("\(group.styles.count)").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                .font(.system(size: 12, weight: !showingResetOptions && browsingGroup == group ? .semibold : .regular))
                                .padding(.horizontal, 11).frame(height: 37)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(!showingResetOptions && browsingGroup == group ? 0.09 : 0)))
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        Divider().padding(.vertical, 6)
                        Button { showingResetOptions = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "party.popper").frame(width: 18)
                                Text("On reset")
                                Spacer()
                            }.font(.system(size: 12, weight: showingResetOptions ? .semibold : .regular))
                                .padding(.horizontal, 11).frame(height: 37)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(showingResetOptions ? 0.09 : 0)))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }.frame(width: 157).padding(.top, 3)
                    Divider()
                    ScrollView {
                        if showingResetOptions {
                            ProviderResetOptions().padding(.trailing, 4)
                        } else {
                          VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(browsingGroup.title).font(.system(size: 18, weight: .semibold, design: .rounded))
                                Text(browsingGroup.caption).font(.system(size: 11)).foregroundStyle(.secondary)
                            }.padding(.top, 4)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                                ForEach(browsingGroup.styles) { style in layoutCard(style, readings: readings) }
                            }.padding(2)
                          }
                        }
                    }
                }
                if !showingResetOptions && (controller.style.travelKind != nil || controller.style == .peekaboo) {
                    HStack {
                        Picker("Visits", selection: Binding(
                            get: { controller.style == .peekaboo ? controller.peekFrequency : controller.travelFrequency },
                            set: { controller.style == .peekaboo ? controller.selectPeekFrequency($0) : controller.selectTravelFrequency($0) }
                        )) {
                            ForEach(ProviderTravelFrequency.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).frame(maxWidth: 360)
                        Spacer()
                        Text(controller.style == .peekaboo ? "10-second visits · Click for stats" : "Drag to steer · Click for stats")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)).toggleStyle(.checkbox)
                    Spacer()
                    if controller.screens.count > 1 {
                        Picker("Display", selection: Binding(get: { controller.displayID }, set: controller.selectDisplay)) {
                            Text("Current").tag("")
                            ForEach(controller.screens, id: \.self) { Text($0.localizedName).tag(ProviderDisplayController.id(for: $0)) }
                        }.frame(maxWidth: 250)
                    }
                }.font(.system(size: 11))
                if let loginError { Text(loginError).font(.system(size: 10)).foregroundStyle(.secondary) }
                Text("Click a pet for details. Drag a floating view to move it.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(20).frame(minWidth: 820, minHeight: 578)
                .onAppear { browsingGroup = controller.style.group }
                .onChange(of: controller.style) { if !controller.layoutShuffle.isEnabled { browsingGroup = $0.group } }
        }
    }

    private func layoutShuffleControls(at now: Date) -> some View {
        HStack(spacing: 14) {
            Toggle(isOn: Binding(get: { controller.layoutShuffle.isEnabled }, set: controller.setLayoutShuffleEnabled)) {
                Label("Shuffle layouts", systemImage: "shuffle")
            }.toggleStyle(.switch).controlSize(.small)
            if controller.layoutShuffle.isEnabled {
                Picker("Change every", selection: Binding(get: { controller.layoutShuffle.interval }, set: controller.selectLayoutShuffleInterval)) {
                    ForEach(ProviderLayoutShuffleInterval.allCases) { Text($0.title).tag($0) }
                }.frame(width: 183).controlSize(.small)
                Spacer(minLength: 0)
                Group {
                    if !controller.isVisible { Text("Paused while hidden") }
                    else if let next = controller.layoutShuffle.nextChangeAt, next > now {
                        Text("Next in ") + Text(next, style: .relative)
                    } else { Text("After your interaction") }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                Button("Next", action: controller.nextShuffledLayout).controlSize(.small)
                    .disabled(!controller.isVisible).help("Switch to the next shuffled layout now")
            } else {
                Spacer()
                Text("A different view, on your schedule.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.font(.system(size: 12))
        .help("Shuffle visits every layout. Choosing a layout yourself turns Shuffle off.")
    }

    private func layoutCard(_ style: ProviderDisplayStyle, readings: [ProviderReading]) -> some View {
        let selected = controller.style == style
        let size = ProviderDisplayGeometry.size(style: style, providerCount: controller.selection.providers.count)
        let scale = min(214 / size.width, 92 / size.height, 1)
        return Button { controller.selectStyle(style) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(Color(red: 0.15, green: 0.20, blue: 0.23))
                    if style.isCorner {
                        ProviderCornerPreview(style: style, readings: readings).allowsHitTesting(false)
                    } else {
                        ProviderWidgetFace(style: style, readings: readings, animatePets: false)
                            .scaleEffect(scale).frame(width: 218, height: 102)
                            .allowsHitTesting(false)
                    }
                }.frame(height: 102).clipped()
                HStack {
                    Text(style.title(for: controller.selection)).font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer(minLength: 1)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.35))
                }
                Text(style.caption).font(.system(size: 9)).foregroundStyle(.secondary)
                    .lineLimit(2).frame(height: 25, alignment: .topLeading)
            }
            .padding(9)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(selected ? 0.07 : 0.025)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.08), lineWidth: 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(style.title(for: controller.selection) + (selected ? ", selected" : "") + ". " + style.caption)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = nil
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
