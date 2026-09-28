import SwiftUI
import UIKit

/// A single palette for the phone and its Home Screen companions.
/// The system controls appearance; provider colours carry the same meaning in every size.
enum CompanionStyle {
    static let paper = adaptive(0xF6F5F0, 0x111820)
    static let surface = adaptive(0xEEF0EC, 0x1B252E)
    static let ink = adaptive(0x263237, 0xEFF2EE)
    static let secondary = adaptive(0x6B787A, 0x9BAAAF)
    static let line = adaptive(0xD7DEDA, 0x34434B)
    static let field = adaptive(0xE8ECE7, 0x243039)
    static let reset = adaptive(0x466E59, 0xA3C7A9)
    static let session = adaptive(0x9E6928, 0xE3B97A)
    static func tint(_ provider: DisplayProvider) -> Color {
        provider == .codex ? adaptive(0x496FC0, 0x90AFF3) : adaptive(0xAF6248, 0xE9A080)
    }
    static func wash(_ provider: DisplayProvider) -> Color {
        provider == .codex ? adaptive(0xE5EBF2, 0x202E40) : adaptive(0xF0E7DF, 0x342A27)
    }
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

/// The gaps make the allowance readable without a large filled surface.
/// A partly filled tick preserves the exact fraction of the reported percentage.
struct CompanionDial: View {
    let value: Double?
    let tint: Color
    var tickCount = 40
    var lineWidth: CGFloat = 7

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = max(0, min(size.width, size.height) / 2 - lineWidth / 2 - 2)
            let fraction = (MobileProviderReading.valid(value) ?? 0) / 100
            let step = 270 / Double(tickCount)
            for index in 0..<tickCount {
                let start = 135 + Double(index) * step + step * 0.18
                let length = step * 0.64
                var track = Path()
                track.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(start + length), clockwise: false)
                context.stroke(track, with: .color(tint.opacity(0.15)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                let progress = min(1, max(0, fraction * Double(tickCount) - Double(index)))
                if progress > 0 {
                    var fill = Path()
                    fill.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(start + length * progress), clockwise: false)
                    context.stroke(fill, with: .color(tint), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct CompanionMeter: View {
    let value: Double?
    let tint: Color
    var segments = 24
    var height: CGFloat = 4
    var body: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 2
            let width = max(0, (geometry.size.width - CGFloat(segments - 1) * gap) / CGFloat(segments))
            HStack(spacing: gap) {
                ForEach(0..<segments, id: \.self) { index in
                    let fraction = min(1, max(0, (MobileProviderReading.valid(value) ?? 0) / 100 * Double(segments) - Double(index)))
                    Rectangle().fill(tint.opacity(0.15))
                        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: width * fraction) }
                        .frame(width: width)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct CompanionPetDial: View {
    let reading: MobileProviderReading
    var frame = 0
    var waving = false
    var lineWidth: CGFloat = 7
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                CompanionDial(value: reading.usage, tint: CompanionStyle.tint(reading.provider), lineWidth: lineWidth)
                Ellipse().fill(CompanionStyle.tint(reading.provider).opacity(0.09))
                    .frame(width: side * 0.43, height: side * 0.06).offset(y: side * 0.26)
                QuotaPetImage(provider: reading.provider, frame: frame, waving: waving)
                    .frame(width: side * (reading.provider == .codex ? 0.47 : 0.51), height: side * 0.53)
                    .offset(y: -side * 0.015)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct CompanionDottedField: View {
    var body: some View {
        Canvas { context, size in
            for x in stride(from: 7.0, through: size.width, by: 14) {
                for y in stride(from: 7.0, through: size.height, by: 14) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(CompanionStyle.secondary.opacity(0.12)))
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
