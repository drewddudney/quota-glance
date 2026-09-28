import SwiftUI

/// Elapsed time is supplied by the short-lived reset stage. These adventures
/// own no timers, windows, sound playback, or persisted state.
struct ResetGardenScene: View {
    let t: Double
    let size: CGSize
    let ground: CGFloat
    let provider: DisplayProvider
    let animated: Bool
    let greeting: Date?

    private var scale: Double { min(1.35, max(0.85, Double(size.height) / 900)) }
    private var flowerX: Double { Double(size.width) * 0.56 }
    private var floorY: Double { Double(ground) }
    private var growth: Double { adventureEase((t - 2.25) / 1.15) }
    private var bloom: Double { adventureBloom((t - 3.35) / 0.65) }
    private var arrival: Double { adventureEase(t / 1.0) }
    private var pour: Double { adventureWindow(t, 1.05, 2.30, edge: 0.20) }
    private var petX: Double { flowerX - 130 * scale - 190 * scale * (1 - arrival) }
    private var flowerTop: Double { floorY - (21 + 185 * growth) * scale }

    var body: some View {
        ZStack(alignment: .topLeading) {
            AdventureGardenBed().scaleEffect(scale)
                .position(x: flowerX - 9 * scale, y: floorY - 1 * scale)
                .opacity(adventureEase(t / 0.45))

            // A single, visible seed swells before the first leaves break out.
            AdventureSeed().scaleEffect(scale * (1 + 0.2 * sin(t * 13) * pour))
                .rotationEffect(.degrees(sin(t * 11) * 9 * pour))
                .position(x: flowerX, y: floorY - 13 * scale)
                .opacity(1 - adventureClamp((t - 2.3) / 0.25))

            AdventureFlowerStem(growth: growth, sway: sin(max(0, t - 3.2) * 2.2) * 0.05 * growth)
                .frame(width: 130 * scale, height: 205 * scale)
                .position(x: flowerX, y: floorY - 111 * scale)
                .opacity(growth > 0 ? 1 : 0)
            AdventureFlowerHead(open: bloom, phase: t, provider: provider)
                .scaleEffect(scale * (0.18 + 0.82 * growth))
                .rotationEffect(.degrees(sin(max(0, t - 3.2) * 2.2) * 4))
                .position(x: flowerX + sin(max(0, t - 3.2) * 2.2) * 9 * growth * scale, y: flowerTop)
                .opacity(growth > 0 ? 1 : 0)

            watering
            gardenParticles

            let hopping = t > 4.9 && t < 5.65 ? sin((t - 4.9) / 0.75 * .pi) : 0
            let walking = t < 1.0 ? abs(sin(t * 15)) * 6 : 0
            ProviderPet(provider: provider, animated: animated, greeting: greeting)
                .frame(width: 85 * scale, height: 85 * scale)
                .rotationEffect(.degrees(-pour * 11 + hopping * -9))
                .position(x: petX - max(0, hopping) * 8 * scale,
                          y: floorY - ((provider == .claude ? 32 : 47) + walking + max(0, hopping) * 31) * scale)
                .opacity(adventureClamp(t / 0.15))

            AdventureWateringCan().scaleEffect(scale * 0.87)
                .rotationEffect(.degrees(pour * 28 - 7))
                .position(x: petX + (40 + 13 * pour) * scale,
                          y: floorY - (39 + 13 * pour) * scale + adventureEase((t - 2.3) / 0.45) * 19 * scale)
                .opacity(1 - adventureEase((t - 2.85) / 0.35))

            ForEach(0..<3) { index in
                let age = max(0, t - 3.7 - Double(index) * 0.23)
                let visibility = adventureWindow(t, 3.7 + Double(index) * 0.23, 7.45, edge: 0.3)
                let direction = index == 1 ? -1.0 : 1.0
                AdventureButterfly(phase: t * 8 + Double(index), tint: index == 1 ? provider.tint : AdventureInk.petals)
                    .scaleEffect(scale * (index == 2 ? 0.55 : 0.75))
                    .rotationEffect(.degrees(sin(age * 2.2 + Double(index)) * 16))
                    .position(x: flowerX + direction * (35 + age * 34) * scale + sin(age * 3) * 19 * scale,
                              y: flowerTop - (22 + age * 24 + sin(age * 2 + Double(index)) * 16) * scale)
                    .opacity(visibility)
            }
        }
        .frame(width: size.width, height: size.height)
        .mask(alignment: .top) { Rectangle().frame(height: max(1, Double(ground) + 14 * scale)) }
        .allowsHitTesting(false)
    }

