import SwiftUI

/// The corner dial keeps all three readings inside one small instrument.
/// Its pet sits on the rim, leaving no separate badge hanging into the Dock.
struct ProviderCornerDial: View {
    let reading: ProviderReading
    let animated: Bool
    var greeting: Date?
    private var signal: Color { ProviderPalette.signal(reading.provider) }

    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.075, green: 0.115, blue: 0.14))
                .overlay(Circle().stroke(.white.opacity(0.07), lineWidth: 1))
                .frame(width: 96, height: 96)
                .position(x: 50, y: 60)
            ZStack {
                ring(reading.usage, tint: reading.tint, diameter: 94, width: 3)
                ring(reading.calendar, tint: .white.opacity(0.56), diameter: 84, width: 1, dotted: true)
                ring(reading.thirdValue, tint: signal, diameter: 74, width: 2)
                VStack(spacing: 0) {
                    Text(ProviderReading.percent(reading.usage))
                        .font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Text("Week " + ProviderReading.percent(reading.calendar, calendar: true))
                        .font(.system(size: 9, weight: .medium)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.64))
                        .lineLimit(1).minimumScaleFactor(0.9)
                    Text(reading.provider == .codex
                         ? "Reset " + ProviderReading.percent(reading.thirdValue)
                         : (reading.fiveHourRemaining?.replacingOccurrences(of: " ", with: "") ?? "—") + " " + ProviderReading.percent(reading.thirdValue))
                        .font(.system(size: 8.5, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(signal).lineLimit(1).minimumScaleFactor(0.85)
                }.frame(width: 66)
            }.frame(width: 96, height: 96).position(x: 50, y: 60)
            ProviderPet(provider: reading.provider, animated: animated, greeting: greeting)
                .frame(width: 28, height: 32)
                .position(x: reading.provider == .codex ? 22 : 78, y: 16)
        }.frame(width: ProviderDisplayGeometry.cornerWidth, height: 110)
    }

    private func ring(_ value: Double?, tint: Color, diameter: CGFloat, width: CGFloat, dotted: Bool = false) -> some View {
        let stroke = StrokeStyle(lineWidth: width, lineCap: .round, dash: dotted ? [1, 4] : [])
        return ZStack {
            Circle().stroke(tint.opacity(0.15), style: stroke)
            Circle().trim(from: 0, to: ProviderReading.fraction(value)).stroke(tint, style: stroke)
                .rotationEffect(.degrees(-90))
        }.frame(width: diameter, height: diameter)
    }
}

struct ProviderCornerPerch: View {
    let reading: ProviderReading
    let animated: Bool
    var greeting: Date?
    private var signal: Color { ProviderPalette.signal(reading.provider) }
    private var left: Bool { reading.provider == .codex }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 2) {
                if left { pet }
                VStack(alignment: left ? .leading : .trailing, spacing: 1) {
                    Text(reading.name.uppercased()).font(.system(size: 7.5, weight: .bold, design: .rounded)).tracking(0.4)
                        .foregroundStyle(reading.tint)
                    Text(ProviderReading.percent(reading.usage))
                        .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7).allowsTightening(true)
                }.frame(maxWidth: .infinity, alignment: left ? .leading : .trailing)
                if !left { pet }
            }.frame(height: 38)
            ProviderMiniRail(value: reading.usage, color: reading.tint)
            VStack(spacing: 5) {
                metric("Week", reading.calendar, .white.opacity(0.62), calendar: true)
                metric(reading.provider == .codex ? "Reset" : reading.fiveHourRemaining ?? "—", reading.thirdValue, signal)
            }
        }
        .padding(.horizontal, 7).padding(.top, 6).padding(.bottom, 8)
        .frame(width: ProviderDisplayGeometry.cornerWidth, height: 114)
        .foregroundStyle(.white)
        .background(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 13)
                .fill(Color(red: 0.075, green: 0.115, blue: 0.14))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(reading.tint.opacity(0.18), lineWidth: 0.8))
                .frame(height: 100)
        }
        .overlay(alignment: .bottom) {
            Capsule().fill(reading.tint.opacity(0.7)).frame(width: 80, height: 2).offset(y: -1)
        }
    }

    private var pet: some View {
        ProviderPet(provider: reading.provider, animated: animated, greeting: greeting).frame(width: 28, height: 32)
            .offset(y: -2)
    }

    private func metric(_ title: String, _ value: Double?, _ tint: Color, calendar: Bool = false) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title).font(.system(size: 9, weight: .medium)).lineLimit(1)
                Spacer(minLength: 2)
                Text(ProviderReading.percent(value, calendar: calendar))
                    .font(.system(size: 9, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            ProviderMiniRail(value: value, color: tint, segmented: calendar)
        }.foregroundStyle(tint)
    }
}

