import AppKit
import SwiftUI

/// The outside rail is weekly usage. The seven small steps are the week clock.
/// The inner instrument is provider-specific: a reset forecast or session fuel.
struct ProviderPetWing: View {
    let reading: ProviderReading
    var animatePet = true
    var solo = false
    private var codex: Bool { reading.provider == .codex }
    private let quiet = Color(red: 0.61, green: 0.67, blue: 0.69)
    private let green = Color(red: 0.57, green: 0.91, blue: 0.69)
    private let amber = Color(red: 0.97, green: 0.77, blue: 0.46)

    var body: some View {
        HStack(spacing: 6) {
            if codex {
                pet
                weekly
                Spacer(minLength: 0)
                resetGauge
            } else {
                sessionGauge
                Spacer(minLength: 0)
                weekly
                pet
            }
        }
        .padding(.horizontal, 13)
        .padding(.bottom, 1)
        .frame(width: ProviderDisplayGeometry.edgeCellWidth, height: ProviderDisplayGeometry.edgeHeight)
        .background {
            // A low, local pool of the provider colour gives the pet its own seat.
            RadialGradient(colors: [reading.tint.opacity(0.13), .clear],
                           center: codex ? .leading : .trailing, startRadius: 0, endRadius: 130)
        }
        .overlay { rim.allowsHitTesting(false) }
    }

    private var pet: some View {
        ProviderPet(provider: reading.provider, animated: animatePet)
            .frame(width: 30, height: 32)
            .accessibilityHidden(true)
    }

    private var weekly: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(reading.name.uppercased())
                .font(.system(size: 7, weight: .bold, design: .rounded)).tracking(1)
                .foregroundStyle(reading.tint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(ProviderReading.percent(reading.usage))
                    .font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(Color(white: 0.96))
                Text("used").font(.system(size: 8, weight: .medium)).foregroundStyle(quiet)
            }.frame(height: 17)
            HStack(spacing: 4) {
                WeekSteps(value: reading.calendar).frame(width: 27, height: 3)
                Text(ProviderReading.percent(reading.calendar, calendar: true) + " wk")
                    .font(.system(size: 7, weight: .medium, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
            }.foregroundStyle(quiet)
            .help("Week elapsed: \(ProviderReading.percent(reading.calendar, calendar: true))")
        }.frame(width: 64, alignment: .leading)
    }

    private var resetGauge: some View {
        let countdown = reading.announcedResetCountdown(at: .now)
        let announced = countdown != nil
        let signal = announced ? amber : green
        return HStack(spacing: 5) {
            ZStack {
                Circle().trim(from: 0.10, to: 0.90)
                    .stroke(signal.opacity(0.16), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Circle().trim(from: 0.10, to: 0.10 + 0.80 * ProviderReading.fraction(reading.resetChance))
                    .stroke(signal, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Image(systemName: announced ? "clock" : "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .bold)).rotationEffect(.degrees(-90))
                    .foregroundStyle(signal)
            }.rotationEffect(.degrees(90)).frame(width: 21, height: 21)
            VStack(alignment: .leading, spacing: 1) {
                Text(announced && countdown != "Delayed" ? "RESET IN" : "RESET")
                    .font(.system(size: 6.5, weight: .bold)).tracking(0.7).foregroundStyle(signal.opacity(0.72))
                Text(countdown ?? ProviderReading.percent(reading.resetChance))
                    .font(.system(size: announced ? 12 : 14, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.78)
                    .foregroundStyle(signal)
            }
        }.frame(width: 78, height: 29)
            .help(announced
                  ? "Codex reset announced for \(reading.announcedResetAt?.formatted(date: .abbreviated, time: .shortened) ?? "unknown time"). Forecast: \(ProviderReading.percent(reading.resetChance))"
                  : "Codex reset forecast: \(ProviderReading.percent(reading.resetChance))")
    }

    private var sessionGauge: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(reading.fiveHourRemaining ?? "—")
                .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(amber)
            HStack(spacing: 4) {
                Image(systemName: "hourglass.bottomhalf.filled").font(.system(size: 6))
                Text(ProviderReading.percent(reading.fiveHourUsage) + " used")
                    .font(.system(size: 7, weight: .medium)).monospacedDigit()
            }.foregroundStyle(amber.opacity(0.72))
            GeometryReader { geo in
                Capsule().fill(amber.opacity(0.16))
                    .overlay(alignment: .leading) {
                        Capsule().fill(amber).frame(width: geo.size.width * ProviderReading.fraction(reading.fiveHourUsage))
                    }
            }.frame(height: 2)
        }.frame(width: 65)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 9).fill(amber.opacity(0.055)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(amber.opacity(0.10), lineWidth: 0.5))
            .help("Claude five-hour usage: \(ProviderReading.percent(reading.fiveHourUsage)); \(reading.fiveHourRemaining ?? "unknown time") left")
    }

    private var rim: some View {
        let progress = ProviderReading.fraction(reading.usage)
        return ZStack {
            WingRail(right: !codex, whole: solo).stroke(reading.tint.opacity(0.18), lineWidth: 1.7)
            if progress > 0 {
                WingRail(right: !codex, whole: solo).trim(from: 0, to: progress)
                    .stroke(reading.tint, style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
                    .shadow(color: reading.tint.opacity(0.5), radius: 3)
                WingRail(right: !codex, whole: solo).trim(from: max(0, progress - 0.002), to: progress)
                    .stroke(Color(white: 0.96), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
    }
}

private struct WingRail: Shape {
    let right: Bool
    var whole = false
    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = 1.5
        let radius: CGFloat = 13.5
        var path = Path()
        if whole {
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY - inset))
            path.addLine(to: CGPoint(x: radius + inset, y: rect.maxY - inset))
            path.addQuadCurve(to: CGPoint(x: inset, y: rect.maxY - radius - inset), control: CGPoint(x: inset, y: rect.maxY - inset))
            path.addLine(to: CGPoint(x: inset, y: inset))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: inset))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - radius - inset))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - radius - inset, y: rect.maxY - inset), control: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
            path.closeSubpath()
            return path
        }
        // Fill from the bottom seam, around the outside, and back to the top seam.
        path.move(to: CGPoint(x: rect.maxX - 8, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: radius + inset, y: rect.maxY - inset))
        path.addQuadCurve(to: CGPoint(x: inset, y: rect.maxY - radius - inset),
                          control: CGPoint(x: inset, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: inset, y: inset))
        path.addLine(to: CGPoint(x: rect.maxX - 8, y: inset))
        return right ? path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.width, ty: 0)) : path
    }
}

