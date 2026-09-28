import SwiftUI

/// A tiny concession cart arrives, overfills with token popcorn, then its
/// operator waves. All motion comes from the celebration's one shared clock.
struct ResetPopcornScene: View {
    let t: Double
    let size: CGSize
    let ground: CGFloat
    let provider: DisplayProvider
    let animated: Bool
    let greeting: Date?

    private var arrival: Double { partyEase(t / 1.9) }
    private var cartX: Double { -130 + (Double(size.width) * 0.57 + 130) * arrival }
    private var moving: Bool { t < 1.9 }
    private var filling: Double { partyEase((t - 2.2) / 1.7) }
    private var bustle: Double { t > 2.2 && t < 4.35 ? sin(t * 33) * 1.15 : 0 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Ellipse().fill(.black.opacity(0.13)).frame(width: 240, height: 13)
                .position(x: cartX - 27, y: ground - 1)
            PartyPopcornCart(provider: provider, fill: filling,
                             wheelAngle: (cartX + 130) / 12,
                             lidLift: filling * 9 + abs(bustle) * 2)
                .rotationEffect(.degrees(moving ? sin(t * 16) * 0.4 : bustle * 0.45))
                .position(x: cartX, y: Double(ground) - 97 + bustle)
            ProviderPet(provider: provider, animated: animated, greeting: t >= 5.4 ? greeting : nil)
                .frame(width: 72, height: 76)
                .rotationEffect(.degrees(moving ? 5 + sin(t * 17) * 3 : 0))
                .position(x: cartX - 123 + partyEase((t - 4.7) / 0.55) * 8,
                          y: Double(ground) - 38 - (moving ? abs(sin(t * 17)) * 6 * (1 - partyEase((t - 1.6) / 0.3)) : 0))
            PartyPopcornBurst(time: t, origin: CGPoint(x: cartX + 7, y: Double(ground) - 118), floor: ground - 6)
            ForEach(0..<11) { i in
                PartyKernel(token: i % 3 != 0)
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(Double(i * 37)))
                    .position(x: cartX + 92 + Double(i % 5) * 12 - Double(i / 5) * 6,
                              y: Double(ground) - 6 - Double(i / 5) * 8)
                    .opacity(partyEase((t - 3.85 - Double(i) * 0.05) / 0.3))
            }
        }.frame(width: size.width, height: size.height, alignment: .topLeading)
            .allowsHitTesting(false)
    }
}

/// The pet blows a bubble, hops aboard, floats upward, then lands in one last
/// soft bubble after the big one bursts. The real pet art stays unmodified.
struct ResetBubbleScene: View {
    let t: Double
    let size: CGSize
    let ground: CGFloat
    let provider: DisplayProvider
    let animated: Bool
    let greeting: Date?

    private var startX: Double { Double(size.width) * 0.48 - 90 }
    private var inflation: Double { partyEase((t - 1) / 1.3) }
    private var popped: Bool { t >= 4.85 }
    private var bubble: CGPoint { bubblePosition(at: min(t, 4.85)) }
    private var propFade: Double { 1 - partyEase((t - 2.8) / 0.65) }

    private func bubblePosition(at time: Double) -> CGPoint {
        let rise = partyEase((time - 2.55) / 2.3)
        let bloom = partyEase((time - 1) / 1.3)
        let bob = time > 2.55 ? sin((time - 2.55) * .pi * 2 / 0.9) * 9 : 0
        let height = min(255, Double(ground) * 0.36)
        return CGPoint(x: startX + 58 + bloom * 69 + rise * 50 + sin(max(0, time - 2.55) * 2.5) * rise * 15,
                       y: Double(ground) - 77 - bloom * 8 - rise * height + bob)
    }