    private var watering: some View {
        Canvas { context, _ in
            for index in 0..<36 {
                let birth = 1.1 + Double(index) * 0.033
                let age = t - birth
                guard age >= 0, age < 0.46 else { continue }
                let p = age / 0.46
                let origin = CGPoint(x: petX + 83 * scale, y: floorY - 61 * scale)
                let endX = flowerX + (adventureNoise(index) - 0.5) * 26 * scale
                let point = CGPoint(x: origin.x + (endX - origin.x) * p,
                                    y: origin.y + (floorY - 13 * scale - origin.y) * p - sin(p * .pi) * 11 * scale)
                var drop = context
                drop.translateBy(x: point.x, y: point.y)
                drop.rotate(by: .degrees(-22))
                drop.fill(Path(ellipseIn: CGRect(x: -1.8 * scale, y: -4 * scale, width: 3.6 * scale, height: 8 * scale)),
                          with: .color(AdventureInk.water.opacity(0.9)))
            }
        }
    }

    private var gardenParticles: some View {
        Canvas { context, _ in
            let sproutAge = t - 2.25
            if sproutAge > 0, sproutAge < 0.8 {
                for i in 0..<9 {
                    let vx = (adventureNoise(i + 70) - 0.5) * 86
                    let y = floorY - 12 * scale - (60 * sproutAge - 80 * sproutAge * sproutAge) * scale
                    let x = flowerX + vx * sproutAge * scale
                    let r = (2 + adventureNoise(i + 20) * 3) * scale
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r * 0.7)),
                                 with: .color(AdventureInk.soil.opacity(1 - sproutAge / 0.8)))
                }
            }
            for i in 0..<19 {
                let age = t - 3.45 - Double(i % 5) * 0.09
                guard age > 0, age < 2.5 else { continue }
                let angle = Double(i) / 19 * .pi * 2
                let radius = (62 * age + 12 * sin(age * 2)) * scale
                let x = flowerX + cos(angle) * radius
                let y = floorY - 206 * scale + sin(angle) * radius * 0.64 - (90 * age - 39 * age * age) * scale
                adventureDrawCoin(&context, point: CGPoint(x: x, y: y), radius: (5.5 + adventureNoise(i) * 2) * scale,
                                  turn: age * 5 + Double(i), opacity: min(1, (2.5 - age) / 0.8))
            }
            for i in 0..<12 {
                let age = t - 3.45 - Double(i) * 0.10
                guard age > 0, age < 1.6 else { continue }
                let angle = Double(i) * 2.4
                let radius = (42 + age * 46) * scale
                adventureDrawSparkle(&context, point: CGPoint(x: flowerX + cos(angle) * radius,
                    y: floorY - (205 + age * 35) * scale + sin(angle) * radius * 0.7),
                    radius: (3 + sin(age / 1.6 * .pi) * 4) * scale,
                    color: AdventureInk.gold.opacity(sin(age / 1.6 * .pi)))
            }
        }
    }
}

struct ResetTreasureScene: View {
    let t: Double
    let size: CGSize
    let ground: CGFloat
    let provider: DisplayProvider
    let animated: Bool
    let greeting: Date?

    private var scale: Double { min(1.35, max(0.85, Double(size.height) / 900)) }
    private var chestX: Double { Double(size.width) * 0.60 }
    private var floorY: Double { Double(ground) }
    private var reveal: Double { adventureBloom((t - 1.55) / 0.55) }
    private var lid: Double { adventureEase((t - 2.75) / 0.48) }
    private var jump: Double { adventureClamp((t - 3.60) / 0.90) }
    private var emerge: Double { adventureEase((t - 5.02) / 0.56) }

