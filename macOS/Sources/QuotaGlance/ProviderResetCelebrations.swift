import AppKit
import Combine
import SwiftUI

@MainActor
final class ProviderResetCelebrationController: ObservableObject {
    static let shared = ProviderResetCelebrationController()
    @Published private(set) var codexAnimation = ProviderResetCelebrationController.saved(.codex)
    @Published private(set) var claudeAnimation = ProviderResetCelebrationController.saved(.claude)
    @Published private(set) var soundEnabled = ResetAutomationSettings.soundEnabled
    private var shuffle = ProviderResetShuffle()
    private var random = SystemRandomNumberGenerator()
    private let sound = ProviderResetAudioPlayer()
    private var subscriptions = Set<AnyCancellable>()
    private var detector = ProviderResetDetector()
    private var seen = UserDefaults.standard.stringArray(forKey: "QuotaGlance.resetCelebrations.seen") ?? []
    private var pending: [ProviderResetEvent] = []
    private var panel: NSPanel?
    private var finishTask: Task<Void, Never>?

    private static func key(_ provider: DisplayProvider) -> String { "QuotaGlance.resetCelebration." + provider.rawValue }
    private static func saved(_ provider: DisplayProvider) -> ProviderResetAnimation {
        UserDefaults.standard.string(forKey: key(provider)).flatMap(ProviderResetAnimation.init(rawValue:))
            ?? (provider == .codex ? .loopPlane : .tokenPool)
    }
    func animation(for provider: DisplayProvider) -> ProviderResetAnimation {
        provider == .codex ? codexAnimation : claudeAnimation
    }
    func select(_ animation: ProviderResetAnimation, for provider: DisplayProvider) {
        if provider == .codex { codexAnimation = animation } else { claudeAnimation = animation }
        UserDefaults.standard.set(animation.rawValue, forKey: Self.key(provider))
    }

    func setSoundEnabled(_ value: Bool) {
        soundEnabled = value
        UserDefaults.standard.set(value, forKey: ResetAutomationSettings.soundEnabledKey)
        if !value { sound.stop() }
    }

    func start(codex: DashboardModel, claude: ClaudeUsageModel) {
        guard subscriptions.isEmpty else { return }
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }
                let enabled = ResetAutomationSettings.soundEnabled
                if self.soundEnabled != enabled {
                    self.soundEnabled = enabled
                    if !enabled { self.sound.stop() }
                }
            }.store(in: &subscriptions)
        _ = detector.codex(completedAt: codex.resetLifecycle.completedAt, now: Date())
        codex.$resetLifecycle.receive(on: RunLoop.main).sink { [weak self] state in
            guard let self, let event = self.detector.codex(completedAt: state.completedAt, now: Date()) else { return }
            self.receive(event)
        }.store(in: &subscriptions)
        // Read after all @Published values have committed, including verified.
        claude.objectWillChange.debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self, weak claude] in
                guard let self, let claude,
                      let event = self.detector.claude(snapshot: claude.snapshot,
                                                       verified: claude.verified && claude.problem == nil, now: Date()) else { return }
                self.receive(event)
            }.store(in: &subscriptions)
        _ = detector.claude(snapshot: claude.snapshot, verified: claude.verified, now: Date())
    }

    private func receive(_ event: ProviderResetEvent) {
        guard !seen.contains(event.identity) else { return }
        seen = Array((seen + [event.identity]).suffix(40))
        UserDefaults.standard.set(seen, forKey: "QuotaGlance.resetCelebrations.seen")
        guard ProviderSelection.current.contains(event.provider), animation(for: event.provider) != .off else { return }
        pending.append(event)
        if panel == nil { playNext() }
    }

    func preview(_ provider: DisplayProvider) {
        guard animation(for: provider) != .off else { return }
        finishTask?.cancel()
        sound.stop()
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        play(ProviderResetEvent(provider: provider, identity: "preview", caption: provider.name + " is refilled"))
    }

    private func playNext() {
        while !pending.isEmpty {
            let event = pending.removeFirst()
            guard ProviderSelection.current.contains(event.provider), animation(for: event.provider) != .off else { continue }
            play(event)
            return
        }
    }

    private func play(_ event: ProviderResetEvent) {
        let displayID = ProviderDisplayController.shared.displayID
        guard let screen = NSScreen.screens.first(where: { ProviderDisplayController.id(for: $0) == displayID })
                ?? NSScreen.main ?? NSScreen.screens.first else { return }
        guard let animation = shuffle.resolve(animation(for: event.provider), for: event.provider, using: &random) else { return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if ResetAutomationSettings.soundEnabled { sound.prepare(animation, reducedMotion: reduced) }
        let overlay = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlay.title = event.provider.name + " reset celebration"
        overlay.isReleasedWhenClosed = false
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.hidesOnDeactivate = false
        overlay.level = .statusBar
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        overlay.contentView = NSHostingView(rootView: ProviderResetStage(
            animation: animation, provider: event.provider, caption: event.caption,
            bottomInset: max(24, screen.visibleFrame.minY - screen.frame.minY + 20),
            reducedMotion: reduced))
        panel = overlay
        overlay.orderFrontRegardless()
        if ResetAutomationSettings.soundEnabled { sound.play() }
        finishTask = Task { [weak self, weak overlay] in
            try? await Task.sleep(nanoseconds: UInt64((reduced ? 3 : animation.duration) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            overlay?.orderOut(nil)
            overlay?.contentView = nil
            self.sound.stop()
            self.panel = nil
            self.finishTask = nil
            self.playNext()
        }
    }
}

struct ProviderResetOptions: View {
    @ObservedObject private var celebrations = ProviderResetCelebrationController.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("A little refill ritual").font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Pick a celebration for each pet. It plays when a fresh quota is confirmed.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Toggle("Sound effects", isOn: Binding(get: { celebrations.soundEnabled }, set: celebrations.setSoundEnabled))
                .toggleStyle(.switch).controlSize(.small)
            ForEach(DisplayProvider.allCases) { provider in
                let animation = celebrations.animation(for: provider)
                HStack(alignment: .top, spacing: 16) {
                    ProviderResetThumbnail(animation: animation, provider: provider)
                        .frame(width: 152, height: 144).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(provider.name).font(.system(size: 17, weight: .semibold, design: .rounded))
                            Spacer()
                            Button { celebrations.preview(provider) } label: { Label("Preview", systemImage: "play.fill") }
                                .controlSize(.small).disabled(animation == .off)
                        }
                        Picker(provider.name + " reset animation", selection: Binding(
                            get: { celebrations.animation(for: provider) },
                            set: { celebrations.select($0, for: provider) })) {
                            ForEach(ProviderResetAnimation.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden()
                        Text(animation.caption).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(provider == .codex ? "When your Codex quota resets" : "When your Claude week or session resets")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }.padding(.vertical, 9)
                }
                if provider == .codex { Divider() }
            }
            Text("Plays on your selected display. Your clicks pass through. Respects Reduce Motion.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}
