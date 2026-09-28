import SwiftUI

/// One short-lived timeline drives the whole scene. No animation work remains
/// after the transparent, click-through celebration window has been removed.
struct ProviderResetStage: View {
    let animation: ProviderResetAnimation
    let provider: DisplayProvider
    let caption: String
    var bottomInset: CGFloat = 100
    var reducedMotion = false
    var previewElapsed: TimeInterval?
    @State private var startedAt = Date()

    var body: some View {
        GeometryReader { geometry in
            if let previewElapsed {
                scene(at: previewElapsed, size: geometry.size)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    scene(at: context.date.timeIntervalSince(startedAt), size: geometry.size)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }

    @ViewBuilder private func scene(at t: Double, size: CGSize) -> some View {
        let ground = size.height - bottomInset - 20
        if reducedMotion {
            HStack(spacing: 12) {
                ProviderPet(provider: provider, animated: false).frame(width: 52, height: 52)
                Text(caption).font(.system(size: 17, weight: .semibold, design: .rounded))
            }.padding(16).foregroundStyle(ProviderPalette.ink)
                .background(Color(red: 0.98, green: 0.95, blue: 0.85), in: RoundedRectangle(cornerRadius: 18))
                .position(x: size.width / 2, y: ground - 45)
        } else {
            ZStack(alignment: .topLeading) {
                switch animation {
                case .loopPlane: loopPlane(t, size: size)
                case .tokenPool: cannonball(t, size: size, ground: ground)
                case .parachute: delivery(t, size: size, ground: ground)
                case .popcorn:
                    ResetPopcornScene(t: t, size: size, ground: ground, provider: provider,
                                      animated: previewElapsed == nil, greeting: startedAt.addingTimeInterval(5.4))
                    ResetRibbon(caption: caption, subtitle: "freshly popped")
                        .position(x: size.width * 0.57, y: ground - 305)
                        .opacity(resetReveal(t, start: 5.0, end: 7.1))
                case .bubble:
                    ResetBubbleScene(t: t, size: size, ground: ground, provider: provider,
                                     animated: previewElapsed == nil, greeting: startedAt.addingTimeInterval(6.25))
                    ResetRibbon(caption: caption, subtitle: "a little lighter now")
                        .position(x: size.width * 0.48 + 116, y: ground - 142)
                        .opacity(resetReveal(t, start: 6.25, end: 7.25))
                case .garden:
                    ResetGardenScene(t: t, size: size, ground: ground, provider: provider,
                                     animated: previewElapsed == nil, greeting: startedAt.addingTimeInterval(5.55))
                    ResetRibbon(caption: caption, subtitle: "room to grow")
                        .position(x: size.width * 0.56 - 245 * min(1.35, max(0.85, size.height / 900)),
                                  y: ground - 175 * min(1.35, max(0.85, size.height / 900)))
                        .opacity(resetReveal(t, start: 5.4, end: 7.1))
                case .treasure:
                    ResetTreasureScene(t: t, size: size, ground: ground, provider: provider,
                                       animated: previewElapsed == nil, greeting: startedAt.addingTimeInterval(5.55))
                    ResetRibbon(caption: caption, subtitle: "quite a little haul")
                        .position(x: size.width * 0.60, y: ground - 240 * min(1.35, max(0.85, size.height / 900)))
                        .opacity(resetReveal(t, start: 5.55, end: 7.1))
                case .shuffle, .off: EmptyView()
                }
            }.frame(width: size.width, height: size.height)
                .opacity(min(1, max(0, (animation.duration - t) / 0.6)))
        }
    }

    private func loopPlane(_ t: Double, size: CGSize) -> some View {
        let flight = ResetFlight.pose(at: t, size: size)
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                // A stream of individual paper pieces stays behind the plane.
                for i in 0..<240 {
                    let birth = Double(i) * 0.026
                    let age = t - birth
                    guard age > 0, age < 2.6 else { continue }
                    let origin = ResetFlight.pose(at: birth, size: size).position
                    let seed = resetNoise(i)
                    let point = CGPoint(x: origin.x - 48 + (seed - 0.5) * age * 100,
                                        y: origin.y + 12 + age * age * 37 + sin(age * 4 + Double(i)) * 14)
                    drawPaper(&context, at: point, index: i, rotation: age * 3 + seed * 8,
                              opacity: min(1, (2.6 - age) / 0.7))
                }
            }
            ProviderTravelArtwork(kind: .plane, providers: [provider], phase: t, animated: previewElapsed == nil)
                .scaleEffect(1.25).rotationEffect(.radians(flight.angle))
                .position(flight.position)
            ResetRibbon(caption: caption, subtitle: "back in the clouds")
                .position(x: size.width * 0.48, y: size.height * 0.48 + 85)
                .opacity(resetReveal(t, start: 3.8, end: 6.7))
                .offset(y: 8 * (1 - resetReveal(t, start: 3.8, end: 6.7)))
        }
    }

