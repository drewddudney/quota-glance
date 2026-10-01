import AudioToolbox
import SwiftUI
import UIKit

enum PhoneResetAnimation: String, CaseIterable, Identifiable {
    case shuffle, loopPlane, tokenPool, specialDelivery, bubblePop, off

    static let codexKey = "QuotaGlance.mobile.codexResetAnimation"
    static let claudeKey = "QuotaGlance.mobile.claudeResetAnimation"
    static let soundKey = "QuotaGlance.mobile.resetSound"
    static let performances: [Self] = [.loopPlane, .tokenPool, .specialDelivery, .bubblePop]

    var id: String { rawValue }
    var title: String {
        switch self {
        case .shuffle: "Shuffle"
        case .loopPlane: "Loop-the-loop"
        case .tokenPool: "Token cannonball"
        case .specialDelivery: "Special delivery"
        case .bubblePop: "Bubble pop"
        case .off: "Off"
        }
    }
    var subtitle: String {
        switch self {
        case .shuffle: "A different little adventure each time."
        case .loopPlane: "A pet pilot paints the sky with confetti."
        case .tokenPool: "A running jump into a fresh pool of tokens."
        case .specialDelivery: "A parachute drops a crate of possibilities."
        case .bubblePop: "One giant bubble, one very happy landing."
        case .off: "No reset scene for this pet."
        }
    }
    var impactAt: Double {
        switch self {
        case .loopPlane: 3.1
        case .tokenPool: 2.9
        case .specialDelivery: 3.2
        case .bubblePop: 3.3
        case .shuffle, .off: 0
        }
    }
    var soundName: String { rawValue }
    static func selected(for provider: DisplayProvider) -> Self {
        let key = provider == .codex ? codexKey : claudeKey
        return Self(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .shuffle
    }
}

@MainActor
final class PhonePetCelebrationCoordinator: ObservableObject {
    struct Event: Identifiable {
        let id = UUID()
        let provider: DisplayProvider
        let animation: PhoneResetAnimation
        let beganAt = Date()
    }
    static let shared = PhonePetCelebrationCoordinator()
    static let enabledKey = "QuotaGlance.mobile.petCelebrations"
    private static let lastResetKey = "QuotaGlance.mobile.lastPetReset"

    @Published private(set) var event: Event?
    private var pending: [DisplayProvider] = []
    private var bag: [DisplayProvider: [PhoneResetAnimation]] = [:]
    private var previousScene: [DisplayProvider: PhoneResetAnimation] = [:]
    private var ending: Task<Void, Never>?
    private var impact: Task<Void, Never>?

    func observe(previous: QuotaSnapshot, current: QuotaSnapshot) {
        guard UIApplication.shared.applicationState == .active,
              UserDefaults.standard.object(forKey: Self.enabledKey) == nil
                || UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
        for provider in ProviderActivityDetector.resets(previous: previous, current: current) {
            let anchor = provider == .codex
                ? current.usageWindowStart ?? current.calendarDeadlineAt ?? current.capturedAt
                : current.claude?.resetAt ?? current.capturedAt
            let identity = "\(provider.rawValue):\(Int(anchor.timeIntervalSince1970 / 3600))"
            let key = Self.lastResetKey + "." + provider.rawValue
            guard UserDefaults.standard.string(forKey: key) != identity else { continue }
            UserDefaults.standard.set(identity, forKey: key)
            pending.append(provider)
        }
        showNext()
    }

    func preview(_ provider: DisplayProvider) {
        ending?.cancel()
        impact?.cancel()
        pending = [provider]
        event = nil
        showNext()
    }

    private func resolve(_ provider: DisplayProvider) -> PhoneResetAnimation? {
        let selected = PhoneResetAnimation.selected(for: provider)
        guard selected != .off else { return nil }
        guard selected == .shuffle else { previousScene[provider] = selected; return selected }
        var choices = bag[provider] ?? []
        if choices.isEmpty { choices = PhoneResetAnimation.performances.shuffled() }
        if choices.count > 1, choices.first == previousScene[provider] {
            choices.swapAt(0, Int.random(in: 1..<choices.count))
        }
        let next = choices.removeFirst()
        bag[provider] = choices
        previousScene[provider] = next
        return next
    }

