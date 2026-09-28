import Foundation

enum ProviderResetAnimation: String, CaseIterable, Identifiable {
    case shuffle, loopPlane, tokenPool, parachute, popcorn, bubble, garden, treasure, off
    static var performances: [Self] { allCases.filter { $0 != .shuffle && $0 != .off } }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .shuffle: return "Shuffle"
        case .loopPlane: return "Loop-the-loop"
        case .tokenPool: return "Token cannonball"
        case .parachute: return "Special delivery"
        case .popcorn: return "Popcorn party"
        case .bubble: return "Bubble bounce"
        case .garden: return "Token garden"
        case .treasure: return "Treasure dive"
        case .off: return "Off"
        }
    }
    var caption: String {
        switch self {
        case .shuffle: return "A surprise from all seven. Every scene gets a turn."
        case .loopPlane: return "A pet pilot, one big loop, and a trail of confetti."
        case .tokenPool: return "A running jump into a pool full of tokens. Splash."
        case .parachute: return "A parachute brings a fresh crate of tokens."
        case .popcorn: return "A little cinema cart pops a fresh batch of tokens."
        case .bubble: return "A giant bubble, a floating pet, and a sparkly pop."
        case .garden: return "A watered seed blooms into a garden of tokens."
        case .treasure: return "One tiny treasure hunter. A chest full of possibility."
        case .off: return "Keep reset celebrations quiet."
        }
    }
    var duration: TimeInterval { self == .loopPlane ? 7.2 : 7.6 }
}

/// Separate shuffled bags give both pets every scene before repeating one.
/// The next bag also avoids an immediate repeat across the cycle boundary.
struct ProviderResetShuffle {
    private var bags: [DisplayProvider: [ProviderResetAnimation]] = [:]
    private var previous: [DisplayProvider: ProviderResetAnimation] = [:]

    mutating func resolve<R: RandomNumberGenerator>(_ choice: ProviderResetAnimation,
                                                    for provider: DisplayProvider,
                                                    using random: inout R) -> ProviderResetAnimation? {
        guard choice != .off else { return nil }
        guard choice == .shuffle else { previous[provider] = choice; return choice }
        var bag = bags[provider] ?? []
        if bag.isEmpty { bag = ProviderResetAnimation.performances.shuffled(using: &random) }
        if bag.count > 1, bag.first == previous[provider] {
            bag.swapAt(0, Int.random(in: 1..<bag.count, using: &random))
        }
        let next = bag.removeFirst()
        bags[provider] = bag
        previous[provider] = next
        return next
    }
}

struct ProviderResetEvent: Equatable {
    let provider: DisplayProvider
    let identity: String
    let caption: String
}