    private func cannonball(_ t: Double, size: CGSize, ground: CGFloat) -> some View {
        let poolX = size.width * 0.72
        let running = min(1, max(0, (t - 0.2) / 2.25))
        let jumping = min(1, max(0, (t - 2.45) / 0.9))
        let landed = t >= 3.35
        let runX = -80 + (poolX - 100) * running
        let petX = t < 2.45 ? runX : poolX - 180 + 180 * jumping
        let petY = ground - 51 - (t < 2.45 ? abs(sin(t * 17)) * 11 : sin(jumping * .pi) * 175)
        let surface = ground - 26
        return ZStack(alignment: .topLeading) {
            TokenPoolBack().position(x: poolX, y: surface)
                .opacity(min(1, t * 3)).scaleEffect(0.94 + min(1, t * 3) * 0.06)
            Canvas { context, _ in
                if t < 3.35 {
                    for i in 0..<18 {
                        let age = t - Double(i) * 0.14
                        guard age > 0, age < 0.8 else { continue }
                        let x = -80 + (poolX - 100) * min(1, Double(i) * 0.14 / 2.25)
                        let r = 3 + age * 9
                        context.fill(Path(ellipseIn: CGRect(x: x - age * 35, y: ground - 10 - age * 9,
                                                             width: r, height: r * 0.55)),
                                     with: .color(Color(red: 0.93, green: 0.87, blue: 0.70).opacity((0.8 - age) * 0.7)))
                    }
                }
            }
            if !landed {
                ProviderPet(provider: provider, animated: previewElapsed == nil)
                    .frame(width: 77, height: 77)
                    .rotationEffect(.degrees(t < 2.45 ? -8 + sin(t * 17) * 6 : jumping * 360))
                    .scaleEffect(t < 2.45 ? 1 : 1 - sin(jumping * .pi) * 0.17)
                    .position(x: petX, y: petY)
            } else {
                ProviderPet(provider: provider, animated: previewElapsed == nil, greeting: startedAt.addingTimeInterval(4.3))
                    .frame(width: 78, height: 78)
                    .position(x: poolX, y: ground - 50 + 45 * (1 - resetEase((t - 3.95) / 0.6)) + sin(t * 4) * 2)
                    .opacity(t > 3.95 ? 1 : 0)
            }
            TokenPoolFront(ripple: landed ? max(0, 1 - (t - 3.35) / 2) : 0, time: t)
                .position(x: poolX, y: surface + 21)
                .opacity(min(1, t * 3))
            TokenSplash(age: t - 3.35, origin: CGPoint(x: poolX, y: ground - 26), count: 35)
            ResetRibbon(caption: caption, subtitle: "the pool is full again")
                .position(x: poolX, y: ground - 150).opacity(resetReveal(t, start: 4.5, end: 7.0))
        }
    }

    private func delivery(_ t: Double, size: CGSize, ground: CGFloat) -> some View {
        let descent = resetEase(t / 3.5)
        let landed = t >= 3.5
        let x = size.width * 0.60 + sin(min(t, 3.5) * 2) * 24 * (1 - descent)
        let y = -100 + (ground + 60) * descent
        let drift = max(0, t - 3.7)
        return ZStack(alignment: .topLeading) {
            ResetParachute().rotationEffect(.degrees(landed ? drift * 22 : sin(t * 2) * 6))
                .position(x: x + drift * 90, y: y - 132 - drift * 65)
                .opacity(max(0, 1 - drift / 1.2))
            ProviderPet(provider: provider, animated: previewElapsed == nil,
                        greeting: startedAt.addingTimeInterval(4.4))
                .frame(width: 74, height: 74)
                .position(x: x, y: y - 43 - resetEase((t - 3.6) / 0.7) * 15)
            ResetParcel(open: resetEase((t - 3.7) / 0.45))
                .rotationEffect(.degrees(landed && t < 3.9 ? sin((t - 3.5) * 30) * 4 * (1 - (t - 3.5) / 0.4) : 0))
                .position(x: x, y: y)
            TokenSplash(age: t - 3.9, origin: CGPoint(x: x, y: y - 25), count: 24)
            ResetRibbon(caption: caption, subtitle: "a fresh delivery of possibilities")
                .position(x: x, y: ground - 177).opacity(resetReveal(t, start: 4.6, end: 7.0))
        }
    }
}