    private func showNext() {
        guard event == nil else { return }
        while !pending.isEmpty {
            let provider = pending.removeFirst()
            guard let animation = resolve(provider) else { continue }
            let playing = Event(provider: provider, animation: animation)
            event = playing
            impact = Task { [weak self] in
                try? await Task.sleep(for: .seconds(animation.impactAt))
                guard !Task.isCancelled, self?.event?.id == playing.id else { return }
                PhoneResetSound.play(animation)
            }
            ending = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6.4))
                guard !Task.isCancelled, self?.event?.id == playing.id else { return }
                self?.event = nil
                self?.showNext()
            }
            return
        }
    }
}

@MainActor
private enum PhoneResetSound {
    private static var sounds: [PhoneResetAnimation: SystemSoundID] = [:]

    static func play(_ animation: PhoneResetAnimation) {
        guard UIApplication.shared.applicationState == .active,
              UserDefaults.standard.object(forKey: PhoneResetAnimation.soundKey) == nil
                || UserDefaults.standard.bool(forKey: PhoneResetAnimation.soundKey) else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if let sound = sounds[animation] {
            AudioServicesPlaySystemSound(sound)
            return
        }
        guard let url = Bundle.main.url(forResource: "Reset-\(animation.soundName)", withExtension: "wav") else { return }
        var sound: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &sound) == noErr else { return }
        sounds[animation] = sound
        AudioServicesPlaySystemSound(sound)
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
                    Label("\(event.provider.name) quota restored", systemImage: "sparkles")
                        .font(.headline).padding(18)
                        .background(.regularMaterial, in: Capsule())
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.28)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: scenePhase != .active)) { timeline in
                        PhoneResetScene(event: event,
                            time: max(0, timeline.date.timeIntervalSince(event.beganAt)),
                            size: geometry.size)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct PhoneResetScene: View {
    let event: PhonePetCelebrationCoordinator.Event
    let time: Double
    let size: CGSize

    private var tint: Color { PhoneStyle.tint(event.provider) }
    private var center: CGPoint { CGPoint(x: size.width * 0.52, y: size.height * 0.31) }
    private var reveal: Double { clamp((time - 3.5) / 0.5) * clamp((6.4 - time) / 0.55) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch event.animation {
            case .loopPlane: plane
            case .tokenPool: pool
            case .specialDelivery: delivery
            case .bubblePop: bubble
            case .shuffle, .off: EmptyView()
            }
            if time > 3.5 {
                VStack(spacing: 2) {
                    Text(event.provider.name.uppercased() + " REFUELED")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(2.4)
                        .foregroundStyle(tint)
                    Text("Fresh quota, fresh start")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(PhoneStyle.ink)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(PhoneStyle.paper, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(tint.opacity(0.35), lineWidth: 1))
                .shadow(color: tint.opacity(0.18), radius: 22, y: 8)
                .position(x: size.width / 2, y: center.y + 165)
                .opacity(reveal)
                .offset(y: (1 - reveal) * 12)
            }
        }
        .frame(width: size.width, height: size.height)
        .opacity(clamp((6.4 - time) / 0.4))
    }

    private var plane: some View {
        let radius = min(79.0, size.width * 0.2)
        let loop = clamp((time - 1.25) / 2.2)
        let angle = loop * 2 * Double.pi
        let x = time < 1.25 ? -115 + (center.x + 115) * time / 1.25
            : time < 3.45 ? center.x + radius * sin(angle)
            : center.x + (time - 3.45) * (size.width + 160) / 2.3
        let y = time < 1.25 ? center.y + radius
            : time < 3.45 ? center.y + radius * cos(angle)
            : center.y + radius - (time - 3.45) * 38
        return ZStack(alignment: .topLeading) {
            confetti(at: CGPoint(x: center.x, y: center.y + 13), onset: 3.0, width: 285)
            Canvas { context, _ in
                guard time > 0.3 else { return }
                var trail = Path()
                let end = min(time, 3.5)
                for step in 0..<55 {
                    let sample = end - Double(step) * 0.045
                    guard sample >= 0 else { break }
                    let pose = flightPose(sample, center: center, radius: radius, width: size.width)
                    if step == 0 { trail.move(to: pose) } else { trail.addLine(to: pose) }
                }
                context.stroke(trail, with: .color(tint.opacity(0.25)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            ZStack {
                sprite("ResetPlane", width: 166, height: 112)
                QuotaPetImage(provider: event.provider, frame: Int(time * 7) % 4, waving: true)
                    .frame(width: 39, height: 42).offset(x: -7, y: -18)
            }
            .rotationEffect(.radians(time >= 1.25 && time < 3.45 ? -angle : -0.06))
            .position(x: x, y: y)
        }
    }

    private var pool: some View {
        let splashAt = 2.9
        let run = clamp(time / 1.35)
        let jump = clamp((time - 1.35) / 1.55)
        let water = CGPoint(x: size.width * 0.65, y: center.y + 48)
        let petX = time < 1.35 ? -44 + (water.x - 95 + 44) * run : water.x - 95 + 95 * jump
        let petY = water.y - 55 - (time < 1.35 ? abs(sin(time * 20)) * 8 : sin(jump * .pi) * 135)
        return ZStack(alignment: .topLeading) {
            sprite("ResetTokenPool", width: 286, height: 186)
                .position(x: water.x, y: water.y + 23)
            if time < splashAt {
                QuotaPetImage(provider: event.provider, frame: Int(time * 8) % 4, waving: true)
                    .frame(width: 65, height: 70)
                    .rotationEffect(.degrees(time < 1.35 ? sin(time * 20) * 7 : jump * 345))
                    .position(x: petX, y: petY)
            }
            sprite("ResetSplash", width: 254, height: 174)
                .position(x: water.x, y: water.y - 60)
                .scaleEffect(0.62 + 0.48 * clamp((time - splashAt) / 0.46))
                .opacity(clamp((time - splashAt) / 0.11) * clamp((4.2 - time) / 0.66))
            if time >= 3.45 {
                QuotaPetImage(provider: event.provider, frame: Int(time * 6) % 4, waving: true)
                    .frame(width: 61, height: 65)
                    .position(x: water.x, y: water.y - 36 - 18 * clamp((time - 3.45) / 0.45))
                    .opacity(clamp((time - 3.45) / 0.35))
            }
        }
    }

    private var delivery: some View {
        let fall = ease(clamp(time / 3.2))
        let landing = CGPoint(x: center.x, y: center.y + 75)
        let y = -145 + (landing.y + 145) * fall
        let sway = sin(time * 3) * (1 - fall) * 24
        return ZStack(alignment: .topLeading) {
            confetti(at: landing, onset: 3.2, width: 235)
            ZStack {
                sprite("ResetParachute", width: 190, height: 271)
                QuotaPetImage(provider: event.provider, frame: Int(time * 6) % 4, waving: true)
                    .frame(width: 56, height: 60).offset(y: 77)
                    .opacity(time < 4.0 ? 1 : 0)
            }
            .position(x: landing.x + sway, y: y - 75)
            .opacity(time < 4.0 ? 1 : clamp((4.7 - time) / 0.7))
            if time > 3.2 {
                QuotaPetImage(provider: event.provider, frame: Int(time * 6) % 4, waving: true)
                    .frame(width: 61, height: 65)
                    .position(x: landing.x + 77, y: landing.y - 30)
                    .opacity(clamp((time - 4.0) / 0.45))
            }
        }
    }

    private var bubble: some View {
        let rise = ease(clamp(time / 3.3))
        let bubbleCenter = CGPoint(x: center.x + sin(time * 3) * 27,
                                   y: size.height + 85 - (size.height - center.y + 105) * rise)
        let popped = time >= 3.3
        return ZStack(alignment: .topLeading) {
            confetti(at: center, onset: 3.3, width: 268)
            if !popped {
                ZStack {
                    sprite("ResetBubble", width: 191, height: 191)
                    QuotaPetImage(provider: event.provider, frame: Int(time * 7) % 4, waving: true)
                        .frame(width: 79, height: 83)
                }
                    .scaleEffect(0.76 + 0.24 * rise + 0.05 * sin(time * 7))
                    .position(bubbleCenter)
            } else {
                QuotaPetImage(provider: event.provider, frame: Int(time * 6) % 4, waving: true)
                    .frame(width: 82, height: 86)
                    .rotationEffect(.degrees(12 * sin((time - 3.3) * 4)))
                    .position(x: center.x, y: center.y + 45 - 25 * ease(clamp((time - 3.3) / 0.6)))
                    .opacity(clamp((time - 3.3) / 0.25))
            }
        }
    }

    private func flightPose(_ t: Double, center: CGPoint, radius: Double, width: Double) -> CGPoint {
        let loop = clamp((t - 1.25) / 2.2)
        if t < 1.25 { return CGPoint(x: -115 + (center.x + 115) * t / 1.25, y: center.y + radius) }
        if t < 3.45 { return CGPoint(x: center.x + radius * sin(loop * 2 * .pi), y: center.y + radius * cos(loop * 2 * .pi)) }
        return CGPoint(x: center.x + (t - 3.45) * (width + 160) / 2.3, y: center.y + radius - (t - 3.45) * 38)
    }

    private func sprite(_ name: String, width: CGFloat, height: CGFloat) -> some View {
        Image(name).resizable().interpolation(.none).scaledToFit().frame(width: width, height: height)
    }

    private func confetti(at point: CGPoint, onset: Double, width: CGFloat) -> some View {
        let elapsed = time - onset
        return sprite("ResetConfetti", width: width, height: width)
            .position(point)
            .scaleEffect(0.42 + 0.65 * clamp(elapsed / 0.7))
            .opacity(clamp(elapsed / 0.15) * clamp((2.25 - elapsed) / 0.9))
    }

    private func clamp(_ value: Double) -> Double { max(0, min(1, value)) }
    private func ease(_ value: Double) -> Double { value * value * (3 - 2 * value) }
}

struct PhonePetMotionSettings: View {
    @AppStorage(PhonePetCelebrationCoordinator.enabledKey) private var enabled = true
    @AppStorage(PhoneResetAnimation.codexKey) private var codexChoice = PhoneResetAnimation.shuffle.rawValue
    @AppStorage(PhoneResetAnimation.claudeKey) private var claudeChoice = PhoneResetAnimation.shuffle.rawValue
    @AppStorage(PhoneResetAnimation.soundKey) private var soundEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Celebrate fresh quotas", isOn: $enabled)
                Toggle("Sound & haptics", isOn: $soundEnabled).disabled(!enabled)
            }
            Section("Choose each pet’s scene") {
                Picker("Codex", selection: $codexChoice) {
                    ForEach(PhoneResetAnimation.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Claude", selection: $claudeChoice) {
                    ForEach(PhoneResetAnimation.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }
            Section("Try it") {
                Button("Play Codex scene") { PhonePetCelebrationCoordinator.shared.preview(.codex) }
                    .disabled(!enabled || codexChoice == PhoneResetAnimation.off.rawValue)
                Button("Play Claude scene") { PhonePetCelebrationCoordinator.shared.preview(.claude) }
                    .disabled(!enabled || claudeChoice == PhoneResetAnimation.off.rawValue)
            }
            Section { Text("Scenes play once when a fresh quota is detected while the app is open. Reduce Motion shows a quiet message.")
                .font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("Pet animations")
        .overlay { PhonePetCelebrationOverlay() }
    }
}