    private var tug: Double { t < 1.8 ? sin(t * 10) * min(1, t) : 0 }
    private var chestY: Double { floorY - 37 * scale + 34 * (1 - reveal) * scale }
    private var run: Double { adventureEase(t / 0.8) }
    private var walkingX: Double { chestX - (90 + 50 * run) * scale }
    private var actorX: Double { t < 3.6 ? walkingX : chestX - 140 * scale + 140 * jump * scale }
    private var actorY: Double { floorY - ((provider == .claude ? 32 : 47) + (t < 1.8 ? abs(tug) * 2 : 0) + sin(jump * .pi) * 148) * scale }

    var body: some View {
        ZStack(alignment: .topLeading) {
            AdventureTreasureSand().scaleEffect(scale)
                .position(x: chestX + scale, y: floorY - 3 * scale)
                .opacity(adventureEase(t / 0.4))
            rope
            chestDust
            AdventureChestBack(open: lid).scaleEffect(scale)
                .rotationEffect(.degrees(t < 1.8 ? tug * 1.5 : 0))
                .position(x: chestX, y: chestY - 27 * scale)
                .opacity(adventureClamp(t / 0.15))
            treasureParticles
            petActor
            AdventureChestFront().scaleEffect(scale)
                .rotationEffect(.degrees(t < 1.8 ? tug * 1.5 : 0))
                .position(x: chestX, y: chestY)
                .opacity(adventureClamp(t / 0.15))
            if t < 2.12 {
                AdventureTreasureSand().scaleEffect(scale)
                    .position(x: chestX, y: floorY + 14 * scale)
                    .opacity(1 - adventureEase((t - 1.75) / 0.35))
            }
            diveParticles
        }
        .frame(width: size.width, height: size.height)
        .mask(alignment: .top) { Rectangle().frame(height: max(1, Double(ground) + 14 * scale)) }
        .allowsHitTesting(false)
    }

