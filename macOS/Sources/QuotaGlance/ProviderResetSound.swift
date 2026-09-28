import AVFoundation
import Foundation
import OSLog

@MainActor
final class ProviderResetAudioPlayer {
    private var player: AVAudioPlayer?
    private var cache: [String: Data] = [:]
    private let logger = Logger(subsystem: "com.example.quotaglance", category: "ResetSounds")

    func prepare(_ animation: ProviderResetAnimation, reducedMotion: Bool) {
        stop()
        let key = animation.rawValue + (reducedMotion ? ".short" : "")
        guard let data = cache[key] ?? ProviderResetSoundtrack.data(for: animation, reducedMotion: reducedMotion) else { return }
        cache[key] = data
        do {
            let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
            player.volume = 0.55
            player.prepareToPlay()
            self.player = player
        } catch {
            logger.error("Could not play reset effect: \(error.localizedDescription, privacy: .public)")
        }
    }

    func play() { player?.play() }
    func stop() { player?.stop(); player = nil }
}

/// Original, locally synthesized cartoon effects. Cue times share the scene's
/// timeline; silence between cues keeps the whole celebration from becoming a jingle.
enum ProviderResetSoundtrack {
    private enum Voice { case bell, tone, pop, bubble, whoosh, motor, splash, water, thud, wood }
    private struct Cue {
        let start: Double
        let duration: Double
        let voice: Voice
        let frequency: Double
        let endFrequency: Double
        let level: Double
        init(_ start: Double, _ duration: Double, _ voice: Voice,
             _ frequency: Double = 440, _ endFrequency: Double? = nil, _ level: Double = 0.4) {
            self.start = start; self.duration = duration; self.voice = voice
            self.frequency = frequency; self.endFrequency = endFrequency ?? frequency; self.level = level
        }
    }
    private static let sampleRate = 22_050.0

    static func data(for animation: ProviderResetAnimation, reducedMotion: Bool = false) -> Data? {
        let cues = reducedMotion ? shortCues(animation) : cues(animation)
        guard let end = cues.map({ $0.start + $0.duration }).max() else { return nil }
        var samples = [Double](repeating: 0, count: Int(ceil((end + 0.08) * sampleRate)))
        for (index, cue) in cues.enumerated() { mix(cue, index: index, into: &samples) }
        return wave(samples)
    }

