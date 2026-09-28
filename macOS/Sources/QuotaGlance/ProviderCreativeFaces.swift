import SwiftUI

enum ProviderPalette {
    static let ink = Color(red: 0.12, green: 0.17, blue: 0.19)
    static let green = Color(red: 0.57, green: 0.91, blue: 0.69)
    static let amber = Color(red: 0.97, green: 0.77, blue: 0.46)
    static func signal(_ provider: DisplayProvider, dark: Bool = true) -> Color {
        if provider == .codex { return dark ? green : Color(red: 0.18, green: 0.43, blue: 0.31) }
        return dark ? amber : Color(red: 0.54, green: 0.33, blue: 0.13)
    }
}

struct ProviderMiniRail: View {
    let value: Double?
    let color: Color
    var segmented = false
    var body: some View {
        GeometryReader { geo in
            if segmented {
                HStack(spacing: 2) {
                    ForEach(0..<7) { index in
                        Capsule().fill(color.opacity(0.14)).overlay(alignment: .leading) {
                            Capsule().fill(color).frame(width: max(0, (geo.size.width - 12) / 7)
                                * min(1, max(0, ProviderReading.fraction(value) * 7 - CGFloat(index))))
                        }
                    }
                }
            } else {
                Capsule().fill(color.opacity(0.16)).overlay(alignment: .leading) {
                    Capsule().fill(color).frame(width: geo.size.width * ProviderReading.fraction(value))
                }
            }
        }.frame(height: 3)
    }
}

struct ProviderOrbitDial: View {
    let reading: ProviderReading
    let animated: Bool
    var greeting: Date?
    private var signal: Color { ProviderPalette.signal(reading.provider) }
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Color(red: 0.08, green: 0.13, blue: 0.16))
                    .overlay(Circle().stroke(Color.white.opacity(0.09), lineWidth: 1))
                    .frame(width: 112, height: 112)
                Circle().stroke(reading.tint.opacity(0.16), lineWidth: 5)
                Circle().trim(from: 0, to: ProviderReading.fraction(reading.usage))
                    .stroke(reading.tint, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                Circle().stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 2, dash: [1, 5]))
                    .padding(8)
                Circle().trim(from: 0, to: ProviderReading.fraction(reading.calendar))
                    .stroke(Color.white.opacity(0.65), style: StrokeStyle(lineWidth: 2, dash: [1, 5]))
                    .rotationEffect(.degrees(-90)).padding(8)
                VStack(spacing: 1) {
                    Text(reading.name.uppercased()).font(.system(size: 8, weight: .bold, design: .rounded)).tracking(1)
                        .foregroundStyle(reading.tint)
                    Text(ProviderReading.percent(reading.usage)).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Color.white)
                    Text("used · " + ProviderReading.percent(reading.calendar, calendar: true) + " week")
                        .font(.system(size: 8, weight: .medium)).foregroundStyle(Color.white.opacity(0.55))
                }.padding(.top, 8)
                ProviderPet(provider: reading.provider, animated: animated, greeting: greeting)
                    .frame(width: 38, height: 41)
                    .offset(x: reading.provider == .codex ? -38 : 38, y: -47)
            }.frame(width: 118, height: 118)
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: reading.provider == .codex ? "arrow.counterclockwise" : "hourglass")
                        .font(.system(size: 8, weight: .semibold))
                    Text(reading.provider == .codex ? "Reset " + ProviderReading.percent(reading.thirdValue) : (reading.fiveHourRemaining ?? "—") + " · " + ProviderReading.percent(reading.thirdValue))
                        .font(.system(size: 9, weight: .semibold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                ProviderMiniRail(value: reading.thirdValue, color: signal).frame(width: 82)
            }.foregroundStyle(signal).frame(width: 110, height: 28)
                .background(Capsule().fill(Color(red: 0.09, green: 0.15, blue: 0.17)))
                .overlay(Capsule().stroke(signal.opacity(0.22), lineWidth: 0.8)).offset(y: -2)
        }.frame(width: 140, height: 166).padding(.top, 7)
    }
}