    private var rope: some View {
        Canvas { context, _ in
            if t < 2.1 {
                let hand = CGPoint(x: walkingX + 30 * scale, y: floorY - (43 + tug * 1.3) * scale)
                let latch = CGPoint(x: chestX - 78 * scale, y: chestY - 16 * scale)
                var rope = Path()
                rope.move(to: hand)
                rope.addQuadCurve(to: latch, control: CGPoint(x: (Double(hand.x) + Double(latch.x)) / 2, y: Double(hand.y) + 14 * (1 - run) * scale))
                context.stroke(rope, with: .color(AdventureInk.rope), style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round))
            }
        }
    }

    @ViewBuilder private var petActor: some View {
        if t < 4.5 {
            let rotation = t < 1.8 ? -14 - tug * 3 : (t < 3.6 ? sin(t * 5) * 2 : jump * 205)
            ProviderPet(provider: provider, animated: animated, greeting: nil)
                .frame(width: 85 * scale, height: 85 * scale)
                .rotationEffect(.degrees(rotation))
                .scaleEffect(t < 3.6 ? 1 : 1 - sin(jump * .pi) * 0.12)
                .position(x: actorX, y: actorY)
                .opacity(adventureClamp(t / 0.15))
        } else if t >= 5.02 {
            ProviderPet(provider: provider, animated: animated, greeting: greeting)
                .frame(width: 86 * scale, height: 86 * scale)
                .rotationEffect(.degrees(sin(max(0, t - 5.3) * 3) * 3))
                .position(x: chestX, y: floorY - (38 + emerge * 66) * scale)
                .opacity(emerge)
            AdventureToken().scaleEffect(scale * 0.67)
                .rotationEffect(.degrees(-15 + sin(t * 3) * 6))
                .position(x: chestX + 35 * scale, y: floorY - (35 + emerge * 49) * scale)
                .opacity(emerge)
        }
    }

    private var diveParticles: some View {
        Canvas { context, _ in
            for i in 0..<11 {
                let age = t - 4.5 - Double(i % 3) * 0.035
                guard age > 0, age < 1.3 else { continue }
                let vx = (adventureNoise(i + 28) - 0.5) * 150
                let vy = 95 + adventureNoise(i + 8) * 42
                let point = CGPoint(x: chestX + vx * age * scale,
                    y: floorY - 60 * scale - (vy * age - 110 * age * age) * scale)
                adventureDrawCoin(&context, point: point,
                    radius: 5.5 * scale, turn: age * 8 + Double(i), opacity: min(1, (1.3 - age) / 0.4))
            }
            if t > 5.35, t < 6.4 {
                let age = t - 5.35
                for i in 0..<5 {
                    let angle = Double(i) / 5 * .pi * 2
                    let point = CGPoint(x: chestX + cos(angle) * (52 + age * 16) * scale,
                        y: floorY - 105 * scale + sin(angle) * (47 + age * 16) * scale)
                    adventureDrawSparkle(&context, point: point,
                        radius: 7 * sin(age / 1.05 * .pi) * scale,
                        color: AdventureInk.gold.opacity(sin(age / 1.05 * .pi)))
                }
            }
        }
    }

    private var chestDust: some View {
        Canvas { context, _ in
            for i in 0..<20 {
                let age = t - 1.8 - Double(i % 5) * 0.025
                guard age > 0, age < 0.9 else { continue }
                let direction = adventureNoise(i + 44) - 0.5
                let r = (3 + age * 11) * scale
                let x = chestX + direction * (110 + age * 200) * scale
                let y = floorY - (10 + 38 * age - 24 * age * age) * scale
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r / 2, width: r * 2, height: r)),
                             with: .color(AdventureInk.sand.opacity((1 - age / 0.9) * 0.6)))
            }
        }
    }

    private var treasureParticles: some View {
        Canvas { context, _ in
            for i in 0..<30 {
                let age = t - 3.05 - Double(i % 6) * 0.045
                guard age > 0, age < 2.6 else { continue }
                let vx = (adventureNoise(i + 3) - 0.5) * 215
                let vy = 175 + adventureNoise(i + 43) * 106
                let point = CGPoint(x: chestX + vx * age * scale,
                                    y: floorY - 59 * scale - (vy * age - 112 * age * age) * scale)
                adventureDrawCoin(&context, point: point, radius: (5 + adventureNoise(i + 1) * 4) * scale,
                                  turn: age * 6 + Double(i), opacity: min(1, (2.6 - age) / 0.6))
            }
            if t > 2.95, t < 4.3 {
                for i in 0..<8 {
                    let age = t - 2.95
                    let a = Double(i) / 8 * .pi * 2
                    adventureDrawSparkle(&context, point: CGPoint(x: chestX + cos(a) * (55 + age * 37) * scale,
                        y: floorY - 100 * scale + sin(a) * (38 + age * 33) * scale),
                        radius: (4 + adventureNoise(i) * 4) * scale,
                        color: AdventureInk.gold.opacity(sin(age / 1.35 * .pi)))
                }
            }
        }
    }
}

struct ResetGardenThumbnail: View {
    let provider: DisplayProvider
    var body: some View {
        ZStack(alignment: .topLeading) {
            AdventureGardenBed().scaleEffect(0.47).position(x: 82, y: 127)
            AdventureFlowerStem(growth: 1, sway: 0).frame(width: 66, height: 99).position(x: 105, y: 83)
            AdventureFlowerHead(open: 1, phase: 0, provider: provider).scaleEffect(0.51).position(x: 105, y: 35)
            ProviderPet(provider: provider, animated: false).frame(width: 58, height: 58).rotationEffect(.degrees(-8)).position(x: 39, y: 102)
            AdventureWateringCan().scaleEffect(0.50).rotationEffect(.degrees(17)).position(x: 69, y: 113)
            AdventureButterfly(phase: 0.7, tint: provider.tint).scaleEffect(0.48).rotationEffect(.degrees(-18)).position(x: 43, y: 49)
            AdventureToken().scaleEffect(0.30).position(x: 137, y: 72)
        }.frame(width: 152, height: 144).clipped().accessibilityHidden(true)
    }
}

