import SwiftUI

/// The artwork, lettering and rails all ripple together, as strips of one cloth.
/// Canvas symbols keep the stats readable while avoiding an image per frame.
struct ProviderClothBanner: View {
    let readings: [ProviderReading]
    var width: CGFloat = 337
    var phase: Double = 0
    var flutter: CGFloat = 0
    var heading: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            guard let cloth = context.resolveSymbol(id: "cloth") else { return }
            for x in stride(from: CGFloat(0), to: width, by: 3) {
                let distance = heading > 0 ? 1 - x / width : x / width
                let wave = sin(phase * 3 - Double(distance) * 6)
                    + 0.18 * sin(phase * 5.2 - Double(distance) * 11)
                let lift = CGFloat(wave) * flutter * pow(distance, 0.8)
                var strip = context
                strip.clip(to: Path(CGRect(x: x, y: 0, width: min(3, width - x), height: size.height)))
                strip.draw(cloth, at: CGPoint(x: width / 2, y: size.height / 2 + lift))
            }
        } symbols: {
            ProviderStatsBanner(readings: readings, width: width, heading: heading).tag("cloth")
        }
        .frame(width: width, height: readings.count == 1 ? 78 : 100)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readings.map(\.help).joined(separator: ". "))
    }
}

private struct ProviderStatsBanner: View {
    let readings: [ProviderReading]
    let width: CGFloat
    let heading: CGFloat
    var body: some View {
        VStack(spacing: 7) {
            ForEach(readings, id: \.provider) { reading in
                HStack(spacing: 8) {
                    Text(reading.name.uppercased())
                        .font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(0.5)
                        .frame(width: 43, alignment: .leading)
                    metric("Used", reading.usage, reading.tint)
                    metric("Week", reading.calendar, ProviderPalette.ink.opacity(0.57), calendar: true)
                    metric(reading.provider == .codex ? "Reset" : reading.fiveHourRemaining ?? "—",
                           reading.thirdValue, ProviderPalette.signal(reading.provider, dark: false))
                }
            }
        }
        .padding(.leading, heading > 0 ? 23 : 13).padding(.trailing, heading > 0 ? 13 : 23)
        .frame(width: width, height: readings.count == 1 ? 44 : 66).foregroundStyle(ProviderPalette.ink)
        .background(BannerShape().scale(x: heading, y: 1).fill(Color(red: 0.96, green: 0.93, blue: 0.80)))
        .overlay(BannerShape().scale(x: heading, y: 1).stroke(Color(red: 0.63, green: 0.58, blue: 0.41).opacity(0.55), lineWidth: 0.6))
        .overlay(alignment: heading > 0 ? .trailing : .leading) {
            Rectangle().fill(Color(red: 0.66, green: 0.60, blue: 0.43).opacity(0.35))
                .frame(width: 1, height: readings.count == 1 ? 32 : 54).padding(.horizontal, 5)
        }
    }
    private func metric(_ label: String, _ value: Double?, _ color: Color, calendar: Bool = false) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text(label).font(.system(size: 7, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text(ProviderReading.percent(value, calendar: calendar))
                    .font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            }
            ProviderMiniRail(value: value, color: color, segmented: calendar)
        }.frame(maxWidth: .infinity)
    }
}

struct ProviderTravelArtwork: View {
    let kind: ProviderTravelKind
    var providers: [DisplayProvider] = [.codex, .claude]
    var phase: Double = 0
    var animated = false
    var greeting: Date?

    var body: some View {
        Group {
            switch kind {
            case .plane: plane
            case .balloon: balloon
            case .skateboard: skateboard
            }
        }.frame(width: kind.size.width, height: kind.size.height)
    }