    private var petPosition: CGPoint {
        if t < 0.95 {
            let walk = partyEase(t / 0.95)
            return CGPoint(x: -60 + (startX + 60) * walk,
                           y: Double(ground) - 38 - abs(sin(t * 19)) * 6 * (1 - partyEase((t - 0.7) / 0.25)))
        }
        if t < 2.3 { return CGPoint(x: startX, y: Double(ground) - 38) }
        if t < 2.72 {
            let hop = partyEase((t - 2.3) / 0.42)
            return CGPoint(x: startX + (bubble.x - startX) * hop,
                           y: Double(ground) - 38 + (bubble.y + 8 - Double(ground) + 38) * hop - sin(hop * .pi) * 68)
        }
        if !popped { return CGPoint(x: bubble.x, y: bubble.y + 8) }
        let fall = min(1, max(0, (t - 4.85) / 1.3))
        let landAge = max(0, t - 6.15)
        let bounce = sin(landAge * 15) * exp(-landAge * 6) * 13
        return CGPoint(x: bubble.x + partyEase(fall) * 36,
                       y: bubble.y + 8 + (Double(ground) - 38 - bubble.y - 8) * fall * fall - bounce)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Ellipse().fill(.black.opacity(popped ? 0.09 : 0.11 - partyEase((t - 2.55) / 2.3) * 0.08))
                .frame(width: popped ? 62 : 83, height: 9)
                .position(x: petPosition.x, y: Double(ground) - 1)
            props
            if !popped && t > 1 {
                PartyBubbleGlass(time: t, rimOnly: false)
                    .frame(width: 138, height: 138)
                    .scaleEffect(max(0.05, inflation))
                    .scaleEffect(x: 1 + sin(t * 6) * 0.014, y: 1 - sin(t * 6) * 0.014)
                    .position(bubble)
            }
            trailBubbles
            ProviderPet(provider: provider, animated: animated, greeting: t >= 6.25 ? greeting : nil)
                .frame(width: 71, height: 75)
                .rotationEffect(.degrees(petAngle))
                .scaleEffect(x: landingSquash, y: 2 - landingSquash)
                .position(petPosition)
            if !popped && t > 1 {
                PartyBubbleGlass(time: t, rimOnly: true)
                    .frame(width: 138, height: 138)
                    .scaleEffect(max(0.05, inflation))
                    .scaleEffect(x: 1 + sin(t * 6) * 0.014, y: 1 - sin(t * 6) * 0.014)
                    .position(bubble)
            }
            PartyBubblePop(age: t - 4.85, origin: bubble)
            if t >= 6.05 && t < 6.8 {
                let landing = partyEase((t - 6.05) / 0.75)
                Ellipse().stroke(Color(red: 0.68, green: 0.91, blue: 0.85).opacity((1 - landing) * 0.7), lineWidth: 1.5)
                    .frame(width: 32 + landing * 65, height: 8 + landing * 13)
                    .position(x: petPosition.x, y: Double(ground) - 2)
            }
        }.frame(width: size.width, height: size.height, alignment: .topLeading)
            .allowsHitTesting(false)
    }

    private var petAngle: Double {
        if t < 0.95 { return sin(t * 19) * 4 }
        if t < 2.3 { return 7 * inflation }
        if t < 2.72 { return sin((t - 2.3) / 0.42 * .pi) * -15 }
        if !popped { return sin(t * 4) * 5 }
        return sin(min(1, (t - 4.85) / 1.3) * .pi) * 13
    }
    private var landingSquash: Double {
        let age = t - 6.15
        return age >= 0 && age < 0.35 ? 1 + sin(age / 0.35 * .pi) * 0.10 : 1
    }

    private var props: some View {
        ZStack(alignment: .topLeading) {
            PartyBubbleBottle().frame(width: 27, height: 39)
                .position(x: startX + 55, y: Double(ground) - 19)
            PartyBubbleWand()
                .frame(width: 38, height: 48)
                .rotationEffect(.degrees(24 + partyEase((t - 2.4) / 0.3) * 48))
                .position(x: startX + 58, y: Double(ground) - 63 + partyEase((t - 2.4) / 0.3) * 34)
            if t > 1 && t < 2.3 {
                Canvas { context, _ in
                    for i in 0..<3 {
                        let phase = (t * 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        var path = Path()
                        let x = startX + 29 + phase * 32
                        let y = Double(ground) - 55 + Double(i - 1) * 7
                        path.move(to: CGPoint(x: x, y: y))
                        path.addQuadCurve(to: CGPoint(x: x + 8, y: y - 1), control: CGPoint(x: x + 4, y: y - 4))
                        context.stroke(path, with: .color(.white.opacity(sin(phase * .pi) * 0.45)),
                                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    }
                }
            }
        }.opacity(partyEase((t - 0.6) / 0.3) * propFade)
    }

    private var trailBubbles: some View {
        ForEach(0..<4) { i in
            let age = t - 2.65 - Double(i) * 0.32
            if age > 0 && age < 2.0 {
                let birth = bubblePosition(at: 2.65 + Double(i) * 0.32)
                PartyBubbleGlass(time: t + Double(i), rimOnly: false)
                    .frame(width: 9 + Double(i % 2) * 5, height: 9 + Double(i % 2) * 5)
                    .position(x: birth.x - 48 - age * 13, y: birth.y + 60 - age * 30)
                    .opacity(min(1, (2 - age) * 1.5))
            }
        }
    }
}

struct ResetPopcornThumbnail: View {
    let provider: DisplayProvider
    var body: some View {
        ZStack(alignment: .topLeading) {
            PartyPopcornCart(provider: provider, fill: 1, wheelAngle: 0, lidLift: 8)
                .scaleEffect(0.59).position(x: 96, y: 81)
            ProviderPet(provider: provider, animated: false).frame(width: 40, height: 44)
                .position(x: 28, y: 111)
            ForEach(0..<5) { i in
                PartyKernel(token: i % 2 == 0).frame(width: 9, height: 9)
                    .rotationEffect(.degrees(Double(i) * 31))
                    .position(x: 76 + Double(i) * 12, y: 14 - sin(Double(i) * .pi / 4) * 9)
            }
        }.frame(width: 152, height: 144).allowsHitTesting(false)
    }
}

struct ResetBubbleThumbnail: View {
    let provider: DisplayProvider
    var body: some View {
        ZStack(alignment: .topLeading) {
            PartyBubbleGlass(time: 1.2, rimOnly: false).frame(width: 103, height: 103).position(x: 91, y: 64)
            ProviderPet(provider: provider, animated: false).frame(width: 49, height: 53).position(x: 91, y: 69)
            PartyBubbleGlass(time: 1.2, rimOnly: true).frame(width: 103, height: 103).position(x: 91, y: 64)
            PartyBubbleBottle().frame(width: 24, height: 35).position(x: 31, y: 120)
            PartyBubbleWand().frame(width: 28, height: 35).rotationEffect(.degrees(-29)).position(x: 25, y: 84)
            PartyBubbleGlass(time: 2, rimOnly: false).frame(width: 14, height: 14).position(x: 136, y: 132)
        }.frame(width: 152, height: 144).allowsHitTesting(false)
    }
}

private struct PartyPopcornCart: View {
    let provider: DisplayProvider
    let fill: Double
    let wheelAngle: Double
    let lidLift: Double
    private let cream = Color(red: 0.98, green: 0.89, blue: 0.70)
    private let metal = Color(red: 0.62, green: 0.48, blue: 0.27)
    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: 38, y: 143)); p.addLine(to: CGPoint(x: 16, y: 137))
                p.addQuadCurve(to: CGPoint(x: 7, y: 143), control: CGPoint(x: 7, y: 137))
                p.addLine(to: CGPoint(x: 7, y: 155))
            }.stroke(metal, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            ForEach([54.0, 161.0], id: \.self) { x in
                ZStack {
                    Circle().fill(Color(red: 0.11, green: 0.20, blue: 0.22))
                    Circle().stroke(cream, lineWidth: 3).padding(3)
                    Path { p in
                        p.move(to: CGPoint(x: 3, y: 13)); p.addLine(to: CGPoint(x: 23, y: 13))
                        p.move(to: CGPoint(x: 13, y: 3)); p.addLine(to: CGPoint(x: 13, y: 23))
                    }.stroke(metal, lineWidth: 1.5).rotationEffect(.radians(wheelAngle))
                    Circle().fill(metal).frame(width: 4, height: 4)
                }.frame(width: 26, height: 26).position(x: x, y: 181)
            }
            RoundedRectangle(cornerRadius: 7).fill(provider.tint.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(metal, lineWidth: 1))
                .frame(width: 148, height: 50).position(x: 108, y: 147)
            RoundedRectangle(cornerRadius: 3).fill(cream).frame(width: 55, height: 29).position(x: 108, y: 147)
            HStack(spacing: 1) {
                ForEach(0..<3) { i in
                    PartyKernel(token: true).frame(width: 13, height: 13).offset(y: i == 1 ? -3 : 2)
                }
            }.position(x: 108, y: 147)
            RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.78, green: 0.96, blue: 0.91).opacity(0.11))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(cream.opacity(0.66), lineWidth: 1))
                .frame(width: 132, height: 83).position(x: 108, y: 80)
            ForEach(0..<37) { i in
                PartyKernel(token: i % 3 != 0).frame(width: 12, height: 12)
                    .rotationEffect(.degrees(Double(i * 51)))
                    .position(x: 52 + Double(i % 10) * 12 + Double(i / 10 % 2) * 3,
                              y: 114 - Double(i / 10) * 11)
                    .opacity(fill > Double(i) / 45 ? 1 : 0)
            }
            Path { p in
                for x: CGFloat in [40, 176] {
                    p.move(to: CGPoint(x: x, y: 34)); p.addLine(to: CGPoint(x: x, y: 123))
                }
            }.stroke(metal, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            Path { p in
                p.move(to: CGPoint(x: 55, y: 49)); p.addLine(to: CGPoint(x: 87, y: 49))
                p.move(to: CGPoint(x: 53, y: 52)); p.addLine(to: CGPoint(x: 53, y: 72))
            }.stroke(.white.opacity(0.38), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            PartyCartAwning(provider: provider).frame(width: 168, height: 32)
                .rotationEffect(.degrees(-fill * 3), anchor: .leading)
                .position(x: 108, y: 23 - lidLift)
        }.frame(width: 200, height: 196)
    }
}

