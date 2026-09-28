import Foundation

enum ProviderLayoutShuffleInterval: Int, CaseIterable, Identifiable {
    case minute = 60, hour = 3_600, day = 86_400
    var id: Int { rawValue }
    var title: String {
        switch self { case .minute: "1 minute"; case .hour: "1 hour"; case .day: "1 day" }
    }
}

/// Persist both the deadline and the remaining choices. Relaunching keeps an
/// hourly/daily schedule; waking after several intervals makes one change.
struct ProviderLayoutShuffle {
    private(set) var isEnabled = false
    private(set) var interval = ProviderLayoutShuffleInterval.hour
    private(set) var nextChangeAt: Date?
    private var remaining: [ProviderDisplayStyle] = []
    private static let key = "QuotaGlance.layoutShuffle."

    static func load(from defaults: UserDefaults = .standard) -> Self {
        var value = Self()
        value.isEnabled = defaults.bool(forKey: key + "enabled")
        value.interval = ProviderLayoutShuffleInterval(rawValue: defaults.integer(forKey: key + "interval")) ?? .hour
        value.nextChangeAt = defaults.object(forKey: key + "nextChangeAt") as? Date
        var seen = Set<ProviderDisplayStyle>()
        value.remaining = (defaults.stringArray(forKey: key + "remaining") ?? [])
            .compactMap(ProviderDisplayStyle.init(rawValue:)).filter { seen.insert($0).inserted }
        return value
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Self.key + "enabled")
        defaults.set(interval.rawValue, forKey: Self.key + "interval")
        defaults.set(nextChangeAt, forKey: Self.key + "nextChangeAt")
        defaults.set(remaining.map(\.rawValue), forKey: Self.key + "remaining")
    }

    mutating func setEnabled(_ enabled: Bool, at now: Date) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        remaining.removeAll()
        nextChangeAt = enabled ? now : nil
    }

    mutating func setInterval(_ value: ProviderLayoutShuffleInterval, at now: Date) {
        guard value != interval else { return }
        interval = value
        nextChangeAt = isEnabled ? now.addingTimeInterval(Double(value.rawValue)) : nil
    }

    func isDue(at now: Date) -> Bool {
        isEnabled && (nextChangeAt == nil || nextChangeAt! <= now)
    }

    mutating func advance<R: RandomNumberGenerator>(after current: ProviderDisplayStyle,
                                                   at now: Date, using random: inout R) -> ProviderDisplayStyle? {
        guard isEnabled else { return nil }
        if remaining.isEmpty || remaining == [current] {
            remaining = ProviderDisplayStyle.allCases.shuffled(using: &random)
        }
        if remaining.first == current, remaining.count > 1 {
            remaining.swapAt(0, Int.random(in: 1..<remaining.count, using: &random))
        }
        nextChangeAt = now.addingTimeInterval(Double(interval.rawValue))
        return remaining.removeFirst()
    }
}