enum ResetFlight {
    static func pose(at t: Double, size: CGSize) -> (position: CGPoint, angle: Double) {
        let x: Double = size.width * 0.48
        let baseline: Double = size.height * 0.48
        let radius: Double = min(155, size.height * 0.19)
        if t < 1.9 {
            return (CGPoint(x: -160 + (x + 160) * max(0, t) / 1.9, y: baseline), 0)
        } else if t < 4.5 {
            let theta: Double = .pi / 2 - (t - 1.9) / 2.6 * 2 * .pi
            return (CGPoint(x: x + cos(theta) * radius, y: baseline - radius + sin(theta) * radius), theta - .pi / 2)
        } else {
            let exit: Double = (t - 4.5) / 2.7
            let distance: Double = size.width + 180 - x
            return (CGPoint(x: x + distance * exit,
                            y: baseline - exit * exit * 130), -atan(260 * exit / distance))
        }
    }
}

private struct ResetRibbon: View {
    let caption: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 3) {
            Text(caption).font(.system(size: 18, weight: .heavy, design: .rounded))
            Text(subtitle).font(.system(size: 10, weight: .medium)).tracking(0.3)
        }.foregroundStyle(ProviderPalette.ink).padding(.horizontal, 27).padding(.vertical, 11)
            .background(ResetFlag().fill(Color(red: 0.98, green: 0.93, blue: 0.76)))
            .overlay(ResetFlag().stroke(Color(red: 0.57, green: 0.48, blue: 0.29).opacity(0.6), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.13), radius: 7, y: 3)
    }
}

private struct ResetFlag: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: .zero); p.addLine(to: CGPoint(x: r.maxX, y: 0))
            p.addLine(to: CGPoint(x: r.maxX - 11, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: 0, y: r.maxY)); p.addLine(to: CGPoint(x: 11, y: r.midY)); p.closeSubpath()
        }
    }
}

private struct TokenPoolBack: View {
    var body: some View {
        ZStack {
            Ellipse().fill(Color(red: 0.20, green: 0.51, blue: 0.56)).frame(width: 256, height: 70)
            Ellipse().stroke(Color(red: 0.91, green: 0.79, blue: 0.57), lineWidth: 10).frame(width: 244, height: 60)
            ForEach(0..<16) { i in
                TokenCoin().frame(width: 15, height: 15)
                    .scaleEffect(y: 0.65).rotationEffect(.degrees(Double(i) * 19))
                    .offset(x: cos(Double(i) * 2.4) * Double(35 + i * 4), y: sin(Double(i) * 2.4) * 17)
            }
        }.frame(width: 268, height: 80)
    }
}

private struct TokenPoolFront: View {
    var ripple: Double = 0
    var time: Double = 0
    var body: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addCurve(to: CGPoint(x: 248, y: 0), control1: CGPoint(x: 22, y: 40), control2: CGPoint(x: 226, y: 40))
                p.addLine(to: CGPoint(x: 248, y: 25))
                p.addCurve(to: CGPoint(x: 0, y: 25), control1: CGPoint(x: 227, y: 70), control2: CGPoint(x: 20, y: 70))
                p.closeSubpath()
            }.fill(Color(red: 0.31, green: 0.63, blue: 0.66))
            Path { p in
                p.move(to: .zero)
                p.addCurve(to: CGPoint(x: 248, y: 0), control1: CGPoint(x: 22, y: 40), control2: CGPoint(x: 226, y: 40))
            }.stroke(Color(red: 0.97, green: 0.86, blue: 0.65), style: StrokeStyle(lineWidth: 9, lineCap: .round))
            ForEach(0..<10) { i in
                Capsule().fill(Color.white.opacity(0.15)).frame(width: 3, height: 18)
                    .position(x: 19 + CGFloat(i) * 23.3, y: 20 + sin(Double(i) / 9 * .pi) * 20)
            }
            if ripple > 0 {
                Ellipse().stroke(Color(red: 0.84, green: 0.96, blue: 0.91).opacity(ripple * 0.6), lineWidth: 2)
                    .frame(width: 35 + (1 - ripple) * 165, height: 7 + (1 - ripple) * 25)
                    .offset(y: -25)
            }
        }.frame(width: 248, height: 58)
    }
}