struct ResetTreasureThumbnail: View {
    let provider: DisplayProvider
    var body: some View {
        ZStack(alignment: .topLeading) {
            AdventureTreasureSand().scaleEffect(0.5).position(x: 78, y: 132)
            AdventureChestBack(open: 0.95).scaleEffect(0.52).position(x: 104, y: 94)
            ProviderPet(provider: provider, animated: false).frame(width: 65, height: 65).rotationEffect(.degrees(-17)).position(x: 47, y: 82)
            AdventureChestFront().scaleEffect(0.52).position(x: 104, y: 108)
            ForEach(0..<4) { i in
                AdventureToken().scaleEffect(i == 1 ? 0.4 : 0.29)
                    .rotationEffect(.degrees(Double(i) * 21 - 18))
                    .position(x: 62 + Double(i) * 22, y: 26 + sin(Double(i) * 1.8) * 12)
            }
        }.frame(width: 152, height: 144).clipped().accessibilityHidden(true)
    }
}

private enum AdventureInk {
    static let leaf = Color(red: 0.40, green: 0.63, blue: 0.39)
    static let leafDark = Color(red: 0.20, green: 0.39, blue: 0.29)
    static let petals = Color(red: 0.98, green: 0.71, blue: 0.46)
    static let gold = Color(red: 0.99, green: 0.78, blue: 0.36)
    static let goldDark = Color(red: 0.66, green: 0.43, blue: 0.18)
    static let water = Color(red: 0.49, green: 0.83, blue: 0.88)
    static let soil = Color(red: 0.45, green: 0.32, blue: 0.23)
    static let sand = Color(red: 0.84, green: 0.70, blue: 0.47)
    static let rope = Color(red: 0.72, green: 0.59, blue: 0.37)
    static let wood = Color(red: 0.55, green: 0.31, blue: 0.18)
    static let woodLight = Color(red: 0.72, green: 0.43, blue: 0.23)
    static let woodDark = Color(red: 0.32, green: 0.20, blue: 0.14)
}

private struct AdventureGardenBed: View {
    var body: some View {
        ZStack {
            Ellipse().fill(.black.opacity(0.10)).frame(width: 284, height: 25).offset(y: 11)
            Ellipse().fill(AdventureInk.leafDark).frame(width: 272, height: 31)
            Ellipse().fill(AdventureInk.soil).frame(width: 125, height: 20).offset(x: 9, y: -4)
            ForEach(0..<8) { i in
                AdventureLeaf().fill(i % 2 == 0 ? AdventureInk.leaf : AdventureInk.leafDark)
                    .frame(width: 8, height: 25).rotationEffect(.degrees(Double(i % 3) * 20 - 20))
                    .offset(x: -118 + Double(i) * 34, y: -10 - Double(i % 2) * 3)
            }
        }.frame(width: 284, height: 42)
    }
}

private struct AdventureSeed: View {
    var body: some View {
        Ellipse().fill(AdventureInk.gold).frame(width: 14, height: 8)
            .overlay { Ellipse().stroke(AdventureInk.goldDark, lineWidth: 1) }
            .rotationEffect(.degrees(-15))
    }
}

private struct AdventureFlowerStem: View {
    let growth: Double
    let sway: Double
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let bottom = CGPoint(x: w / 2, y: h)
            let top = CGPoint(x: w / 2 + w * sway, y: h * (1 - growth))
            ZStack {
                Path { p in
                    p.move(to: bottom)
                    p.addCurve(to: top, control1: CGPoint(x: w * (0.5 + 0.27 * growth), y: h * (1 - growth * 0.30)), control2: CGPoint(x: w * (0.5 - 0.28 * growth), y: h * (1 - growth * 0.72)))
                }.stroke(AdventureInk.leafDark, style: StrokeStyle(lineWidth: max(3, w * 0.048), lineCap: .round))
                AdventureLeaf().fill(AdventureInk.leaf).frame(width: w * 0.31, height: h * 0.31)
                    .rotationEffect(.degrees(-57), anchor: .bottom)
                    .scaleEffect(adventureClamp((growth - 0.17) / 0.83), anchor: .bottom)
                    .position(x: w * 0.46, y: h * 0.75)
                AdventureLeaf().fill(AdventureInk.leaf).frame(width: w * 0.24, height: h * 0.25)
                    .rotationEffect(.degrees(54), anchor: .bottom)
                    .scaleEffect(adventureClamp((growth - 0.42) / 0.58), anchor: .bottom)
                    .position(x: w * 0.53, y: h * 0.56)
            }
        }
    }
}