private struct PartyCartAwning: View {
    let provider: DisplayProvider
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7) { i in
                RoundedRectangle(cornerRadius: 7)
                    .fill(i % 2 == 0 ? provider.tint : Color(red: 0.99, green: 0.90, blue: 0.74))
            }
        }.overlay(alignment: .top) {
            Capsule().fill(Color(red: 0.98, green: 0.86, blue: 0.65)).frame(height: 4)
        }
    }
}

private struct PartyKernel: View {
    let token: Bool
    var body: some View {
        if token {
            Circle().fill(Color(red: 0.99, green: 0.78, blue: 0.34))
                .overlay(Circle().stroke(Color(red: 0.69, green: 0.43, blue: 0.18), lineWidth: 0.8))
                .overlay { Image(systemName: "sparkle").resizable().scaledToFit().padding(3.5).foregroundStyle(Color(red: 0.67, green: 0.41, blue: 0.14)) }
        } else {
            ZStack {
                Circle().fill(Color(red: 0.99, green: 0.95, blue: 0.81)).scaleEffect(0.75).offset(x: -2, y: 1)
                Circle().fill(Color(red: 0.99, green: 0.95, blue: 0.81)).scaleEffect(0.75).offset(x: 2, y: 1)
                Circle().fill(Color(red: 0.99, green: 0.95, blue: 0.81)).scaleEffect(0.75).offset(y: -2)
                Circle().fill(Color(red: 0.85, green: 0.66, blue: 0.34)).frame(width: 3, height: 3).offset(y: 1)
            }
        }
    }
}

