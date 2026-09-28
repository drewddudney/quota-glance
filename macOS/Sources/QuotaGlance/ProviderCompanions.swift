import AppKit
import SwiftUI

enum ProviderCompanionGeometry {
    static func petFrame(provider: DisplayProvider, peek: Bool, in visible: NSRect) -> NSRect {
        let size = peek ? NSSize(width: 272, height: 116) : NSSize(width: 66, height: 98)
        let left = provider == .codex
        let y = visible.minY + visible.height * (left ? 0.58 : 0.40) - size.height / 2
        return NSRect(x: left ? visible.minX : visible.maxX - size.width,
                      y: min(visible.maxY - size.height, max(visible.minY, y)), width: size.width, height: size.height)
    }

}

@MainActor
final class ProviderCompanionPose: ObservableObject {
    @Published var revealed = false
    @Published var greeting: Date?
}

/// Small edge windows for buddies and visits; interactive travel has its own
/// moving window and runs a frame timer only during an active pass.
@MainActor
final class ProviderCompanionController {
    private var travel: ProviderTravelController?
    private var panels: [ProviderPanel] = []
    private var poses: [DisplayProvider: ProviderCompanionPose] = [:]
    private var cycle: Task<Void, Never>?
    private var peekRest: Task<Void, Never>?
    private var peekFrequency = ProviderTravelFrequency.often
    private var occupied: Set<DisplayProvider> = []
    private var generation = UUID()
    private weak var owner: ProviderDisplayController?
    var anchorPanel: NSPanel? { panels.first { $0.isVisible } ?? (travel?.panel?.isVisible == true ? travel?.panel : nil) }
    var isInteracting: Bool { !occupied.isEmpty || travel?.isInteracting == true }
    func setFrequency(_ value: ProviderTravelFrequency) { travel?.setFrequency(value) }
    func setPeekFrequency(_ value: ProviderTravelFrequency) {
        peekFrequency = value
        // Wake a hidden visit immediately; never dismiss an open stats popover.
        peekRest?.cancel()
    }

    func stop() {
        travel?.stop(); travel = nil
        generation = UUID()
        cycle?.cancel(); cycle = nil
        peekRest?.cancel(); peekRest = nil
        occupied.removeAll()
        for panel in panels { panel.contentView = nil; panel.close() }
        panels.removeAll(); poses.removeAll()
    }

    func start(style: ProviderDisplayStyle, screen: NSScreen, owner: ProviderDisplayController) {
        stop()
        self.owner = owner
        peekFrequency = owner.peekFrequency
        let token = generation
        if let kind = style.travelKind {
            travel = ProviderTravelController(kind: kind, screen: screen, owner: owner)
            travel?.start()
        } else if style == .screenBuddies {
            for provider in owner.selection.providers {
                let pair = makePet(provider: provider, peek: false, screen: screen, token: token)
                pair.1.revealed = true
                pair.1.greeting = .now
                pair.0.orderFrontRegardless()
            }
        } else {
            cycle = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.peekLoop(screen: screen, token: token)
                } catch { /* A mode change, Hide, display change, or quit cancels the visit. */ }
            }
        }
    }

    func wave() { poses.values.forEach { $0.greeting = .now } }

    private func makePanel(title: String, frame: NSRect) -> ProviderPanel {
        let panel = ProviderPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = title
        panel.identifier = NSUserInterfaceItemIdentifier("QuotaGlance.Companion.\(panels.count)")
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
        panels.append(panel)
        return panel
    }

    private func makePet(provider: DisplayProvider, peek: Bool, screen: NSScreen, token: UUID) -> (ProviderPanel, ProviderCompanionPose) {
        let pose = ProviderCompanionPose()
        poses[provider] = pose
        let panel = makePanel(title: provider.name + (peek ? " · Peekaboo" : " · Screen buddy"),
                              frame: ProviderCompanionGeometry.petFrame(provider: provider, peek: peek, in: screen.visibleFrame))
        panel.contentView = NSHostingView(rootView: ProviderCompanionScene(provider: provider, peek: peek, pose: pose,
            codex: .shared, claude: ClaudeBarController.shared.model, menu: { [weak owner] in owner?.contextMenu() ?? NSMenu() },
            onExpansion: { [weak self] expanded in
                guard let self, self.generation == token else { return }
                if expanded { self.occupied.insert(provider) } else { self.occupied.remove(provider) }
            }))
        return (panel, pose)
    }

    private func peekLoop(screen: NSScreen, token: UUID) async throws {
        let providers = owner?.selection.providers ?? [.codex, .claude]
        let pets = providers.map { makePet(provider: $0, peek: true, screen: screen, token: token) }
        var index = 0
        while !Task.isCancelled && generation == token {
            let visitStarted = ProcessInfo.processInfo.systemUptime
            let (panel, pose) = pets[index % pets.count]
            panel.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(120))
            pose.greeting = .now; pose.revealed = true
            try await Task.sleep(for: .seconds(10))
            // A person reading/clicking a popover owns its lifetime.
            while !occupied.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
            pose.revealed = false
            try await Task.sleep(for: .milliseconds(600))
            panel.orderOut(nil)
            index += 1
            let delay = peekFrequency.rest(after: ProcessInfo.processInfo.systemUptime - visitStarted)
            let rest = Task<Void, Never> { try? await Task.sleep(for: .seconds(delay)) }
            peekRest = rest
            await rest.value
            peekRest = nil
        }
    }


}

private struct ProviderCompanionScene: View {
    let provider: DisplayProvider
    let peek: Bool
    @ObservedObject var pose: ProviderCompanionPose
    @ObservedObject var codex: MenuBarSummaryModel
    @ObservedObject var claude: ClaudeUsageModel
    let menu: () -> NSMenu
    let onExpansion: (Bool) -> Void
    @State private var details = false
    @State private var selection: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let reading = provider == .codex ? ProviderReading.codex(codex, at: context.date) : ProviderReading.claude(claude, at: context.date)
            Group {
                if peek { ProviderPeekCard(reading: reading, left: provider == .codex, animated: true, greeting: pose.greeting) }
                else { ProviderHangingPet(reading: reading, left: provider == .codex, animated: true, greeting: pose.greeting) }
            }
            .overlay {
                ProviderInteraction(help: reading.help, canDrag: false, onClick: greet, menu: menu)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(provider.name + " pet. " + reading.help)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { greet() }
        }
        .offset(x: peek && !pose.revealed && !reduceMotion ? (provider == .codex ? -280 : 280) : 0)
        .opacity(peek && !pose.revealed && reduceMotion ? 0 : 1)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.52, dampingFraction: 0.82), value: pose.revealed)
        .clipped()
        .popover(isPresented: $details, arrowEdge: provider == .codex ? .trailing : .leading) {
            ProviderDetailView(provider: provider, codex: codex, claude: claude)
        }
        .onChange(of: details) { onExpansion($0) }
        .onDisappear { selection?.cancel(); onExpansion(false) }
        .preferredColorScheme(.dark)
    }
    private func greet() {
        selection?.cancel()
        pose.greeting = .now
        onExpansion(true)
        selection = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 450)) }
            catch { return }
            details = true
        }
    }
}