private struct TokenCoin: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.97, green: 0.76, blue: 0.35))
            Circle().stroke(Color(red: 0.64, green: 0.39, blue: 0.17), lineWidth: 1)
            Image(systemName: "sparkle").resizable().scaledToFit().padding(4)
                .foregroundStyle(Color(red: 0.61, green: 0.39, blue: 0.15))
        }
    }
}

private struct TokenSplash: View {
    let age: Double
    let origin: CGPoint
    var count = 30
    var body: some View {
        Canvas { context, _ in
            guard age >= 0, age < 2.8 else { return }
            for i in 0..<count {
                let seed = resetNoise(i)
                let vx = (seed - 0.5) * 310
                let vy = -170 - resetNoise(i + 39) * 180
                let x = origin.x + vx * age
                let y = origin.y + vy * age + 185 * age * age
                guard y < origin.y + 60 else { continue }
                var c = context
                c.opacity = min(1, (2.8 - age) / 0.5)
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(age * (seed - 0.5) * 12))
                if i % 3 == 0 {
                    c.fill(Path(ellipseIn: CGRect(x: -3, y: -7, width: 6, height: 14)),
                           with: .color(Color(red: 0.53, green: 0.84, blue: 0.84)))
                } else if let coin = c.resolveSymbol(id: "token") {
                    c.scaleBy(x: 0.35 + abs(cos(age * 7 + Double(i))) * 0.65, y: 1)
                    c.draw(coin, at: .zero)
                }
            }
        } symbols: { TokenCoin().frame(width: 18, height: 18).tag("token") }
    }
}

private struct ResetParachute: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                for x: CGFloat in [4, 48, 92, 136, 180] {
                    p.move(to: CGPoint(x: x, y: 65))
                    p.addLine(to: CGPoint(x: x < 92 ? 68 : 116, y: 159))
                }
            }.stroke(Color(red: 0.88, green: 0.79, blue: 0.58), lineWidth: 1.5)
            UnevenParachute().fill(Color(red: 0.96, green: 0.81, blue: 0.54))
                .frame(width: 184, height: 78)
            UnevenParachute().fill(Color(red: 0.30, green: 0.61, blue: 0.66))
                .frame(width: 96, height: 78).offset(x: 44)
            UnevenParachute().fill(Color(red: 0.98, green: 0.90, blue: 0.70))
                .frame(width: 40, height: 78).offset(x: 72)
        }.frame(width: 184, height: 165)
    }
}

private struct UnevenParachute: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: r.height * 0.85))
            p.addCurve(to: CGPoint(x: r.maxX, y: r.height * 0.85),
                       control1: CGPoint(x: 0, y: -r.height * 0.3), control2: CGPoint(x: r.maxX, y: -r.height * 0.3))
            p.addQuadCurve(to: CGPoint(x: 0, y: r.height * 0.85), control: CGPoint(x: r.midX, y: r.height * 0.56))
            p.closeSubpath()
        }
    }
}

private struct ResetParcel: View {
    var open: Double = 0
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.68, green: 0.44, blue: 0.26))
            ForEach([-15.0, 0, 15], id: \.self) { y in
                Rectangle().fill(Color(red: 0.88, green: 0.66, blue: 0.40)).frame(height: 2).offset(y: y)
            }
            HStack {
                RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.90, green: 0.71, blue: 0.44)).frame(width: 9)
                Spacer()
                RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.90, green: 0.71, blue: 0.44)).frame(width: 9)
            }.padding(.horizontal, 9)
            Text("QUOTA MAIL").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6)
                .foregroundStyle(Color(red: 0.34, green: 0.23, blue: 0.15)).padding(5)
                .background(Color(red: 0.96, green: 0.89, blue: 0.71)).rotationEffect(.degrees(-7))
            RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.90, green: 0.70, blue: 0.42)).frame(width: 126, height: 9)
                .rotationEffect(.degrees(-open * 22), anchor: .leading).offset(x: -open * 20, y: -31 - open * 6)
        }.frame(width: 120, height: 59)
    }
}