private struct AdventureLeaf: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX, y: r.maxY))
            p.addCurve(to: CGPoint(x: r.midX, y: 0), control1: CGPoint(x: -r.width * 0.25, y: r.height * 0.8), control2: CGPoint(x: 0, y: r.height * 0.2))
            p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX * 1.1, y: r.height * 0.24), control2: CGPoint(x: r.maxX * 1.25, y: r.height * 0.77))
            p.closeSubpath()
        }
    }
}

private struct AdventureFlowerHead: View {
    let open: Double
    let phase: Double
    let provider: DisplayProvider
    var body: some View {
        ZStack {
            ForEach(0..<8) { i in
                Ellipse().fill(i % 2 == 0 ? AdventureInk.petals : Color(red: 1, green: 0.86, blue: 0.56))
                    .overlay { Ellipse().stroke(AdventureInk.goldDark.opacity(0.28), lineWidth: 0.8) }
                    .frame(width: 31, height: 53)
                    .offset(y: -29 * open)
                    .rotationEffect(.degrees(Double(i) * 45 + sin(phase * 1.5) * 2))
                    .scaleEffect(x: 0.30 + open * 0.70, y: 0.44 + open * 0.56)
            }
            Circle().fill(AdventureInk.gold).frame(width: 39, height: 39)
            Circle().stroke(AdventureInk.goldDark.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [1.5, 3.5])).frame(width: 29, height: 29)
            Image(systemName: "sparkle").font(.system(size: 19, weight: .medium)).foregroundStyle(AdventureInk.goldDark)
            Circle().fill(Color.white.opacity(0.32)).frame(width: 8, height: 8).offset(x: -8, y: -10)
        }.frame(width: 117, height: 117)
    }
}

private struct AdventureWateringCan: View {
    var body: some View {
        ZStack {
            Ellipse().stroke(AdventureInk.water.opacity(0.95), lineWidth: 6).frame(width: 33, height: 29).offset(x: -20, y: -4)
            Path { p in
                p.move(to: CGPoint(x: 30, y: 24)); p.addLine(to: CGPoint(x: 62, y: 6))
                p.addLine(to: CGPoint(x: 66, y: 14)); p.addLine(to: CGPoint(x: 34, y: 36)); p.closeSubpath()
            }.fill(AdventureInk.water)
            RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.37, green: 0.67, blue: 0.70)).frame(width: 37, height: 35).offset(x: -3, y: 3)
            Ellipse().fill(AdventureInk.water).frame(width: 35, height: 9).offset(x: -3, y: -14)
            Capsule().fill(AdventureInk.water.opacity(0.55)).frame(width: 4, height: 21).offset(x: -13, y: 5)
            Ellipse().fill(Color(red: 0.70, green: 0.87, blue: 0.84)).frame(width: 9, height: 19).rotationEffect(.degrees(-28)).offset(x: 31, y: -18)
            ForEach(0..<3) { i in Circle().fill(AdventureInk.leafDark.opacity(0.7)).frame(width: 1.7, height: 1.7).offset(x: 30 + Double(i % 2) * 3, y: -22 + Double(i) * 4) }
        }.frame(width: 70, height: 48)
    }
}