    private static func cues(_ animation: ProviderResetAnimation) -> [Cue] {
        switch animation {
        case .loopPlane:
            return [Cue(0.20, 0.60, .motor, 115, 160, 0.20),
                    Cue(1.90, 0.80, .whoosh, 200, 650, 0.28),
                    Cue(3.45, 0.45, .whoosh, 500, 150, 0.22),
                    Cue(3.82, 0.24, .bell, 1047, nil, 0.18),
                    Cue(4.00, 0.28, .bell, 1319, nil, 0.17),
                    Cue(4.19, 0.30, .bell, 1568, nil, 0.14)]
        case .tokenPool:
            return [Cue(0.65, 0.09, .thud, 150, 75, 0.18), Cue(0.96, 0.08, .thud, 180, 90, 0.16),
                    Cue(1.25, 0.08, .thud, 150, 75, 0.14), Cue(1.52, 0.08, .thud, 180, 90, 0.12),
                    Cue(2.45, 0.40, .whoosh, 180, 800, 0.23),
                    Cue(3.35, 0.48, .splash, 130, 60, 0.55),
                    Cue(3.48, 0.18, .bubble, 480, 190, 0.30), Cue(3.71, 0.20, .bubble, 690, 290, 0.26),
                    Cue(4.25, 0.27, .bell, 784, nil, 0.20)]
        case .parachute:
            return [Cue(0.30, 0.50, .whoosh, 310, 220, 0.13),
                    Cue(3.50, 0.16, .thud, 165, 70, 0.34), Cue(3.87, 0.12, .wood, 390, 240, 0.22),
                    Cue(3.99, 0.22, .bell, 784, nil, 0.26), Cue(4.13, 0.23, .bell, 988, nil, 0.24),
                    Cue(4.29, 0.30, .bell, 1175, nil, 0.22)]
        case .popcorn:
            return [Cue(2.25, 0.11, .pop, 1100, 210, 0.40), Cue(2.61, 0.10, .pop, 1400, 260, 0.34),
                    Cue(2.84, 0.10, .pop, 900, 190, 0.38), Cue(3.14, 0.12, .pop, 1500, 300, 0.30),
                    Cue(3.38, 0.10, .pop, 1050, 230, 0.35), Cue(3.55, 0.16, .pop, 1700, 320, 0.40),
                    Cue(3.80, 0.27, .bell, 1319, nil, 0.20)]
        case .bubble:
            return [Cue(1.00, 0.90, .whoosh, 150, 370, 0.16), Cue(2.40, 0.18, .bubble, 280, 650, 0.20),
                    Cue(3.30, 0.20, .bubble, 260, 520, 0.22), Cue(4.20, 0.22, .bubble, 360, 720, 0.22),
                    Cue(4.85, 0.12, .pop, 1800, 450, 0.34),
                    Cue(4.97, 0.25, .bell, 1568, nil, 0.17), Cue(5.12, 0.28, .bell, 2093, nil, 0.12),
                    Cue(6.15, 0.14, .bubble, 350, 140, 0.20)]
        case .garden:
            return [Cue(1.10, 0.70, .water, 200, 130, 0.28), Cue(1.26, 0.14, .bubble, 640, 330, 0.13),
                    Cue(1.56, 0.12, .bubble, 750, 400, 0.12), Cue(2.25, 0.15, .pop, 450, 800, 0.24),
                    Cue(3.45, 0.30, .bell, 523, nil, 0.29), Cue(3.61, 0.35, .bell, 659, nil, 0.25),
                    Cue(3.77, 0.40, .bell, 784, nil, 0.23), Cue(5.35, 0.15, .tone, 1250, 1750, 0.12)]
        case .treasure:
            return [Cue(1.80, 0.20, .thud, 100, 55, 0.28), Cue(1.81, 0.23, .whoosh, 180, 80, 0.16),
                    Cue(2.75, 0.12, .wood, 320, 160, 0.35), Cue(2.80, 0.10, .wood, 600, 250, 0.22),
                    Cue(3.05, 0.30, .bell, 988, nil, 0.26), Cue(3.15, 0.24, .bell, 1480, nil, 0.22),
                    Cue(3.30, 0.30, .bell, 1175, nil, 0.22), Cue(3.47, 0.22, .bell, 1760, nil, 0.16),
                    Cue(4.50, 0.20, .bubble, 650, 160, 0.35), Cue(5.35, 0.38, .bell, 1320, nil, 0.23)]
        case .shuffle, .off: return []
        }
    }

    private static func shortCues(_ animation: ProviderResetAnimation) -> [Cue] {
        switch animation {
        case .loopPlane: return [Cue(0, 0.35, .whoosh, 200, 600, 0.22), Cue(0.22, 0.28, .bell, 1319, nil, 0.18)]
        case .tokenPool: return [Cue(0, 0.30, .splash, 130, 60, 0.40), Cue(0.20, 0.18, .bubble, 690, 290, 0.24)]
        case .parachute: return [Cue(0, 0.12, .thud, 165, 70, 0.26), Cue(0.14, 0.32, .bell, 1175, nil, 0.23)]
        case .popcorn: return [Cue(0, 0.10, .pop, 1100, 210, 0.34), Cue(0.16, 0.10, .pop, 1400, 260, 0.30), Cue(0.31, 0.12, .pop, 1700, 320, 0.30)]
        case .bubble: return [Cue(0, 0.22, .bubble, 280, 650, 0.26), Cue(0.25, 0.12, .pop, 1800, 450, 0.24)]
        case .garden: return [Cue(0, 0.25, .water, 200, 130, 0.24), Cue(0.24, 0.25, .bell, 659, nil, 0.22), Cue(0.38, 0.28, .bell, 784, nil, 0.20)]
        case .treasure: return [Cue(0, 0.12, .wood, 320, 160, 0.28), Cue(0.12, 0.28, .bell, 988, nil, 0.22), Cue(0.25, 0.30, .bell, 1480, nil, 0.20)]
        case .shuffle, .off: return []
        }
    }