struct TicketShape: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            let notch: CGFloat = 5
            p.move(to: CGPoint(x: 12, y: 0))
            p.addLine(to: CGPoint(x: r.maxX - 12, y: 0))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: 12), control: CGPoint(x: r.maxX, y: 0))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY - notch))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY + notch), control: CGPoint(x: r.maxX - notch * 2, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 12))
            p.addQuadCurve(to: CGPoint(x: r.maxX - 12, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: 12, y: r.maxY))
            p.addQuadCurve(to: CGPoint(x: 0, y: r.maxY - 12), control: CGPoint(x: 0, y: r.maxY))
            p.addLine(to: CGPoint(x: 0, y: r.midY + notch))
            p.addQuadCurve(to: CGPoint(x: 0, y: r.midY - notch), control: CGPoint(x: notch * 2, y: r.midY))
            p.addLine(to: CGPoint(x: 0, y: 12))
            p.addQuadCurve(to: CGPoint(x: 12, y: 0), control: .zero)
            p.closeSubpath()
        }
    }
}

struct ProviderTicket: View {
    let reading: ProviderReading
    let animated: Bool
    var greeting: Date?
    private var ink: Color { ProviderPalette.ink }
    var body: some View {
        HStack(spacing: 9) {
            ProviderPet(provider: reading.provider, animated: animated, greeting: greeting).frame(width: 37, height: 45)
            VStack(alignment: .leading, spacing: 1) {
                Text(reading.name.uppercased()).font(.system(size: 8, weight: .bold, design: .rounded)).tracking(0.8)
                Text(ProviderReading.percent(reading.usage)).font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
                ProviderMiniRail(value: reading.usage, color: reading.provider == .codex ? Color(red: 0.25, green: 0.53, blue: 0.66) : Color(red: 0.69, green: 0.34, blue: 0.21))
            }.frame(width: 58, alignment: .leading)
            Rectangle().fill(ink.opacity(0.13)).frame(width: 1, height: 41)
            VStack(spacing: 6) {
                metric("Week", reading.calendar, color: ink.opacity(0.58), calendar: true)
                metric(reading.provider == .codex ? "Reset" : reading.fiveHourRemaining ?? "—", reading.thirdValue,
                       color: ProviderPalette.signal(reading.provider, dark: false))
            }.frame(width: 115)
        }.padding(.horizontal, 14).frame(width: 276, height: 68)
            .foregroundStyle(ink)
            .background(TicketShape().fill(reading.provider == .codex ? Color(red: 0.86, green: 0.94, blue: 0.94) : Color(red: 0.98, green: 0.86, blue: 0.73)))
            .overlay(TicketShape().stroke(Color.white.opacity(0.38), lineWidth: 1))
    }
    private func metric(_ title: String, _ value: Double?, color: Color, calendar: Bool = false) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(title).font(.system(size: 8, weight: .medium))
                Spacer(minLength: 2)
                Text(ProviderReading.percent(value, calendar: calendar)).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            ProviderMiniRail(value: value, color: color, segmented: calendar)
        }.foregroundStyle(color)
    }
}

struct ProviderArcadeColumn: View {
    let reading: ProviderReading
    let animated: Bool
    var greeting: Date?
    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                ProviderPet(provider: reading.provider, animated: animated, greeting: greeting).frame(width: 33, height: 34)
                Text(reading.name.uppercased()).font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(0.4)
                    .foregroundStyle(reading.tint)
            }.frame(height: 34)
            cell("USED", reading.usage, reading.tint, large: true)
            cell("WEEK", reading.calendar, Color.white.opacity(0.63), calendar: true)
            cell(reading.provider == .codex ? "RESET" : reading.fiveHourRemaining ?? "—", reading.thirdValue, ProviderPalette.signal(reading.provider))
        }.padding(.horizontal, 6).frame(width: 108)
    }
    private func cell(_ title: String, _ value: Double?, _ color: Color, large: Bool = false, calendar: Bool = false) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 6.5, weight: .semibold, design: .monospaced)).tracking(0.5).lineLimit(1)
                Text(ProviderReading.percent(value, calendar: calendar)).font(.system(size: large ? 22 : 16, weight: .semibold, design: .monospaced)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
            GeometryReader { geo in
                VStack(spacing: 2) {
                    ForEach((0..<8).reversed(), id: \.self) { tick in
                        Rectangle().fill(ProviderReading.fraction(value) * 8 > CGFloat(tick) ? color : color.opacity(0.14))
                    }
                }.frame(height: geo.size.height)
            }.frame(width: 5, height: 26)
        }.padding(.horizontal, 8).frame(height: large ? 46 : 38)
            .foregroundStyle(color)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.24)))
    }
}