struct ProviderResetThumbnail: View {
    let animation: ProviderResetAnimation
    let provider: DisplayProvider
    var body: some View {
        ZStack {
            switch animation {
            case .shuffle:
                ForEach(0..<3) { index in
                    RoundedRectangle(cornerRadius: 12)
                        .fill([Color(red: 0.44, green: 0.73, blue: 0.78), Color(red: 0.93, green: 0.64, blue: 0.45), Color(red: 0.97, green: 0.89, blue: 0.68)][index])
                        .frame(width: 78, height: 95)
                        .rotationEffect(.degrees(Double(index - 1) * 14))
                        .offset(x: Double(index - 1) * 17, y: Double(index) * 3 - 4)
                }
                ProviderPet(provider: provider, animated: false).frame(width: 54, height: 57).offset(x: 17, y: -5)
                Image(systemName: "shuffle").font(.system(size: 19, weight: .bold))
                    .foregroundStyle(ProviderPalette.ink).offset(x: 17, y: 35)
            case .loopPlane:
                Circle().trim(from: 0.05, to: 0.88)
                    .stroke(provider.tint.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                    .frame(width: 88, height: 88).offset(x: -14, y: -5)
                ProviderTravelArtwork(kind: .plane, providers: [provider])
                    .scaleEffect(0.80).rotationEffect(.degrees(-24)).offset(x: 15, y: 20)
                ForEach(0..<8) { i in
                    RoundedRectangle(cornerRadius: 1).fill(i % 2 == 0 ? provider.tint : Color.orange.opacity(0.8))
                        .frame(width: 4, height: 7).rotationEffect(.degrees(Double(i) * 37))
                        .offset(x: -52 + Double(i) * 8, y: 45 - Double(i % 3) * 14)
                }
            case .tokenPool:
                TokenPoolBack().scaleEffect(0.48).offset(y: 30)
                ProviderPet(provider: provider, animated: false).frame(width: 61, height: 61).rotationEffect(.degrees(-14)).offset(y: -5)
                TokenPoolFront().scaleEffect(0.48).offset(y: 42)
                ForEach(0..<5) { i in
                    TokenCoin().frame(width: 12, height: 12).offset(x: -55 + Double(i) * 26, y: -25 - sin(Double(i)) * 22)
                }
            case .parachute:
                ResetParachute().scaleEffect(0.62).offset(y: -13)
                ProviderPet(provider: provider, animated: false).frame(width: 46, height: 46).offset(y: 19)
                ResetParcel().scaleEffect(0.60).offset(y: 44)
            case .popcorn: ResetPopcornThumbnail(provider: provider)
            case .bubble: ResetBubbleThumbnail(provider: provider)
            case .garden: ResetGardenThumbnail(provider: provider)
            case .treasure: ResetTreasureThumbnail(provider: provider)
            case .off:
                ProviderPet(provider: provider, animated: false).frame(width: 65, height: 65).opacity(0.45)
                Text("zzz").font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(.secondary).offset(x: 35, y: -30)
            }
        }.frame(width: 152, height: 144).clipped().accessibilityHidden(true)
    }
}

private func resetNoise(_ index: Int) -> Double {
    let v = sin(Double(index + 1) * 127.1) * 43_758.5453
    return v - floor(v)
}
private func resetEase(_ raw: Double) -> Double {
    let t = min(1, max(0, raw))
    return 1 - pow(1 - t, 3)
}
private func resetReveal(_ t: Double, start: Double, end: Double) -> Double {
    min(1, max(0, (t - start) / 0.35)) * min(1, max(0, (end - t) / 0.35))
}
private func drawPaper(_ context: inout GraphicsContext, at point: CGPoint, index: Int, rotation: Double, opacity: Double) {
    let colors = [Color(red: 0.55, green: 0.80, blue: 0.83), Color(red: 0.98, green: 0.75, blue: 0.38),
                  Color(red: 0.93, green: 0.57, blue: 0.41), Color(red: 0.68, green: 0.82, blue: 0.53)]
    var c = context
    c.opacity = opacity
    c.translateBy(x: point.x, y: point.y)
    c.rotate(by: .radians(rotation))
    c.scaleBy(x: 0.3 + abs(cos(rotation)) * 0.7, y: 1)
    c.fill(Path(roundedRect: CGRect(x: -3, y: -5, width: 6, height: 10), cornerRadius: 1),
           with: .color(colors[index % colors.count]))
}