private struct PartyPopcornBurst: View {
    let time: Double
    let origin: CGPoint
    let floor: CGFloat
    var body: some View {
        Canvas { context, _ in
            for i in 0..<53 {
                let birth = i < 37 ? 2.25 + Double(i) * 0.051 : 3.55 + Double(i - 37) * 0.011
                let age = time - birth
                guard age > 0, age < 2.8 else { continue }
                let seed = partyNoise(i)
                let vx = (seed - 0.42) * 225
                let vy = -140 - partyNoise(i + 43) * 170
                let x = origin.x + vx * age
                let y = origin.y + vy * age + 162 * age * age
                guard y < floor else { continue }
                var c = context
                c.opacity = min(1, (2.8 - age) / 0.4)
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(age * (seed - 0.5) * 9))
                c.scaleBy(x: i % 3 == 0 ? 1 : 0.5 + abs(cos(age * 5 + Double(i))) * 0.5, y: 1)
                if let kernel = c.resolveSymbol(id: i % 3 == 0 ? "pop" : "token") { c.draw(kernel, at: .zero) }
            }
        } symbols: {
            PartyKernel(token: false).frame(width: 13, height: 13).tag("pop")
            PartyKernel(token: true).frame(width: 14, height: 14).tag("token")
        }
    }
}