private struct WeekSteps: View {
    let value: Double?
    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<7) { day in
                GeometryReader { geo in
                    Capsule().fill(Color.white.opacity(0.13))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.56))
                                .frame(width: geo.size.width * min(1, max(0, ProviderReading.fraction(value) * 7 - CGFloat(day))))
                        }
                }
            }
        }
    }
}

/// Only these tiny views tick for the pets; quota data keeps its normal cadence.
struct ProviderPet: View {
    let provider: DisplayProvider
    let animated: Bool
    var greeting: Date? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if animated && !reduceMotion {
            TimelineView(.animation(minimumInterval: 0.20)) { context in
                appearance(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            appearance(at: 0)
        }
    }

    @ViewBuilder private func appearance(at time: TimeInterval) -> some View {
        let beat = Int(time * 5) % 40
        let blink = beat == 29
        let elapsed = greeting.map { time - $0.timeIntervalSinceReferenceDate } ?? 10
        let waving = elapsed >= 0 && elapsed < 1.6
        let waveFrame = max(0, Int(elapsed * 5)) % 4
        if provider == .codex, let frame = waving ? ProviderPetArt.codexWaveFrames[waveFrame] : ProviderPetArt.codexFrames[blink ? 1 : 0] {
            Image(nsImage: frame).resizable().interpolation(.high).scaledToFit()
                .offset(y: beat < 20 ? 0 : -0.7)
        } else if provider == .claude, let frame = ProviderPetArt.clawdFrames[waving ? [0, 2, 1, 2][waveFrame] : (blink ? 1 : 0)] {
            Image(nsImage: frame).resizable().interpolation(.high).scaledToFit()
                .rotationEffect(.degrees(waving ? sin(elapsed * 12) * 6 : 0), anchor: .bottom)
        } else {
            ProviderBrandMark(provider: provider).fill(provider.tint).padding(8)
        }
    }
}

enum ProviderPetArt {
    // The native preview renderer supplies its resource folder explicitly.
    static var previewResourceDirectory: URL?
    static let codexFrames: [NSImage?] = {
        let url = previewResourceDirectory?.appendingPathComponent("CodexPet.webp")
            ?? Bundle.main.url(forResource: "CodexPet", withExtension: "webp")
        guard let url, let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [nil, nil] }
        return [0, 1].map { column in
            guard let frame = cg.cropping(to: CGRect(x: column * 192, y: 0, width: 192, height: 208)) else { return nil }
            return NSImage(cgImage: frame, size: NSSize(width: 192, height: 208))
        }
    }()

    static let codexWaveFrames: [NSImage?] = {
        let url = previewResourceDirectory?.appendingPathComponent("CodexPet.webp")
            ?? Bundle.main.url(forResource: "CodexPet", withExtension: "webp")
        guard let url, let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return Array(repeating: nil, count: 4) }
        return (0..<4).map { column in
            guard let frame = cg.cropping(to: CGRect(x: column * 192, y: 3 * 208, width: 192, height: 208)) else { return nil }
            return NSImage(cgImage: frame, size: NSSize(width: 192, height: 208))
        }
    }()

    /// Unmodified frames 0 and 6 from Claude desktop's clawd-laptop.webm.
    /// The shared source viewport removes the animation's empty stage while
    /// preserving its original silhouette, colour, and wink movement.
    static let clawdFrames: [NSImage?] = ["ClawdIdle", "ClawdWink", "ClawdWave"].map { name in
        let url = previewResourceDirectory?.appendingPathComponent(name + ".png")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        guard let url, let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let frame = cg.cropping(to: CGRect(x: 736, y: 1050, width: 1200, height: 800)) else {
            return nil
        }
        return NSImage(cgImage: frame, size: NSSize(width: 1200, height: 800))
    }
}
