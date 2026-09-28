import SwiftUI
import UIKit

@MainActor
final class PhonePetCelebrationCoordinator: ObservableObject {
    struct Event: Identifiable {
        let id = UUID()
        let provider: DisplayProvider
        let beganAt = Date()
    }
    static let shared = PhonePetCelebrationCoordinator()
    static let enabledKey = "QuotaGlance.mobile.petCelebrations"
    @Published private(set) var event: Event?
    private var pending: [DisplayProvider] = []
    private var ending: Task<Void, Never>?

    func observe(previous: QuotaSnapshot, current: QuotaSnapshot) {
        guard UIApplication.shared.applicationState == .active,
              UserDefaults.standard.object(forKey: Self.enabledKey) == nil || UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
        pending.append(contentsOf: ProviderActivityDetector.resets(previous: previous, current: current))
        showNext()
    }
    func preview(_ provider: DisplayProvider) {
        ending?.cancel()
        pending = [provider]
        event = nil
        showNext()
    }
    private func showNext() {
        guard event == nil, !pending.isEmpty else { return }
        event = Event(provider: pending.removeFirst())
        ending = Task {
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            event = nil
            showNext()
        }
    }
}

struct PhonePetCelebrationOverlay: View {
    @ObservedObject private var coordinator = PhonePetCelebrationCoordinator.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        if let event = coordinator.event {
            GeometryReader { geometry in
                if reduceMotion {
                    Label("\(event.provider.name) refueled", systemImage: "sparkles")
                        .font(.headline).padding(20).background(.regularMaterial, in: Capsule())
                        .position(x: geometry.size.width / 2, y: 140)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: scenePhase != .active)) { context in
                        let time = max(0, context.date.timeIntervalSince(event.beganAt))
                        if event.provider == .codex { plane(time, size: geometry.size) }
                        else { pool(time, size: geometry.size) }
                    }
                }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private func plane(_ time: Double, size: CGSize) -> some View {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.32)
        let loop = min(1, max(0, (time - 1.3) / 2.4))
        let theta = loop * 2 * Double.pi
        let radius = min(68.0, size.width * 0.19)
        let x = time < 1.3 ? -90 + (center.x + 90) * time / 1.3
            : time < 3.7 ? center.x + radius * sin(theta) : center.x + (time - 3.7) * (size.width + 130) / 2.3
        let y = time < 1.3 || time >= 3.7 ? center.y + radius : center.y + radius * cos(theta)
        return ZStack {
            particles(time: time - 2.2, origin: center, splash: false)
            ZStack {
                Capsule().fill(Color(red: 0.3, green: 0.55, blue: 0.95)).frame(width: 92, height: 23)
                RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.6, green: 0.8, blue: 1)).frame(width: 76, height: 8).offset(x: -5, y: 15)
                RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.6, green: 0.8, blue: 1)).frame(width: 78, height: 8).offset(x: -5, y: -10)
                Capsule().fill(.white.opacity(0.65)).frame(width: 5, height: 39).offset(x: 46)
                    .scaleEffect(y: 0.5 + 0.5 * abs(sin(time * 24)))
                QuotaPetImage(provider: .codex, frame: Int(time * 6) % 4, waving: true)
                    .frame(width: 38, height: 43).offset(x: -8, y: -23)
            }
            .rotationEffect(.radians(time >= 1.3 && time < 3.7 ? -theta : -0.06))
            .position(x: x, y: y)
            if time > 3.2 {
                Text("Codex refueled.").font(.system(.title3, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10).background(.regularMaterial, in: Capsule())
                    .position(x: center.x, y: center.y + radius + 90)
                    .opacity(min(1, (time - 3.2) * 2))
            }
        }
    }

    private func pool(_ time: Double, size: CGSize) -> some View {
        let center = CGPoint(x: size.width * 0.61, y: size.height * 0.44)
        let jump = min(1, max(0, (time - 1.3) / 1.5))
        let runEnd = center.x - 80
        let x = time < 1.3 ? -40 + (runEnd + 40) * time / 1.3 : runEnd + 80 * jump
        let y = center.y - 40 - sin(jump * Double.pi) * 145 + (time < 1.3 ? sin(time * 24) * 4 : 0)
        return ZStack {
            Ellipse().fill(Color(red: 0.15, green: 0.55, blue: 0.69).opacity(0.93)).frame(width: 184, height: 57)
                .overlay(Ellipse().stroke(.white.opacity(0.5), lineWidth: 4)).position(center)
            ForEach(0..<11) { index in
                RoundedRectangle(cornerRadius: 3).fill(QuotaStyle.session)
                    .frame(width: 13, height: 9).rotationEffect(.degrees(Double(index * 29)))
                    .position(x: center.x - 67 + Double(index % 6) * 25, y: center.y - 8 + Double(index / 6) * 15)
            }
            if time < 2.8 {
                QuotaPetImage(provider: .claude, frame: Int(time * 8) % 4, waving: true)
                    .frame(width: 49, height: 51)
                    .rotationEffect(.degrees(jump * 360)).scaleEffect(1 - jump * 0.22)
                    .position(x: x, y: y)
            }
            particles(time: time - 2.8, origin: center, splash: true)
            if time > 3.4 {
                QuotaPetImage(provider: .claude, frame: Int(time * 5) % 4, waving: true)
                    .frame(width: 42, height: 44).position(x: center.x, y: center.y - 15)
                    .opacity(min(1, (time - 3.4) * 2))
                Text("Fresh tokens. Cannonball!").font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10).background(.regularMaterial, in: Capsule())
                    .position(x: size.width / 2, y: center.y + 69).opacity(min(1, (time - 3.4) * 2))
            }
        }
    }

    private func particles(time: Double, origin: CGPoint, splash: Bool) -> some View {
        Canvas { context, _ in
            guard time > 0, time < 3 else { return }
            for index in 0..<38 {
                let angle = Double(index) * 2.399963
                let speed = 50 + Double(index % 7) * 21
                let x = origin.x + cos(angle) * speed * time
                let y = origin.y - (70 + abs(sin(angle)) * speed) * time + 80 * time * time
                let opacity = max(0, 1 - time / 3)
                let colors: [Color] = splash ? [QuotaStyle.session, .cyan, .white] : [.blue, QuotaStyle.reset, QuotaStyle.session, .pink]
                var particle = context
                particle.translateBy(x: x, y: y)
                particle.rotate(by: .radians(time * Double(index % 5 + 1)))
                particle.fill(Path(roundedRect: CGRect(x: -3, y: -4, width: splash ? 6 : 5, height: splash ? 6 : 9), cornerRadius: 2),
                              with: .color(colors[index % colors.count].opacity(opacity)))
            }
        }
    }
}

struct PhonePetMotionSettings: View {
    @AppStorage(PhonePetCelebrationCoordinator.enabledKey) private var enabled = true
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section { Toggle("Celebrate fresh quotas", isOn: $enabled) }
            Section("Try a celebration") {
                Button("Codex · Loop-the-loop") { PhonePetCelebrationCoordinator.shared.preview(.codex) }
                Button("Claude · Token cannonball") { PhonePetCelebrationCoordinator.shared.preview(.claude) }
            }
            Section { Text("Pets react to usage updates. Reset celebrations play while the app is open. Reduce Motion keeps them still.").font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("Pet animations")
        .overlay { PhonePetCelebrationOverlay() }
    }
}