private struct CornerQuarter: Shape {
    var radius: CGFloat = 96
    var right = false
    var filled = false
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: 2, y: rect.height - 2)
        var path = Path()
        if filled {
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x, y: center.y - radius))
        }
        path.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        if filled { path.closeSubpath() }
        return right ? path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.width, ty: 0)) : path
    }
}

struct ProviderCornerArc: View {
    let reading: ProviderReading
    let animated: Bool
    var greeting: Date?
    private var right: Bool { reading.provider == .claude }
    private var signal: Color { ProviderPalette.signal(reading.provider) }
    var body: some View {
        ZStack(alignment: right ? .bottomTrailing : .bottomLeading) {
            CornerQuarter(radius: 96, right: right, filled: true).fill(Color(red: 0.075, green: 0.115, blue: 0.14))
            arc(reading.usage, radius: 96, tint: reading.tint, width: 3)
            arc(reading.calendar, radius: 89, tint: .white.opacity(0.60), width: 1)
            arc(reading.thirdValue, radius: 82, tint: signal, width: 2)
            VStack(alignment: right ? .trailing : .leading, spacing: 1) {
                Text(reading.name.uppercased()).font(.system(size: 7.5, weight: .bold, design: .rounded)).tracking(0.5)
                    .foregroundStyle(reading.tint)
                Text(ProviderReading.percent(reading.usage))
                    .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .frame(width: 58, alignment: right ? .trailing : .leading)
                Text("Week " + ProviderReading.percent(reading.calendar, calendar: true))
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.62))
                Text(reading.provider == .codex ? "Reset " + ProviderReading.percent(reading.thirdValue)
                     : (reading.fiveHourRemaining ?? "—") + " · " + ProviderReading.percent(reading.thirdValue))
                    .font(.system(size: 8.5, weight: .semibold)).monospacedDigit().foregroundStyle(signal)
                    .lineLimit(1).minimumScaleFactor(0.9)
            }.frame(width: 72, alignment: right ? .trailing : .leading)
                .padding(.bottom, 7).padding(right ? .trailing : .leading, 7)
            ProviderPet(provider: reading.provider, animated: animated, greeting: greeting)
                .frame(width: 28, height: 32)
                .position(x: right ? 26 : 74, y: 22)
        }.frame(width: ProviderDisplayGeometry.cornerWidth, height: 106)
    }
    private func arc(_ value: Double?, radius: CGFloat, tint: Color, width: CGFloat) -> some View {
        ZStack {
            CornerQuarter(radius: radius, right: right).stroke(tint.opacity(0.16), lineWidth: width)
            CornerQuarter(radius: radius, right: right).trim(from: 0, to: ProviderReading.fraction(value))
                .stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }
}

struct ProviderCornerPreview: View {
    let style: ProviderDisplayStyle
    let readings: [ProviderReading]
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.17)).frame(width: 76, height: 24)
            HStack(alignment: .bottom, spacing: 0) {
                if let codex = readings.first(where: { $0.provider == .codex }) { thumbnail(codex) }
                Spacer(minLength: 80)
                if let claude = readings.first(where: { $0.provider == .claude }) { thumbnail(claude) }
            }
        }.padding(.horizontal, 2).padding(.bottom, 2)
    }
    private func thumbnail(_ reading: ProviderReading) -> some View {
        let size = ProviderDisplayGeometry.size(style: style, providerCount: 1)
        let scale = min(66 / size.width, 80 / size.height)
        return ProviderWidgetFace(style: style, readings: [reading], animatePets: false)
            .scaleEffect(scale).frame(width: size.width * scale, height: size.height * scale)
    }
}