private struct PartyBubbleGlass: View {
    let time: Double
    let rimOnly: Bool
    private let shimmer = [Color(red: 0.61, green: 0.92, blue: 0.92), Color(red: 0.92, green: 0.75, blue: 0.88),
                           Color(red: 0.99, green: 0.88, blue: 0.64), Color(red: 0.64, green: 0.91, blue: 0.78),
                           Color(red: 0.61, green: 0.92, blue: 0.92)]
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if !rimOnly {
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.015), Color.cyan.opacity(0.045), Color.white.opacity(0.12)],
                                                 center: .center, startRadius: 0, endRadius: geo.size.width * 0.52))
                    Circle().stroke(AngularGradient(colors: shimmer.map { $0.opacity(0.38) }, center: .center,
                                                    angle: .degrees(time * 13)), lineWidth: 2.5)
                } else {
                    Circle().stroke(AngularGradient(colors: shimmer.map { $0.opacity(0.87) }, center: .center,
                                                    angle: .degrees(time * 13)), lineWidth: 1.3)
                    Circle().trim(from: 0.56, to: 0.71).stroke(.white.opacity(0.82), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                        .padding(geo.size.width * 0.075)
                    Circle().trim(from: 0.02, to: 0.11).stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .padding(geo.size.width * 0.055)
                }
            }
        }
    }
}

private struct PartyBubbleBottle: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.29, green: 0.64, blue: 0.63))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.3), lineWidth: 0.8))
                    .frame(height: geo.size.height * 0.82).offset(y: geo.size.height * 0.09)
                RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.94, green: 0.82, blue: 0.57))
                    .frame(width: geo.size.width * 0.72, height: geo.size.height * 0.17).offset(y: -geo.size.height * 0.39)
                Circle().stroke(Color.white.opacity(0.65), lineWidth: 1.3).frame(width: geo.size.width * 0.48)
                Circle().stroke(Color.white.opacity(0.4), lineWidth: 1).frame(width: geo.size.width * 0.22).offset(x: 4, y: 5)
            }
        }
    }
}

private struct PartyBubbleWand: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.addEllipse(in: CGRect(x: geo.size.width * 0.24, y: 1, width: geo.size.width * 0.52, height: geo.size.height * 0.43))
                p.move(to: CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.44))
                p.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height))
            }.stroke(Color(red: 0.98, green: 0.82, blue: 0.47), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
    }
}

private struct PartyBubblePop: View {
    let age: Double
    let origin: CGPoint
    var body: some View {
        Canvas { context, _ in
            guard age >= 0, age < 1.85 else { return }
            let colors = [Color(red: 0.63, green: 0.93, blue: 0.91), Color(red: 0.96, green: 0.82, blue: 0.89), Color(red: 0.99, green: 0.90, blue: 0.67)]
            if age < 0.32 {
                let r = 69 + age * 155
                context.stroke(Path(ellipseIn: CGRect(x: origin.x - r, y: origin.y - r, width: r * 2, height: r * 2)),
                               with: .color(.white.opacity((1 - age / 0.32) * 0.6)), lineWidth: 1)
            }
            for i in 0..<31 {
                let angle = Double(i) / 31 * .pi * 2
                let speed = 40 + partyNoise(i) * 78
                let distance = 67 + speed * age
                let x = origin.x + cos(angle) * distance
                let y = origin.y + sin(angle) * distance + age * age * 32
                let opacity = min(1, (1.85 - age) / 0.65)
                let color = colors[i % colors.count].opacity(opacity)
                if i % 3 == 0 {
                    let r = 3.5 + age * 2
                    context.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color), lineWidth: 1.2)
                } else {
                    let r = 2.5 + partyNoise(i + 24) * 2
                    var star = Path()
                    star.move(to: CGPoint(x: x - r, y: y)); star.addQuadCurve(to: CGPoint(x: x, y: y - r * 1.4), control: CGPoint(x: x, y: y))
                    star.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x, y: y))
                    star.addQuadCurve(to: CGPoint(x: x, y: y + r * 1.4), control: CGPoint(x: x, y: y))
                    star.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x, y: y)); star.closeSubpath()
                    context.fill(star, with: .color(color))
                }
            }
        }
    }
}

private func partyEase(_ value: Double) -> Double {
    let t = min(1, max(0, value))
    return t * t * (3 - 2 * t)
}
private func partyNoise(_ value: Int) -> Double {
    let x = sin(Double(value) * 43.173 + 7.71) * 9817.153
    return x - floor(x)
}