    private var plane: some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(providers) { pet($0, width: 31, height: 34) }
            }.offset(x: 3, y: -16)
            Biplane().frame(width: 124, height: 65).offset(y: 7)
            Capsule().fill(Color(red: 0.86, green: 0.84, blue: 0.70)).frame(width: 3, height: 35)
                .scaleEffect(y: animated ? 0.18 + abs(cos(phase * 25)) * 0.82 : 1).offset(x: 55, y: 7)
        }
    }

    private var balloon: some View {
        ZStack(alignment: .topLeading) {
            BalloonEnvelope().fill(Color(red: 0.91, green: 0.77, blue: 0.53)).frame(width: 126, height: 130).offset(x: 5)
            BalloonEnvelope().fill(Color(red: 0.40, green: 0.66, blue: 0.72)).frame(width: 85, height: 130).offset(x: 25.5)
            BalloonEnvelope().fill(Color(red: 0.93, green: 0.86, blue: 0.67)).frame(width: 38, height: 130).offset(x: 49)
            BalloonEnvelope().stroke(Color(red: 0.98, green: 0.91, blue: 0.74).opacity(0.6), lineWidth: 1)
                .frame(width: 126, height: 130).offset(x: 5)
            Path { p in
                p.move(to: CGPoint(x: 47, y: 123)); p.addLine(to: CGPoint(x: 45, y: 165))
                p.move(to: CGPoint(x: 89, y: 123)); p.addLine(to: CGPoint(x: 91, y: 165))
            }.stroke(Color(red: 0.79, green: 0.72, blue: 0.53), lineWidth: 1.2)
            HStack(spacing: 0) {
                ForEach(providers) { pet($0, width: 34, height: 38) }
            }.position(x: 68, y: 148)
            RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.60, green: 0.38, blue: 0.23))
                .frame(width: 57, height: 26).position(x: 68, y: 173)
            Path { p in
                for y: CGFloat in [166, 172, 178] {
                    p.move(to: CGPoint(x: 43, y: y)); p.addLine(to: CGPoint(x: 93, y: y))
                }
                for x: CGFloat in [49, 58, 68, 78, 87] {
                    p.move(to: CGPoint(x: x, y: 163)); p.addLine(to: CGPoint(x: x, y: 183))
                }
            }.stroke(Color(red: 0.86, green: 0.66, blue: 0.42).opacity(0.65), lineWidth: 1)
            Capsule().fill(Color(red: 0.93, green: 0.75, blue: 0.48)).frame(width: 61, height: 5).position(x: 68, y: 160)
        }.frame(width: 136, height: 192)
    }

    private var skateboard: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 2) {
                ForEach(providers) { pet($0, width: 47, height: 50) }
            }.position(x: 77, y: 40)
            Path { p in
                p.move(to: CGPoint(x: 15, y: 57))
                p.addQuadCurve(to: CGPoint(x: 33, y: 64), control: CGPoint(x: 20, y: 64))
                p.addLine(to: CGPoint(x: 120, y: 64))
                p.addQuadCurve(to: CGPoint(x: 137, y: 54), control: CGPoint(x: 133, y: 64))
            }.stroke(Color(red: 0.96, green: 0.67, blue: 0.44), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            Capsule().fill(Color(red: 0.32, green: 0.59, blue: 0.60)).frame(width: 83, height: 3).position(x: 77, y: 62)
            ForEach([42.0, 111.0], id: \.self) { x in
                ZStack {
                    Circle().fill(Color(red: 0.90, green: 0.88, blue: 0.69))
                    Circle().stroke(Color(red: 0.17, green: 0.30, blue: 0.32), lineWidth: 2)
                    Rectangle().fill(Color(red: 0.32, green: 0.59, blue: 0.60)).frame(width: 2, height: 11)
                        .rotationEffect(.radians(animated ? phase * 15 : 0))
                    Circle().fill(ProviderPalette.ink).frame(width: 4, height: 4)
                }.frame(width: 15, height: 15).position(x: x, y: 75)
            }
        }.frame(width: 150, height: 88)
    }

    private func pet(_ provider: DisplayProvider, width: CGFloat, height: CGFloat) -> some View {
        ProviderPet(provider: provider, animated: animated, greeting: greeting).frame(width: width, height: height)
    }
}

private struct BalloonEnvelope: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.width * 0.34, y: r.maxY))
            p.addCurve(to: CGPoint(x: 0, y: r.height * 0.35), control1: CGPoint(x: r.width * 0.26, y: r.height * 0.82), control2: CGPoint(x: 0, y: r.height * 0.66))
            p.addCurve(to: CGPoint(x: r.width, y: r.height * 0.35), control1: CGPoint(x: 0, y: -r.height * 0.12), control2: CGPoint(x: r.width, y: -r.height * 0.12))
            p.addCurve(to: CGPoint(x: r.width * 0.66, y: r.maxY), control1: CGPoint(x: r.width, y: r.height * 0.66), control2: CGPoint(x: r.width * 0.74, y: r.height * 0.82))
            p.closeSubpath()
        }
    }
}

/// A shared renderer for live, physics-driven visits and still layout previews.
struct ProviderTravelComposition: View {
    let physics: ProviderTravelPhysics
    let readings: [ProviderReading]
    var animated = true
    var greeting: Date?
    private var area: CGRect { physics.renderBounds }
    private func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - area.minX, y: area.maxY - p.y) }

    var body: some View {
        let vehicle = local(physics.position)
        let banner = local(physics.bannerPosition)
        ZStack(alignment: .topLeading) {
            Path { path in
                if physics.kind == .balloon {
                    for side: CGFloat in [-1, 1] {
                        let start = CGPoint(x: vehicle.x + side * 22, y: vehicle.y + 88)
                        let end = CGPoint(x: banner.x + side * 95, y: banner.y - (physics.providerCount == 1 ? 18 : 29))
                        path.move(to: start)
                        path.addQuadCurve(to: end, control: CGPoint(x: start.x, y: end.y - 12))
                    }
                } else {
                    let start = CGPoint(x: vehicle.x - physics.heading * (physics.kind.size.width / 2 - 16), y: vehicle.y + 7)
                    let end = CGPoint(x: banner.x + physics.heading * (physics.kind.bannerWidth / 2 - 3), y: banner.y)
                    path.move(to: start)
                    path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + 7))
                }
            }.stroke(Color(red: 0.79, green: 0.73, blue: 0.55), lineWidth: 1)
            ProviderClothBanner(readings: readings, width: physics.kind.bannerWidth,
                                phase: physics.age, flutter: animated ? min(3.2, 1.2 + abs(physics.velocity.dx) / 160) : 0,
                                heading: physics.heading)
                .position(banner)
            ProviderTravelArtwork(kind: physics.kind, providers: readings.map(\.provider), phase: physics.age, animated: animated, greeting: greeting)
                .scaleEffect(x: physics.kind == .balloon ? 1 : physics.heading, y: 1)
                .rotationEffect(.degrees(physics.bank)).position(vehicle)
        }.frame(width: area.width, height: area.height)
    }
}

struct ProviderTravelPreview: View {
    let kind: ProviderTravelKind
    let readings: [ProviderReading]
    var body: some View {
        let pose = ProviderTravelPhysics(kind: kind, bounds: CGRect(x: 0, y: 0, width: 1200, height: 900), parked: true, providerCount: readings.count)
        ProviderTravelComposition(physics: pose, readings: readings, animated: false)
    }
}