private struct AdventureButterfly: View {
    let phase: Double
    let tint: Color
    var body: some View {
        ZStack {
            ForEach([-1.0, 1.0], id: \.self) { direction in
                ZStack {
                    Ellipse().fill(tint).frame(width: 20, height: 27).rotationEffect(.degrees(direction * 24)).offset(x: direction * 10, y: -5)
                    Ellipse().fill(tint.opacity(0.8)).frame(width: 15, height: 19).rotationEffect(.degrees(direction * -23)).offset(x: direction * 9, y: 11)
                    Ellipse().fill(Color.white.opacity(0.35)).frame(width: 7, height: 12).rotationEffect(.degrees(direction * 24)).offset(x: direction * 10, y: -7)
                }.scaleEffect(x: 0.4 + abs(sin(phase)) * 0.6, y: 1)
            }
            Capsule().fill(AdventureInk.woodDark).frame(width: 3, height: 23)
            Path { p in
                p.move(to: CGPoint(x: 23, y: 12)); p.addQuadCurve(to: CGPoint(x: 16, y: 1), control: CGPoint(x: 19, y: 1))
                p.move(to: CGPoint(x: 25, y: 12)); p.addQuadCurve(to: CGPoint(x: 32, y: 1), control: CGPoint(x: 29, y: 1))
            }.stroke(AdventureInk.woodDark, style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }.frame(width: 48, height: 45)
    }
}

private struct AdventureTreasureSand: View {
    var body: some View {
        ZStack {
            Ellipse().fill(.black.opacity(0.09)).frame(width: 282, height: 24).offset(y: 9)
            Ellipse().fill(AdventureInk.sand).frame(width: 268, height: 27)
            Ellipse().fill(Color(red: 0.92, green: 0.81, blue: 0.61)).frame(width: 208, height: 15).offset(x: -7, y: -5)
            ForEach(0..<14) { i in
                Ellipse().fill(AdventureInk.goldDark.opacity(0.28)).frame(width: 2.5, height: 1.6)
                    .offset(x: (adventureNoise(i) - 0.5) * 237, y: (adventureNoise(i + 8) - 0.5) * 19)
            }
        }.frame(width: 282, height: 37)
    }
}

private struct AdventureChestBack: View {
    let open: Double
    var body: some View {
        ZStack {
            AdventureChestLid().fill(AdventureInk.woodLight)
                .overlay { AdventureChestLid().stroke(AdventureInk.gold, lineWidth: 6) }
                .overlay {
                    ZStack {
                        AdventureChestLid().stroke(AdventureInk.woodDark.opacity(0.45), lineWidth: 1).padding(9)
                        ForEach([-48.0, 48.0], id: \.self) { x in
                            RoundedRectangle(cornerRadius: 2).fill(AdventureInk.gold).frame(width: 12, height: 66).offset(x: x, y: 3)
                        }
                        RoundedRectangle(cornerRadius: 2).fill(AdventureInk.goldDark).frame(width: 17, height: 12).offset(y: 27)
                    }
                }
                .frame(width: 157, height: 75)
                .rotation3DEffect(.degrees((1 - open) * 73), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.3)
                .offset(y: -43)
            Ellipse().fill(AdventureInk.woodDark).frame(width: 158, height: 28).offset(y: -12)
            ForEach(0..<11) { i in
                AdventureToken().scaleEffect(0.36).scaleEffect(y: 0.7)
                    .position(x: 26 + Double(i) * 10.9, y: 48 + sin(Double(i) * 1.7) * 4)
                    .opacity(open)
            }
        }.frame(width: 170, height: 120)
    }
}

private struct AdventureChestLid: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: r.maxY)); p.addLine(to: CGPoint(x: 0, y: r.height * 0.42))
            p.addCurve(to: CGPoint(x: r.maxX, y: r.height * 0.42), control1: CGPoint(x: 0, y: -r.height * 0.16), control2: CGPoint(x: r.maxX, y: -r.height * 0.16))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.closeSubpath()
        }
    }
}

