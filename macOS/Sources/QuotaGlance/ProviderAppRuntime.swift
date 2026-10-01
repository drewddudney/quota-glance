import AppKit
import Combine
import SwiftUI

/// Data collection belongs to the app lifetime, independent of any widget window.
/// Closing a view must not interrupt polling, reset forecasts, or phone sync.
@MainActor
final class ProviderAppRuntime {
    static weak var current: ProviderAppRuntime?
    let model = DashboardModel()
    private var subscriptions = Set<AnyCancellable>()
    private var presentingEligibility = false

    init() {
        Self.current = self
        ProviderResetCelebrationController.shared.start(codex: model, claude: ClaudeBarController.shared.model)
        let center = NotificationCenter.default
        center.publisher(for: .quotaGlanceRefresh).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.model.refresh() }.store(in: &subscriptions)
        center.publisher(for: .quotaGlanceResetCalculatorChanged).receive(on: RunLoop.main)
            .sink { [weak self] notification in
                if let sources = notification.object as? [String] { self?.model.selectForecastSources(sources) }
            }.store(in: &subscriptions)
        center.publisher(for: .quotaGlanceBillingUpdated).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.model.refresh() }.store(in: &subscriptions)
        center.publisher(for: .quotaGlanceMenuInteraction).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.model.noteMenuInteraction() }.store(in: &subscriptions)
        center.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification).receive(on: RunLoop.main)
            .sink { [weak self] notification in
                let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
                if keys == nil || keys?.contains(ResetApplicability.cloudKey) == true {
                    self?.model.syncResetApplicabilityFromCloud()
                }
            }.store(in: &subscriptions)
        model.$resetApplicabilityQuestion.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.presentEligibilityIfNeeded() }.store(in: &subscriptions)
        center.publisher(for: .quotaGlanceProvidersChanged).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.presentEligibilityIfNeeded() }.store(in: &subscriptions)
    }

    private func presentEligibilityIfNeeded() {
        guard !presentingEligibility, ProviderSelection.current.contains(.codex),
              let question = model.resetApplicabilityQuestion else { return }
        presentingEligibility = true
        let alert = NSAlert()
        alert.messageText = "Does this reset apply to your account?"
        alert.informativeText = question.text
        alert.addButton(withTitle: "Yes, it applies")
        alert.addButton(withTitle: "No, not eligible")
        let answer = alert.runModal()
        model.answerResetApplicability(answer == .alertFirstButtonReturn)
        presentingEligibility = false
    }
}

/// The same quota tickets used by the desktop, without the retired dashboard's
/// token inventory, pace charts, and theme controls.
struct ProviderStatusPopover: View {
    @ObservedObject var controller: ProviderDisplayController
    @ObservedObject var codex: MenuBarSummaryModel
    @ObservedObject var claude: ClaudeUsageModel
    let onVisibility: () -> Void
    let onLayout: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let readings = controller.selection.filter([.codex(codex, at: context.date), .claude(claude, at: context.date)])
            VStack(spacing: 12) {
                HStack {
                    Text("Quota Glance").font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Button(action: controller.refresh) { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).help("Refresh quotas").accessibilityLabel("Refresh quotas")
                }
                ProviderWidgetFace(style: .stackedSlate, readings: readings)
                HStack {
                    Button(controller.isVisible ? "Hide widget" : "Show widget", action: onVisibility)
                    Spacer()
                    Button("Layout…", action: onLayout)
                }.controlSize(.small)
            }.padding(16).frame(width: 328)
        }
    }
}
