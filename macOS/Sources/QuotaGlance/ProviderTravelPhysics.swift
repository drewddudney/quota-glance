import Foundation

enum ProviderTravelKind: String {
    case plane, balloon, skateboard
    var size: CGSize {
        switch self {
        case .plane: return CGSize(width: 132, height: 104)
        case .balloon: return CGSize(width: 136, height: 192)
        case .skateboard: return CGSize(width: 150, height: 88)
        }
    }
    var bannerWidth: CGFloat { self == .balloon ? 278 : 337 }
    var speed: CGFloat { self == .plane ? 100 : self == .balloon ? 65 : 135 }
}

enum ProviderTravelFrequency: String, CaseIterable, Identifiable {
    case continuous, often, relaxed
    static let key = "QuotaGlance.travelFrequency"
    var id: String { rawValue }
    var title: String {
        switch self { case .continuous: return "Back-to-back"; case .often: return "Every 45 sec"; case .relaxed: return "Every 2 min" }
    }
    var interval: TimeInterval { self == .continuous ? 0 : self == .often ? 45 : 120 }
    static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .often }
    func rest(after elapsed: TimeInterval) -> TimeInterval { max(4, interval - max(0, elapsed)) }
}

/// Screen coordinates (positive y is up). The vehicle and its sign are separate
/// bodies, so the sign follows a spring instead of moving rigidly with a drag.
struct ProviderTravelPhysics {
    let kind: ProviderTravelKind
    let providerCount: Int
    let bounds: CGRect
    var position: CGPoint
    var velocity: CGVector
    var bannerPosition: CGPoint
    var bannerVelocity = CGVector.zero
    var heading: CGFloat
    var isHeld = false
    var isPaused = false
    var age: TimeInterval = 0
    var bank: CGFloat = 0
    private let lane: CGFloat

    init(kind: ProviderTravelKind, bounds: CGRect, fromLeft: Bool = true, parked: Bool = false, providerCount: Int = 2) {
        self.kind = kind; self.bounds = bounds; self.providerCount = max(1, min(2, providerCount))
        heading = fromLeft ? 1 : -1
        let height = kind.size.height
        lane = kind == .skateboard ? bounds.minY + height / 2 + 14
            : bounds.minY + bounds.height * (kind == .balloon ? 0.64 : 0.72)
        position = CGPoint(x: parked ? bounds.midX + (kind == .balloon ? 0 : 120)
                           : fromLeft ? bounds.minX - kind.size.width / 2 - 2 : bounds.maxX + kind.size.width / 2 + 2, y: lane)
        velocity = CGVector(dx: heading * kind.speed, dy: 0)
        bannerPosition = .zero
        bannerPosition = bannerTarget
    }

    var vehicleRect: CGRect { CGRect(x: position.x - kind.size.width / 2, y: position.y - kind.size.height / 2, width: kind.size.width, height: kind.size.height) }
    var bannerHeight: CGFloat { providerCount == 1 ? 78 : 100 }
    var bannerRect: CGRect { CGRect(x: bannerPosition.x - kind.bannerWidth / 2, y: bannerPosition.y - bannerHeight / 2, width: kind.bannerWidth, height: bannerHeight) }
    var renderBounds: CGRect { vehicleRect.union(bannerRect).insetBy(dx: -18, dy: -20) }
    var hasExited: Bool {
        age > 2 && !isHeld && !isPaused && (heading > 0 ? renderBounds.minX > bounds.maxX : renderBounds.maxX < bounds.minX)
    }
    var bannerTarget: CGPoint {
        if kind == .balloon { return CGPoint(x: position.x, y: position.y - 158) }
        return CGPoint(x: position.x - heading * (kind.size.width / 2 + kind.bannerWidth / 2 + 28),
                       y: min(bounds.maxY - 52, max(bounds.minY + 52, position.y + (kind == .skateboard ? 24 : 0))))
    }

    mutating func grab() { isHeld = true; isPaused = false; velocity = .zero }
    mutating func drag(to point: CGPoint, velocity newVelocity: CGVector) {
        guard point.x.isFinite, point.y.isFinite, newVelocity.dx.isFinite, newVelocity.dy.isFinite else { return }
        position.x = min(bounds.maxX - kind.size.width / 2, max(bounds.minX + kind.size.width / 2, point.x))
        position.y = min(bounds.maxY - kind.size.height / 2, max(bounds.minY + kind.size.height / 2, point.y))
        velocity = CGVector(dx: min(950, max(-950, newVelocity.dx)), dy: min(750, max(-750, newVelocity.dy)))
    }
    mutating func release() {
        isHeld = false; isPaused = false
        if abs(velocity.dx) > 80 { heading = velocity.dx >= 0 ? 1 : -1 }
        if abs(velocity.dx) < 60 { velocity.dx = heading * kind.speed }
    }

    mutating func step(_ interval: TimeInterval, parked: Bool = false) {
        guard interval.isFinite, interval > 0 else { return }
        let dt = CGFloat(min(interval, 1.0 / 20))
        age += Double(dt)
        if !isHeld && !isPaused && !parked {
            let regain: CGFloat = kind == .balloon ? 0.7 : 0.5
            velocity.dx += (heading * kind.speed - velocity.dx) * min(1, regain * dt)
            if kind == .skateboard {
                velocity.dy -= 650 * dt
                if position.y <= lane && velocity.dy < 0 {
                    position.y = lane
                    velocity.dy = abs(velocity.dy) > 60 ? -velocity.dy * 0.28 : 0
                }
            } else {
                let wobble = sin(age * (kind == .balloon ? 1.3 : 0.85)) * (kind == .balloon ? 13 : 5)
                velocity.dy += ((lane + wobble - position.y) * (kind == .balloon ? 0.8 : 0.3) - velocity.dy * 1.3) * dt
            }
            position.x += velocity.dx * dt; position.y += velocity.dy * dt
            let ceiling = bounds.maxY - kind.size.height / 2 - 4
            let floor = kind == .skateboard ? lane : bounds.minY + kind.size.height / 2 + 4
            if position.y > ceiling { position.y = ceiling; velocity.dy = min(0, velocity.dy) * 0.3 }
            if position.y < floor {
                position.y = floor
                velocity.dy = kind == .skateboard && abs(velocity.dy) > 60 ? -velocity.dy * 0.28 : 0
            }
        }
        let targetBank: CGFloat
        if parked { targetBank = 0 }
        else if kind == .balloon { targetBank = max(-12, min(12, velocity.dx * 0.045)) }
        else {
            let angle = CGFloat(atan2(Double(velocity.dy), abs(Double(velocity.dx)) + 70.0))
            let degrees = -angle * (180 / CGFloat.pi) * heading * 0.55
            targetBank = max(-23, min(23, degrees))
        }
        bank += (targetBank - bank) * min(1, dt * 7)
        let target = bannerTarget
        let stiffness: CGFloat = kind == .balloon ? 28 : 44
        bannerVelocity.dx += (target.x - bannerPosition.x) * stiffness * dt
        bannerVelocity.dy += (target.y - bannerPosition.y) * stiffness * dt
        let decay = exp(-CGFloat(kind == .balloon ? 5 : 8) * dt)
        bannerVelocity.dx *= decay; bannerVelocity.dy *= decay
        bannerPosition.x += bannerVelocity.dx * dt; bannerPosition.y += bannerVelocity.dy * dt
        bannerPosition.y = min(bounds.maxY - 52, max(bounds.minY + 52, bannerPosition.y))
    }
}