private struct AdventureChestFront: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(AdventureInk.wood)
            ForEach([-19.0, 0, 19], id: \.self) { y in
                Rectangle().fill(AdventureInk.woodDark.opacity(0.65)).frame(height: 1.5).offset(y: y)
            }
            ForEach([-52.0, 52.0], id: \.self) { x in
                Rectangle().fill(AdventureInk.gold).frame(width: 13).offset(x: x)
                ForEach([-20.0, 20.0], id: \.self) { y in
                    Circle().fill(AdventureInk.goldDark).frame(width: 3, height: 3).offset(x: x, y: y)
                }
            }
            RoundedRectangle(cornerRadius: 8).stroke(AdventureInk.goldDark, lineWidth: 2)
            Capsule().fill(AdventureInk.gold).frame(height: 5).offset(y: -32)
            RoundedRectangle(cornerRadius: 4).fill(AdventureInk.gold).frame(width: 24, height: 25).offset(y: -12)
            Circle().fill(AdventureInk.woodDark).frame(width: 6, height: 6).offset(y: -15)
            Capsule().fill(AdventureInk.woodDark).frame(width: 3, height: 8).offset(y: -10)
            Capsule().fill(Color.white.opacity(0.13)).frame(width: 20, height: 3).offset(x: -20, y: 22)
        }.frame(width: 164, height: 67).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct AdventureToken: View {
    var body: some View {
        ZStack {
            Circle().fill(AdventureInk.gold)
            Circle().stroke(AdventureInk.goldDark, lineWidth: 1.7)
            Circle().stroke(AdventureInk.goldDark.opacity(0.45), lineWidth: 1).padding(5)
            Image(systemName: "sparkle").font(.system(size: 17, weight: .semibold)).foregroundStyle(AdventureInk.goldDark)
            Circle().fill(.white.opacity(0.3)).frame(width: 5, height: 5).offset(x: -8, y: -8)
        }.frame(width: 33, height: 33)
    }
}

private func adventureClamp(_ value: Double) -> Double { min(1, max(0, value)) }
private func adventureEase(_ value: Double) -> Double { let p = adventureClamp(value); return 1 - pow(1 - p, 3) }
private func adventureBloom(_ value: Double) -> Double {
    let p = adventureClamp(value)
    return p < 1 ? 1 - pow(1 - p, 3) + sin(p * .pi) * 0.12 : 1
}
private func adventureWindow(_ time: Double, _ start: Double, _ end: Double, edge: Double) -> Double {
    adventureClamp((time - start) / edge) * adventureClamp((end - time) / edge)
}
private func adventureNoise(_ index: Int) -> Double {
    let value = sin(Double(index + 1) * 127.1) * 43_758.5453
    return value - floor(value)
}
private func adventureDrawCoin(_ context: inout GraphicsContext, point: CGPoint, radius: Double, turn: Double, opacity: Double) {
    var c = context
    c.opacity = max(0, opacity)
    c.translateBy(x: point.x, y: point.y)
    c.rotate(by: .radians(sin(turn) * 0.4))
    c.scaleBy(x: 0.3 + abs(cos(turn)) * 0.7, y: 1)
    let rect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
    c.fill(Path(ellipseIn: rect), with: .color(AdventureInk.gold))
    c.stroke(Path(ellipseIn: rect), with: .color(AdventureInk.goldDark), lineWidth: 0.8)
    c.stroke(Path(ellipseIn: rect.insetBy(dx: radius * 0.25, dy: radius * 0.25)), with: .color(AdventureInk.goldDark.opacity(0.4)), lineWidth: 0.6)
}
private func adventureDrawSparkle(_ context: inout GraphicsContext, point: CGPoint, radius: Double, color: Color) {
    guard radius > 0 else { return }
    var path = Path()
    path.move(to: CGPoint(x: point.x, y: point.y - radius))
    path.addQuadCurve(to: CGPoint(x: point.x + radius, y: point.y), control: point)
    path.addQuadCurve(to: CGPoint(x: point.x, y: point.y + radius), control: point)
    path.addQuadCurve(to: CGPoint(x: point.x - radius, y: point.y), control: point)
    path.addQuadCurve(to: CGPoint(x: point.x, y: point.y - radius), control: point)
    path.closeSubpath()
    context.fill(path, with: .color(color))
}