    private static func mix(_ cue: Cue, index: Int, into samples: inout [Double]) {
        let first = Int(cue.start * sampleRate)
        let count = Int(cue.duration * sampleRate)
        var noiseState = UInt64(index + 19) &* 0x9e3779b97f4a7c15
        var filtered = 0.0
        for i in 0..<count {
            let time = Double(i) / sampleRate
            let progress = time / cue.duration
            let phase = 2 * Double.pi * (cue.frequency * time + 0.5 * (cue.endFrequency - cue.frequency) * time * progress)
            noiseState = noiseState &* 6364136223846793005 &+ 1442695040888963407
            let noise = Double(noiseState >> 32) / Double(UInt32.max) * 2 - 1
            filtered += 0.18 * (noise - filtered)
            let attack = min(1, time / 0.006)
            let release = min(1, (cue.duration - time) / 0.025)
            let signal: Double
            let envelope: Double
            switch cue.voice {
            case .bell:
                signal = sin(phase) * 0.70 + sin(phase * 2.756) * 0.20 + sin(phase * 5.404) * 0.10
                envelope = exp(-5.2 * progress)
            case .tone:
                signal = sin(phase) * 0.85 + sin(phase * 2) * 0.15
                envelope = sin(.pi * progress)
            case .pop:
                signal = sin(phase) * 0.65 + noise * 0.22 + filtered * 0.13
                envelope = exp(-7 * progress)
            case .bubble:
                signal = sin(phase + sin(progress * .pi) * 3) * 0.9 + sin(phase * 2) * 0.10
                envelope = sin(.pi * progress) * exp(-2 * progress)
            case .whoosh:
                signal = filtered * 2.2 + sin(phase) * 0.12
                envelope = pow(sin(.pi * progress), 1.5)
            case .motor:
                signal = (sin(phase) * 0.65 + sin(phase * 2) * 0.18 + filtered * 0.3) * (0.7 + sin(time * 2 * .pi * 26) * 0.3)
                envelope = sin(.pi * progress)
            case .splash:
                signal = filtered * 2.8 + (noise - filtered) * 0.20 + sin(phase) * 0.15
                envelope = exp(-3.2 * progress) * (0.78 + sin(time * 39) * 0.22)
            case .water:
                signal = filtered * 2.0 + (noise - filtered) * 0.15
                envelope = sin(.pi * progress) * (0.70 + sin(time * 37) * sin(time * 19) * 0.3)
            case .thud:
                signal = sin(phase) * 0.85 + filtered * 0.25
                envelope = exp(-6 * progress)
            case .wood:
                signal = sin(phase) * 0.5 + sin(phase * 2.13) * 0.2 + noise * 0.3
                envelope = exp(-9 * progress)
            }
            samples[first + i] += signal * envelope * attack * release * cue.level
        }
    }

    private static func wave(_ samples: [Double]) -> Data {
        let byteCount = UInt32(samples.count * 2)
        var data = Data()
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            Swift.withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8); word(UInt32(36) + byteCount)
        data.append(contentsOf: "WAVEfmt ".utf8); word(UInt32(16)); word(UInt16(1)); word(UInt16(1))
        word(UInt32(sampleRate)); word(UInt32(sampleRate * 2)); word(UInt16(2)); word(UInt16(16))
        data.append(contentsOf: "data".utf8); word(byteCount)
        for sample in samples {
            // A soft limiter and a conservative ceiling avoid sharp/loud peaks.
            word(Int16((tanh(sample * 1.2) * 0.48 * Double(Int16.max)).rounded()))
        }
        return data
    }
}