struct BookmarkShape: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 14, y: 0))
            p.addLine(to: CGPoint(x: r.maxX, y: 0))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY - 15))
            p.addLine(to: CGPoint(x: 0, y: r.maxY))
            p.addLine(to: CGPoint(x: 0, y: 14))
            p.addQuadCurve(to: CGPoint(x: 14, y: 0), control: .zero)
            p.closeSubpath()
        }
    }
}

struct ProviderBookmark: View {
    let reading: ProviderReading
    let animated: Bool
    var greeting: Date?
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 4) {
                ProviderPet(provider: reading.provider, animated: animated, greeting: greeting)
                    .frame(width: 46, height: 49).rotationEffect(.degrees(-9))
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(reading.name.uppercased()).font(.system(size: 7, weight: .bold)).tracking(0.8)
                    Text(ProviderReading.percent(reading.usage)).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.75)
                }.foregroundStyle(reading.tint)
            }
            ProviderMiniRail(value: reading.usage, color: reading.tint).frame(width: 92)
            HStack(spacing: 4) {
                Text("wk " + ProviderReading.percent(reading.calendar, calendar: true)).font(.system(size: 8, weight: .medium)).monospacedDigit()
                ProviderMiniRail(value: reading.calendar, color: Color.white.opacity(0.5), segmented: true)
            }.foregroundStyle(Color.white.opacity(0.55)).frame(width: 92)
            HStack(spacing: 4) {
                Text(reading.provider == .codex ? "Reset" : reading.fiveHourRemaining ?? "—").font(.system(size: 8))
                Spacer(minLength: 0)
                Text(ProviderReading.percent(reading.thirdValue)).font(.system(size: 9, weight: .semibold)).monospacedDigit()
            }.foregroundStyle(ProviderPalette.signal(reading.provider)).frame(width: 92)
            ProviderMiniRail(value: reading.thirdValue, color: ProviderPalette.signal(reading.provider)).frame(width: 92)
        }.padding(.leading, 4).padding(.trailing, 12).frame(width: 142, height: 98)
    }
}

struct ProviderHangingPet: View {
    let reading: ProviderReading
    let left: Bool
    let animated: Bool
    var greeting: Date?
    var body: some View {
        ZStack(alignment: left ? .leading : .trailing) {
            RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.12, green: 0.19, blue: 0.21)).frame(width: 14, height: 83)
            Capsule().fill(reading.tint.opacity(0.23)).overlay(alignment: .bottom) {
                Capsule().fill(reading.tint).frame(height: 72 * ProviderReading.fraction(reading.usage))
            }.frame(width: 3, height: 72).padding(.horizontal, 2)
            VStack(spacing: 2) {
                ProviderPet(provider: reading.provider, animated: animated, greeting: greeting)
                    .frame(width: 50, height: 55).rotationEffect(.degrees(left ? 13 : -13))
                Text(ProviderReading.percent(reading.usage)).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(reading.tint).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(Color(red: 0.07, green: 0.12, blue: 0.15)))
            }.padding(left ? .leading : .trailing, 7)
        }.frame(width: 66, height: 98)
    }
}

struct ProviderPeekCard: View {
    let reading: ProviderReading
    let left: Bool
    let animated: Bool
    var greeting: Date?
    var body: some View {
        HStack(spacing: 7) {
            if left { pet }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(reading.name).font(.system(size: 11, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("hello!").font(.system(size: 8, weight: .medium)).foregroundStyle(reading.tint)
                }
                HStack(spacing: 10) {
                    metric("Used", reading.usage, reading.tint)
                    metric("Week", reading.calendar, Color.white.opacity(0.62), calendar: true)
                    metric(reading.provider == .codex ? "Reset" : reading.fiveHourRemaining ?? "—", reading.thirdValue, ProviderPalette.signal(reading.provider))
                }
            }.foregroundStyle(.white).padding(12).frame(width: 206)
                .background(RoundedRectangle(cornerRadius: 15).fill(Color(red: 0.085, green: 0.13, blue: 0.16)))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(reading.tint.opacity(0.35), lineWidth: 1))
            if !left { pet }
        }.frame(width: 272, height: 116)
    }
    private var pet: some View {
        ProviderPet(provider: reading.provider, animated: animated, greeting: greeting).frame(width: 55, height: 64)
    }
    private func metric(_ title: String, _ value: Double?, _ color: Color, calendar: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 7)).lineLimit(1).minimumScaleFactor(0.8)
            Text(ProviderReading.percent(value, calendar: calendar)).font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            ProviderMiniRail(value: value, color: color, segmented: calendar)
        }.foregroundStyle(color).frame(maxWidth: .infinity)
    }
}

struct ProviderFlyby: View {
    let readings: [ProviderReading]
    let animated: Bool
    var body: some View { ProviderTravelPreview(kind: .plane, readings: readings) }
}

struct BannerShape: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: .zero); p.addLine(to: CGPoint(x: r.maxX, y: 3))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 3)); p.addLine(to: CGPoint(x: 0, y: r.maxY))
            p.addLine(to: CGPoint(x: 12, y: r.midY)); p.closeSubpath()
        }
    }
}

struct Biplane: View {
    var body: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 17, y: 33)); p.addLine(to: CGPoint(x: 9, y: 11))
                p.addQuadCurve(to: CGPoint(x: 24, y: 9), control: CGPoint(x: 20, y: 5))
                p.addLine(to: CGPoint(x: 40, y: 33))
            }.fill(Color(red: 0.89, green: 0.68, blue: 0.41))
            Path { p in
                p.move(to: CGPoint(x: 13, y: 34)); p.addLine(to: CGPoint(x: 104, y: 23))
                p.addQuadCurve(to: CGPoint(x: 112, y: 42), control: CGPoint(x: 126, y: 29))
                p.addQuadCurve(to: CGPoint(x: 67, y: 51), control: CGPoint(x: 98, y: 54))
                p.addLine(to: CGPoint(x: 13, y: 40)); p.closeSubpath()
            }.fill(Color(red: 0.39, green: 0.69, blue: 0.80))
            Path { p in
                p.move(to: CGPoint(x: 43, y: 16)); p.addLine(to: CGPoint(x: 49, y: 47))
                p.move(to: CGPoint(x: 87, y: 16)); p.addLine(to: CGPoint(x: 79, y: 47))
            }.stroke(Color(red: 0.23, green: 0.37, blue: 0.39), lineWidth: 2)
            Capsule().fill(Color(red: 0.98, green: 0.82, blue: 0.54)).frame(width: 82, height: 6).position(x: 64, y: 15)
            Capsule().fill(Color(red: 0.89, green: 0.67, blue: 0.39)).frame(width: 80, height: 6).position(x: 61, y: 46)
            Circle().fill(Color(red: 0.17, green: 0.25, blue: 0.28)).frame(width: 9, height: 9).position(x: 77, y: 57)
            Circle().fill(Color(red: 0.79, green: 0.78, blue: 0.68)).frame(width: 3, height: 3).position(x: 77, y: 57)
            Capsule().fill(Color(red: 0.93, green: 0.73, blue: 0.42)).frame(width: 26, height: 4).position(x: 15, y: 37)
        }
    }
}
