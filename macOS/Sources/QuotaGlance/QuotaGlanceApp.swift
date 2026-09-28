import AppKit
import Charts
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import WebKit

@main
struct QuotaGlanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appSettings) {
                Button("Layout…") { ProviderDisplayController.shared.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let quotaGlanceRefresh = Notification.Name("QuotaGlance.refresh")
    static let quotaGlanceThemeChanged = Notification.Name("QuotaGlance.themeChanged")
    static let quotaGlancePaceRateChanged = Notification.Name("QuotaGlance.paceRateChanged")
    static let quotaGlanceResetCalculatorChanged = Notification.Name("QuotaGlance.resetCalculatorChanged")
    static let quotaGlanceBillingUpdated = Notification.Name("QuotaGlance.billingUpdated")
    static let quotaGlanceDockChanged = Notification.Name("QuotaGlance.dockChanged")
    static let quotaGlanceMenuInteraction = Notification.Name("QuotaGlance.menuInteraction")
    static let quotaGlanceMenuBarSummaryChanged = Notification.Name("QuotaGlance.menuBarSummaryChanged")
    static let quotaGlanceShowTweets = Notification.Name("QuotaGlance.showTweets")
    static let quotaGlancePrivateLiveFeedTest = Notification.Name("QuotaGlance.privateLiveFeedTest")
    static let quotaGlanceProvidersChanged = Notification.Name("QuotaGlance.providersChanged")
    static let quotaGlanceOpenCodexResetCalculator = Notification.Name("QuotaGlance.openCodexResetCalculator")
}

enum DockPosition: String, CaseIterable, Sendable {
    case floating
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    static let defaultsKey = "QuotaGlance.dockPosition"

    var isMounted: Bool { self != .floating }
    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }

    var isEdge: Bool { isMounted && !isCorner }

    var mountedSize: NSSize {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return NSSize(width: 176, height: 176)
        case .left, .right:
            return NSSize(width: 112, height: 330)
        case .top, .bottom:
            return NSSize(width: 330, height: 112)
        case .floating:
            return .zero
        }
    }
}

enum DockingGeometry {
    static func candidate(
        for point: NSPoint,
        in visibleFrame: NSRect,
        threshold: CGFloat = 8
    ) -> DockPosition {
        let nearLeft = abs(point.x - visibleFrame.minX) <= threshold
        let nearRight = abs(point.x - visibleFrame.maxX) <= threshold
        let nearTop = abs(point.y - visibleFrame.maxY) <= threshold
        let nearBottom = abs(point.y - visibleFrame.minY) <= threshold
        if nearTop && nearLeft { return .topLeft }
        if nearTop && nearRight { return .topRight }
        if nearBottom && nearLeft { return .bottomLeft }
        if nearBottom && nearRight { return .bottomRight }
        if nearLeft { return .left }
        if nearRight { return .right }
        if nearTop { return .top }
        if nearBottom { return .bottom }
        return .floating
    }

    static func candidate(
        for frame: NSRect,
        in visibleFrame: NSRect,
        threshold: CGFloat = 46
    ) -> DockPosition {
        let nearLeft = abs(frame.minX - visibleFrame.minX) <= threshold
        let nearRight = abs(frame.maxX - visibleFrame.maxX) <= threshold
        let nearTop = abs(frame.maxY - visibleFrame.maxY) <= threshold
        let nearBottom = abs(frame.minY - visibleFrame.minY) <= threshold

        if nearTop && nearLeft { return .topLeft }
        if nearTop && nearRight { return .topRight }
        if nearBottom && nearLeft { return .bottomLeft }
        if nearBottom && nearRight { return .bottomRight }
        if nearLeft { return .left }
        if nearRight { return .right }
        if nearTop { return .top }
        if nearBottom { return .bottom }
        return .floating
    }

    static func mountedFrame(
        for position: DockPosition,
        in visibleFrame: NSRect,
        sideFraction: CGFloat,
        scale: CGFloat = 1
    ) -> NSRect {
        guard position.isMounted else { return .zero }
        let baseSize = position.mountedSize
        let size = NSSize(width: baseSize.width * scale, height: baseSize.height * scale)
        let fraction = max(0, min(1, sideFraction))
        let sideX = visibleFrame.minX + fraction * visibleFrame.width - size.width / 2
        let sideY = visibleFrame.minY + fraction * visibleFrame.height - size.height / 2
        let clampedX = min(max(sideX, visibleFrame.minX), visibleFrame.maxX - size.width)
        let clampedY = min(max(sideY, visibleFrame.minY), visibleFrame.maxY - size.height)

        switch position {
        case .topLeft:
            return NSRect(x: visibleFrame.minX, y: visibleFrame.maxY - size.height, width: size.width, height: size.height)
        case .topRight:
            return NSRect(x: visibleFrame.maxX - size.width, y: visibleFrame.maxY - size.height, width: size.width, height: size.height)
        case .bottomLeft:
            return NSRect(x: visibleFrame.minX, y: visibleFrame.minY, width: size.width, height: size.height)
        case .bottomRight:
            return NSRect(x: visibleFrame.maxX - size.width, y: visibleFrame.minY, width: size.width, height: size.height)
        case .left:
            return NSRect(x: visibleFrame.minX, y: clampedY, width: size.width, height: size.height)
        case .right:
            return NSRect(x: visibleFrame.maxX - size.width, y: clampedY, width: size.width, height: size.height)
        case .top:
            return NSRect(x: clampedX, y: visibleFrame.maxY - size.height, width: size.width, height: size.height)
        case .bottom:
            return NSRect(x: clampedX, y: visibleFrame.minY, width: size.width, height: size.height)
        case .floating:
            return .zero
        }
    }

    static func sideFraction(for frame: NSRect, position: DockPosition, in visibleFrame: NSRect) -> CGFloat {
        switch position {
        case .left, .right:
            return (frame.midY - visibleFrame.minY) / max(1, visibleFrame.height)
        case .top, .bottom:
            return (frame.midX - visibleFrame.minX) / max(1, visibleFrame.width)
        case .topLeft: return 0
        case .topRight: return 1
        case .bottomLeft: return 0
        case .bottomRight: return 1
        case .floating: return 0.5
        }
    }
}

enum FloatingLayoutGeometry {
    private static let minimumSide: CGFloat = 118
    private static let compactTransitionSide: CGFloat = 132
    private static let stripRatio: CGFloat = 3

    static func isCompact(_ size: NSSize) -> Bool {
        let shortSide = max(1, min(size.width, size.height))
        let longSide = max(size.width, size.height)
        // A compact window is genuinely square. The very tight ratio keeps
        // the near-square squeeze plateau below from changing layouts early,
        // while still recognizing previously saved 118...220 pt circles.
        return longSide <= 220 && longSide / shortSide <= 1.001
    }

    static func normalized(_ size: NSSize) -> NSSize {
        let width = min(max(size.width, minimumSide), 1200)
        let height = min(max(size.height, minimumSide), 1200)
        let clamped = NSSize(width: width, height: height)
        if isCompact(clamped) {
            let side = min(220, max(minimumSide, sqrt(width * height)))
            return NSSize(width: side, height: side)
        }
        if height > width {
            let longSide = min(1200, max(420, height))
            return NSSize(width: longSide / 3, height: longSide)
        }
        let longSide = min(1200, max(420, width))
        return NSSize(width: longSide, height: longSide / 3)
    }

    static func resized(from startSize: NSSize, deltaX: CGFloat, deltaY: CGFloat) -> NSSize {
        if isCompact(startSize) {
            let horizontalChange = deltaX
            let verticalChange = -deltaY
            let change = abs(horizontalChange) >= abs(verticalChange) ? horizontalChange : verticalChange
            let side = min(220, max(minimumSide, startSize.width + change))
            return NSSize(width: side, height: side)
        }
        if startSize.height > startSize.width {
            let horizontalChange = deltaX
            let verticalEquivalent = -deltaY / 3
            let usesHorizontalGesture = abs(horizontalChange) >= abs(verticalEquivalent)
            if startSize.width <= compactTransitionSide,
               startSize.height < compactTransitionSide * stripRatio {
                let rawChange = usesHorizontalGesture ? horizontalChange : -deltaY
                return verticalSquish(longSide: startSize.height + rawChange)
            }
            let change = usesHorizontalGesture ? horizontalChange : verticalEquivalent
            let proposedWidth = startSize.width + change
            if proposedWidth < compactTransitionSide {
                let gestureScale: CGFloat = usesHorizontalGesture ? 1 : stripRatio
                let longSide = compactTransitionSide * stripRatio
                    + (proposedWidth - compactTransitionSide) * gestureScale
                return verticalSquish(longSide: longSide)
            }
            let width = min(400, proposedWidth)
            return NSSize(width: width, height: width * stripRatio)
        }
        let verticalChange = -deltaY
        let horizontalEquivalent = deltaX / 3
        let usesVerticalGesture = abs(verticalChange) >= abs(horizontalEquivalent)
        if startSize.height <= compactTransitionSide,
           startSize.width < compactTransitionSide * stripRatio {
            let rawChange = usesVerticalGesture ? verticalChange : deltaX
            return horizontalSquish(longSide: startSize.width + rawChange)
        }
        let change = usesVerticalGesture ? verticalChange : horizontalEquivalent
        let proposedHeight = startSize.height + change
        if proposedHeight < compactTransitionSide {
            let gestureScale: CGFloat = usesVerticalGesture ? 1 : stripRatio
            let longSide = compactTransitionSide * stripRatio
                + (proposedHeight - compactTransitionSide) * gestureScale
            return horizontalSquish(longSide: longSide)
        }
        let height = min(400, proposedHeight)
        return NSSize(width: height * stripRatio, height: height)
    }

    private static func verticalSquish(longSide: CGFloat) -> NSSize {
        if longSide <= minimumSide {
            return NSSize(width: minimumSide, height: minimumSide)
        }
        if longSide <= compactTransitionSide {
            // Require deliberate extra inward travel before entering the
            // circle. The half point preserves vertical-strip identity and
            // prevents SwiftUI from swapping layouts during this deadband.
            return NSSize(width: compactTransitionSide, height: compactTransitionSide + 0.5)
        }
        return NSSize(
            width: compactTransitionSide,
            height: min(compactTransitionSide * stripRatio, longSide)
        )
    }

    private static func horizontalSquish(longSide: CGFloat) -> NSSize {
        if longSide <= minimumSide {
            return NSSize(width: minimumSide, height: minimumSide)
        }
        if longSide <= compactTransitionSide {
            // Hold the smallest horizontal strip until the pointer has been
            // pushed all the way through the squeeze zone.
            return NSSize(width: compactTransitionSide + 0.5, height: compactTransitionSide)
        }
        return NSSize(
            width: min(compactTransitionSide * stripRatio, longSide),
            height: compactTransitionSide
        )
    }
}

@MainActor
final class WindowDockController {
    static let shared = WindowDockController()

    private enum Key {
        static let sideFraction = "QuotaGlance.dockSideFraction"
        static let screenX = "QuotaGlance.dockScreenX"
        static let screenY = "QuotaGlance.dockScreenY"
        static let floatingWidth = "QuotaGlance.floatingWidth"
        static let floatingHeight = "QuotaGlance.floatingHeight"
        static let mountedScale = "QuotaGlance.mountedScale"
        static let lastStripVertical = "QuotaGlance.lastStripVertical"
    }

    private weak var window: NSWindow?
    private var moveObserver: NSObjectProtocol?
    private var localMouseUpMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var scaleGestureMonitor: Any?
    private var isApplyingFrame = false
    private var isResizing = false
    private var sawMove = false
    var requiresResizableStyle: Bool { isApplyingFrame || isResizing }

    private init() { }

    var position: DockPosition {
        DockPosition(rawValue: UserDefaults.standard.string(forKey: DockPosition.defaultsKey) ?? "") ?? .floating
    }

    var savedFloatingSize: NSSize? {
        let width = UserDefaults.standard.double(forKey: Key.floatingWidth)
        let height = UserDefaults.standard.double(forKey: Key.floatingHeight)
        guard width >= 118, height >= 118, width <= 1200, height <= 1200 else { return nil }
        return FloatingLayoutGeometry.normalized(NSSize(width: width, height: height))
    }

    func setFrame(_ frame: NSRect, on window: NSWindow, animated: Bool) {
        apply(frame, to: window, animated: animated)
    }

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        detach()
        self.window = window
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.windowDidMove() }
        }
        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            Task { @MainActor in self?.finishMoveIfNeeded() }
            return event
        }
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in self?.finishMoveIfNeeded() }
        }
        scaleGestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel]) { [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }
            if event.type == .scrollWheel, !event.momentumPhase.isEmpty { return nil }
            let factor: CGFloat
            if event.type == .magnify {
                factor = max(0.82, min(1.18, 1 + event.magnification * 0.85))
            } else {
                let delta = max(-12, min(12, event.scrollingDeltaY))
                guard abs(delta) >= 0.08 else { return nil }
                factor = exp(delta * (event.hasPreciseScrollingDeltas ? 0.012 : 0.075))
            }
            Task { @MainActor in self.resizeWidget(by: factor, window: window) }
            return nil
        }
        restoreDock(on: window)
    }

    func restoreDock(on window: NSWindow) {
        guard position.isMounted, let screen = persistedScreen() ?? window.screen ?? NSScreen.main else { return }
        let fraction = UserDefaults.standard.object(forKey: Key.sideFraction) as? Double ?? 0.5
        applyMountedFrame(position, to: window, screen: screen, sideFraction: fraction, animated: false)
    }

    private func resizeWidget(by factor: CGFloat, window: NSWindow) {
        guard factor.isFinite, factor > 0 else { return }
        let currentPosition = position
        let screen = window.screen ?? screen(at: NSEvent.mouseLocation) ?? NSScreen.main
        guard let screen else { return }

        if currentPosition.isMounted {
            let base = currentPosition.mountedSize
            let minimumScale = max(0.68, 118 / min(base.width, base.height))
            let oldScale = UserDefaults.standard.object(forKey: Key.mountedScale) as? Double ?? 1
            let newScale = min(2, max(Double(minimumScale), oldScale * Double(factor)))
            guard abs(newScale - oldScale) > 0.0005 else { return }
            UserDefaults.standard.set(newScale, forKey: Key.mountedScale)
            let fraction = UserDefaults.standard.object(forKey: Key.sideFraction) as? Double ?? 0.5
            applyMountedFrame(
                currentPosition,
                to: window,
                screen: screen,
                sideFraction: CGFloat(fraction),
                animated: false
            )
            return
        }

        let currentSize = window.frame.size
        let compact = FloatingLayoutGeometry.isCompact(currentSize)
        let newSize: NSSize
        if compact, factor > 1, currentSize.width >= 219.5 {
            let vertical = UserDefaults.standard.bool(forKey: Key.lastStripVertical)
            newSize = vertical ? NSSize(width: 140, height: 420) : NSSize(width: 420, height: 140)
        } else {
            if !compact {
                UserDefaults.standard.set(currentSize.height > currentSize.width, forKey: Key.lastStripVertical)
            }
            let shortSide = min(currentSize.width, currentSize.height)
            let delta = shortSide * (factor - 1)
            if compact || currentSize.height > currentSize.width {
                newSize = FloatingLayoutGeometry.resized(from: currentSize, deltaX: delta, deltaY: 0)
            } else {
                newSize = FloatingLayoutGeometry.resized(from: currentSize, deltaX: 0, deltaY: -delta)
            }
        }

        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        var frame = NSRect(
            x: center.x - newSize.width / 2,
            y: center.y - newSize.height / 2,
            width: newSize.width,
            height: newSize.height
        )
        let visible = screen.visibleFrame
        frame.origin.x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width))
        frame.origin.y = min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height))
        apply(frame, to: window, animated: false)
        saveFloatingSize(newSize)
    }

    func undock(_ window: NSWindow? = nil) {
        guard let target = window ?? self.window, position.isMounted else { return }
        let screen = target.screen ?? screen(at: NSEvent.mouseLocation) ?? NSScreen.main
        setPosition(.floating)
        let size = savedFloatingSize ?? NSSize(width: 220, height: 220)
        let center = NSPoint(x: target.frame.midX, y: target.frame.midY)
        var frame = NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        if let visible = screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width))
            frame.origin.y = min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height))
        }
        apply(frame, to: target, animated: true)
    }

    func beginResizeInteraction() {
        isResizing = true
        sawMove = false
        window?.styleMask.insert(.resizable)
    }

    func endResizeInteraction() {
        isResizing = false
        sawMove = false
        if let window, position == .floating { saveFloatingSize(window.frame.size) }
        window?.styleMask.remove(.resizable)
    }

    private func windowDidMove() {
        guard !isApplyingFrame, !isResizing, NSEvent.pressedMouseButtons & 1 != 0 else { return }
        sawMove = true
    }

    private func finishMoveIfNeeded() {
        guard sawMove, !isResizing, let window else { return }
        sawMove = false
        let targetScreen = screen(at: NSEvent.mouseLocation) ?? window.screen ?? NSScreen.main
        guard let targetScreen else { return }
        // Mounting is intentionally cursor-only. The window's border may
        // touch a screen edge during an ordinary move without latching.
        // Test against the physical screen boundary so the menu bar and Dock
        // do not create large invisible magnetic zones.
        let candidate = DockingGeometry.candidate(for: NSEvent.mouseLocation, in: targetScreen.frame)
        if candidate.isMounted {
            if position == .floating { saveFloatingSize(window.frame.size) }
            let fraction = DockingGeometry.sideFraction(for: window.frame, position: candidate, in: targetScreen.visibleFrame)
            UserDefaults.standard.set(Double(fraction), forKey: Key.sideFraction)
            UserDefaults.standard.set(Double(targetScreen.frame.minX), forKey: Key.screenX)
            UserDefaults.standard.set(Double(targetScreen.frame.minY), forKey: Key.screenY)
            // SwiftUI's floating three-dial layout can reject the tiny mounted
            // frame if it is still active. Hide for two render passes: mount
            // the lightweight sector first, force layout, then resize before
            // making the window visible again. This prevents both the giant
            // side dial and the one-frame giant corner flash.
            window.alphaValue = 0
            setPosition(candidate)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                window.contentView?.layoutSubtreeIfNeeded()
                self.applyMountedFrame(candidate, to: window, screen: targetScreen, sideFraction: fraction, animated: false)
                DispatchQueue.main.async { [weak window] in
                    window?.contentView?.layoutSubtreeIfNeeded()
                    window?.alphaValue = 1
                }
            }
        } else if position.isMounted {
            undock(window)
        } else {
            saveFloatingSize(window.frame.size)
        }
    }

    private func applyMountedFrame(_ position: DockPosition, to window: NSWindow, screen: NSScreen, sideFraction: CGFloat, animated: Bool) {
        let scale = UserDefaults.standard.object(forKey: Key.mountedScale) as? Double ?? 1
        let base = position.mountedSize
        let minimumScale = max(0.68, 118 / min(base.width, base.height))
        let frame = DockingGeometry.mountedFrame(
            for: position,
            in: screen.visibleFrame,
            sideFraction: sideFraction,
            scale: min(2, max(minimumScale, CGFloat(scale)))
        )
        apply(frame, to: window, animated: animated)
    }

    private func apply(_ frame: NSRect, to window: NSWindow, animated: Bool) {
        isApplyingFrame = true
        // Background moves always begin non-resizable, which prevents macOS
        // from ever entering its edge-tiling mode. Grant resize capability
        // only around our explicit programmatic frame change.
        window.styleMask.insert(.resizable)
        window.setFrame(frame, display: true, animate: animated)
        DispatchQueue.main.async { [weak self, weak window] in
            self?.isApplyingFrame = false
            window?.styleMask.remove(.resizable)
        }
    }

    private func saveFloatingSize(_ size: NSSize) {
        guard size.width >= 118, size.height >= 118 else { return }
        UserDefaults.standard.set(Double(size.width), forKey: Key.floatingWidth)
        UserDefaults.standard.set(Double(size.height), forKey: Key.floatingHeight)
    }

    private func setPosition(_ position: DockPosition) {
        UserDefaults.standard.set(position.rawValue, forKey: DockPosition.defaultsKey)
        NotificationCenter.default.post(name: .quotaGlanceDockChanged, object: position.rawValue)
    }

    private func persistedScreen() -> NSScreen? {
        let x = UserDefaults.standard.double(forKey: Key.screenX)
        let y = UserDefaults.standard.double(forKey: Key.screenY)
        return NSScreen.screens.min { lhs, rhs in
            hypot(lhs.frame.minX - x, lhs.frame.minY - y) < hypot(rhs.frame.minX - x, rhs.frame.minY - y)
        }
    }

    private func screen(at point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func detach() {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        if let localMouseUpMonitor { NSEvent.removeMonitor(localMouseUpMonitor) }
        if let globalMouseUpMonitor { NSEvent.removeMonitor(globalMouseUpMonitor) }
        if let scaleGestureMonitor { NSEvent.removeMonitor(scaleGestureMonitor) }
        moveObserver = nil
        localMouseUpMonitor = nil
        globalMouseUpMonitor = nil
        scaleGestureMonitor = nil
    }

}

enum WidgetTheme: String, CaseIterable, Identifiable {
    case current
    case marine
    case oled
    case radar
    case eInk
    case retro

    static let defaultsKey = "QuotaGlance.widgetTheme"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .current: return "Current"
        case .marine: return "Marine"
        case .oled: return "OLED"
        case .radar: return "Radar"
        case .eInk: return "E-Ink"
        case .retro: return "Retro"
        }
    }

    var isLight: Bool { self == .eInk }
}

struct PopoverPalette {
    let background: Color
    let surface: Color
    let raisedSurface: Color
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let rule: Color
    let pace: Color
    let reset: Color
    let billing: Color
    let cornerRadius: CGFloat
    let numberDesign: Font.Design
}

extension WidgetTheme {
    var popoverPalette: PopoverPalette {
        switch self {
        case .current:
            return PopoverPalette(
                background: Color(hex: 0x08121E), surface: Color(hex: 0x0C1927),
                raisedSurface: Color(hex: 0x112338), primary: .white,
                secondary: Color.white.opacity(0.68), tertiary: Color.white.opacity(0.38),
                rule: Color.white.opacity(0.11), pace: Color(hex: 0x2F80ED),
                reset: Color(hex: 0x68D9A0), billing: Color(hex: 0xF2AD3E),
                cornerRadius: 18, numberDesign: .rounded
            )
        case .marine:
            return PopoverPalette(
                background: Color(hex: 0x071321), surface: Color(hex: 0x0B1B2A),
                raisedSurface: Color(hex: 0x102438), primary: Color(hex: 0xF3F0E7),
                secondary: Color(hex: 0xB9C5CE), tertiary: Color(hex: 0x718391),
                rule: Color(hex: 0x66829A).opacity(0.25), pace: Color(hex: 0x3B8FEA),
                reset: Color(hex: 0x83E2AE), billing: Color(hex: 0xEFB44C),
                cornerRadius: 15, numberDesign: .monospaced
            )
        case .oled:
            return PopoverPalette(
                background: Color(hex: 0x050C16), surface: Color(hex: 0x091521),
                raisedSurface: Color(hex: 0x0E2033), primary: Color(hex: 0xF5F7F5),
                secondary: Color.white.opacity(0.64), tertiary: Color.white.opacity(0.32),
                rule: Color.white.opacity(0.09), pace: Color(hex: 0x258DFA),
                reset: Color(hex: 0x72F5B5), billing: Color(hex: 0xFFB321),
                cornerRadius: 13, numberDesign: .monospaced
            )
        case .radar:
            return PopoverPalette(
                background: Color(hex: 0x071313), surface: Color(hex: 0x0B1A19),
                raisedSurface: Color(hex: 0x0E2320), primary: Color(hex: 0xE8FFF5),
                secondary: Color(hex: 0xA7C9BC), tertiary: Color(hex: 0x5F8277),
                rule: Color(hex: 0x5E8B7E).opacity(0.28), pace: Color(hex: 0x2685E5),
                reset: Color(hex: 0x6FE0AC), billing: Color(hex: 0xE7B24C),
                cornerRadius: 16, numberDesign: .monospaced
            )
        case .eInk:
            return PopoverPalette(
                background: Color(hex: 0xE4E1D8), surface: Color(hex: 0xD8D6CF),
                raisedSurface: Color(hex: 0xF0EEE8), primary: Color(hex: 0x252725),
                secondary: Color(hex: 0x4F534F), tertiary: Color(hex: 0x747974),
                rule: Color.black.opacity(0.18), pace: Color(hex: 0x2868B2),
                reset: Color(hex: 0x3A8B62), billing: Color(hex: 0xA86F13),
                cornerRadius: 12, numberDesign: .monospaced
            )
        case .retro:
            return PopoverPalette(
                background: Color(hex: 0x0B0E0B), surface: Color(hex: 0x111611),
                raisedSurface: Color(hex: 0x172017), primary: Color(hex: 0xD9F5D7),
                secondary: Color(hex: 0x92B890), tertiary: Color(hex: 0x587157),
                rule: Color(hex: 0x77A374).opacity(0.24), pace: Color(hex: 0x3182E8),
                reset: Color(hex: 0x63E18A), billing: Color(hex: 0xE3A633),
                cornerRadius: 10, numberDesign: .monospaced
            )
        }
    }
}

enum UsagePaceRate: String, CaseIterable, Identifiable {
    case fiveMinutes
    case oneHour
    case twelveHours
    case twentyFourHours
    case total

    static let defaultsKey = "QuotaGlance.usagePaceRate"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fiveMinutes: return "Running · 5 Minutes"
        case .oneHour: return "1 Hour"
        case .twelveHours: return "12 Hours"
        case .twentyFourHours: return "24 Hours"
        case .total: return "Total"
        }
    }

    var compactLabel: String {
        switch self {
        case .fiveMinutes: return "5M RUNNING"
        case .oneHour: return "1H RATE"
        case .twelveHours: return "12H RATE"
        case .twentyFourHours: return "24H RATE"
        case .total: return "TOTAL RATE"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .fiveMinutes: return 5 * 60
        case .oneHour: return 60 * 60
        case .twelveHours: return 12 * 60 * 60
        case .twentyFourHours: return 24 * 60 * 60
        case .total: return nil
        }
    }

    var basisLabel: String {
        switch self {
        case .fiveMinutes: return "Running 5-minute pace"
        case .oneHour: return "Last-hour pace"
        case .twelveHours: return "Last-12-hour pace"
        case .twentyFourHours: return "Last-24-hour pace"
        case .total: return "Total pace"
        }
    }

    var collectionLabel: String {
        switch self {
        case .fiveMinutes: return "five-minute running"
        case .oneHour: return "one-hour"
        case .twelveHours: return "12-hour"
        case .twentyFourHours: return "24-hour"
        case .total: return "total"
        }
    }

    var flatScope: String {
        switch self {
        case .fiveMinutes: return "the last five minutes"
        case .oneHour: return "the last hour"
        case .twelveHours: return "the last 12 hours"
        case .twentyFourHours: return "the last 24 hours"
        case .total: return "this reset window"
        }
    }
}

enum ForecastSource: String, CaseIterable, Identifiable, Sendable {
    case lunarWerx
    case codexResets
    case willCodexQuotaReset
    case gussuri
    case polymarket
    case average

    static let defaultsKey = "QuotaGlance.resetCalculatorSource"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lunarWerx: return "LunarWerx"
        case .codexResets: return "Codex Resets"
        case .willCodexQuotaReset: return "Will Codex Reset?"
        case .gussuri: return "Reset Observatory"
        case .polymarket: return "Polymarket"
        case .average: return "Average of All"
        }
    }

    var hostLabel: String {
        switch self {
        case .lunarWerx: return "codex.lunarwerx.com"
        case .codexResets: return "codex-resets.com"
        case .willCodexQuotaReset: return "willcodexquotareset.com"
        case .gussuri: return "codex.gussuriworks.com"
        case .polymarket: return "polymarket.com"
        case .average: return "5 sources"
        }
    }

    var url: URL? {
        switch self {
        case .lunarWerx: return URL(string: "https://codex.lunarwerx.com")
        case .codexResets: return URL(string: "https://codex-resets.com")
        case .willCodexQuotaReset: return URL(string: "https://www.willcodexquotareset.com")
        case .gussuri: return URL(string: "https://codex.gussuriworks.com/en")
        case .polymarket:
            return URL(string: UserDefaults.standard.string(forKey: "QuotaGlance.polymarketEventURL") ?? "https://polymarket.com")
        case .average: return nil
        }
    }

    static var calculatorCases: [ForecastSource] {
        [.lunarWerx, .codexResets, .willCodexQuotaReset, .gussuri, .polymarket]
    }
}

enum ForecastSourceSelection {
    static let defaultsKey = "QuotaGlance.resetCalculatorSources"

    static func load(from defaults: UserDefaults = .standard) -> Set<ForecastSource> {
        if let stored = defaults.array(forKey: defaultsKey) as? [String] {
            let sources = Set(stored.compactMap(ForecastSource.init(rawValue:)))
                .intersection(ForecastSource.calculatorCases)
            if !sources.isEmpty { return sources }
        }
        let legacy = ForecastSource(
            rawValue: defaults.string(forKey: ForecastSource.defaultsKey) ?? ""
        ) ?? .lunarWerx
        return legacy == .average ? Set(ForecastSource.calculatorCases) : [legacy]
    }

    static func save(_ sources: Set<ForecastSource>, to defaults: UserDefaults = .standard) {
        let valid = sources.intersection(ForecastSource.calculatorCases)
        guard !valid.isEmpty else { return }
        let ordered = ForecastSource.calculatorCases.filter(valid.contains)
        defaults.set(ordered.map(\.rawValue), forKey: defaultsKey)
        defaults.set(
            ordered.count == 1 ? ordered[0].rawValue : ForecastSource.average.rawValue,
            forKey: ForecastSource.defaultsKey
        )
    }

    static func label(for sources: Set<ForecastSource>) -> String {
        let ordered = ForecastSource.calculatorCases.filter(sources.contains)
        if ordered.count == 1 { return ordered[0].displayName }
        return "Average of \(ordered.count)"
    }
}

@MainActor
private final class ResetCalculatorMenuView: NSView {
    private var buttons: [ForecastSource: NSButton] = [:]
    private let selectionLabel = NSTextField(labelWithString: "")

    init(selectedSources: Set<ForecastSource>) {
        super.init(frame: NSRect(x: 0, y: 0, width: 238, height: 184))

        let title = NSTextField(labelWithString: "AVERAGE SELECTED SOURCES")
        title.font = .monospacedSystemFont(ofSize: 9, weight: .semibold)
        title.textColor = .secondaryLabelColor

        selectionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        selectionLabel.textColor = .labelColor

        let header = NSStackView(views: [title, selectionLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 2

        let sourceStack = NSStackView()
        sourceStack.orientation = .vertical
        sourceStack.alignment = .leading
        sourceStack.spacing = 2

        for source in ForecastSource.calculatorCases {
            let button = NSButton(
                checkboxWithTitle: source.displayName,
                target: self,
                action: #selector(toggleSource(_:))
            )
            button.identifier = NSUserInterfaceItemIdentifier(source.rawValue)
            button.state = selectedSources.contains(source) ? .on : .off
            button.font = .systemFont(ofSize: 13)
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            sourceStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 214).isActive = true
            buttons[source] = button
        }

        let stack = NSStackView(views: [header, sourceStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10)
        ])

        updateSelectionLabel(selectedSources)
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func toggleSource(_ sender: NSButton) {
        guard
            let rawValue = sender.identifier?.rawValue,
            let source = ForecastSource(rawValue: rawValue),
            ForecastSource.calculatorCases.contains(source)
        else { return }

        var selected = ForecastSourceSelection.load()
        if sender.state == .on {
            selected.insert(source)
        } else if selected.count > 1 {
            selected.remove(source)
        } else {
            sender.state = .on
            NSSound.beep()
            return
        }

        ForecastSourceSelection.save(selected)
        for (source, button) in buttons {
            button.state = selected.contains(source) ? .on : .off
        }
        updateSelectionLabel(selected)
        NotificationCenter.default.post(
            name: .quotaGlanceResetCalculatorChanged,
            object: ForecastSource.calculatorCases.filter(selected.contains).map(\.rawValue)
        )
    }

    private func updateSelectionLabel(_ selected: Set<ForecastSource>) {
        selectionLabel.stringValue = ForecastSourceSelection.label(for: selected)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let claudeBar = ClaudeBarController.shared
    private let providerDisplay = ProviderDisplayController.shared
    private let statusPopover = NSPopover()
    private var statusClockTimer: Timer?
    private var runtime: ProviderAppRuntime?
    private var claudeStatusObservation: AnyCancellable?
    private var shouldExitForExistingInstance = false
    private var calculatorWindow: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        shouldExitForExistingInstance = NSRunningApplication
            .runningApplications(withBundleIdentifier: identifier)
            .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if shouldExitForExistingInstance {
            NSApp.terminate(nil)
        } else {
            clearPersistedSystemTilingFrames()
        }
    }

    private func clearPersistedSystemTilingFrames() {
        // SwiftUI assigned an internal frame-autosave key even though this
        // borderless utility window is not restorable. If macOS edge tiling
        // ever catches a drag, that key can resurrect a giant tiled frame on
        // later focus changes. Quota Glance persists its own compact size and
        // dock state, so these system-only frame records are unwanted.
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("NSWindow Frame SwiftUI.") && key.contains("QuotaGlance.DashboardView") {
            defaults.removeObject(forKey: key)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !shouldExitForExistingInstance else { return }
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClick)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        runtime = ProviderAppRuntime()
        configureStatusPopover()
        NotificationCenter.default.addObserver(self, selector: #selector(menuBarSummaryChanged), name: .quotaGlanceProvidersChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showCodexResetCalculator), name: .quotaGlanceOpenCodexResetCalculator, object: nil)
        claudeStatusObservation = claudeBar.model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }
        updateStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuBarSummaryChanged),
            name: .quotaGlanceMenuBarSummaryChanged,
            object: nil
        )
        statusClockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusItem() }
        }

        DispatchQueue.main.async { [weak self] in
            self?.providerDisplay.restore()
            BillingSyncCoordinator.runAutomaticSyncIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusClockTimer?.invalidate()
        claudeBar.stop()
        providerDisplay.stop()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleStatusItemClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusPopover.performClose(nil)
            showMenu()
        } else {
            toggleStatusPopover()
        }
    }

    private func configureStatusPopover() {
        statusPopover.behavior = .transient
        statusPopover.animates = true
        statusPopover.contentViewController = NSHostingController(
            rootView: ProviderStatusPopover(controller: providerDisplay, codex: .shared, claude: claudeBar.model,
                onVisibility: { [weak self] in
                    self?.statusPopover.performClose(nil)
                    self?.providerDisplay.toggleVisibility()
                }, onLayout: { [weak self] in
                    self?.statusPopover.performClose(nil)
                    self?.providerDisplay.showSettings()
                })
        )
    }

    private func toggleStatusPopover() {
        guard let button = statusItem?.button else { return }
        NotificationCenter.default.post(name: .quotaGlanceMenuInteraction, object: nil)
        if statusPopover.isShown {
            statusPopover.performClose(nil)
        } else {
            statusPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func menuBarSummaryChanged() {
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let readings = providerDisplay.selection.filter([
            ProviderReading.codex(.shared, at: .now), ProviderReading.claude(claudeBar.model, at: .now)
        ])
        let title = readings.map { $0.name + " " + ProviderReading.percent($0.usage) }.joined(separator: " · ")
        let result = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.labelColor
        ])
        if providerDisplay.selection.contains(.codex), MenuBarSummaryModel.shared.payload.unreadTweet {
            result.append(NSAttributedString(string: " •", attributes: [.foregroundColor: NSColor.systemBlue]))
        }
        button.image = nil
        button.attributedTitle = result
        button.toolTip = readings.map { $0.name + ": " + $0.status }.joined(separator: "\n")
        button.setAccessibilityLabel("Quota Glance, " + title)
        statusPopover.contentSize = NSSize(width: 328, height: readings.count == 1 ? 184 : 258)
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: providerDisplay.isVisible ? "Hide widget" : "Show widget", action: #selector(toggleDashboardVisibilityFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Layout…", action: #selector(showDisplayOptions), keyEquivalent: ",")
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        menu.addItem(.separator())

        let codexItem = NSMenuItem(title: "Codex", action: nil, keyEquivalent: "")
        let codexMenu = NSMenu(title: "Codex")
        codexMenu.addItem(withTitle: "Reset calculator…", action: #selector(showCodexResetCalculator), keyEquivalent: "")
        codexMenu.addItem(resetActionsMenuItem())
        codexMenu.items.forEach { $0.target = self }
        codexItem.submenu = codexMenu
        if providerDisplay.selection.contains(.codex) { menu.addItem(codexItem) }

        let advancedItem = NSMenuItem(title: "Advanced", action: nil, keyEquivalent: "")
        let advancedMenu = NSMenu(title: "Advanced")
        advancedMenu.addItem(privateLiveFeedMenuItem())
        advancedMenu.addItem(.separator())
        if providerDisplay.selection.contains(.claude) {
            advancedMenu.addItem(withTitle: "Claude sign-in…", action: #selector(connectClaude), keyEquivalent: "")
        }
        advancedMenu.items.forEach { $0.target = self }
        advancedItem.submenu = advancedMenu
        menu.addItem(advancedItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func toggleDashboardVisibilityFromMenu() { providerDisplay.toggleVisibility() }
    @objc private func connectClaude() { claudeBar.model.connect() }
    @objc private func showDisplayOptions() { providerDisplay.showSettings() }

    @objc private func showCodexResetCalculator() {
        if calculatorWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Codex reset calculator"
            window.isReleasedWhenClosed = false
            window.center()
            calculatorWindow = window
        }
        calculatorWindow?.contentView = ResetCalculatorMenuView(selectedSources: ForecastSourceSelection.load())
        calculatorWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func refresh() {
        NotificationCenter.default.post(name: .quotaGlanceMenuInteraction, object: nil)
        NotificationCenter.default.post(name: .quotaGlanceRefresh, object: nil)
        claudeBar.model.refresh()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            case .notRegistered, .notFound:
                try SMAppService.mainApp.register()
            @unknown default:
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Quota Glance could not update Launch at Login: %@", error.localizedDescription)
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc private func toggleResetCalculator(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let source = ForecastSource(rawValue: rawValue),
            ForecastSource.calculatorCases.contains(source)
        else { return }
        var selected = ForecastSourceSelection.load()
        if selected.contains(source) {
            guard selected.count > 1 else {
                NSSound.beep()
                return
            }
            selected.remove(source)
        } else {
            selected.insert(source)
        }
        ForecastSourceSelection.save(selected)
        sender.state = selected.contains(source) ? .on : .off
        NotificationCenter.default.post(
            name: .quotaGlanceResetCalculatorChanged,
            object: ForecastSource.calculatorCases.filter(selected.contains).map(\.rawValue)
        )
    }

    private func resetActionsMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: "After a Codex reset", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Reset Actions")

        let sound = NSMenuItem(
            title: "Reset Sound Effects",
            action: #selector(toggleResetSound),
            keyEquivalent: ""
        )
        sound.state = ResetAutomationSettings.soundEnabled ? .on : .off
        submenu.addItem(sound)

        let clockStarter = NSMenuItem(
            title: "Start Weekly Clock with Hello",
            action: #selector(toggleResetClockStarter),
            keyEquivalent: ""
        )
        clockStarter.state = ResetClockStarterSettings.isEnabled ? .on : .off
        submenu.addItem(clockStarter)
        if let result = ResetClockStarterSettings.lastResult {
            let status = NSMenuItem(title: "Last hello: \(result)", action: nil, keyEquivalent: "")
            status.isEnabled = false
            submenu.addItem(status)
        }
        submenu.addItem(.separator())

        let shortcutTitle = ResetAutomationSettings.shortcutName.map { "Shortcut: \($0)" }
            ?? "Choose Shortcut…"
        submenu.addItem(withTitle: shortcutTitle, action: #selector(configureResetShortcut), keyEquivalent: "")
        if ResetAutomationSettings.shortcutName != nil {
            submenu.addItem(withTitle: "Clear Shortcut", action: #selector(clearResetShortcut), keyEquivalent: "")
        }

        let hookTitle = ResetAutomationSettings.executablePath.map {
            "Hook: \(($0 as NSString).lastPathComponent)"
        } ?? "Choose Executable Hook…"
        submenu.addItem(withTitle: hookTitle, action: #selector(chooseResetHook), keyEquivalent: "")
        if ResetAutomationSettings.executablePath != nil {
            submenu.addItem(withTitle: "Clear Executable Hook", action: #selector(clearResetHook), keyEquivalent: "")
        }

        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Preview Celebration & Test Hook", action: #selector(testResetActions), keyEquivalent: "")
        submenu.addItem(withTitle: "Send Test Hello Now", action: #selector(testResetClockStarter), keyEquivalent: "")
        submenu.items.forEach { $0.target = self }
        root.submenu = submenu
        return root
    }

    private func privateLiveFeedMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: "Private iPhone Live Feed", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Private iPhone Live Feed")

        let status = NSMenuItem(title: PrivateLiveActivitySettings.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        submenu.addItem(status)

        let enabled = NSMenuItem(title: "Enabled", action: #selector(togglePrivateLiveFeed), keyEquivalent: "")
        enabled.state = PrivateLiveActivitySettings.isEnabled ? .on : .off
        enabled.isEnabled = PrivateLiveActivitySettings.isConfigured
        submenu.addItem(enabled)
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Configure APNs Key…", action: #selector(configurePrivateLiveFeed), keyEquivalent: "")
        if PrivateLiveActivitySettings.isConfigured {
            submenu.addItem(withTitle: "Send Test Update", action: #selector(testPrivateLiveFeed), keyEquivalent: "")
            submenu.addItem(withTitle: "Remove Private Key", action: #selector(clearPrivateLiveFeed), keyEquivalent: "")
        }
        submenu.items.forEach { $0.target = self }
        root.submenu = submenu
        return root
    }

    @objc private func togglePrivateLiveFeed() {
        guard PrivateLiveActivitySettings.isConfigured else { return }
        UserDefaults.standard.set(
            !PrivateLiveActivitySettings.isEnabled,
            forKey: PrivateLiveActivitySettings.enabledKey
        )
    }

    @objc private func configurePrivateLiveFeed() {
        let panel = NSOpenPanel()
        panel.title = "Choose your private APNs signing key"
        panel.message = "The .p8 file will be stored only in this Mac’s Keychain."
        panel.prompt = "Choose Key"
        panel.allowedContentTypes = [.data]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let pem = try? String(contentsOf: url, encoding: .utf8) else { return }

        let filenameKeyID = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "AuthKey_", with: "")
        let keyID = NSTextField(string: PrivateLiveActivitySettings.keyID ?? filenameKeyID)
        keyID.placeholderString = "APNs Key ID"
        let teamID = NSTextField(string: PrivateLiveActivitySettings.teamID ?? "")
        teamID.placeholderString = "Apple Developer Team ID"
        let labels = NSStackView(views: [
            NSTextField(labelWithString: "Key ID"), keyID,
            NSTextField(labelWithString: "Team ID"), teamID
        ])
        labels.orientation = .vertical
        labels.spacing = 6
        labels.frame = NSRect(x: 0, y: 0, width: 340, height: 92)

        let alert = NSAlert()
        alert.messageText = "Configure private Live Activity updates"
        alert.informativeText = "These credentials remain in your local Keychain and are never included in phone snapshots or uploads."
        alert.accessoryView = labels
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try PrivateAPNsKeychain.save(pem)
            UserDefaults.standard.set(keyID.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: PrivateLiveActivitySettings.keyIDKey)
            UserDefaults.standard.set(teamID.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: PrivateLiveActivitySettings.teamIDKey)
            UserDefaults.standard.set(true, forKey: PrivateLiveActivitySettings.enabledKey)
            UserDefaults.standard.set("Configured · waiting for iPhone", forKey: PrivateLiveActivitySettings.lastStatusKey)
        } catch {
            let failure = NSAlert(error: error)
            failure.runModal()
        }
    }

    @objc private func testPrivateLiveFeed() {
        Task {
            await PrivateLiveActivityRelay.shared.forceNextUpdate()
            await MainActor.run {
                NotificationCenter.default.post(name: .quotaGlancePrivateLiveFeedTest, object: nil)
            }
        }
    }

    @objc private func clearPrivateLiveFeed() {
        PrivateAPNsKeychain.delete()
        UserDefaults.standard.removeObject(forKey: PrivateLiveActivitySettings.keyIDKey)
        UserDefaults.standard.removeObject(forKey: PrivateLiveActivitySettings.teamIDKey)
        UserDefaults.standard.removeObject(forKey: PrivateLiveActivitySettings.enabledKey)
        UserDefaults.standard.removeObject(forKey: PrivateLiveActivitySettings.lastStatusKey)
    }

    @objc private func toggleResetSound() {
        UserDefaults.standard.set(
            !ResetAutomationSettings.soundEnabled,
            forKey: ResetAutomationSettings.soundEnabledKey
        )
    }

    @objc private func toggleResetClockStarter() {
        UserDefaults.standard.set(
            !ResetClockStarterSettings.isEnabled,
            forKey: ResetClockStarterSettings.enabledKey
        )
    }

    @objc private func testResetClockStarter() {
        ResetClockStarter.forceTest()
    }

    @objc private func configureResetShortcut() {
        let alert = NSAlert()
        alert.messageText = "Shortcut after a quota reset"
        alert.informativeText = "Enter the exact name of a Shortcut in the Shortcuts app. It will run only after a confirmed reset."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: ResetAutomationSettings.shortcutName ?? "")
        field.placeholderString = "Shortcut name"
        field.frame = NSRect(x: 0, y: 0, width: 310, height: 24)
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            UserDefaults.standard.removeObject(forKey: ResetAutomationSettings.shortcutNameKey)
        } else {
            UserDefaults.standard.set(value, forKey: ResetAutomationSettings.shortcutNameKey)
        }
    }

    @objc private func clearResetShortcut() {
        UserDefaults.standard.removeObject(forKey: ResetAutomationSettings.shortcutNameKey)
    }

    @objc private func chooseResetHook() {
        let panel = NSOpenPanel()
        panel.message = "Choose a trusted executable or script to run after a confirmed quota reset."
        panel.prompt = "Choose Hook"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: ResetAutomationSettings.executablePathKey)
    }

    @objc private func clearResetHook() {
        UserDefaults.standard.removeObject(forKey: ResetAutomationSettings.executablePathKey)
    }

    @objc private func testResetActions() {
        let summary = MenuBarSummaryModel.shared
        ProviderResetCelebrationController.shared.preview(.codex)
        ResetAutomationRunner.dispatch(
            ResetAutomationEvent(
                event: "quota_reset_test",
                observedAt: Date(),
                usedPercent: summary.weeklyWindow?.usedPercent ?? 0,
                resetAt: summary.weeklyWindow?.resetAt,
                planName: summary.payload.planName
            )
        )
    }

    private func enableLaunchAtLoginIfNeeded() {
        switch SMAppService.mainApp.status {
        case .notRegistered, .notFound:
            do {
                try SMAppService.mainApp.register()
            } catch {
                NSLog("Quota Glance could not enable Launch at Login: %@", error.localizedDescription)
            }
        case .enabled, .requiresApproval:
            break
        @unknown default:
            break
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@MainActor
final class DashboardModel: ObservableObject {
    var providerRunoutAt: Date? {
        UsagePace.calculate(usedPercent: usedPercent, windowStartDate: usageWindowStart,
            resetAt: resetAt, usageHistory: usageHistory, localTokensTotal: localTokensTotal,
            localTokenPace: localTokenPace, usageIntelligence: usageIntelligence, rate: .oneHour).projectedExhaustion
    }

    @Published var usedPercent: Double?
    @Published var weekElapsedPercent: Double?
    @Published var resetAt: Date?
    @Published var resetDeadlineIsCredit = false
    @Published var planName = "Codex"
    @Published var weeklyTokens: Int64?
    @Published var localTokensTotal: Int64?
    @Published var localTokenPace: LocalTokenPaceSnapshot?
    @Published var usageIntelligence: UsageIntelligenceSnapshot?
    @Published var secondaryQuota: SecondaryQuotaSnapshot?
    @Published var quotaInventory: [CodexQuotaWindow] = []
    @Published var creditSummary: CodexCreditSummary?
    @Published var resetCredits: [CodexResetCredit] = []
    @Published var activeTasks: [CodexTaskSnapshot] = []
    @Published var usageDays: [UsageDay] = []
    @Published var usageHistory: [UsageCheckpoint] = UsageHistoryStore.load()
    @Published var weeklyArchives: [WeeklyUsageArchive] = WeeklyUsageArchiveStore.load()
    @Published var usageWindowStart: Date?
    @Published var usageWindowDurationMinutes: Double?
    @Published var forecastPercent: Double?
    @Published var forecastLabel: String?
    @Published var resetAnnouncement: ResetAnnouncement?
    @Published var resetApplicabilityQuestion: ResetAnnouncement?
    @Published var resetLifecycle = ResetLifecycleStore.load()
    @Published var resetIntel: ResetIntelSnapshot?
    @Published var newTweetAlert: TiboTweet?
    @Published var forecastSnapshot: ForecastSnapshot?
    @Published var forecastURL = URL(string: "https://codex-resets.com")!
    @Published var codexStatus = "Connecting to Codex…"
    @Published var forecastStatus = "Checking reset signals…"
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false

    private var usageRefreshTask: Task<Void, Never>?
    private var forecastTimer: Timer?
    private var progressTimer: Timer?
    private var forecastRefreshGeneration = 0
    private var lastCodexSuccessfulAt: Date?
    private var lastCodexAttemptFailed = false
    private var lastMenuInteractionAt: Date?
    private var lastCodingActivityAt: Date?
    private var previousLocalTokenTotal: Int64?
    private let adaptiveRefreshPolicy = AdaptiveRefreshPolicy()
    private let observedTweetKey = "QuotaGlance.observedTiboTweetID"
    private let clearedTweetKey = "QuotaGlance.clearedTiboTweetID"
    private let observedTweetsKey = "QuotaGlance.observedTiboTweetIDs.v2"
    private let tweetWatermarkKey = "QuotaGlance.observedTiboTweetDate.v2"
    init() {
        NSUbiquitousKeyValueStore.default.synchronize()
        MenuBarSummaryModel.shared.onClearTweet = { [weak self] in self?.clearNewTweetAlert() }
        ClaudeBarController.shared.model.onSnapshotChanged = { [weak self] in self?.publishMobileSnapshot() }
        restoreCachedCodexState()
        refresh()
        startAdaptiveUsageRefresh()
        // Reset forecasts and Tibo posts remain lightweight and timely.
        forecastTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshForecast() }
        }
        // Calendar progress changes by only ~0.005% every 30 seconds. Updating
        // the entire SwiftUI tree every second wasted work without changing a
        // visible pixel on any dial.
        progressTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateCalendarProgress() }
        }
    }

    deinit {
        usageRefreshTask?.cancel()
        forecastTimer?.invalidate()
        progressTimer?.invalidate()
    }

    private func updateCalendarProgress() {
        guard let resetAt else { return }
        weekElapsedPercent = CodexService.calendarProgress(to: resetAt, at: Date())
    }

    func refresh() {
        refreshForecast()
        refreshCodex()
    }

    func noteMenuInteraction() {
        lastMenuInteractionAt = Date()
        // Opening the summary should never leave visibly stale data waiting
        // for the ordinary adaptive timer.
        if lastCodexSuccessfulAt.map({ Date().timeIntervalSince($0) >= 2 * 60 }) ?? true {
            refreshCodex()
        }
    }

    private func startAdaptiveUsageRefresh() {
        usageRefreshTask?.cancel()
        usageRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let process = ProcessInfo.processInfo
                let constrained = process.isLowPowerModeEnabled
                    || process.thermalState == .serious
                    || process.thermalState == .critical
                let decision = adaptiveRefreshPolicy.nextDelay(for: .init(
                    now: Date(),
                    lastInteractionAt: lastMenuInteractionAt,
                    lastCodingActivityAt: lastCodingActivityAt,
                    isConstrained: constrained,
                    pendingResetConfirmation: resetLifecycle.hasPendingResetCandidate
                ))
                var remaining = decision.interval
                while remaining > 0, !Task.isCancelled {
                    let slice = min(60, remaining)
                    do {
                        try await Task.sleep(for: .seconds(slice))
                    } catch {
                        return
                    }
                    remaining -= slice
                    if let activity = CodexActivityProbe.latestActivity(),
                       Date().timeIntervalSince(activity) <= 5 * 60 {
                        lastCodingActivityAt = max(lastCodingActivityAt ?? .distantPast, activity)
                        // The probe itself already supplied the one-minute
                        // throttle, so refresh now instead of making an active
                        // turn wait through a second minute.
                        remaining = 0
                    }
                }
                await performCodexRefresh()
            }
        }
    }

    func rebuildUsageIntelligence() {
        guard let windowStart = usageWindowStart else { return }
        Task {
            let snapshot = await Task.detached(priority: .utility) {
                try? UsageIntelligenceStore.rebuild(windowStart: windowStart)
            }.value
            if let snapshot {
                usageIntelligence = snapshot
                publishMobileSnapshot()
            }
        }
    }

    func purgeUsageData() {
        try? UsageIntelligenceStore.purge()
        UsageHistoryStore.purge()
        usageHistory = []
        if let windowStart = usageWindowStart {
            usageIntelligence = .empty(windowStart: windowStart)
        } else {
            usageIntelligence = nil
        }
        publishMobileSnapshot()
    }

    private func refreshCodex() {
        Task { await performCodexRefresh() }
    }

    private func performCodexRefresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        do {
            let liveSnapshot = try await CodexService.fetch()
            let cached = CodexSnapshotStore.save(liveSnapshot)
            lastCodexSuccessfulAt = cached.savedAt
            lastCodexAttemptFailed = false
            applyCodexSnapshot(cached.snapshot, recordedAt: cached.savedAt, isLive: true)
        } catch {
            lastCodexAttemptFailed = true
            codexStatus = error.localizedDescription
            publishMenuBarSummary()
        }

        lastUpdated = Date()
        isRefreshing = false
    }

    private func refreshForecast() {
        forecastRefreshGeneration += 1
        let generation = forecastRefreshGeneration
        forecastStatus = "Checking reset signals…"
        Task {
            do {
                let forecast = try await ForecastService.fetch()
                guard generation == forecastRefreshGeneration else { return }
                applyForecast(forecast, statusPrefix: "Live")
            } catch {
                guard generation == forecastRefreshGeneration else { return }
                // A failed verification must not erase the provider values the
                // user was just able to inspect and select from.
                if forecastSnapshot == nil {
                    forecastPercent = nil
                    forecastLabel = nil
                    resetIntel = nil
                    forecastStatus = "Reset signals unavailable"
                } else {
                    forecastStatus = "Cached · refresh unavailable"
                }
            }
        }
    }

    func selectForecastSources(_ rawValues: [String]) {
        let sources = Set(rawValues.compactMap(ForecastSource.init(rawValue:)))
            .intersection(ForecastSource.calculatorCases)
        guard !sources.isEmpty else { return }

        // Every provider result is already retained in forecastSnapshot.
        // Recompose from that cache synchronously so the dial changes during
        // the menu click itself, then verify all sources in the background.
        if let providers = forecastSnapshot?.providers,
           let cached = try? ForecastService.snapshot(from: providers, selected: sources) {
            applyForecast(cached, statusPrefix: "Cached")
        }
        refreshForecast()
    }

    private func applyForecast(_ forecast: ForecastSnapshot, statusPrefix: String) {
        resetLifecycle = ResetLifecycleStore.observeAnnouncement(forecast.announcement)
        forecastLabel = forecast.displayLabel
        let activeAnnouncement = resetLifecycle.isRecentlyCompleted()
            ? nil
            : activeAnnouncementAfterLastCompletion(forecast.announcement)
        let response = activeAnnouncement.flatMap { announcement -> ResetApplicabilityResponse? in
            guard announcement.requiresApplicabilityConfirmation,
                  let response = ResetApplicability.load(),
                  response.announcementID == announcement.id else { return nil }
            return response
        }
        let declined = response?.applies == false
        forecastPercent = declined ? forecast.baselineScore : forecast.score
        resetAnnouncement = declined ? nil : activeAnnouncement
        resetApplicabilityQuestion = activeAnnouncement?.requiresApplicabilityConfirmation == true
            && response == nil ? activeAnnouncement : nil
        updateTweetAlert(from: forecast.intel?.tweets ?? [])
        resetIntel = forecast.intel
        forecastSnapshot = forecast
        forecastURL = ForecastSource.calculatorCases
            .first(where: forecast.selectedSources.contains)?.url
            ?? forecast.providers.first?.source.url
            ?? URL(string: "https://codex.lunarwerx.com")!
        forecastStatus = "\(statusPrefix) · \(ForecastSourceSelection.label(for: forecast.selectedSources))"
        lastUpdated = Date()
        publishMenuBarSummary()
        publishMobileSnapshot()
    }

    func answerResetApplicability(_ applies: Bool) {
        guard let announcement = resetApplicabilityQuestion ?? forecastSnapshot?.announcement else { return }
        ResetApplicability.save(announcementID: announcement.id, applies: applies)
        resetApplicabilityQuestion = nil
        if let forecastSnapshot {
            applyForecast(forecastSnapshot, statusPrefix: "Account answer")
        }
    }

    func syncResetApplicabilityFromCloud() {
        guard let forecastSnapshot else { return }
        applyForecast(forecastSnapshot, statusPrefix: "Synced answer")
    }

    private func activeAnnouncementAfterLastCompletion(
        _ announcement: ResetAnnouncement?
    ) -> ResetAnnouncement? {
        guard let announcement, announcement.isActive() else { return nil }
        guard let completedAt = resetLifecycle.completedAt else { return announcement }
        if announcement.detectedAt <= completedAt { return nil }
        if let expectedAt = announcement.expectedAt, expectedAt <= completedAt { return nil }
        return announcement
    }

    private func restoreCachedCodexState() {
        if let cached = CodexSnapshotStore.load() {
            applyCodexSnapshot(cached.snapshot, recordedAt: cached.savedAt, isLive: false)
            return
        }
        // First launch after upgrading: hydrate the visible dials from the
        // durable checkpoint history while the richer snapshot is fetched.
        guard let checkpoint = usageHistory.last else { return }
        usedPercent = checkpoint.usedPercent
        resetAt = checkpoint.resetAt
        weeklyTokens = checkpoint.weeklyTokens
        localTokensTotal = checkpoint.localTokensTotal
        usageIntelligence = UsageIntelligenceStore.cachedSnapshot(windowStart: checkpoint.windowStart)
        usageWindowStart = checkpoint.windowStart
        weekElapsedPercent = CodexService.calendarProgress(to: checkpoint.resetAt, at: Date())
        lastUpdated = checkpoint.recordedAt
        codexStatus = "Cached history · refreshing"
    }

    private func applyCodexSnapshot(
        _ snapshot: CodexSnapshot,
        recordedAt: Date,
        isLive: Bool
    ) {
        if isLive,
           let previousWindowStart = usageWindowStart,
           snapshot.usageWindowStart.timeIntervalSince(previousWindowStart) > UsageHistoryStore.windowTolerance,
           let previousResetAt = resetAt {
            weeklyArchives = WeeklyUsageArchiveStore.capture(
                windowStart: previousWindowStart,
                resetAt: previousResetAt,
                finalUsedPercent: usedPercent ?? 0,
                intelligence: usageIntelligence,
                checkpoints: usageHistory,
                capturedAt: recordedAt
            )
        }
        let previousResetCompletion = resetLifecycle.completedAt
        resetLifecycle = ResetLifecycleStore.observeUsage(
            windowStart: snapshot.usageWindowStart,
            usedPercent: snapshot.usedPercent,
            planName: snapshot.planName,
            observedAt: recordedAt
        )
        let justReset = resetLifecycle.completedAt != nil
            && resetLifecycle.completedAt != previousResetCompletion
        // The celebration controller plays the selected scene's synchronized sound.
        if justReset && isLive {
            ResetAutomationRunner.dispatch(
                ResetAutomationEvent(
                    event: "quota_reset",
                    observedAt: recordedAt,
                    usedPercent: snapshot.usedPercent,
                    resetAt: snapshot.resetAt,
                    planName: snapshot.planName
                )
            )
        }
        if isLive,
           resetLifecycle.isRecentlyCompleted(at: recordedAt),
           let completedAt = resetLifecycle.completedAt {
            ResetClockStarter.startIfNeeded(for: completedAt, now: recordedAt)
        }
        if resetLifecycle.isRecentlyCompleted() {
            resetAnnouncement = nil
        }
        resetAt = snapshot.resetAt
        resetDeadlineIsCredit = snapshot.resetDeadlineIsCredit
        planName = snapshot.planName
        BillingSyncCoordinator.noteLocalPlan(snapshot.planName)
        weeklyTokens = snapshot.weeklyTokens
        localTokensTotal = snapshot.localTokensTotal
        if isLive,
           let previousLocalTokenTotal,
           let currentTotal = snapshot.localTokensTotal,
           currentTotal > previousLocalTokenTotal {
            lastCodingActivityAt = recordedAt
        }
        previousLocalTokenTotal = snapshot.localTokensTotal
        localTokenPace = snapshot.localTokenPace
        usageIntelligence = snapshot.usageIntelligence
        secondaryQuota = snapshot.secondaryQuota
        quotaInventory = snapshot.quotaInventory ?? []
        creditSummary = snapshot.creditSummary
        resetCredits = snapshot.resetCredits ?? []
        activeTasks = snapshot.activeTasks ?? []
        if isLive, !activeTasks.isEmpty {
            lastCodingActivityAt = recordedAt
        }
        if let total = snapshot.localTokensTotal,
           let sinceReset = snapshot.localTokenPace?.sinceReset {
            LocalTokenBaselineStore.note(
                windowStart: snapshot.usageWindowStart,
                currentTotal: total,
                tokensSinceReset: sinceReset
            )
        }
        usageDays = snapshot.usageDays
        if isLive {
            usageHistory = UsageHistoryStore.record(
                UsageCheckpoint(
                    recordedAt: recordedAt,
                    windowStart: snapshot.usageWindowStart,
                    resetAt: snapshot.resetAt,
                    usedPercent: snapshot.usedPercent,
                    weeklyTokens: snapshot.weeklyTokens,
                    localTokensTotal: snapshot.localTokensTotal,
                    rollingFiveMinuteTokens: snapshot.localTokenPace?.fiveMinutes,
                    apiEquivalentUSD: snapshot.usageIntelligence?.apiEquivalentUSD,
                    quotaWeightedUSD: snapshot.usageIntelligence?.quotaWeightedUSD
                )
            )
        }
        // Keep the graph axis tied to Codex's current authoritative window.
        // Older builds reused the first near-matching start time; small reset
        // deadline corrections then stretched the axis and visually shifted
        // every saved percentage checkpoint.
        usageWindowStart = snapshot.usageWindowStart
        usageWindowDurationMinutes = snapshot.windowDurationMinutes
        // The primary dial, menu bar, phone snapshot, and pace chart must all
        // use Codex's authoritative quota value. Token-derived projection is
        // reserved for the fractional Live Activity display; promoting it here
        // can make every primary surface jump by the estimator's full cap when
        // a large local ledger gap catches up.
        usedPercent = snapshot.usedPercent
        weekElapsedPercent = snapshot.weekElapsedPercent
        lastUpdated = recordedAt
        codexStatus = isLive
            ? "Live · \(snapshot.planName) plan"
            : "Cached · \(snapshot.planName) plan"
        publishMenuBarSummary()
        publishMobileSnapshot()
    }

    func publishMenuBarSummary() {
        let primary = usedPercent.flatMap { used in
            resetAt.map { reset in
                MenuBarQuotaWindow(
                    id: "primary",
                    label: "Codex",
                    usedPercent: used,
                    resetAt: reset,
                    durationMinutes: usageWindowDurationMinutes ?? 0
                )
            }
        }
        let secondary = secondaryQuota.map {
            MenuBarQuotaWindow(
                id: "secondary",
                label: "Codex",
                usedPercent: $0.usedPercent,
                resetAt: $0.resetAt,
                durationMinutes: $0.windowDurationMinutes
            )
        }
        let inventory = quotaInventory.map {
            MenuBarQuotaWindow(
                id: $0.id,
                label: $0.label,
                usedPercent: $0.usedPercent,
                resetAt: $0.resetAt,
                durationMinutes: $0.windowDurationMinutes
            )
        }
        let pace = UsagePace.calculate(
            usedPercent: usedPercent,
            windowStartDate: usageWindowStart,
            resetAt: resetAt,
            usageHistory: usageHistory,
            localTokensTotal: localTokensTotal,
            localTokenPace: localTokenPace,
            usageIntelligence: usageIntelligence,
            rate: .oneHour
        )
        let range = forecastSnapshot?.range.map {
            "RANGE \(Int($0.lowerBound.rounded()))–\(Int($0.upperBound.rounded()))%"
        }
        MenuBarSummaryModel.shared.update(
            MenuBarSummaryPayload(
                primary: primary,
                secondary: secondary,
                inventory: inventory,
                planName: planName,
                paceHeadline: pace.title,
                paceRunout: pace.estimatedRunout,
                forecastPercent: forecastPercent,
                forecastRange: range,
                expectedResetAt: resetAnnouncement == nil ? nil : resetLifecycle.activeExpectedAt(),
                resetIsDelayed: resetAnnouncement != nil && resetLifecycle.isDelayed(),
                lastBlessingAt: resetIntel?.lastBlessingAt,
                unreadTweet: newTweetAlert != nil,
                lastSuccessfulAt: lastCodexSuccessfulAt,
                lastAttemptFailed: lastCodexAttemptFailed,
                statusMessage: codexStatus,
                calendarDeadlineAt: resetAt,
                newTweet: newTweetAlert,
                tweets: resetIntel?.tweets ?? []
            )
        )
    }

    func publishMobileSnapshot() {
        let defaults = UserDefaults.standard
        let renewalTimestamp = defaults.double(forKey: BillingDefaults.renewalTimestamp)
        let renewalDate = renewalTimestamp > 0 ? Date(timeIntervalSince1970: renewalTimestamp) : nil
        let selectedSources = ForecastSourceSelection.load(from: defaults)
        let selectedSource = selectedSources.count == 1
            ? selectedSources.first!
            : .average
        let pace = UsagePace.calculate(
            usedPercent: usedPercent,
            windowStartDate: usageWindowStart,
            resetAt: resetAt,
            usageHistory: usageHistory,
            localTokensTotal: localTokensTotal,
            localTokenPace: localTokenPace,
            usageIntelligence: usageIntelligence,
            rate: .oneHour
        )
        let announcement = resetAnnouncement
        let sourceAnnouncement = forecastSnapshot?.announcement
        let applicabilityResponse = sourceAnnouncement.flatMap { source -> ResetApplicabilityResponse? in
            guard let response = ResetApplicability.load(),
                  response.announcementID == source.id else { return nil }
            return response
        }
        let mobileHistory = mobileUsageHistory(now: Date())
        var snapshot = MobileQuotaSnapshot(
            capturedAt: Date(),
            weekElapsedPercent: weekElapsedPercent,
            usagePercent: usedPercent,
            resetChancePercent: forecastPercent,
            resetAt: resetAt,
            usageWindowStart: usageWindowStart,
            windowDurationMinutes: usageWindowDurationMinutes,
            // The ledger includes cached input, cache writes, output, and
            // reasoning tokens. That is the cumulative number the pace UI
            // promises, so prefer it over the narrower account usage bucket.
            weeklyTokens: max(weeklyTokens ?? 0, usageIntelligence?.tokens.total ?? 0),
            planName: defaults.string(forKey: BillingDefaults.webPlanName) ?? planName,
            renewalDate: renewalDate,
            selectedSource: selectedSource.rawValue,
            selectedSources: ForecastSource.calculatorCases
                .filter(selectedSources.contains)
                .map(\.rawValue),
            providers: (forecastSnapshot?.providers ?? [])
                .map {
                MobileProviderReading(
                    source: $0.source.rawValue,
                    percent: $0.score,
                    updatedAt: $0.updatedAt
                )
            },
            resetAnnounced: announcement?.isActive() == true,
            announcementID: sourceAnnouncement?.id,
            announcementText: sourceAnnouncement?.text,
            announcementDate: sourceAnnouncement?.detectedAt,
            announcementExpectedAt: announcement == nil ? nil : resetLifecycle.expectedAt,
            announcementRequiresApplicabilityConfirmation: sourceAnnouncement?.requiresApplicabilityConfirmation,
            announcementAppliesToAccount: applicabilityResponse?.applies,
            announcementApplicabilityAnsweredAt: applicabilityResponse?.answeredAt,
            resetCompletedAt: resetLifecycle.completedAt,
            announcementURL: sourceAnnouncement?.url,
            lastBlessingAt: resetIntel?.lastBlessingAt,
            resetCreditExpiresAt: resetDeadlineIsCredit ? resetAt : nil,
            estimatedRunoutAt: pace.projectedExhaustion,
            paceWindowLabel: "last-hour",
            forecastUpdatedAt: forecastSnapshot?.providers.compactMap(\.updatedAt).max(),
            usageHistory: mobileHistory,
            tokenPace: localTokenPace.map {
                MobileTokenPace(
                    fiveMinutes: $0.fiveMinutes,
                    oneHour: $0.oneHour,
                    twelveHours: $0.twelveHours,
                    twentyFourHours: $0.twentyFourHours,
                    sinceReset: $0.sinceReset
                )
            },
            usageIntelligence: usageIntelligence.map {
                let input = $0.tokens.uncachedInput + $0.tokens.cachedInput + $0.tokens.cacheWriteInput
                return MobileUsageIntelligence(
                    apiEquivalentUSD: $0.apiEquivalentUSD,
                    quotaWeightedUSD: $0.quotaWeightedUSD,
                    gpt6CodexCredits: $0.gpt6CodexCredits,
                    pricingCoverage: $0.pricingCoverage,
                    speedCoverage: $0.speedCoverage,
                    fastShare: $0.fastShare,
                    eventCount: $0.eventCount,
                    ledgerBytes: $0.ledgerBytes,
                    topModel: $0.modelSummaries.first?.model,
                    totalTokens: $0.tokens.total,
                    cacheHitRate: input > 0 ? Double($0.tokens.cachedInput) / Double(input) : nil,
                    costTimeline: $0.costTimeline.map {
                        MobileCostPoint(date: $0.date, apiEquivalentUSD: $0.apiEquivalentUSD)
                    }
                )
            },
            secondaryQuota: secondaryQuota.map {
                MobileSecondaryQuota(
                    usedPercent: $0.usedPercent,
                    resetAt: $0.resetAt,
                    windowDurationMinutes: $0.windowDurationMinutes
                )
            },
            quotaInventory: quotaInventory.map {
                MobileQuotaWindow(
                    id: $0.id,
                    label: $0.label,
                    scope: $0.scope,
                    usedPercent: $0.usedPercent,
                    resetAt: $0.resetAt,
                    windowDurationMinutes: $0.windowDurationMinutes
                )
            },
            creditSummary: creditSummary.map {
                MobileCreditSummary(hasCredits: $0.hasCredits, unlimited: $0.unlimited, balance: $0.balance)
            },
            resetCredits: resetCredits.map {
                MobileResetCredit(
                    id: $0.id,
                    resetType: $0.resetType,
                    status: $0.status,
                    expiresAt: $0.expiresAt,
                    description: $0.description
                )
            },
            activeTasks: activeTasks.map {
                MobileCodexTask(id: $0.id, name: $0.name, state: $0.state, source: $0.source, updatedAt: $0.updatedAt)
            },
            weeklyArchives: weeklyArchives.map {
                MobileWeeklyArchive(
                    windowStart: $0.windowStart,
                    resetAt: $0.resetAt,
                    finalUsedPercent: $0.finalUsedPercent,
                    totalTokens: $0.totalTokens,
                    apiEquivalentUSD: $0.apiEquivalentUSD,
                    cacheHitRate: $0.cacheHitRate,
                    fastShare: $0.fastShare,
                    topModel: $0.modelSummaries.first?.model,
                    points: $0.points.map {
                        MobileWeeklyArchivePoint(
                            date: $0.date,
                            usedPercent: $0.usedPercent,
                            apiEquivalentUSD: $0.apiEquivalentUSD
                        )
                    }
                )
            },
            tiboPosts: (resetIntel?.tweets ?? [])
                .filter { ($0.date ?? .distantPast) >= Date().addingTimeInterval(-7 * 86_400) }
                .prefix(50)
                .map {
                    MobileTiboPost(
                        id: $0.alertIdentity,
                        date: $0.date,
                        text: $0.text,
                        inReplyTo: $0.inReplyTo,
                        url: $0.url,
                        isResetOriented: $0.isResetOriented
                    )
                }
        )
        snapshot.usageUpdatedAt = lastCodexSuccessfulAt ?? .distantPast
        snapshot.claude = ClaudeBarController.shared.model.mobileSnapshot
        Task { await MobileSnapshotPublisher.shared.schedule(snapshot) }
    }

    private func mobileUsageHistory(now: Date) -> [MobileUsagePoint]? {
        guard let usageWindowStart else { return nil }
        let window = usageHistory
            .filter {
                abs($0.windowStart.timeIntervalSince(usageWindowStart))
                    < UsageHistoryStore.windowTolerance
                    && $0.recordedAt >= usageWindowStart
                    && $0.recordedAt <= now
            }
            .sorted { $0.recordedAt < $1.recordedAt }
        guard !window.isEmpty else { return nil }

        let firstLocal = window.compactMap(\.localTokensTotal).first
        let firstOfficial = window.first?.weeklyTokens ?? 0
        var compacted: [UsageCheckpoint] = []
        var lastOlderBucket: Int?
        for point in window {
            if point.recordedAt >= now.addingTimeInterval(-24 * 3_600) {
                compacted.append(point)
            } else {
                let bucket = Int(point.recordedAt.timeIntervalSince1970 / (30 * 60))
                if bucket != lastOlderBucket {
                    compacted.append(point)
                    lastOlderBucket = bucket
                } else {
                    compacted[compacted.count - 1] = point
                }
            }
        }

        var result = [MobileUsagePoint(date: usageWindowStart, usedPercent: 0, tokens: 0)]
        result.append(contentsOf: compacted.map { point in
            let localDelta = firstLocal.flatMap { baseline in
                point.localTokensTotal.map { max(0, $0 - baseline) }
            }
            let anchoredLocal = localDelta.map { max(0, firstOfficial + $0) }
            let tokens = max(point.weeklyTokens, anchoredLocal ?? 0)
            return MobileUsagePoint(
                date: point.recordedAt,
                usedPercent: point.usedPercent,
                tokens: tokens > 0 ? tokens : nil
            )
        })

        // Account usage buckets and the local ledger count different token
        // categories. Rescale the cumulative history to the ledger's complete
        // total so the phone does not show a smaller number in the chart than
        // in the intelligence header, while preserving the observed curve.
        if let ledgerTotal = usageIntelligence?.tokens.total,
           ledgerTotal > 0,
           let reportedTotal = result.compactMap(\.tokens).max(),
           reportedTotal > 0 {
            let scale = Double(ledgerTotal) / Double(reportedTotal)
            result = result.map { point in
                MobileUsagePoint(
                    date: point.date,
                    usedPercent: point.usedPercent,
                    tokens: point.tokens.map { Int64((Double($0) * scale).rounded()) }
                )
            }
        }

        if let usedPercent {
            let currentTokens = max(
                result.compactMap(\.tokens).max() ?? 0,
                usageIntelligence?.tokens.total ?? 0
            )
            let current = MobileUsagePoint(
                date: now,
                usedPercent: usedPercent,
                tokens: currentTokens > 0 ? currentTokens : nil
            )
            if let last = result.last, now.timeIntervalSince(last.date) < 30 {
                result[result.count - 1] = current
            } else {
                result.append(current)
            }
        }
        return result
    }

    func clearNewTweetAlert() {
        guard let newTweetAlert else { return }
        UserDefaults.standard.set(newTweetAlert.alertIdentity, forKey: clearedTweetKey)
        self.newTweetAlert = nil
        publishMenuBarSummary()
    }

    private func updateTweetAlert(from tweets: [TiboTweet]) {
        guard let newest = tweets.first else { return }

        let defaults = UserDefaults.standard
        let observedID = defaults.string(forKey: observedTweetKey)
            .map(TiboTweet.canonicalizeStoredIdentity)
        let clearedID = defaults.string(forKey: clearedTweetKey)
            .map(TiboTweet.canonicalizeStoredIdentity)
        let existing = defaults.stringArray(forKey: observedTweetsKey)
        var seen = Set(existing ?? [])
        if let observedID { seen.insert(observedID) }
        if let clearedID { seen.insert(clearedID) }
        let savedTimestamp = defaults.double(forKey: tweetWatermarkKey)
        let watermark = savedTimestamp > 0 ? Date(timeIntervalSince1970: savedTimestamp) : nil

        // A mirror can discover yesterday's post after another provider has
        // already shown it. Notify only for an unseen identity newer than the
        // newest posted time we have observed, never because feed order moved.
        let candidate: TiboTweet? = existing == nil ? nil : tweets
            .filter { tweet in
                guard !seen.contains(tweet.alertIdentity), let date = tweet.date else { return false }
                return watermark.map { date > $0 } ?? true
            }
            .max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }

        let currentIdentities = tweets.map(\.alertIdentity)
        let currentSet = Set(currentIdentities)
        let history = currentIdentities + seen.filter { !currentSet.contains($0) }
        defaults.set(Array(history.prefix(256)), forKey: observedTweetsKey)
        defaults.set(newest.alertIdentity, forKey: observedTweetKey)
        if let newestDate = tweets.compactMap(\.date).max() {
            defaults.set(max(watermark ?? .distantPast, newestDate).timeIntervalSince1970, forKey: tweetWatermarkKey)
        }

        if existing == nil {
            // Upgrade migration: everything already in the feed is baseline.
            defaults.set(newest.alertIdentity, forKey: clearedTweetKey)
            return
        }

        // Do not clear this automatically when the source refreshes or the
        // app relaunches. It remains visible until the user taps the check.
        if let candidate, clearedID != candidate.alertIdentity {
            newTweetAlert = candidate
        }
    }
}

struct CodexSnapshot: Codable, Sendable {
    let usedPercent: Double
    let resetAt: Date
    let resetDeadlineIsCredit: Bool
    let weeklyTokens: Int64
    let localTokensTotal: Int64?
    let localTokenPace: LocalTokenPaceSnapshot?
    let usageIntelligence: UsageIntelligenceSnapshot?
    let secondaryQuota: SecondaryQuotaSnapshot?
    let quotaInventory: [CodexQuotaWindow]?
    let creditSummary: CodexCreditSummary?
    let resetCredits: [CodexResetCredit]?
    let activeTasks: [CodexTaskSnapshot]?
    let usageDays: [UsageDay]
    let usageWindowStart: Date
    let windowDurationMinutes: Double?
    let weekElapsedPercent: Double
    let planName: String
}

struct CodexQuotaWindow: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let scope: String
    let usedPercent: Double
    let resetAt: Date
    let windowDurationMinutes: Double
}

struct CodexCreditSummary: Codable, Equatable, Sendable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

struct CodexResetCredit: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let resetType: String
    let status: String
    let grantedAt: Date?
    let expiresAt: Date?
    let description: String?
}

struct CodexTaskSnapshot: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let state: String
    let source: String
    let updatedAt: Date
}

struct UsageDay: Codable, Identifiable, Sendable {
    let date: Date
    let tokens: Int64

    var id: Date { date }
}

struct LocalTokenPaceSnapshot: Codable, Equatable, Sendable {
    let fiveMinutes: Int64
    let oneHour: Int64
    let twelveHours: Int64
    let twentyFourHours: Int64
    let sinceReset: Int64

    func tokens(for rate: UsagePaceRate) -> Int64 {
        switch rate {
        case .fiveMinutes: return fiveMinutes
        case .oneHour: return oneHour
        case .twelveHours: return twelveHours
        case .twentyFourHours: return twentyFourHours
        case .total: return sinceReset
        }
    }
}

/// A local, time-stamped usage reading. Codex exposes daily buckets, but not
/// the short-interval points needed for a useful pace line, so Quota Glance records a
/// lightweight checkpoint while it is running.
struct UsageCheckpoint: Codable, Identifiable, Sendable {
    let recordedAt: Date
    let windowStart: Date
    let resetAt: Date
    let usedPercent: Double
    let weeklyTokens: Int64
    let localTokensTotal: Int64?
    let rollingFiveMinuteTokens: Int64?
    let apiEquivalentUSD: Double?
    let quotaWeightedUSD: Double?

    var id: Date { recordedAt }
}

enum UsageHistoryStore {
    private static let legacyDefaultsKey = "QuotaGlance.usageCheckpoints.v1"
    // Codex can revise an inferred weekly deadline as expiring sub-windows
    // disappear. Keep those readings in one real quota window while remaining
    // far below the seven-day distance between actual weekly resets.
    static let windowTolerance: TimeInterval = 2 * 60 * 60
    private static let minimumSampleInterval: TimeInterval = 5 * 60
    // One complete weekly window plus a day of overlap is enough to recover
    // around a reset without retaining an ever-growing usage archive.
    private static let retention: TimeInterval = 8 * 86_400
    private static let maximumCheckpointCount = 2_500
    private static let historyURL = applicationSupportDirectory
        .appendingPathComponent("usage-history-v2.json")
    private static let backupURL = applicationSupportDirectory
        .appendingPathComponent("usage-history-v2.backup.json")
    private static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quota Glance", isDirectory: true)
    }
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    static func load() -> [UsageCheckpoint] {
        if let checkpoints = decodeFile(at: historyURL) {
            return checkpoints.sorted { $0.recordedAt < $1.recordedAt }
        }
        if let checkpoints = decodeFile(at: backupURL) {
            save(checkpoints)
            return checkpoints.sorted { $0.recordedAt < $1.recordedAt }
        }
        // Preserve every checkpoint collected by builds that used
        // UserDefaults, then move future writes to a durable atomic file.
        if let data = UserDefaults.standard.data(forKey: legacyDefaultsKey),
           let checkpoints = try? decoder.decode([UsageCheckpoint].self, from: data) {
            save(checkpoints)
            return checkpoints.sorted { $0.recordedAt < $1.recordedAt }
        }
        return []
    }

    static func purge() {
        for url in [historyURL, backupURL] where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }

    static func record(_ checkpoint: UsageCheckpoint) -> [UsageCheckpoint] {
        var checkpoints = load()
        let now = checkpoint.recordedAt

        // Keep the local file small and discard stale windows after a month.
        checkpoints.removeAll { now.timeIntervalSince($0.recordedAt) > retention }

        let sameWindow = checkpoints.indices.filter {
            isSameWindow(checkpoints[$0], as: checkpoint)
        }
        let canonicalWindowStart = sameWindow.first.map { checkpoints[$0].windowStart }
            ?? checkpoint.windowStart
        let canonicalResetAt = sameWindow.first.map { checkpoints[$0].resetAt }
            ?? checkpoint.resetAt
        let mostRecent = sameWindow.max { checkpoints[$0].recordedAt < checkpoints[$1].recordedAt }
            .map { checkpoints[$0] }
        let lastKnownTokens: Int64 = sameWindow.reversed().compactMap { index in
            let tokens = checkpoints[index].weeklyTokens
            return tokens > 0 ? tokens : nil
        }.first ?? 0
        // A Codex process restart can briefly return a zero or stale reading.
        // Usage cannot move backwards inside one quota window, so retain the
        // last durable values until the service catches back up.
        let stablePercent = max(checkpoint.usedPercent, mostRecent?.usedPercent ?? 0)
        let stableLocalTokens: Int64? = {
            guard let previous = mostRecent?.localTokensTotal else {
                return checkpoint.localTokensTotal
            }
            return max(previous, checkpoint.localTokensTotal ?? previous)
        }()
        let bucketedCheckpoint = UsageCheckpoint(
            recordedAt: bucketStart(for: now),
            windowStart: canonicalWindowStart,
            resetAt: canonicalResetAt,
            usedPercent: stablePercent,
            weeklyTokens: checkpoint.weeklyTokens > 0 ? checkpoint.weeklyTokens : lastKnownTokens,
            localTokensTotal: stableLocalTokens,
            rollingFiveMinuteTokens: checkpoint.rollingFiveMinuteTokens,
            apiEquivalentUSD: max(checkpoint.apiEquivalentUSD ?? 0, mostRecent?.apiEquivalentUSD ?? 0),
            quotaWeightedUSD: max(checkpoint.quotaWeightedUSD ?? 0, mostRecent?.quotaWeightedUSD ?? 0)
        )

        let shouldPersist: Bool
        if let latestIndex = sameWindow.max(by: {
            checkpoints[$0].recordedAt < checkpoints[$1].recordedAt
        }), sampleBucket(for: checkpoints[latestIndex].recordedAt) == sampleBucket(for: now) {
            // Refresh only inside the same fixed five-minute bucket. Comparing
            // against a moving "latest timestamp" meant every minute reset the
            // timer and a second checkpoint could never be created.
            checkpoints[latestIndex] = bucketedCheckpoint
            // The current chart still receives this in-memory value, but the
            // durable file is written only once per fixed five-minute bucket.
            shouldPersist = false
        } else {
            checkpoints.append(bucketedCheckpoint)
            shouldPersist = true
        }

        checkpoints.sort { $0.recordedAt < $1.recordedAt }
        if checkpoints.count > maximumCheckpointCount {
            checkpoints = Array(checkpoints.suffix(maximumCheckpointCount))
        }
        if shouldPersist {
            save(checkpoints)
        }
        return checkpoints
    }

    static func canonicalWindowStart(for proposedStart: Date, resetAt: Date) -> Date {
        let probe = UsageCheckpoint(
            recordedAt: Date(),
            windowStart: proposedStart,
            resetAt: resetAt,
            usedPercent: 0,
            weeklyTokens: 0,
            localTokensTotal: nil,
            rollingFiveMinuteTokens: nil,
            apiEquivalentUSD: nil,
            quotaWeightedUSD: nil
        )
        return load().last(where: { isSameWindow($0, as: probe) })?.windowStart ?? proposedStart
    }

    static func pointCount(windowStart: Date?, resetAt: Date?) -> Int {
        guard let windowStart, let resetAt else { return 0 }
        let probe = UsageCheckpoint(
            recordedAt: Date(),
            windowStart: windowStart,
            resetAt: resetAt,
            usedPercent: 0,
            weeklyTokens: 0,
            localTokensTotal: nil,
            rollingFiveMinuteTokens: nil,
            apiEquivalentUSD: nil,
            quotaWeightedUSD: nil
        )
        return load().filter { isSameWindow($0, as: probe) }.count
    }

    static func sampleIntervalDescription() -> String {
        "5m"
    }

    /// Returns the cumulative-token change over the requested trailing
    /// interval using the tiny persisted checkpoint ledger. If Quota Glance
    /// has collected less than the full interval, the earliest available
    /// sample is used so short-lived installs still produce a useful pace.
    static func localTokenBurn(
        currentTotal: Int64,
        windowStart: Date,
        now: Date,
        interval: TimeInterval
    ) -> Int64 {
        let samples = load()
            .filter {
                abs($0.windowStart.timeIntervalSince(windowStart)) < windowTolerance
                    && $0.recordedAt >= windowStart
                    && $0.recordedAt < now
                    && $0.localTokensTotal != nil
            }
            .sorted { $0.recordedAt < $1.recordedAt }
        guard !samples.isEmpty else { return 0 }

        let cutoff = max(windowStart, now.addingTimeInterval(-interval))
        let baseline = samples.last(where: { $0.recordedAt <= cutoff })
            ?? samples.first
        return max(0, currentTotal - (baseline?.localTokensTotal ?? currentTotal))
    }

    private static func sampleBucket(for date: Date) -> Int64 {
        Int64(floor(date.timeIntervalSince1970 / minimumSampleInterval))
    }

    private static func bucketStart(for date: Date) -> Date {
        Date(timeIntervalSince1970: Double(sampleBucket(for: date)) * minimumSampleInterval)
    }

    private static func isSameWindow(_ lhs: UsageCheckpoint, as rhs: UsageCheckpoint) -> Bool {
        abs(lhs.resetAt.timeIntervalSince(rhs.resetAt)) < windowTolerance
            || abs(lhs.windowStart.timeIntervalSince(rhs.windowStart)) < windowTolerance
    }

    private static func decodeFile(at url: URL) -> [UsageCheckpoint]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode([UsageCheckpoint].self, from: data)
    }

    private static func save(_ checkpoints: [UsageCheckpoint]) {
        guard let data = try? encoder.encode(checkpoints) else { return }
        do {
            try FileManager.default.createDirectory(
                at: applicationSupportDirectory,
                withIntermediateDirectories: true
            )
            if let existing = try? Data(contentsOf: historyURL),
               (try? decoder.decode([UsageCheckpoint].self, from: existing)) != nil {
                try existing.write(to: backupURL, options: .atomic)
            }
            try data.write(to: historyURL, options: .atomic)
        } catch {
            // The in-memory history remains usable; the next refresh retries.
        }
    }
}

/// Persists one cumulative-token baseline per weekly quota window. This lets
/// total pace remain exact without rereading an entire week's rollout logs on
/// every five-minute sample.
private enum LocalTokenBaselineStore {
    private static let windowKey = "QuotaGlance.localTokenBaseline.windowStart"
    private static let totalKey = "QuotaGlance.localTokenBaseline.total"
    private static let tolerance: TimeInterval = 2 * 60 * 60

    static func note(windowStart: Date, currentTotal: Int64, tokensSinceReset: Int64) {
        guard currentTotal >= 0, tokensSinceReset >= 0, currentTotal >= tokensSinceReset else { return }
        let defaults = UserDefaults.standard
        let storedStart = Date(timeIntervalSince1970: defaults.double(forKey: windowKey))
        if defaults.object(forKey: totalKey) != nil,
           abs(storedStart.timeIntervalSince(windowStart)) < tolerance {
            return
        }
        defaults.set(windowStart.timeIntervalSince1970, forKey: windowKey)
        defaults.set(NSNumber(value: currentTotal - tokensSinceReset), forKey: totalKey)
    }

    static func tokensSinceReset(windowStart: Date, currentTotal: Int64) -> Int64? {
        let defaults = UserDefaults.standard
        guard let number = defaults.object(forKey: totalKey) as? NSNumber else { return nil }
        let storedStart = Date(timeIntervalSince1970: defaults.double(forKey: windowKey))
        guard abs(storedStart.timeIntervalSince(windowStart)) < tolerance else { return nil }
        return max(0, currentTotal - number.int64Value)
    }
}

private struct CachedCodexEnvelope: Codable {
    let savedAt: Date
    let snapshot: CodexSnapshot
}

/// The graph checkpoints and the live dashboard snapshot have different jobs:
/// checkpoints build a historical curve, while this cache makes every dial
/// and pace bucket available immediately after Quota Glance or Codex restarts.
private enum CodexSnapshotStore {
    private static let directory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Quota Glance", isDirectory: true)
    private static let snapshotURL = directory.appendingPathComponent("codex-snapshot-v1.json")
    private static let backupURL = directory.appendingPathComponent("codex-snapshot-v1.backup.json")
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    static func load() -> CachedCodexEnvelope? {
        decode(at: snapshotURL) ?? decode(at: backupURL)
    }

    static func save(_ incoming: CodexSnapshot, at date: Date = Date()) -> CachedCodexEnvelope {
        let snapshot: CodexSnapshot
        if let previous = load()?.snapshot, isSameWindow(previous, incoming) {
            snapshot = merged(previous: previous, incoming: incoming)
        } else {
            snapshot = incoming
        }
        let envelope = CachedCodexEnvelope(savedAt: date, snapshot: snapshot)
        guard let data = try? encoder.encode(envelope) else { return envelope }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let existing = try? Data(contentsOf: snapshotURL),
               (try? decoder.decode(CachedCodexEnvelope.self, from: existing)) != nil {
                try existing.write(to: backupURL, options: .atomic)
            }
            try data.write(to: snapshotURL, options: .atomic)
        } catch {
            // Keep the in-memory snapshot; a later successful refresh retries.
        }
        return envelope
    }

    private static func decode(at url: URL) -> CachedCodexEnvelope? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CachedCodexEnvelope.self, from: data)
    }

    private static func isSameWindow(_ lhs: CodexSnapshot, _ rhs: CodexSnapshot) -> Bool {
        abs(lhs.usageWindowStart.timeIntervalSince(rhs.usageWindowStart))
            < UsageHistoryStore.windowTolerance
    }

    private static func merged(previous: CodexSnapshot, incoming: CodexSnapshot) -> CodexSnapshot {
        let pace: LocalTokenPaceSnapshot? = {
            guard let current = incoming.localTokenPace else { return previous.localTokenPace }
            guard let old = previous.localTokenPace else { return current }
            return LocalTokenPaceSnapshot(
                fiveMinutes: current.fiveMinutes,
                oneHour: current.oneHour,
                twelveHours: current.twelveHours,
                twentyFourHours: current.twentyFourHours,
                sinceReset: max(old.sinceReset, current.sinceReset)
            )
        }()
        let days: [UsageDay] = {
            guard !incoming.usageDays.isEmpty else { return previous.usageDays }
            var byDay = Dictionary(uniqueKeysWithValues: previous.usageDays.map { ($0.date, $0) })
            for day in incoming.usageDays {
                if let old = byDay[day.date] {
                    byDay[day.date] = UsageDay(date: day.date, tokens: max(old.tokens, day.tokens))
                } else {
                    byDay[day.date] = day
                }
            }
            return byDay.values.sorted { $0.date < $1.date }
        }()
        return CodexSnapshot(
            usedPercent: max(previous.usedPercent, incoming.usedPercent),
            resetAt: incoming.resetAt,
            resetDeadlineIsCredit: incoming.resetDeadlineIsCredit,
            weeklyTokens: max(previous.weeklyTokens, incoming.weeklyTokens),
            localTokensTotal: maxOptional(previous.localTokensTotal, incoming.localTokensTotal),
            localTokenPace: pace,
            usageIntelligence: incoming.usageIntelligence ?? previous.usageIntelligence,
            secondaryQuota: incoming.secondaryQuota ?? previous.secondaryQuota,
            quotaInventory: incoming.quotaInventory ?? previous.quotaInventory,
            creditSummary: incoming.creditSummary ?? previous.creditSummary,
            resetCredits: incoming.resetCredits ?? previous.resetCredits,
            activeTasks: incoming.activeTasks ?? previous.activeTasks,
            usageDays: days,
            usageWindowStart: previous.usageWindowStart,
            windowDurationMinutes: incoming.windowDurationMinutes ?? previous.windowDurationMinutes,
            weekElapsedPercent: incoming.weekElapsedPercent,
            planName: incoming.planName == "Codex" ? previous.planName : incoming.planName
        )
    }

    private static func maxOptional(_ lhs: Int64?, _ rhs: Int64?) -> Int64? {
        switch (lhs, rhs) {
        case let (left?, right?): return max(left, right)
        case let (left?, nil): return left
        case let (nil, right?): return right
        case (nil, nil): return nil
        }
    }
}

enum DashboardError: LocalizedError {
    case codexNotFound
    case invalidCodexResponse
    case forecastUnavailable
    case billingLoginRequired
    case billingUnavailable

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "Codex executable not found"
        case .invalidCodexResponse: return "Codex usage is unavailable"
        case .forecastUnavailable: return "Forecast temporarily unavailable"
        case .billingLoginRequired: return "Sign in to ChatGPT in Quota Glance"
        case .billingUnavailable: return "ChatGPT billing is temporarily unavailable"
        }
    }
}

enum CodexService {
    static func fetch() async throws -> CodexSnapshot {
        try await Task.detached(priority: .utility) {
            // Foundation's FileHandle and JSON APIs create autoreleased NSData
            // objects. A long-lived Swift concurrency worker does not promise
            // to drain them after this job, which previously retained roughly
            // 256 KB per rollout chunk forever.
            try autoreleasepool { try fetchSynchronously() }
        }.value
    }

    private static func fetchSynchronously() throws -> CodexSnapshot {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        guard let codexPath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw DashboardError.codexNotFound
        }

        let process = Process()
        let output = Pipe()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()

        let messages = [
            #"{"method":"initialize","id":0,"params":{"clientInfo":{"name":"quota_glance","title":"Quota Glance","version":"1.0.0"}}}"#,
            #"{"method":"initialized","params":{}}"#,
            #"{"method":"account/rateLimits/read","id":1}"#,
            #"{"method":"account/usage/read","id":2}"#,
            #"{"method":"thread/list","id":3,"params":{"limit":30,"archived":false,"sortKey":"updated_at","sortDirection":"desc","useStateDbOnly":true}}"#
        ].joined(separator: "\n") + "\n"
        input.fileHandleForWriting.write(Data(messages.utf8))
        // The account endpoints are asynchronous. Keep stdin alive briefly so the
        // app-server can deliver both responses before EOF shuts the connection down.
        Thread.sleep(forTimeInterval: 1.5)
        try? input.fileHandleForWriting.close()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        var rateResult: [String: Any]?
        var usageResult: [String: Any]?
        var threadResult: [String: Any]?
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard
                let lineData = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let id = object["id"] as? Int,
                let result = object["result"] as? [String: Any]
            else { continue }
            if id == 1 { rateResult = result }
            if id == 2 { usageResult = result }
            if id == 3 { threadResult = result }
        }

        guard
            let rateLimits = rateResult?["rateLimits"] as? [String: Any],
            let primary = rateLimits["primary"] as? [String: Any],
            let usedPercent = number(primary["usedPercent"]),
            let resetsAt = number(primary["resetsAt"]),
            let durationMinutes = number(primary["windowDurationMins"])
        else { throw DashboardError.invalidCodexResponse }

        let weeklyResetDate = Date(timeIntervalSince1970: resetsAt)
        let windowStartDate = weeklyResetDate.addingTimeInterval(-durationMinutes * 60)
        let resetCreditExpiry = earliestAvailableResetCreditExpiry(
            in: rateResult,
            before: weeklyResetDate
        )
        let resetDate = resetCreditExpiry ?? weeklyResetDate
        // The orange dial represents the seven-day weekly cycle. If a reset
        // credit expires early, use that expiry as the deadline while keeping
        // the same one-week visual baseline the user expects.
        let elapsed = calendarProgress(to: resetDate, at: Date())
        let usageDays = dailyUsageSince(windowStartDate, usageResult: usageResult)
        let weeklyTokens = usageDays.reduce(Int64(0)) { $0 + $1.tokens }
        let localTokensTotal = localCodexTokenTotal()
        let usageIntelligence = UsageIntelligenceStore.refresh(windowStart: windowStartDate)
        let localTokenPace = localTokenPaceSnapshot(
            windowStart: windowStartDate,
            now: Date(),
            currentTotal: localTokensTotal,
            ledgerPace: usageIntelligence.recentTokenPace
        )
        let secondaryQuota: SecondaryQuotaSnapshot? = {
            guard let secondary = rateLimits["secondary"] as? [String: Any],
                  let used = number(secondary["usedPercent"] ?? secondary["used_percent"]),
                  let secondaryReset = number(secondary["resetsAt"] ?? secondary["resets_at"]),
                  let secondaryDuration = number(secondary["windowDurationMins"] ?? secondary["window_minutes"])
            else { return nil }
            return SecondaryQuotaSnapshot(
                usedPercent: max(0, min(100, used)),
                resetAt: Date(timeIntervalSince1970: secondaryReset),
                windowDurationMinutes: secondaryDuration
            )
        }()
        let plan = displayPlanName(rateLimits["planType"] as? String)
        let quotaInventory = quotaWindows(from: rateResult)
        let creditSummary = creditSummary(from: rateLimits["credits"] as? [String: Any])
        let resetCredits = resetCredits(from: rateResult)
        let activeTasks = activeTasks(from: threadResult)

        return CodexSnapshot(
            usedPercent: usedPercent,
            resetAt: resetDate,
            resetDeadlineIsCredit: resetCreditExpiry != nil,
            weeklyTokens: weeklyTokens,
            localTokensTotal: localTokensTotal,
            localTokenPace: localTokenPace,
            usageIntelligence: usageIntelligence,
            secondaryQuota: secondaryQuota,
            quotaInventory: quotaInventory,
            creditSummary: creditSummary,
            resetCredits: resetCredits,
            activeTasks: activeTasks,
            usageDays: usageDays,
            // Pace analysis follows the actual Codex usage window. The orange
            // dial can still use its separate seven-day visual baseline.
            usageWindowStart: windowStartDate,
            windowDurationMinutes: durationMinutes,
            weekElapsedPercent: elapsed,
            planName: plan
        )
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func quotaWindows(from result: [String: Any]?) -> [CodexQuotaWindow] {
        guard let byID = result?["rateLimitsByLimitId"] as? [String: Any] else { return [] }
        var windows: [CodexQuotaWindow] = []
        for (limitID, raw) in byID {
            guard let limit = raw as? [String: Any] else { continue }
            let label = (limit["limitName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let display = (label?.isEmpty == false ? label! : limitID == "codex" ? "Codex" : limitID)
            for (key, scope) in [("primary", "Short window"), ("secondary", "Weekly window")] {
                guard let window = limit[key] as? [String: Any],
                      let used = number(window["usedPercent"] ?? window["used_percent"]),
                      let reset = number(window["resetsAt"] ?? window["resets_at"]),
                      let minutes = number(window["windowDurationMins"] ?? window["window_minutes"])
                else { continue }
                windows.append(CodexQuotaWindow(
                    id: limitID + "." + key,
                    label: display,
                    scope: scope,
                    usedPercent: max(0, min(100, used)),
                    resetAt: Date(timeIntervalSince1970: reset),
                    windowDurationMinutes: minutes
                ))
            }
        }
        return windows.sorted {
            if $0.label != $1.label { return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            return $0.windowDurationMinutes < $1.windowDurationMinutes
        }
    }

    private static func creditSummary(from value: [String: Any]?) -> CodexCreditSummary? {
        guard let value else { return nil }
        let has = value["hasCredits"] as? Bool ?? false
        let unlimited = value["unlimited"] as? Bool ?? false
        let balance = value["balance"].map { String(describing: $0) }
        return CodexCreditSummary(hasCredits: has, unlimited: unlimited, balance: balance)
    }

    private static func resetCredits(from result: [String: Any]?) -> [CodexResetCredit] {
        guard let container = result?["rateLimitResetCredits"] as? [String: Any],
              let credits = container["credits"] as? [[String: Any]] else { return [] }
        return credits.compactMap { credit in
            guard let id = credit["id"] as? String,
                  let type = credit["resetType"] as? String,
                  let status = credit["status"] as? String else { return nil }
            return CodexResetCredit(
                id: id,
                resetType: type,
                status: status,
                grantedAt: number(credit["grantedAt"]).map(Date.init(timeIntervalSince1970:)),
                expiresAt: number(credit["expiresAt"]).map(Date.init(timeIntervalSince1970:)),
                description: credit["description"] as? String
            )
        }.sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
    }

    private static func activeTasks(from result: [String: Any]?) -> [CodexTaskSnapshot] {
        guard let threads = result?["data"] as? [[String: Any]] else { return [] }
        return threads.compactMap { thread in
            guard let id = thread["id"] as? String,
                  let updated = number(thread["updatedAt"] ?? thread["updated_at"])
            else { return nil }
            let rolloutIsActive = (thread["path"] as? String).map {
                CodexActivityProbe.isTurnActive(rolloutURL: URL(fileURLWithPath: $0))
            } ?? false
            // Loaded/open threads are not necessarily doing work. Only a rollout with
            // an active turn should keep the phone Live Activity alive.
            let updatedAt = Date(timeIntervalSince1970: updated)
            guard rolloutIsActive, Date().timeIntervalSince(updatedAt) <= 10 * 60 else { return nil }
            let rawName = (thread["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return CodexTaskSnapshot(
                id: id,
                name: rawName?.isEmpty == false ? rawName! : "Codex task",
                state: "active",
                source: (thread["source"] as? String) ?? "Codex",
                updatedAt: updatedAt
            )
        }
    }

    private static func displayPlanName(_ rawValue: String?) -> String {
        switch rawValue?.lowercased() {
        case "free": return "Free"
        case "go": return "Go"
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "prolite": return "Pro Lite"
        case "team": return "Team"
        case "business", "self_serve_business_prolite", "self_serve_business_usage_based": return "Business"
        case "edu": return "Edu"
        case "enterprise", "ent26", "enterprise_cbp_automation", "enterprise_cbp_usage_based": return "Enterprise"
        default: return "Codex"
        }
    }

    private static func localCodexTokenTotal() -> Int64? {
        let database = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/state_5.sqlite")
        guard FileManager.default.fileExists(atPath: database.path) else { return nil }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, "SELECT COALESCE(SUM(tokens_used), 0) FROM threads;"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let value = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Int64(value)
        } catch {
            return nil
        }
    }

    private static func localTokenPaceSnapshot(
        windowStart: Date,
        now: Date,
        currentTotal: Int64?,
        ledgerPace: LocalTokenPaceSnapshot?
    ) -> LocalTokenPaceSnapshot? {
        guard currentTotal != nil || ledgerPace != nil else { return nil }
        let intervals: [TimeInterval] = [5 * 60, 60 * 60, 12 * 60 * 60, 24 * 60 * 60]
        let databaseTotals = intervals.map { interval -> Int64 in
            guard let currentTotal else { return 0 }
            return UsageHistoryStore.localTokenBurn(
                currentTotal: currentTotal, windowStart: windowStart, now: now, interval: interval
            )
        }
        let totals = [
            max(databaseTotals[0], ledgerPace?.fiveMinutes ?? 0),
            max(databaseTotals[1], ledgerPace?.oneHour ?? 0),
            max(databaseTotals[2], ledgerPace?.twelveHours ?? 0),
            max(databaseTotals[3], ledgerPace?.twentyFourHours ?? 0)
        ]

        let sinceReset: Int64 = {
            if let currentTotal,
               let persisted = LocalTokenBaselineStore.tokensSinceReset(
                    windowStart: windowStart,
                    currentTotal: currentTotal
               ) {
                return max(persisted, ledgerPace?.sinceReset ?? 0)
            }
            // On the first sample of a new quota window, seed from the oldest
            // retained checkpoint. Future five-minute samples remain exact.
            return max(totals[3], ledgerPace?.sinceReset ?? 0)
        }()

        return LocalTokenPaceSnapshot(
            fiveMinutes: totals[0],
            oneHour: totals[1],
            twelveHours: totals[2],
            twentyFourHours: totals[3],
            sinceReset: sinceReset
        )
    }

    static func calendarProgress(to resetDate: Date, at now: Date) -> Double {
        let weekStartDate = resetDate.addingTimeInterval(-7 * 86_400)
        return strictElapsedPercent(from: weekStartDate, to: resetDate, at: now)
    }

    private static func strictElapsedPercent(from start: Date, to deadline: Date, at now: Date) -> Double {
        guard deadline > start else { return now >= deadline ? 100 : 0 }
        if now <= start { return 0 }
        if now < deadline {
            let fraction = now.timeIntervalSince(start) / deadline.timeIntervalSince(start)
            return max(0, min(99.999_999, fraction * 100))
        }
        return 100
    }

    private static func earliestAvailableResetCreditExpiry(
        in rateResult: [String: Any]?,
        before weeklyResetDate: Date
    ) -> Date? {
        guard
            let resetCredits = rateResult?["rateLimitResetCredits"] as? [String: Any],
            let credits = resetCredits["credits"] as? [[String: Any]]
        else { return nil }

        let now = Date()
        return credits.compactMap { credit -> Date? in
            guard
                (credit["status"] as? String)?.lowercased() == "available",
                let expiryTimestamp = number(credit["expiresAt"])
            else { return nil }
            let expiry = Date(timeIntervalSince1970: expiryTimestamp)
            guard expiry > now, expiry < weeklyResetDate else { return nil }
            return expiry
        }
        .min()
    }

    private static func dailyUsageSince(_ startDate: Date, usageResult: [String: Any]?) -> [UsageDay] {
        guard let buckets = usageResult?["dailyUsageBuckets"] as? [[String: Any]] else { return [] }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let startOfDay = Calendar(identifier: .gregorian).startOfDay(for: startDate)

        return buckets.compactMap { bucket -> UsageDay? in
            guard
                let dateText = bucket["startDate"] as? String,
                let date = formatter.date(from: dateText),
                date >= startOfDay,
                date <= Date(),
                let tokens = bucket["tokens"] as? NSNumber
            else { return nil }
            return UsageDay(date: date, tokens: tokens.int64Value)
        }
        .sorted { $0.date < $1.date }
    }
}

struct ForecastSnapshot: Sendable {
    let score: Double
    let baselineScore: Double
    let displayLabel: String?
    let source: ForecastSource
    let selectedSources: Set<ForecastSource>
    let announcement: ResetAnnouncement?
    let scheduledReset: ResetSchedule?
    let intel: ResetIntelSnapshot?
    let providers: [ResetProviderSnapshot]
    let headline: String?
    let range: ClosedRange<Double>?
}

struct ResetSchedule: Sendable, Equatable {
    let id: String
    let source: ForecastSource
    let announcedAt: Date
    let expectedAt: Date
    let text: String
    let url: URL?
}

struct ResetAnnouncement: Sendable, Equatable {
    let id: String
    let source: ForecastSource
    let detectedAt: Date
    let expectedAt: Date?
    let text: String
    let url: URL?

    var requiresApplicabilityConfirmation: Bool {
        ResetApplicability.requiresConfirmation(text)
    }

    func isActive(at date: Date = Date()) -> Bool {
        let expiresAt = expectedAt?.addingTimeInterval(3 * 3_600)
            ?? detectedAt.addingTimeInterval(36 * 3_600)
        return detectedAt <= date.addingTimeInterval(5 * 60) && date <= expiresAt
    }
}

enum ResetAnnouncementTimeParser {
    static func expectedDate(in text: String, postedAt: Date) -> Date? {
        let normalized = text
            .replacingOccurrences(of: "a.m.", with: "am", options: .caseInsensitive)
            .replacingOccurrences(of: "p.m.", with: "pm", options: .caseInsensitive)

        guard
            let expression = try? NSRegularExpression(
                pattern: #"\b([0-2]?\d)(?::([0-5]\d))?\s*(am|pm)?\s*(PST|PDT|PT|Pacific(?:\s+Time)?|MST|MDT|MT|Mountain(?:\s+Time)?|CST|CDT|CT|Central(?:\s+Time)?|EST|EDT|ET|Eastern(?:\s+Time)?|UTC|GMT)?\b"#,
                options: [.caseInsensitive]
            )
        else { return nil }

        let fullRange = NSRange(normalized.startIndex..., in: normalized)
        let matches = expression.matches(in: normalized, range: fullRange)
        for match in matches {
            guard
                let hourRange = Range(match.range(at: 1), in: normalized),
                let rawHour = Int(normalized[hourRange])
            else { continue }
            let meridiem = Range(match.range(at: 3), in: normalized).map { String(normalized[$0]).lowercased() }
            let zoneToken = Range(match.range(at: 4), in: normalized).map { String(normalized[$0]).uppercased() }
            // Avoid treating unrelated numbers as times. Tibo often writes
            // "14pm PST", so a timezone is sufficient even with odd 24-hour
            // plus meridiem notation.
            guard meridiem != nil || zoneToken != nil else { continue }

            let minute = Range(match.range(at: 2), in: normalized)
                .flatMap { Int(normalized[$0]) } ?? 0
            let sourceZone = timeZone(for: zoneToken)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = sourceZone
            let postedComponents = calendar.dateComponents([.year, .month, .day], from: postedAt)
            guard let postedDay = calendar.date(from: postedComponents) else { continue }

            let lower = normalized.lowercased()
            let dayOffset: Int
            if lower.contains("tomorrow") { dayOffset = 1 }
            else if lower.contains("today") || lower.contains("tonight") { dayOffset = 0 }
            else { dayOffset = 0 }
            guard let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: postedDay) else { continue }

            let possibleHours: [Int]
            if meridiem == nil, rawHour <= 12, zoneToken != nil {
                // “4:30 Central” is common in replies. Choose the next 4:30
                // on that named-zone day, which correctly resolves to PM when
                // the post was made during the afternoon.
                let morning = rawHour == 12 ? 0 : rawHour
                possibleHours = [morning, morning + 12]
            } else if let hour = normalizedHour(rawHour, meridiem: meridiem) {
                possibleHours = [min(23, hour)]
            } else {
                continue
            }

            let candidates = possibleHours.compactMap { hour -> Date? in
                var components = calendar.dateComponents([.year, .month, .day], from: targetDay)
                components.hour = hour
                components.minute = minute
                components.second = 0
                return calendar.date(from: components)
            }.sorted()
            if dayOffset > 0 { return candidates.first }
            if let upcoming = candidates.first(where: { $0 >= postedAt }) { return upcoming }
            if lower.contains("today") || lower.contains("tonight") { continue }
            if let first = candidates.first {
                return calendar.date(byAdding: .day, value: 1, to: first) ?? first
            }
        }
        return nil
    }

    private static func normalizedHour(_ rawHour: Int, meridiem: String?) -> Int? {
        guard (0...23).contains(rawHour) else { return nil }
        guard rawHour <= 12 else { return rawHour }
        switch meridiem {
        case "am": return rawHour == 12 ? 0 : rawHour
        case "pm": return rawHour == 12 ? 12 : rawHour + 12
        default: return rawHour
        }
    }

    private static func timeZone(for token: String?) -> TimeZone {
        let identifier: String
        switch token {
        case "MST", "MDT", "MT", "MOUNTAIN", "MOUNTAIN TIME": identifier = "America/Denver"
        case "CST", "CDT", "CT", "CENTRAL", "CENTRAL TIME": identifier = "America/Chicago"
        case "EST", "EDT", "ET", "EASTERN", "EASTERN TIME": identifier = "America/New_York"
        case "UTC", "GMT": identifier = "UTC"
        default: identifier = "America/Los_Angeles"
        }
        return TimeZone(identifier: identifier) ?? TimeZone(secondsFromGMT: 0)!
    }
}

struct ResetMetric: Identifiable, Sendable {
    let id: String
    let label: String
    let value: String
    let detail: String?
}

struct PolymarketResetForecast: Sendable, Equatable {
    struct Point: Sendable, Equatable, Identifiable {
        var id: Date { deadline }
        let marketLabel: String
        let deadline: Date
        let yesPrice: Double
        let noPrice: Double
        var usesLastTrade: Bool = false

        var axisLabel: String {
            let parts = marketLabel.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { return marketLabel }
            return "\(parts[0].prefix(3)) \(parts[1])"
        }
    }

    let points: [Point]
    let url: URL
}

struct ResetProviderSnapshot: Identifiable, Sendable {
    var id: ForecastSource { source }
    let source: ForecastSource
    let score: Double?
    let displayLabel: String?
    let headline: String?
    let range: ClosedRange<Double>?
    let lastBlessingAt: Date?
    let tweets: [TiboTweet]
    let metrics: [ResetMetric]
    let signals: [ResetMetric]
    let updatedAt: Date?
    /// A provider's probability window (for example “95% by 2 AM”). This is
    /// intentionally separate from an official reset announcement.
    let forecastDeadline: Date?
    let announcement: ResetAnnouncement?
    var polymarketForecast: PolymarketResetForecast? = nil
}

struct TiboTweet: Identifiable, Sendable {
    let id: String
    let date: Date?
    let text: String
    let inReplyTo: String?
    let url: URL?

    var isResetOriented: Bool {
        ResetTweetClassifier.isResetOriented(text: text, replyContext: inReplyTo)
    }

    /// Stable across providers. One site may call the same post a GUID while
    /// another returns the X status number or adds richer reply context.
    var alertIdentity: String {
        if let status = Self.xStatusID(in: url?.absoluteString ?? "")
            ?? Self.xStatusID(in: id) {
            return "x:\(status)"
        }
        let normalized = text.lowercased()
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "text:\(Self.fnv1a64(normalized))"
    }

    static func canonicalizeStoredIdentity(_ value: String) -> String {
        if value.hasPrefix("x:") || value.hasPrefix("text:") { return value }
        if let status = xStatusID(in: value) { return "x:\(status)" }
        return value
    }

    private static func xStatusID(in value: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?:/status/|^)([0-9]{12,})(?:\D|$)"#
        ), let match = expression.firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ), let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }

    private static func fnv1a64(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

enum TiboTweetFilter: String, CaseIterable, Identifiable {
    case reset
    case all

    static let defaultsKey = "QuotaGlance.tiboTweetFilter"
    var id: String { rawValue }
    var label: String { self == .reset ? "Reset" : "All" }
}

enum ResetTweetClassifier {
    static func isResetOriented(text: String, replyContext: String?) -> Bool {
        let combined = [text, replyContext]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        // Include both explicit reset language and the phrases commonly used
        // in replies around quota restoration. Checking the parent/reply text
        // keeps short answers such as “soon” or “yes” in the right thread.
        let directPattern = #"\b(reset(?:s|ting)?|quota|rate[ -]?limit|usage limit|token limit|weekly limit|replenish(?:ed|ment)?|restore(?:d|ation)?|refresh(?:ed)?|bless(?:ed|ing)?|banked|reset button|circle back)\b"#
        if combined.range(of: directPattern, options: [.regularExpression]) != nil {
            return true
        }

        let codexPattern = #"\b(codex|chatgpt)\b[\s\S]{0,80}\b(limit|tokens?|usage|compute|capacity|credits?|allowance|window)\b|\b(limit|tokens?|usage|compute|capacity|credits?|allowance|window)\b[\s\S]{0,80}\b(codex|chatgpt)\b"#
        return combined.range(of: codexPattern, options: [.regularExpression]) != nil
    }
}

struct ResetIntelSnapshot: Sendable {
    let lastBlessingAt: Date?
    let tweets: [TiboTweet]

    /// A plain-language capsule shown inside the reset-signal dial.
    var compactLabel: String? {
        guard let lastBlessingAt else { return nil }
        return "🙏🏻 \(Self.shortAge(lastBlessingAt))"
    }

    private static func shortAge(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "<1M AGO" }
        if seconds < 3_600 { return "\(Int(seconds / 60))M AGO" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))H AGO" }
        if seconds < 604_800 { return "\(Int(seconds / 86_400))D AGO" }
        return "\(Int(seconds / 604_800))W AGO"
    }
}

struct CodexResetsWatchSignal: Sendable {
    let score: Double
    let displayLabel: String?
    let expectedAt: Date?
    let yesVotes: Int?
    let noVotes: Int?
    let tweets: [TiboTweet]
}

enum ForecastService {
    static func fetch() async throws -> ForecastSnapshot {
        let selected = ForecastSourceSelection.load()

        async let lunar = optionalProvider(.lunarWerx)
        async let current = optionalProvider(.codexResets)
        async let original = optionalProvider(.willCodexQuotaReset)
        async let fallback = optionalProvider(.gussuri)
        async let market = optionalProvider(.polymarket)
        let providers = await [lunar, current, original, fallback, market].compactMap { $0 }
        return try snapshot(from: providers, selected: selected)
    }

    static func snapshot(
        from providers: [ResetProviderSnapshot],
        selected: Set<ForecastSource>
    ) throws -> ForecastSnapshot {
        guard !providers.isEmpty, !selected.isEmpty else { throw DashboardError.forecastUnavailable }
        let selectedProviders = providers.filter { selected.contains($0.source) }
        // Selection is authoritative: every checked provider with a live
        // percentage contributes equally to the combined score.
        let scored = selectedProviders.filter { $0.score != nil }
        let singleSource = selected.count == 1 ? selected.first : nil
        let chosen = singleSource.flatMap { source in providers.first { $0.source == source } }
        let values = scored.compactMap(\.score)
        let estimatedScore = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let ranges = scored.compactMap(\.range)
        let lowerAverage = ranges.map(\.lowerBound).reduce(0, +) / Double(max(1, ranges.count))
        let upperAverage = ranges.map(\.upperBound).reduce(0, +) / Double(max(1, ranges.count))
        let combinedRange: ClosedRange<Double>? = ranges.isEmpty ? nil : lowerAverage...upperAverage

        let tweets = aggregateTweets(from: providers)
        let lastBlessing = providers.compactMap(\.lastBlessingAt).max()
        let providerAnnouncement = providers
            .compactMap(\.announcement)
            .filter { $0.isActive() }
            .max { $0.detectedAt < $1.detectedAt }
        let announcementSchedules = providers.compactMap { provider -> ResetSchedule? in
            guard let item = provider.announcement,
                  let expectedAt = ResetAnnouncementTimeParser.expectedDate(
                    in: item.text,
                    postedAt: item.detectedAt
                  ) else { return nil }
            return ResetSchedule(
                id: item.id,
                source: item.source,
                announcedAt: item.detectedAt,
                expectedAt: expectedAt,
                text: item.text,
                url: item.url
            )
        }
        // A dated forecast only describes the selected source's own score.
        // Never attach one provider's horizon to a multi-source average.
        let forecastSchedules = (selected.count == 1 ? selectedProviders : []).compactMap { provider -> ResetSchedule? in
            guard let expectedAt = provider.forecastDeadline, expectedAt > Date() else { return nil }
            return ResetSchedule(
                id: "forecast:\(provider.source.rawValue):\(expectedAt.timeIntervalSince1970)",
                source: provider.source,
                announcedAt: provider.updatedAt ?? Date(),
                expectedAt: expectedAt,
                text: provider.headline ?? "Reset forecast window",
                url: provider.source.url
            )
        }
        let textSchedules = tweets.compactMap { tweet -> ResetSchedule? in
            guard
                tweet.isResetOriented,
                let announcedAt = tweet.date,
                let expectedAt = ResetAnnouncementTimeParser.expectedDate(in: tweet.text, postedAt: announcedAt)
            else { return nil }
            return ResetSchedule(
                id: tweet.alertIdentity,
                source: providers.first(where: { $0.tweets.contains(where: { $0.alertIdentity == tweet.alertIdentity }) })?.source ?? .lunarWerx,
                announcedAt: announcedAt,
                expectedAt: expectedAt,
                text: tweet.text,
                url: tweet.url
            )
        }
        let explicitScheduledReset = (announcementSchedules + textSchedules)
            .filter { $0.expectedAt > Date().addingTimeInterval(-12 * 3_600) }
            // The newest explicit statement supersedes an earlier announced
            // time. Choosing the earliest clock time could resurrect an old
            // missed schedule after Tibo posted a correction in a reply.
            .max { $0.announcedAt < $1.announcedAt }
        let scheduledReset = explicitScheduledReset ?? forecastSchedules
            .filter { $0.expectedAt > Date() }
            .min { $0.expectedAt < $1.expectedAt }
        let announcement: ResetAnnouncement? = {
            if let explicitScheduledReset {
                return ResetAnnouncement(
                    id: "scheduled:\(explicitScheduledReset.id)",
                    source: explicitScheduledReset.source,
                    detectedAt: explicitScheduledReset.announcedAt,
                    expectedAt: explicitScheduledReset.expectedAt,
                    text: explicitScheduledReset.text,
                    url: explicitScheduledReset.url
                )
            }
            guard let providerAnnouncement else { return nil }
            // An announcement without a wall-clock time can still raise the
            // reset score, but it must never create a countdown or delayed
            // state.
            return ResetAnnouncement(
                id: providerAnnouncement.id,
                source: providerAnnouncement.source,
                detectedAt: providerAnnouncement.detectedAt,
                expectedAt: nil,
                text: providerAnnouncement.text,
                url: providerAnnouncement.url
            )
        }()
        let score = announcement == nil ? estimatedScore : 100
        let headline: String?
        if let scheduledReset, announcement != nil {
            headline = "Reset expected \(scheduledReset.expectedAt.formatted(date: .abbreviated, time: .shortened))"
        } else if let scheduledReset {
            headline = "\(Int(estimatedScore.rounded()))% chance by \(scheduledReset.expectedAt.formatted(date: .abbreviated, time: .shortened))"
        } else if announcement != nil {
            headline = "Reset announced · use your quota now"
        } else if selected.count > 1 {
            headline = "Averaging \(selected.count) selected reset estimates"
        } else if let singleSource, chosen?.score == nil {
            headline = "\(singleSource.displayName) has no live percentage"
        } else {
            headline = chosen?.headline
        }
        let source = singleSource ?? .average
        return ForecastSnapshot(
            score: score,
            baselineScore: estimatedScore,
            displayLabel: announcement == nil && singleSource != nil ? chosen?.displayLabel : nil,
            source: source,
            selectedSources: selected,
            announcement: announcement,
            scheduledReset: scheduledReset,
            intel: ResetIntelSnapshot(lastBlessingAt: lastBlessing, tweets: tweets),
            providers: providers,
            headline: headline,
            range: combinedRange
        )
    }

    static func snapshot(
        from providers: [ResetProviderSnapshot],
        selected: ForecastSource
    ) throws -> ForecastSnapshot {
        try snapshot(
            from: providers,
            selected: selected == .average ? Set(ForecastSource.calculatorCases) : [selected]
        )
    }

    private static func optionalProvider(_ source: ForecastSource) async -> ResetProviderSnapshot? {
        do {
            switch source {
            case .lunarWerx: return try await fetchLunarWerx()
            case .codexResets: return try await fetchCodexResets()
            case .willCodexQuotaReset: return try await fetchWillCodexQuotaReset()
            case .gussuri: return try await fetchGussuri()
            case .polymarket: return try await fetchPolymarket()
            case .average: return nil
            }
        } catch {
            NSLog("Quota Glance reset source %@ failed: %@", source.hostLabel, error.localizedDescription)
            return nil
        }
    }

    static func polymarketProvider(from data: Data, now: Date = Date()) throws -> ResetProviderSnapshot {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let markets = root["markets"] as? [[String: Any]]
        else { throw DashboardError.forecastUnavailable }
        let eventURL = (root["slug"] as? String).flatMap {
            URL(string: "https://polymarket.com/event/" + $0)
        } ?? ForecastSource.polymarket.url!

        let candidates = markets.compactMap { market -> (label: String, deadline: Date, yes: Double, no: Double, lastTrade: Bool)? in
            guard
                (market["active"] as? Bool) != false,
                (market["closed"] as? Bool) != true,
                let deadlineText = market["endDate"] as? String,
                let deadline = parseISODate(deadlineText),
                deadline > now,
                let outcomesText = market["outcomes"] as? String,
                let pricesText = market["outcomePrices"] as? String,
                let outcomesData = outcomesText.data(using: .utf8),
                let pricesData = pricesText.data(using: .utf8),
                let outcomes = try? JSONDecoder().decode([String].self, from: outcomesData),
                let prices = try? JSONDecoder().decode([String].self, from: pricesData),
                let yesIndex = outcomes.firstIndex(where: { $0.caseInsensitiveCompare("yes") == .orderedSame }),
                let noIndex = outcomes.firstIndex(where: { $0.caseInsensitiveCompare("no") == .orderedSame }),
                prices.indices.contains(yesIndex), prices.indices.contains(noIndex),
                let yes = Double(prices[yesIndex]), let no = Double(prices[noIndex]),
                yes.isFinite, no.isFinite, (0...1).contains(yes), (0...1).contains(no)
            else { return nil }
            let label = (market["groupItemTitle"] as? String)
                ?? deadline.formatted(date: .abbreviated, time: .omitted)
            let bid = market["bestBid"] as? Double
            let ask = market["bestAsk"] as? Double
            let spread = bid.flatMap { bid in ask.map { $0 - bid } }
                ?? (market["spread"] as? Double)
            // Match Polymarket's display: wide books use the last trade, not midpoint.
            if let spread, spread > 0.10 + 0.0000001 {
                guard let last = market["lastTradePrice"] as? Double,
                      last.isFinite, (0...1).contains(last) else { return nil }
                return (label, deadline, last, 1 - last, true)
            }
            if let bid, let ask, bid.isFinite, ask.isFinite,
               (0...1).contains(bid), (0...1).contains(ask), ask >= bid {
                let midpoint = (bid + ask) / 2
                return (label, deadline, midpoint, 1 - midpoint, false)
            }
            return (label, deadline, yes, no, false)
        }
        guard let earliest = candidates.min(by: { $0.deadline < $1.deadline }) else {
            throw DashboardError.forecastUnavailable
        }

        let forecast = PolymarketResetForecast(
            points: candidates.sorted { $0.deadline < $1.deadline }.map {
                .init(marketLabel: $0.label, deadline: $0.deadline, yesPrice: $0.yes, noPrice: $0.no, usesLastTrade: $0.lastTrade)
            },
            url: eventURL
        )
        let score = earliest.yes * 100
        return ResetProviderSnapshot(
            source: .polymarket,
            score: score,
            displayLabel: "\(Int(score.rounded()))% · \(earliest.label.uppercased())",
            headline: "Market odds of a reset by \(earliest.label)",
            range: nil,
            lastBlessingAt: nil,
            tweets: [],
            metrics: [
                ResetMetric(id: "polymarket-yes", label: "Reset by \(earliest.label)", value: percent(score), detail: earliest.lastTrade ? "Last trade (wide bid–ask gap)" : "Bid–ask midpoint"),
                ResetMetric(id: "polymarket-no", label: "No reset", value: percent(earliest.no * 100), detail: "Market odds of no reset by this date")
            ],
            signals: [],
            updatedAt: (root["updatedAt"] as? String).flatMap(parseISODate) ?? now,
            forecastDeadline: earliest.deadline,
            announcement: nil,
            polymarketForecast: forecast
        )
    }

    static func polymarketSearchProvider(from data: Data, now: Date = Date()) throws -> ResetProviderSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { throw DashboardError.forecastUnavailable }
        let candidates = events.filter {
            ($0["slug"] as? String)?.hasPrefix("openai-resets-codex-weekly-usage-limit-by") == true
                && ($0["closed"] as? Bool) != true
                && ($0["active"] as? Bool) != false
        }.sorted { ($0["startDate"] as? String ?? "") > ($1["startDate"] as? String ?? "") }
        for event in candidates {
            let payload = try JSONSerialization.data(withJSONObject: event)
            if let provider = try? polymarketProvider(from: payload, now: now) { return provider }
        }
        throw DashboardError.forecastUnavailable
    }

    private static func fetchPolymarket() async throws -> ResetProviderSnapshot {
        let endpoint = URL(string: "https://gamma-api.polymarket.com/public-search?q=OpenAI%20resets%20Codex&limit_per_type=20")!
        let provider = try polymarketSearchProvider(from: await fetchData(endpoint))
        if let url = provider.polymarketForecast?.url {
            UserDefaults.standard.set(url.absoluteString, forKey: "QuotaGlance.polymarketEventURL")
        }
        return provider
    }

    private static func fetchCodexResets() async throws -> ResetProviderSnapshot {
        guard let url = ForecastSource.codexResets.url else { throw DashboardError.forecastUnavailable }
        var request = URLRequest(url: url)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("Quota Glance/1.0", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw DashboardError.forecastUnavailable
        }
        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            let html = String(data: data, encoding: .utf8)
        else {
            throw DashboardError.forecastUnavailable
        }

        let watch = codexResetsWatchSignal(in: html)
        let intel = ResetIntelSnapshot(
            lastBlessingAt: lastBlessingDate(in: html),
            tweets: tiboTweets(in: html)
        )

        var metrics: [ResetMetric] = []
        if let expectedAt = watch?.expectedAt {
            metrics.append(ResetMetric(
                id: "codex-resets-window",
                label: "Forecast window",
                value: shortLocalDateTime(expectedAt),
                detail: TimeZone.autoupdatingCurrent.abbreviation(for: expectedAt)
            ))
        }
        if let yesVotes = watch?.yesVotes, let noVotes = watch?.noVotes {
            let total = max(1, yesVotes + noVotes)
            metrics.append(ResetMetric(
                id: "codex-resets-community",
                label: "Community bet",
                value: "\(Int((Double(yesVotes) / Double(total) * 100).rounded()))% yes",
                detail: "\(total.formatted()) votes"
            ))
        }

        return ResetProviderSnapshot(
            source: .codexResets,
            score: watch?.score ?? parseChance(in: html)?.score,
            displayLabel: watch?.displayLabel ?? parseChance(in: html)?.displayLabel,
            headline: watch?.expectedAt.map { "Reset watch ends \($0.formatted(date: .abbreviated, time: .shortened))" }
                ?? "Confirmed reset history",
            range: nil,
            lastBlessingAt: intel.lastBlessingAt,
            tweets: intel.tweets,
            metrics: metrics,
            signals: [],
            updatedAt: Date(),
            forecastDeadline: watch?.expectedAt,
            announcement: codexResetsAnnouncement(in: html, tweets: intel.tweets),
            polymarketForecast: nil
        )
    }

    private static func fetchWillCodexQuotaReset() async throws -> ResetProviderSnapshot {
        let data = try await fetchData(URL(string: "https://www.willcodexquotareset.com/api/forecast")!)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let forecast = root["forecast"] as? [String: Any],
            let score = (forecast["score"] as? NSNumber)?.doubleValue
        else { throw DashboardError.forecastUnavailable }

        let tweets = ((root["tiboPosts"] as? [[String: Any]]) ?? []).compactMap { post -> TiboTweet? in
            guard
                let id = post["guid"] as? String,
                let text = post["title"] as? String
            else { return nil }
            return TiboTweet(
                id: id,
                date: (post["pubDate"] as? String).flatMap(parseISODate),
                text: text,
                inReplyTo: (post["context"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                url: (post["link"] as? String).flatMap(URL.init(string:))
            )
        }

        let breakdown = ((forecast["breakdown"] as? [[String: Any]]) ?? []).prefix(4).compactMap { item -> ResetMetric? in
            guard let label = item["label"] as? String, let points = item["points"] as? NSNumber else { return nil }
            return ResetMetric(id: "will-\(label)", label: label.capitalized, value: "+\(points.intValue)", detail: nil)
        }
        let lastReset = (forecast["latestResetAt"] as? String).flatMap(parseISODate)
        let announcement = announcementFromTweets(
            tweets,
            source: .willCodexQuotaReset,
            explicitlyAnnounced: (forecast["resetAnnounced"] as? Bool) == true
        )
        return ResetProviderSnapshot(
            source: .willCodexQuotaReset,
            score: score,
            displayLabel: nil,
            headline: forecastHeadline(for: score),
            range: nil,
            lastBlessingAt: lastReset,
            tweets: recentTweets(tweets),
            metrics: Array(breakdown),
            signals: [],
            updatedAt: (root["fetchedAt"] as? String).flatMap(parseISODate),
            forecastDeadline: nil,
            announcement: announcement,
            polymarketForecast: nil
        )
    }

    private static func fetchLunarWerx() async throws -> ResetProviderSnapshot {
        let endpoint = URL(string: "https://codex.lunarwerx.com/cnx/aireset/summary/t/5957183")!
        let data = try await fetchData(endpoint)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let chance = (root["chanceToday"] as? NSNumber)?.doubleValue
        else { throw DashboardError.forecastUnavailable }

        let score = chance * 100
        let low = (root["chanceLow"] as? NSNumber).map { $0.doubleValue * 100 }
        let high = (root["chanceHigh"] as? NSNumber).map { $0.doubleValue * 100 }
        let stats = root["stats"] as? [String: Any]
        let cadence = root["cadence"] as? [String: Any]
        var metrics: [ResetMetric] = []
        if let soon = (root["chanceSoon"] as? NSNumber)?.doubleValue,
           let hours = (root["soonWindowHours"] as? NSNumber)?.intValue {
            metrics.append(ResetMetric(id: "lunar-soon", label: "Next \(hours)h", value: percent(soon * 100), detail: nil))
        }
        if let elapsed = (cadence?["elapsedDays"] as? NSNumber)?.doubleValue {
            metrics.append(ResetMetric(id: "lunar-wait", label: "Since reset", value: days(elapsed), detail: nil))
        }
        if let pace = (stats?["pace30Days"] as? NSNumber)?.doubleValue {
            metrics.append(ResetMetric(id: "lunar-pace", label: "30d average", value: days(pace), detail: nil))
        }
        if let percentile = (cadence?["percentile"] as? NSNumber)?.doubleValue {
            metrics.append(ResetMetric(id: "lunar-percentile", label: "Wait percentile", value: percent(percentile * 100), detail: "Share of recent waits that ended sooner"))
        }

        let signalMetrics = ((root["signals"] as? [[String: Any]]) ?? []).compactMap { signal -> ResetMetric? in
            guard
                let id = signal["id"] as? String,
                let label = signal["label"] as? String,
                let state = signal["state"] as? String,
                state != "clear"
            else { return nil }
            return ResetMetric(
                id: "lunar-signal-\(id)",
                label: label,
                value: state == "firing" ? "ACTIVE" : "QUIET",
                detail: signal["detail"] as? String
            )
        }

        let tibo = root["tibo"] as? [String: Any]
        let rawTweets = (((tibo?["tweets"] as? [[String: Any]]) ?? []) + ((tibo?["more"] as? [[String: Any]]) ?? []))
        let tweets = rawTweets.compactMap { post -> TiboTweet? in
            guard let id = post["id"] as? String, let text = post["text"] as? String else { return nil }
            return TiboTweet(
                id: id,
                date: (post["at"] as? String).flatMap(parseISODate),
                text: text,
                inReplyTo: (post["replyContext"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                url: (post["url"] as? String).flatMap(URL.init(string:))
            )
        }
        let pendingPost = rawTweets
            .filter { ($0["pendingReset"] as? Bool) == true }
            .max {
                let lhs = ($0["at"] as? String).flatMap(parseISODate) ?? .distantPast
                let rhs = ($1["at"] as? String).flatMap(parseISODate) ?? .distantPast
                return lhs < rhs
            }
        let announcement = pendingPost.flatMap { post -> ResetAnnouncement? in
            guard
                let id = post["id"] as? String,
                let text = post["text"] as? String,
                let detectedAt = (post["at"] as? String).flatMap(parseISODate)
            else { return nil }
            return ResetAnnouncement(
                id: "lunar:\(id)",
                source: .lunarWerx,
                detectedAt: detectedAt,
                expectedAt: nil,
                text: text,
                url: (post["url"] as? String).flatMap(URL.init(string:))
            )
        }

        return ResetProviderSnapshot(
            source: .lunarWerx,
            score: score,
            displayLabel: nil,
            headline: root["headline"] as? String,
            range: low.flatMap { lower in high.map { lower...$0 } },
            lastBlessingAt: (root["lastReset"] as? String).flatMap(parseISODate),
            tweets: recentTweets(tweets),
            metrics: metrics,
            signals: signalMetrics,
            updatedAt: (root["generatedAt"] as? String).flatMap(parseISODate),
            forecastDeadline: nil,
            announcement: announcement,
            polymarketForecast: nil
        )
    }

    private static func fetchGussuri() async throws -> ResetProviderSnapshot {
        guard let url = ForecastSource.gussuri.url else { throw DashboardError.forecastUnavailable }
        let data = try await fetchData(url)
        guard let html = String(data: data, encoding: .utf8) else { throw DashboardError.forecastUnavailable }
        let normalized = html
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\n", with: "\n")
        guard
            let probability = firstCapture(#"probability24h":\s*([0-9.]+)"#, in: normalized).flatMap(Double.init)
        else { throw DashboardError.forecastUnavailable }

        let probability12 = firstCapture(#"probability12h":\s*([0-9.]+)"#, in: normalized).flatMap(Double.init)
        let probability48 = firstCapture(#"probability48h":\s*([0-9.]+)"#, in: normalized).flatMap(Double.init)
        let probability72 = firstCapture(#"probability72h":\s*([0-9.]+)"#, in: normalized).flatMap(Double.init)
        var metrics: [ResetMetric] = []
        if let probability12 { metrics.append(ResetMetric(id: "gussuri-12", label: "12 hours", value: percent(probability12 * 100), detail: nil)) }
        metrics.append(ResetMetric(id: "gussuri-24", label: "24 hours", value: percent(probability * 100), detail: nil))
        if let probability48 { metrics.append(ResetMetric(id: "gussuri-48", label: "48 hours", value: percent(probability48 * 100), detail: nil)) }
        if let probability72 { metrics.append(ResetMetric(id: "gussuri-72", label: "72 hours", value: percent(probability72 * 100), detail: nil)) }

        var tweets: [TiboTweet] = []
        if let activity = firstCapture(#"strongestTiboActivity":\{([\s\S]*?)\},"recoveryObservation""#, in: normalized),
           let text = firstCapture(#"text":"([\s\S]*?)","createdAt""#, in: activity),
           let urlText = firstCapture(#"sourceUrl":"([^"]+)""#, in: activity) {
            let reply = firstCapture(#"replyContextText":(?:null|"([\s\S]*?)")"#, in: activity)
            tweets.append(TiboTweet(
                id: xStatusID(from: urlText) ?? urlText,
                date: firstCapture(#"createdAt":"([^"]+)""#, in: activity).flatMap(parseISODate),
                text: decodeHTMLEntities(text),
                inReplyTo: reply.flatMap { $0.isEmpty ? nil : decodeHTMLEntities($0) },
                url: URL(string: urlText)
            ))
        }

        let headline = firstCapture(#"displayReasoningSummary":"([^"]+)""#, in: normalized)
            ?? firstCapture(#"expectation":"([^"]+)""#, in: normalized).map { "Reset likelihood: \($0)" }
        let lastReset = firstCapture(#"latestWindow":\{[\s\S]*?"closedAt":"([^"]+)""#, in: normalized).flatMap(parseISODate)
        let announcement = gussuriAnnouncement(in: normalized)
        return ResetProviderSnapshot(
            source: .gussuri,
            score: probability * 100,
            displayLabel: nil,
            headline: headline,
            range: nil,
            lastBlessingAt: lastReset,
            tweets: recentTweets(tweets),
            metrics: metrics,
            signals: [],
            updatedAt: firstCapture(#"checkedAt":"([^"]+)""#, in: normalized).flatMap(parseISODate),
            forecastDeadline: nil,
            announcement: announcement,
            polymarketForecast: nil
        )
    }

    static func isExplicitResetAnnouncement(_ text: String) -> Bool {
        // Topic matches and provider flags alone are not an announcement.
        let value = text.lowercased()
        if value.range(of: #"\b(no|not|won't|wont|never|if|maybe|might|could)\b"#, options: .regularExpression) != nil { return false }
        return value.range(of: #"\b(we(?:'re| are| will|'ll)\s+(?:doing |issuing |granting |giving |a |another |full |weekly )*reset(?:ting)?|(?:usage limits|quotas?|limits)\s+(?:have been|will be|are being)\s+reset|reset(?:s)?\s+(?:is coming|is incoming|is live|at \d|in \d|today|tonight|tomorrow))\b"#, options: .regularExpression) != nil
    }

    static func announcementFromTweets(
        _ tweets: [TiboTweet],
        source: ForecastSource,
        explicitlyAnnounced: Bool
    ) -> ResetAnnouncement? {
        guard explicitlyAnnounced else { return nil }
        let tweet = tweets
            .filter(\.isResetOriented)
            .filter { source != .willCodexQuotaReset || isExplicitResetAnnouncement($0.text) }
            .max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        guard let tweet, let detectedAt = tweet.date else { return nil }
        return ResetAnnouncement(
            id: "\(source.rawValue):\(tweet.alertIdentity)",
            source: source,
            detectedAt: detectedAt,
            expectedAt: nil,
            text: tweet.text,
            url: tweet.url
        )
    }

    private static func codexResetsAnnouncement(in html: String, tweets: [TiboTweet]) -> ResetAnnouncement? {
        guard
            let watch = firstCapture(
                #"(<section\s+class="[^"]*\bwatch-card\b[^"]*"[\s\S]*?</section>)"#,
                in: html
            )
        else { return nil }
        let watchText = plainText(from: watch).lowercased()
        let explicitlyAnnounced = watchText.contains("reset announced")
            || watchText.contains("confirmed reset")
            || watch.contains("watch-card--announced")
            || watch.contains("watch-card--confirmed")
        return announcementFromTweets(
            tweets,
            source: .codexResets,
            explicitlyAnnounced: explicitlyAnnounced
        )
    }

    private static func gussuriAnnouncement(in normalizedHTML: String) -> ResetAnnouncement? {
        guard
            let activeWindow = firstCapture(
                #""activeWindow":\{([\s\S]*?)\},"displayReasoningSummary""#,
                in: normalizedHTML
            ),
            activeWindow.range(of: #""active":true"#, options: .regularExpression) != nil,
            firstCapture(#""kind":"([^"]+)""#, in: activeWindow)?.lowercased() == "official",
            let detectedAt = firstCapture(#""openedAt":"([^"]+)""#, in: activeWindow).flatMap(parseISODate)
        else { return nil }

        let sourceURL = firstCapture(#""source":"([^"]+)""#, in: activeWindow)
            .flatMap(URL.init(string:))
        let expectedAt = firstCapture(#""expectedAt":"([^"]+)""#, in: activeWindow)
            .flatMap(parseISODate)
        let summary = firstCapture(#""summary":"([^"]+)""#, in: activeWindow)
            .map(decodeHTMLEntities(_:))
            ?? "An official Codex reset was announced."
        return ResetAnnouncement(
            id: "gussuri:\(sourceURL?.absoluteString ?? detectedAt.ISO8601Format())",
            source: .gussuri,
            detectedAt: detectedAt,
            expectedAt: expectedAt,
            text: summary,
            url: sourceURL
        )
    }

    private static func fetchData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json, text/html;q=0.9", forHTTPHeaderField: "Accept")
        request.setValue("Quota Glance/1.0", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DashboardError.forecastUnavailable
        }
        return data
    }

    private static func aggregateTweets(from providers: [ResetProviderSnapshot]) -> [TiboTweet] {
        var unique: [String: TiboTweet] = [:]
        for tweet in recentTweets(providers.flatMap(\.tweets)) {
            let key = tweet.alertIdentity
            if let existing = unique[key] {
                // When two sites found the same post, retain the copy with
                // reply context so Reset mode can understand terse replies.
                let existingContext = existing.inReplyTo?.count ?? 0
                let candidateContext = tweet.inReplyTo?.count ?? 0
                if candidateContext > existingContext {
                    unique[key] = tweet
                }
            } else {
                unique[key] = tweet
            }
        }
        return unique.values.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private static func recentTweets(_ tweets: [TiboTweet]) -> [TiboTweet] {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        return tweets.filter { ($0.date ?? .distantPast) >= cutoff }
    }

    private static func xStatusID(from value: String) -> String? {
        firstCapture(#"/status/([0-9]+)"#, in: value)
    }


    private static func forecastHeadline(for score: Double) -> String {
        if score >= 70 { return "Reset signals are strong" }
        if score >= 45 { return "A reset is plausible" }
        if score >= 25 { return "A few signals are active" }
        return "Reset signals are quiet"
    }

    private static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private static func days(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "d"
    }

    private static func shortLocalDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "MMM d · h:mm a"
        return formatter.string(from: date)
    }

    static func codexResetsWatchSignal(in html: String) -> CodexResetsWatchSignal? {
        guard let watch = firstCapture(
            #"(<section\s+class="[^"]*\bwatch-card\b[^"]*"[\s\S]*?</section>)"#,
            in: html
        ) else { return nil }

        let chance = firstAttribute("aria-label", in: watch).flatMap(parseProbability)
            ?? firstCapture(#"data-role="watch-chance"[^>]*>([^<]+)<"#, in: watch).flatMap(parseProbability)
            ?? parseChance(in: watch)
        guard let chance else { return nil }

        let expectedAt = firstAttribute("data-expires-at", in: watch).flatMap(parseISODate)
            ?? firstCapture(#"data-role="absolute-time"[^>]*data-datetime="([^"]+)""#, in: watch).flatMap(parseISODate)
        let yesVotes = firstAttribute("data-yes", in: watch).flatMap(Int.init)
        let noVotes = firstAttribute("data-no", in: watch).flatMap(Int.init)
        return CodexResetsWatchSignal(
            score: chance.score,
            displayLabel: chance.displayLabel,
            expectedAt: expectedAt,
            yesVotes: yesVotes,
            noVotes: noVotes,
            tweets: codexResetsWatchTweets(in: watch)
        )
    }

    static func parseChance(in html: String) -> (score: Double, displayLabel: String?)? {
        // The current site presents the signal in its reset-watch/Tibo banner.
        // Prefer the accessible label because it survives small markup changes
        // such as “Reset chance” replacing “24h reset chance”.
        if let watch = firstCapture(
            #"(<section\s+class="[^"]*\bwatch-card\b[^"]*"[\s\S]*?</section>)"#,
            in: html
        ) {
            if let ariaLabel = firstAttribute("aria-label", in: watch),
               let parsed = parseProbability(ariaLabel) {
                return parsed
            }
            if let ariaLabel = firstCapture(
                #"<p\s+class="[^"]*\bwatch-probability\b[^"]*"[^>]*aria-label="([^"]+)""#,
                in: watch
            ),
            let parsed = parseProbability(ariaLabel) {
                return parsed
            }

            if let probabilityHTML = firstCapture(
                #"<p\s+class="[^"]*\bwatch-probability\b[^"]*"[^>]*>([\s\S]*?)</p>"#,
                in: watch
            ),
            let parsed = parseProbability(plainText(from: probabilityHTML)) {
                return parsed
            }
        }

        let text = plainText(from: html)
        for heading in ["24h reset chance", "Reset chance"] {
            guard let label = text.range(of: heading, options: .caseInsensitive) else { continue }
            // The probability appears immediately before the heading in the
            // server-rendered banner, so inspect a small window on both sides.
            let nearbyStart = text.index(label.lowerBound, offsetBy: -180, limitedBy: text.startIndex) ?? text.startIndex
            let nearby = String(text[nearbyStart...].prefix(360))
            if let parsed = parseProbability(nearby) {
                return parsed
            }
        }
        return nil
    }

    private static func parseProbability(_ value: String) -> (score: Double, displayLabel: String?)? {
        guard
            let expression = try? NSRegularExpression(
                pattern: #"([><]?)\s*([0-9]+(?:\.[0-9]+)?)\s*(%|percent)"#,
                options: [.caseInsensitive]
            ),
            let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
            ),
            let scoreRange = Range(match.range(at: 2), in: value),
            let score = Double(value[scoreRange]),
            (0...100).contains(score)
        else { return nil }

        let operatorRange = Range(match.range(at: 1), in: value)
        let explicitLowerBound = operatorRange.map { value[$0] == ">" } ?? false
        let normalized = value.lowercased()
        let ariaLowerBound = normalized.contains("greater than") || normalized.contains("more than")
        let displayLabel = explicitLowerBound || ariaLowerBound
            ? ">\(score.formatted(.number.precision(.fractionLength(0...2))))%"
            : nil
        return (score, displayLabel)
    }

    private static func lastBlessingDate(in html: String) -> Date? {
        guard let expression = try? NSRegularExpression(
            pattern: #"class="hero-figure"[^>]*data-datetime="([^"]+)""#,
            options: [.caseInsensitive]
        ),
        let match = expression.firstMatch(
            in: html,
            range: NSRange(html.startIndex..., in: html)
        ),
        let dateRange = Range(match.range(at: 1), in: html) else { return nil }

        let value = String(html[dateRange])
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func tiboTweets(in html: String) -> [TiboTweet] {
        let now = Date()
        let cutoff = now.addingTimeInterval(-7 * 86_400)
        var parsed: [TiboTweet] = []

        // The newest signal is promoted into the site's reset-watch card. It
        // is not always repeated in the announcement list, so parse that card
        // separately to avoid dropping the most recent Tibo post or its reply
        // context.
        if let watch = firstCapture(
            #"(<section\s+class="[^"]*\bwatch-card\b[^"]*"[\s\S]*?</section>)"#,
            in: html
        ) {
            parsed.append(contentsOf: codexResetsWatchTweets(in: watch))
        }

        let pattern = #"<li\s+class="[^"]*\blog-item\b[^"]*"[\s\S]*?data-datetime="([^"]+)"[\s\S]*?<p\s+class="[^"]*\blog-item-text\b[^"]*"[^>]*>([\s\S]*?)</p>[\s\S]*?<a\s+class="[^"]*\blog-item-link\b[^"]*"[^>]*href="([^"]+)""#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return parsed }

        let matches = expression.matches(
            in: html,
            range: NSRange(html.startIndex..., in: html)
        )
        parsed.append(contentsOf: matches.compactMap { match in
            guard
                let dateRange = Range(match.range(at: 1), in: html),
                let textRange = Range(match.range(at: 2), in: html),
                let urlRange = Range(match.range(at: 3), in: html)
            else { return nil }

            let dateText = String(html[dateRange])
            let date = parseISODate(dateText)
            let text = plainText(from: String(html[textRange]))
            guard !text.isEmpty else { return nil }
            let urlText = String(html[urlRange])
            return TiboTweet(
                id: urlText,
                date: date,
                text: text,
                inReplyTo: nil,
                url: URL(string: urlText)
            )
        })

        // Keep the feed glanceable and useful: only retain dated posts from
        // the last seven days, sort newest first, and de-duplicate the watch
        // card when the same post also appears in the log.
        var seen = Set<String>()
        return parsed
            .filter { tweet in
                guard let date = tweet.date else { return false }
                return date >= cutoff && date <= now.addingTimeInterval(5 * 60)
            }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .filter { seen.insert($0.id).inserted }
    }

    private static func codexResetsWatchTweets(in watch: String) -> [TiboTweet] {
        guard let expression = try? NSRegularExpression(
            pattern: #"<a\s+class="[^"]*\bwatch-tweet\b[^"]*"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }

        return expression.matches(in: watch, range: NSRange(watch.startIndex..., in: watch)).compactMap { match in
            guard
                let urlRange = Range(match.range(at: 1), in: watch),
                let bodyRange = Range(match.range(at: 2), in: watch)
            else { return nil }
            let body = String(watch[bodyRange])
            guard
                let textHTML = firstCapture(#"<span\s+class="[^"]*\bwatch-tweet-text\b[^"]*"[^>]*>([\s\S]*?)</span>"#, in: body)
            else { return nil }
            let text = plainText(from: textHTML)
            guard !text.isEmpty else { return nil }
            let urlText = decodeHTMLEntities(String(watch[urlRange]))
            let context = firstCapture(
                #"<span\s+class="[^"]*\bwatch-tweet-context\b[^"]*"[^>]*>([\s\S]*?)</span>"#,
                in: body
            )
            .map(plainText(from:))
            .flatMap(cleanReplyContext(_:))
            return TiboTweet(
                id: urlText,
                date: firstAttribute("data-datetime", in: body).flatMap(parseISODate),
                text: text,
                inReplyTo: context,
                url: URL(string: urlText)
            )
        }
    }

    private static func cleanReplyContext(_ value: String) -> String? {
        let cleaned = value.replacingOccurrences(
            of: #"^\s*(?:in\s+reply\s+to|replying\s+to)\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\"“”"))
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func parseISODate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func firstCapture(_ pattern: String, in value: String) -> String? {
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ),
            let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
            ),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: value)
        else { return nil }
        return String(value[range])
    }

    private static func firstAttribute(_ name: String, in value: String) -> String? {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*"([^"]+)""#
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ),
            let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
            ),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: value)
        else { return nil }
        return decodeHTMLEntities(String(value[range]))
    }

    private static func firstXURL(in value: String) -> String? {
        let pattern = #"\bhref\s*=\s*"(https?://x\.com/[^"]+)""#
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ),
            let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
            ),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: value)
        else { return nil }
        return decodeHTMLEntities(String(value[range]))
    }

    private static func plainText(from html: String) -> String {
        var text = html
        if let expression = try? NSRegularExpression(pattern: #"<[^>]+>"#) {
            text = expression.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }
        let entities = [
            "&gt;": ">", "&lt;": "<", "&amp;": "&", "&quot;": "\"",
            "&#39;": "'", "&middot;": "·", "&nbsp;": " ",
            "&ldquo;": "“", "&rdquo;": "”", "&lsquo;": "‘", "&rsquo;": "’"
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        if let expression = try? NSRegularExpression(pattern: #"\s+"#) {
            text = expression.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        var text = value
        let entities = [
            "&gt;": ">", "&lt;": "<", "&amp;": "&", "&quot;": "\"",
            "&#39;": "'", "&middot;": "·", "&nbsp;": " ",
            "&ldquo;": "“", "&rdquo;": "”", "&lsquo;": "‘", "&rsquo;": "’"
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

}

private enum ResetCountdownLabel {
    static func short(to expectedAt: Date, now: Date = Date()) -> String {
        guard expectedAt > now else { return "DELAYED" }
        let totalMinutes = max(0, Int(ceil(expectedAt.timeIntervalSince(now) / 60)))
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)D \(hours)H" }
        if hours > 0 { return "\(hours)H \(minutes)M" }
        return "\(minutes)M"
    }
}

private struct BillingSnapshot: Codable, Sendable {
    let planName: String?
    let date: Date?
    let dateLabel: String
    var verifiedAt: Date? = nil
}

private enum BillingDefaults {
    static let renewalTimestamp = "QuotaGlance.subscriptionRenewalTimestamp"
    static let webPlanName = "QuotaGlance.subscriptionWebPlan"
    static let dateLabel = "QuotaGlance.subscriptionDateLabel"
    static let lastSuccessfulSync = "QuotaGlance.subscriptionLastSuccessfulSync"
    static let lastAutomaticAttempt = "QuotaGlance.subscriptionLastAutomaticAttempt"
    static let lastObservedLocalPlan = "QuotaGlance.subscriptionLastObservedLocalPlan"
    static let planChangeSyncPending = "QuotaGlance.subscriptionPlanChangeSyncPending"

    static func save(_ snapshot: BillingSnapshot, now: Date = Date()) {
        let defaults = UserDefaults.standard
        var storedPlan = snapshot.planName
        let previousPlan = defaults.string(forKey: webPlanName)
        if snapshot.planName?.caseInsensitiveCompare("Pro") == .orderedSame,
           previousPlan?.localizedCaseInsensitiveContains("20x") == true {
            storedPlan = previousPlan
        }
        if let planName = storedPlan {
            defaults.set(planName, forKey: webPlanName)
        }
        if let date = snapshot.date {
            defaults.set(date.timeIntervalSince1970, forKey: renewalTimestamp)
        }
        defaults.set(snapshot.dateLabel, forKey: dateLabel)
        defaults.set(now.timeIntervalSince1970, forKey: lastSuccessfulSync)
        NotificationCenter.default.post(name: .quotaGlanceBillingUpdated, object: nil)
    }
}

private enum BillingKeychain {
    static var hasConnectedSession: Bool {
        UserDefaults.standard.double(forKey: BillingDefaults.lastSuccessfulSync) > 0
    }
}

@MainActor
private enum BillingSyncCoordinator {
    private static var isRunning = false

    static func noteLocalPlan(_ planName: String, now: Date = Date()) {
        let normalized = planName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != "Codex" else { return }

        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: BillingDefaults.lastObservedLocalPlan)
        if previous != normalized {
            defaults.set(normalized, forKey: BillingDefaults.lastObservedLocalPlan)
            defaults.set(true, forKey: BillingDefaults.planChangeSyncPending)
            // A real local plan change is more important than the ordinary
            // retry throttle, so allow one immediate capture attempt.
            defaults.removeObject(forKey: BillingDefaults.lastAutomaticAttempt)
        }
        runAutomaticSyncIfNeeded(now: now)
    }

    static func runAutomaticSyncIfNeeded(now: Date = Date()) {
        guard !isRunning else { return }
        let defaults = UserDefaults.standard
        let lastSuccess = Date(timeIntervalSince1970: defaults.double(forKey: BillingDefaults.lastSuccessfulSync))
        let lastAttempt = Date(timeIntervalSince1970: defaults.double(forKey: BillingDefaults.lastAutomaticAttempt))
        let month: TimeInterval = 28 * 24 * 60 * 60
        let retryDelay: TimeInterval = 3 * 24 * 60 * 60
        let planChangePending = defaults.bool(forKey: BillingDefaults.planChangeSyncPending)
        let monthlyCaptureDue = now.timeIntervalSince(lastSuccess) >= month

        guard (planChangePending || monthlyCaptureDue),
              now.timeIntervalSince(lastAttempt) >= retryDelay
        else { return }

        isRunning = true
        defaults.set(now.timeIntervalSince1970, forKey: BillingDefaults.lastAutomaticAttempt)
        Task {
            do {
                let snapshot = try await WebKitBillingService.fetch()
                BillingDefaults.save(snapshot, now: now)
                defaults.set(false, forKey: BillingDefaults.planChangeSyncPending)
            } catch {
                // Automatic capture is deliberately silent. The saved plan
                // and date stay intact, and a failed change capture may retry
                // after three days rather than polling the browser every day.
            }
            isRunning = false
        }
    }
}

@MainActor
private final class WebKitBillingService: NSObject, WKNavigationDelegate {
    static let shared = WebKitBillingService()
    private static let billingURL = URL(string: "https://chatgpt.com/?refresh_account=true#settings/Billing")!

    private let webView: WKWebView
    private var window: NSWindow?
    private var continuation: CheckedContinuation<BillingSnapshot, Error>?
    private var timeout: DispatchWorkItem?
    private var extractionAttempt = 0
    private var userRequestedWindow = false

    override private init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    static func fetch() async throws -> BillingSnapshot {
        try await shared.fetchHeadlessly()
    }

    static func showLogin() {
        shared.showLoginWindow()
    }

    private func fetchHeadlessly() async throws -> BillingSnapshot {
        guard continuation == nil else { throw DashboardError.billingUnavailable }
        userRequestedWindow = false
        ensureWindow()
        window?.orderOut(nil)
        extractionAttempt = 0
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let timeout = DispatchWorkItem { [weak self] in
                self?.finish(.failure(DashboardError.billingUnavailable))
            }
            self.timeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeout)
            webView.load(URLRequest(url: Self.billingURL, cachePolicy: .reloadIgnoringLocalCacheData))
        }
    }

    private func showLoginWindow() {
        userRequestedWindow = true
        ensureWindow()
        window?.title = "Connect ChatGPT Billing"
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        webView.load(URLRequest(url: Self.billingURL))
    }

    private func ensureWindow() {
        guard window == nil else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 580, height: 520)
        self.window = window
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        extractionAttempt = 0
        scheduleExtraction()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(DashboardError.billingUnavailable))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(DashboardError.billingUnavailable))
    }

    private func scheduleExtraction() {
        extractionAttempt += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + (extractionAttempt == 1 ? 1.2 : 1.8)) { [weak self] in
            self?.extractPage()
        }
    }

    private func extractPage() {
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] value, _ in
            guard let self else { return }
            let text = value as? String ?? ""
            if let snapshot = Self.parse(text) {
                BillingDefaults.save(snapshot)
                if userRequestedWindow {
                    window?.title = "Billing connected — saved automatically"
                }
                finish(.success(snapshot))
            } else if extractionAttempt < 7 {
                scheduleExtraction()
            } else if continuation != nil {
                finish(.failure(DashboardError.billingLoginRequired))
            }
        }
    }

    private func finish(_ result: Result<BillingSnapshot, Error>) {
        timeout?.cancel()
        timeout = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    private static func parse(_ text: String) -> BillingSnapshot? {
        let specificPro = firstCapture(
            pattern: #"ChatGPT\s+Pro\s*(\d+\s*x)"#,
            in: text,
            group: 1
        )
        let genericPlan = firstCapture(
            pattern: #"ChatGPT\s+(Pro|Plus|Go|Free)"#,
            in: text,
            group: 1
        )
        let plan: String? = {
            if let specificPro {
                return "Pro " + specificPro.replacingOccurrences(of: " ", with: "")
            }
            if genericPlan?.caseInsensitiveCompare("Pro") == .orderedSame,
               text.range(of: #"\b20\s*x\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                return "Pro 20x"
            }
            return genericPlan
        }()

        var date: Date?
        var label = "NEXT RENEWAL"
        if let match = captures(
            pattern: #"Your plan changes to\s+([^\n]+?)\s+on\s+([A-Z][a-z]+\s+\d{1,2},\s+\d{4})"#,
            in: text
        ), match.count >= 3 {
            date = parseDate(match[2])
            label = "PLAN CHANGES TO " + match[1].uppercased()
        } else if let rawDate = firstCapture(
            pattern: #"(?:renews|renewal|next billing date)[^\n]{0,48}?([A-Z][a-z]+\s+\d{1,2},\s+\d{4})"#,
            in: text,
            group: 1
        ) {
            date = parseDate(rawDate)
        }

        guard plan != nil || date != nil else { return nil }
        return BillingSnapshot(planName: plan, date: date, dateLabel: label, verifiedAt: Date())
    }

    private static func captures(pattern: String, in text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func firstCapture(pattern: String, in text: String, group: Int) -> String? {
        let values = captures(pattern: pattern, in: text)
        guard let values, values.indices.contains(group) else { return nil }
        return values[group]
    }

    private static func parseDate(_ value: String) -> Date? {
        for format in ["MMM d, yyyy", "MMMM d, yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

private struct SubscriptionInfoPopover: View {
    let planName: String
    let theme: WidgetTheme
    @AppStorage(BillingDefaults.renewalTimestamp) private var renewalTimestamp = 0.0
    @AppStorage(BillingDefaults.webPlanName) private var webPlanName = ""
    @AppStorage(BillingDefaults.dateLabel) private var dateLabel = "NEXT RENEWAL"
    @AppStorage(BillingDefaults.lastSuccessfulSync) private var lastSuccessfulSync = 0.0
    @State private var isSyncing = false
    @State private var syncMessage: String?
    @State private var showingDateEditor = false
    @State private var isConnected = BillingKeychain.hasConnectedSession

    private var palette: PopoverPalette { theme.popoverPalette }

    private var renewalDate: Date? {
        guard renewalTimestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: renewalTimestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BILLING CYCLE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(palette.tertiary)
                    Text((webPlanName.isEmpty ? planName : webPlanName).uppercased())
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                Spacer()
                Circle()
                    .fill(isConnected ? Color(hex: 0x7EE6AE) : Color.white.opacity(0.2))
                    .frame(width: 7, height: 7)
                Text(isConnected ? verificationLabel : "LOCAL ONLY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.tertiary)
            }
            .padding(.bottom, 18)

            if let renewalDate {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(dateLabel.replacingOccurrences(of: "PLAN ", with: ""))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.billing.opacity(0.86))
                        Text(renewalDate.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.system(size: 38, weight: .light, design: palette.numberDesign))
                            .tracking(-1.4)
                        Text(renewalDate.formatted(.dateTime.year()))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.tertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(countdownNumber(to: renewalDate))
                            .font(.system(size: 34, weight: .light, design: palette.numberDesign))
                            .monospacedDigit()
                        Text(countdownUnit(to: renewalDate))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(palette.tertiary)
                    }
                }

                cycleTrack(to: renewalDate)
                    .padding(.vertical, 14)

                HStack(spacing: 9) {
                    Image(systemName: dateLabel.contains("CHANGES TO PLUS") ? "arrow.down.right" : "bell")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.billing)
                    Text(dateLabel.contains("CHANGES TO PLUS") ? "$20 PLAN SCHEDULED" : "DOWNGRADE BEFORE RENEWAL")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    Spacer()
                    Button {
                        showingDateEditor.toggle()
                    } label: {
                        Image(systemName: "pencil")
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(palette.surface))
                    }
                    .buttonStyle(.plain)
                }

                if showingDateEditor {
                    DatePicker("Date", selection: renewalBinding, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .padding(.top, 10)
                }
            } else {
                Text("Connect once. Quota Glance will read the plan and next billing change silently afterward.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 18)
            }

            Divider().overlay(palette.rule).padding(.vertical, 14)

            HStack(spacing: 10) {
                actionButton(isSyncing ? "SYNCING" : "REFRESH", icon: "arrow.clockwise") {
                    syncFromWebKit()
                }
                .disabled(isSyncing)
                actionButton(isConnected ? "SESSION" : "SIGN IN", icon: "key.fill") {
                    WebKitBillingService.showLogin()
                    syncMessage = "Sign in once; billing saves automatically."
                }
            }

            if let syncMessage {
                Text(syncMessage)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.tertiary)
                    .padding(.top, 10)
            }
        }
        .padding(18)
        .frame(width: 334)
        .background(
            RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous)
                .fill(palette.background)
                .overlay(
                    RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous)
                        .stroke(palette.billing.opacity(0.3), lineWidth: 1)
                )
        )
        .foregroundStyle(palette.primary)
        .preferredColorScheme(theme.isLight ? .light : .dark)
        .onAppear {
            rollRenewalForwardIfNeeded()
            isConnected = BillingKeychain.hasConnectedSession
        }
        .onReceive(NotificationCenter.default.publisher(for: .quotaGlanceBillingUpdated)) { _ in
            isConnected = true
        }
    }

    private func cycleTrack(to date: Date) -> some View {
        let days = max(0, Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0)
        let progress = CGFloat(max(0, min(1, 1 - Double(days) / 30)))
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(palette.rule).frame(height: 1)
                Rectangle().fill(palette.billing)
                    .frame(width: geometry.size.width * progress, height: 2)
                Circle()
                    .fill(palette.background)
                    .overlay(Circle().stroke(palette.billing, lineWidth: 1.4))
                    .frame(width: 7, height: 7)
                    .offset(x: max(0, geometry.size.width * progress - 3.5))
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 8)
        .accessibilityLabel("Billing cycle progress")
        .accessibilityValue("\(days) days left")
    }

    private var renewalBinding: Binding<Date> {
        Binding(
            get: { renewalDate ?? Date() },
            set: { renewalTimestamp = Calendar.current.startOfDay(for: $0).timeIntervalSince1970 }
        )
    }

    private func countdown(to date: Date) -> String {
        let today = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: date)
        let days = max(0, Calendar.current.dateComponents([.day], from: today, to: target).day ?? 0)
        if days == 0 { return "TODAY" }
        if days == 1 { return "TOMORROW" }
        return "IN \(days) DAYS"
    }

    private func countdownNumber(to date: Date) -> String {
        let today = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: date)
        return "\(max(0, Calendar.current.dateComponents([.day], from: today, to: target).day ?? 0))"
    }

    private func countdownUnit(to date: Date) -> String {
        countdownNumber(to: date) == "1" ? "DAY LEFT" : "DAYS LEFT"
    }

    private var verificationLabel: String {
        guard lastSuccessfulSync > 0 else { return "CACHED" }
        let age = max(0, Date().timeIntervalSince1970 - lastSuccessfulSync)
        if age < 90 { return "VERIFIED NOW" }
        if age < 3_600 { return "VERIFIED \(Int(age / 60))M" }
        if age < 86_400 { return "VERIFIED \(Int(age / 3_600))H" }
        return "VERIFIED \(Int(age / 86_400))D"
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(palette.secondary)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(palette.rule, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func rollRenewalForwardIfNeeded() {
        guard var date = renewalDate else { return }
        let today = Calendar.current.startOfDay(for: Date())
        var attempts = 0
        while date < today && attempts < 24 {
            guard let next = Calendar.current.date(byAdding: .month, value: 1, to: date) else { break }
            date = next
            attempts += 1
        }
        if date.timeIntervalSince1970 != renewalTimestamp {
            renewalTimestamp = date.timeIntervalSince1970
        }
    }

    private func syncFromWebKit() {
        isSyncing = true
        syncMessage = nil
        Task {
            do {
                let snapshot = try await WebKitBillingService.fetch()
                await MainActor.run {
                    BillingDefaults.save(snapshot)
                    if let planName = snapshot.planName { webPlanName = planName }
                    if let date = snapshot.date { renewalTimestamp = date.timeIntervalSince1970 }
                    dateLabel = snapshot.dateLabel
                    isConnected = true
                    syncMessage = snapshot.date == nil
                        ? "Plan synced. No billing date was visible."
                        : "Plan and billing date synced."
                    isSyncing = false
                }
            } catch DashboardError.billingLoginRequired {
                await MainActor.run {
                    WebKitBillingService.showLogin()
                    syncMessage = "Sign in once; billing saves automatically."
                    isSyncing = false
                }
            } catch {
                await MainActor.run {
                    syncMessage = "Billing could not refresh. Your saved date is untouched."
                    isSyncing = false
                }
            }
        }
    }
}

private struct DockMetrics {
    let position: DockPosition
    let size: CGSize

    var center: CGPoint {
        switch position {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .topRight: return CGPoint(x: size.width, y: 0)
        case .bottomLeft: return CGPoint(x: 0, y: size.height)
        case .bottomRight: return CGPoint(x: size.width, y: size.height)
        case .left: return CGPoint(x: 0, y: size.height / 2)
        case .right: return CGPoint(x: size.width, y: size.height / 2)
        case .top: return CGPoint(x: size.width / 2, y: 0)
        case .bottom: return CGPoint(x: size.width / 2, y: size.height)
        case .floating: return CGPoint(x: size.width / 2, y: size.height / 2)
        }
    }

    var readoutScale: CGFloat {
        guard position.isMounted else { return 1 }
        let base = position.mountedSize
        let geometricScale = min(size.width / max(1, base.width), size.height / max(1, base.height))
        // The original type sizes are the legibility floor. Enlarging a
        // mounted dial scales its readouts with the rings; shrinking never
        // turns them back into unreadable microtype.
        return min(2, max(1, geometricScale))
    }

    var diameter: CGFloat {
        switch position {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return 2 * min(size.width, size.height) / 0.94
        case .left, .right: return size.height / 0.94
        case .top, .bottom: return size.width / 0.94
        case .floating: return min(size.width, size.height)
        }
    }

    var controlPoint: CGPoint {
        // The circle's mathematical center sits on the screen boundary.
        // Keep the button just inside that calm central area instead of on
        // top of the blue ring.
        let inset: CGFloat = 23
        switch position {
        case .topLeft: return CGPoint(x: inset, y: inset)
        case .topRight: return CGPoint(x: size.width - inset, y: inset)
        case .bottomLeft: return CGPoint(x: inset, y: size.height - inset)
        case .bottomRight: return CGPoint(x: size.width - inset, y: size.height - inset)
        case .left: return CGPoint(x: size.width - 17, y: size.height / 2)
        case .right: return CGPoint(x: 17, y: size.height / 2)
        case .top: return CGPoint(x: size.width / 2, y: size.height - 17)
        case .bottom: return CGPoint(x: size.width / 2, y: 17)
        case .floating: return center
        }
    }

    var popoverEdge: Edge {
        switch position {
        case .top, .topLeft, .topRight: return .top
        case .bottom, .bottomLeft, .bottomRight: return .bottom
        case .left: return .leading
        case .right: return .trailing
        case .floating: return .top
        }
    }

    var arc: (start: Double, sweep: Double) {
        switch position {
        case .topLeft: return (0, 90)
        case .topRight: return (90, 90)
        case .bottomRight: return (180, 90)
        case .bottomLeft: return (270, 90)
        case .left: return (-90, 180)
        case .right: return (90, 180)
        case .top: return (0, 180)
        case .bottom: return (180, 180)
        case .floating: return (-90, 360)
        }
    }
}

private struct DockClipShape: Shape {
    let position: DockPosition

    func path(in rect: CGRect) -> Path {
        guard position.isMounted else {
            return Path(roundedRect: rect, cornerRadius: 31, style: .continuous)
        }
        if position.isEdge {
            return EdgeRailShape(position: position).path(in: rect)
        }
        let metrics = DockMetrics(position: position, size: rect.size)
        let circleRect = CGRect(
            x: metrics.center.x - metrics.diameter / 2,
            y: metrics.center.y - metrics.diameter / 2,
            width: metrics.diameter,
            height: metrics.diameter
        )
        return Path(ellipseIn: circleRect)
    }
}

private struct EdgeRailShape: Shape {
    let position: DockPosition

    func path(in rect: CGRect) -> Path {
        let vertical = position == .left || position == .right
        let depth = vertical ? rect.width : rect.height
        let bodyInset = depth * 0.18
        let cornerRadius = min(25, depth * 0.28)
        let tabHalf = depth * 0.23
        var path = Path()
        switch position {
        case .left:
            let edge = rect.maxX - bodyInset
            path.move(to: CGPoint(x: cornerRadius, y: rect.minY))
            path.addLine(to: CGPoint(x: edge - cornerRadius, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: edge, y: rect.minY + cornerRadius), control: CGPoint(x: edge, y: rect.minY))
            path.addLine(to: CGPoint(x: edge, y: rect.midY - tabHalf))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.maxX - 2, y: rect.midY - tabHalf * 0.65))
            path.addQuadCurve(to: CGPoint(x: edge, y: rect.midY + tabHalf), control: CGPoint(x: rect.maxX - 2, y: rect.midY + tabHalf * 0.65))
            path.addLine(to: CGPoint(x: edge, y: rect.maxY - cornerRadius))
            path.addQuadCurve(to: CGPoint(x: edge - cornerRadius, y: rect.maxY), control: CGPoint(x: edge, y: rect.maxY))
            path.addLine(to: CGPoint(x: cornerRadius, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius), control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
            path.addQuadCurve(to: CGPoint(x: cornerRadius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        case .right:
            let edge = rect.minX + bodyInset
            path.move(to: CGPoint(x: edge + cornerRadius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius), control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: edge + cornerRadius, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: edge, y: rect.maxY - cornerRadius), control: CGPoint(x: edge, y: rect.maxY))
            path.addLine(to: CGPoint(x: edge, y: rect.midY + tabHalf))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: CGPoint(x: rect.minX + 2, y: rect.midY + tabHalf * 0.65))
            path.addQuadCurve(to: CGPoint(x: edge, y: rect.midY - tabHalf), control: CGPoint(x: rect.minX + 2, y: rect.midY - tabHalf * 0.65))
            path.addLine(to: CGPoint(x: edge, y: rect.minY + cornerRadius))
            path.addQuadCurve(to: CGPoint(x: edge + cornerRadius, y: rect.minY), control: CGPoint(x: edge, y: rect.minY))
        case .top:
            let edge = rect.maxY - bodyInset
            path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius), control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: edge - cornerRadius))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - cornerRadius, y: edge), control: CGPoint(x: rect.maxX, y: edge))
            path.addLine(to: CGPoint(x: rect.midX + tabHalf, y: edge))
            path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.midX + tabHalf * 0.65, y: rect.maxY - 2))
            path.addQuadCurve(to: CGPoint(x: rect.midX - tabHalf, y: edge), control: CGPoint(x: rect.midX - tabHalf * 0.65, y: rect.maxY - 2))
            path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: edge))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: edge - cornerRadius), control: CGPoint(x: rect.minX, y: edge))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
            path.addQuadCurve(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        case .bottom:
            let edge = rect.minY + bodyInset
            path.move(to: CGPoint(x: rect.minX + cornerRadius, y: edge))
            path.addLine(to: CGPoint(x: rect.midX - tabHalf, y: edge))
            path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.midX - tabHalf * 0.65, y: rect.minY + 2))
            path.addQuadCurve(to: CGPoint(x: rect.midX + tabHalf, y: edge), control: CGPoint(x: rect.midX + tabHalf * 0.65, y: rect.minY + 2))
            path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: edge))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: edge + cornerRadius), control: CGPoint(x: rect.maxX, y: edge))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius), control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: edge + cornerRadius))
            path.addQuadCurve(to: CGPoint(x: rect.minX + cornerRadius, y: edge), control: CGPoint(x: rect.minX, y: edge))
        default:
            return Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        }
        path.closeSubpath()
        return path
    }
}

private struct MountedQuotaRail: View {
    let calendarProgress: Double
    let usageProgress: Double
    let resetProgress: Double
    let resetCountdownAt: Date?
    let resetAnnounced: Bool
    let theme: WidgetTheme
    let position: DockPosition

    var body: some View {
        GeometryReader { geometry in
            let vertical = position == .left || position == .right
            let scale = min(1.7, max(1, min(geometry.size.width / 112, geometry.size.height / 330)))
            let railLayout = vertical
                ? AnyLayout(VStackLayout(spacing: 12 * scale))
                : AnyLayout(HStackLayout(spacing: 12 * scale))
            let horizontalInset: Edge.Set = position == .left ? .trailing : position == .right ? .leading : .horizontal
            let verticalInset: Edge.Set = position == .top ? .bottom : position == .bottom ? .top : .vertical

            railLayout {
                railMetric(progress: calendarProgress, color: palette.orange, symbol: "calendar.badge.clock", roundsDown: true, scale: scale)
                railMetric(progress: usageProgress, color: palette.usage, symbol: "chevron.left.forwardslash.chevron.right", roundsDown: false, scale: scale)
                railMetric(
                    progress: resetProgress,
                    color: palette.reset,
                    symbol: "clock.arrow.circlepath",
                    roundsDown: false,
                    countdownAt: resetCountdownAt,
                    alerting: resetAnnounced,
                    scale: scale
                )
            }
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 12 * scale)
            .padding(horizontalInset, 10 * scale)
            .padding(verticalInset, 10 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                EdgeRailShape(position: position)
                    .fill(faceColor)
                    .overlay(EdgeRailShape(position: position).stroke(faceBorderColor, lineWidth: theme == .marine ? 1 : 0.6))
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mounted quota rail")
        .accessibilityValue("Calendar \(Int(calendarProgress.rounded(.down))) percent, Codex usage \(Int(usageProgress.rounded())) percent, reset estimate \(Int(resetProgress.rounded())) percent")
        .animation(.easeOut(duration: 0.35), value: calendarProgress)
        .animation(.easeOut(duration: 0.35), value: usageProgress)
        .animation(.easeOut(duration: 0.35), value: resetProgress)
    }

    private func railMetric(
        progress: Double,
        color: Color,
        symbol: String,
        roundsDown: Bool,
        countdownAt: Date? = nil,
        alerting: Bool = false,
        scale: CGFloat
    ) -> some View {
        let value = roundsDown ? progress.rounded(.down) : progress.rounded()
        let fraction = max(0, min(1, progress / 100))
        let ringSize = 50 * scale
        let lineWidth = 2.6 * scale
        return VStack(spacing: 3 * scale) {
            ZStack {
                Circle()
                    .stroke(color.opacity(trackOpacity), lineWidth: lineWidth)
                if alerting {
                    TimelineView(.periodic(from: .now, by: 0.8)) { context in
                        Circle()
                            .trim(from: 0, to: fraction)
                            .stroke(ResetAlertBar.gradient(at: ResetAlertBar.phase(at: context.date)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                } else {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                if let countdownAt {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        VStack(spacing: 1 * scale) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 8 * scale, weight: .bold))
                            Text(ResetCountdownLabel.short(to: countdownAt, now: context.date))
                                .font(.system(size: 7 * scale, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                                .minimumScaleFactor(0.72)
                        }
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .frame(width: ringSize * 0.72)
                    }
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 10.5 * scale, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(color.opacity(0.9))
                }
            }
            .frame(width: ringSize, height: ringSize)

            if countdownAt == nil {
                Text("\(Int(max(0, min(100, value))))%")
                    .font(.system(size: 12.5 * scale, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(theme.isLight ? Color(hex: 0x242628) : Color.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var palette: (orange: Color, usage: Color, reset: Color) {
        switch theme {
        case .eInk: return (Color(hex: 0xA85D00), Color(hex: 0x2868B2), Color(hex: 0x3A8B62))
        case .marine: return (Color(hex: 0xF1B84B), Color(hex: 0x3B8FEA), Color(hex: 0x83E2AE))
        case .retro: return (Color(hex: 0xFFB21F), Color(hex: 0x3182E8), Color(hex: 0x63E18A))
        case .radar: return (Color(hex: 0xFFC34D), Color(hex: 0x2685E5), Color(hex: 0x6FE0AC))
        case .oled, .current: return (Color(hex: 0xF2AD3E), Color(hex: 0x2F80ED), Color(hex: 0x68D9A0))
        }
    }

    private var faceColor: Color {
        switch theme {
        case .eInk: return Color(hex: 0xF1EFE8).opacity(0.94)
        case .marine: return Color(hex: 0x171A18).opacity(0.95)
        case .retro: return Color.black.opacity(0.93)
        case .radar: return Color(hex: 0x071319).opacity(0.92)
        case .oled, .current: return Color(hex: 0x080B0E).opacity(0.94)
        }
    }

    private var faceBorderColor: Color {
        theme.isLight ? Color.black.opacity(0.22) : Color.white.opacity(0.07)
    }

    private var trackOpacity: Double {
        theme.isLight ? 0.18 : 0.13
    }
}

private struct MountedRingActionView: NSViewRepresentable {
    let position: DockPosition
    let calendarAction: () -> Void
    let usageAction: () -> Void
    let resetAction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(position: position, calendarAction: calendarAction, usageAction: usageAction, resetAction: resetAction)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.position = position
        context.coordinator.calendarAction = calendarAction
        context.coordinator.usageAction = usageAction
        context.coordinator.resetAction = resetAction
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.detach() }

    final class Coordinator {
        var position: DockPosition
        var calendarAction: () -> Void
        var usageAction: () -> Void
        var resetAction: () -> Void
        private weak var view: NSView?
        private var monitor: Any?

        init(position: DockPosition, calendarAction: @escaping () -> Void, usageAction: @escaping () -> Void, resetAction: @escaping () -> Void) {
            self.position = position
            self.calendarAction = calendarAction
            self.usageAction = usageAction
            self.resetAction = resetAction
        }

        func attach(to view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                guard let self, let view = self.view, event.window === view.window else { return event }
                let point = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(point) else { return event }
                if self.position.isEdge {
                    let fraction: CGFloat
                    if self.position == .left || self.position == .right {
                        fraction = 1 - (point.y / max(1, view.bounds.height))
                    } else {
                        fraction = point.x / max(1, view.bounds.width)
                    }
                    if fraction < 1.0 / 3.0 { self.calendarAction() }
                    else if fraction < 2.0 / 3.0 { self.usageAction() }
                    else { self.resetAction() }
                    return nil
                }
                let center: NSPoint
                switch self.position {
                case .topLeft: center = NSPoint(x: 0, y: view.bounds.maxY)
                case .topRight: center = NSPoint(x: view.bounds.maxX, y: view.bounds.maxY)
                case .bottomLeft: center = .zero
                case .bottomRight: center = NSPoint(x: view.bounds.maxX, y: 0)
                case .left: center = NSPoint(x: 0, y: view.bounds.midY)
                case .right: center = NSPoint(x: view.bounds.maxX, y: view.bounds.midY)
                case .top: center = NSPoint(x: view.bounds.midX, y: view.bounds.maxY)
                case .bottom: center = NSPoint(x: view.bounds.midX, y: 0)
                case .floating: center = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
                }
                let distance = hypot(point.x - center.x, point.y - center.y)
                let radius: CGFloat
                if self.position.isCorner {
                    radius = min(view.bounds.width, view.bounds.height)
                } else if self.position == .left || self.position == .right {
                    radius = view.bounds.height / 2
                } else if self.position == .top || self.position == .bottom {
                    radius = view.bounds.width / 2
                } else {
                    radius = min(view.bounds.width, view.bounds.height) / 2
                }
                let normalized = distance / max(1, radius)
                guard normalized <= 1.05 else { return event }
                if normalized >= 0.72 { self.calendarAction() }
                else if normalized >= 0.49 { self.usageAction() }
                else { self.resetAction() }
                return nil
            }
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { detach() }
    }
}

private struct MountedQuotaRings: View {
    let calendarProgress: Double
    let usageProgress: Double
    let resetProgress: Double
    let calendarDetail: String
    let usageDetail: String
    let resetDetail: String
    let resetCountdownAt: Date?
    let resetAnnounced: Bool
    let theme: WidgetTheme
    let position: DockPosition

    var body: some View {
        GeometryReader { geometry in
            let metrics = DockMetrics(position: position, size: geometry.size)
            let strokeBasis = min(geometry.size.width, geometry.size.height)
            let calendarWidth = strokeBasis * (position.isCorner ? 0.032 : 0.075)
            let usageWidth = strokeBasis * (position.isCorner ? 0.030 : 0.072)
            let resetWidth = strokeBasis * (position.isCorner ? 0.028 : 0.067)
            ZStack {
                Circle()
                    .fill(faceColor)
                    .overlay(Circle().stroke(faceBorderColor, lineWidth: theme == .marine ? 2 : 1))
                    .frame(width: metrics.diameter * 0.94, height: metrics.diameter * 0.94)
                    .position(metrics.center)

                mountedRing(
                    progress: calendarProgress,
                    color: palette.orange,
                    diameter: metrics.diameter * 0.82,
                    width: calendarWidth,
                    metrics: metrics
                )
                if position != .floating {
                    mountedPercentage(
                        progress: calendarProgress,
                        color: palette.orange,
                        diameter: metrics.diameter * 0.82,
                        width: calendarWidth,
                        metrics: metrics,
                        roundsDown: true
                    )
                    mountedDetail(
                        calendarDetail,
                        progress: calendarProgress,
                        color: palette.orange,
                        diameter: metrics.diameter * 0.82,
                        width: calendarWidth,
                        metrics: metrics
                    )
                }
                mountedRing(
                    progress: usageProgress,
                    color: palette.usage,
                    diameter: metrics.diameter * 0.61,
                    width: usageWidth,
                    metrics: metrics
                )
                if position != .floating {
                    mountedPercentage(
                        progress: usageProgress,
                        color: palette.usage,
                        diameter: metrics.diameter * 0.61,
                        width: usageWidth,
                        metrics: metrics,
                        roundsDown: false
                    )
                    mountedDetail(
                        usageDetail,
                        progress: usageProgress,
                        color: palette.usage,
                        diameter: metrics.diameter * 0.61,
                        width: usageWidth,
                        metrics: metrics
                    )
                }
                mountedRing(
                    progress: resetProgress,
                    color: palette.reset,
                    diameter: metrics.diameter * 0.40,
                    width: resetWidth,
                    metrics: metrics,
                    alerting: resetAnnounced
                )
                if position != .floating {
                    if let resetCountdownAt {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            mountedResetCountdown(
                                to: resetCountdownAt,
                                now: context.date,
                                color: palette.reset,
                                diameter: metrics.diameter * 0.40,
                                metrics: metrics
                            )
                        }
                    } else {
                        mountedPercentage(
                            progress: resetProgress,
                            color: palette.reset,
                            diameter: metrics.diameter * 0.40,
                            width: resetWidth,
                            metrics: metrics,
                            roundsDown: false
                        )
                        mountedDetail(
                            resetDetail,
                            progress: resetProgress,
                            color: palette.reset,
                            diameter: metrics.diameter * 0.40,
                            width: resetWidth,
                            metrics: metrics
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mounted quota rings")
        .accessibilityValue("Calendar \(Int(calendarProgress.rounded(.down))) percent, Codex usage \(Int(usageProgress.rounded())) percent, reset estimate \(Int(resetProgress.rounded())) percent")
        .animation(.easeOut(duration: 0.35), value: calendarProgress)
        .animation(.easeOut(duration: 0.35), value: usageProgress)
        .animation(.easeOut(duration: 0.35), value: resetProgress)
    }

    @ViewBuilder private func mountedRing(
        progress: Double,
        color: Color,
        diameter: CGFloat,
        width: CGFloat,
        metrics: DockMetrics,
        alerting: Bool = false
    ) -> some View {
        if alerting {
            // The alert sweep is intentionally low-frequency. The former
            // five-frames-per-second timeline kept SwiftUI rendering while
            // the widget was otherwise idle.
            TimelineView(.periodic(from: .now, by: 0.8)) { context in
                mountedRingContent(
                    progress: progress,
                    color: color,
                    diameter: diameter,
                    width: width,
                    metrics: metrics,
                    highlightPhase: ResetAlertBar.phase(at: context.date)
                )
            }
        } else {
            mountedRingContent(progress: progress, color: color, diameter: diameter, width: width, metrics: metrics)
        }
    }

    private func mountedRingContent(
        progress: Double,
        color: Color,
        diameter: CGFloat,
        width: CGFloat,
        metrics: DockMetrics,
        highlightPhase: Double? = nil
    ) -> some View {
        let fraction = max(0, min(1, progress / 100))
        let dash = theme == .retro ? [width * 0.72, width * 0.48] : []
        let cap: CGLineCap = theme == .retro || theme == .eInk ? .butt : .round
        return ZStack {
            MountedArcShape(startDegrees: metrics.arc.start, sweepDegrees: metrics.arc.sweep, fraction: 1)
                .stroke(color.opacity(trackOpacity), style: StrokeStyle(lineWidth: width, lineCap: cap, dash: dash))
            if let highlightPhase {
                MountedArcShape(startDegrees: metrics.arc.start, sweepDegrees: metrics.arc.sweep, fraction: fraction)
                    .stroke(
                        ResetAlertBar.gradient(at: highlightPhase),
                        style: StrokeStyle(lineWidth: width, lineCap: cap, dash: dash)
                    )
                    .shadow(color: color.opacity(shadowOpacity), radius: width * 0.42)
            } else {
                MountedArcShape(startDegrees: metrics.arc.start, sweepDegrees: metrics.arc.sweep, fraction: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: cap, dash: dash))
                    .shadow(color: color.opacity(shadowOpacity), radius: width * 0.42)
            }
        }
        .frame(width: diameter, height: diameter)
        .position(metrics.center)
    }

    private func mountedPercentage(
        progress: Double,
        color: Color,
        diameter: CGFloat,
        width: CGFloat,
        metrics: DockMetrics,
        roundsDown: Bool
    ) -> some View {
        let visibleValue = roundsDown ? progress.rounded(.down) : progress.rounded()
        let scale = metrics.readoutScale
        return Text("\(Int(max(0, min(100, visibleValue))))%")
            .font(.system(size: 9 * scale, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color)
            .shadow(color: faceColor.opacity(0.9), radius: 2 * scale)
            .position(percentagePosition(progress: progress, diameter: diameter, width: width, metrics: metrics))
            .allowsHitTesting(false)
    }

    private func mountedResetCountdown(
        to expectedAt: Date,
        now: Date,
        color: Color,
        diameter: CGFloat,
        metrics: DockMetrics
    ) -> some View {
        let scale = metrics.readoutScale
        return VStack(spacing: 1 * scale) {
            Image(systemName: "hourglass")
                .font(.system(size: 7 * scale, weight: .bold))
            Text(ResetCountdownLabel.short(to: expectedAt, now: now))
                .font(.system(size: 8 * scale, weight: .bold, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .shadow(color: faceColor.opacity(0.9), radius: 2 * scale)
        .position(resetCountdownPosition(diameter: diameter, metrics: metrics))
        .allowsHitTesting(false)
    }

    private func resetCountdownPosition(diameter: CGFloat, metrics: DockMetrics) -> CGPoint {
        let angle = CGFloat(metrics.arc.start + metrics.arc.sweep * 0.66) * .pi / 180
        let radius = diameter * 0.30
        return CGPoint(
            x: metrics.center.x + cos(angle) * radius,
            y: metrics.center.y + sin(angle) * radius
        )
    }

    private func percentagePosition(progress: Double, diameter: CGFloat, width: CGFloat, metrics: DockMetrics) -> CGPoint {
        let fraction = max(0, min(1, progress / 100))
        let angle = CGFloat(metrics.arc.start + metrics.arc.sweep * fraction) * .pi / 180
        let scale = metrics.readoutScale
        // Pull the number just inside its live endpoint, then clamp it away
        // from the clipped screen boundary so every value remains legible.
        let radius = metrics.position == .floating
            ? diameter / 2 + width / 2 + 8
            : max(8, diameter / 2 - width / 2 - 14 * scale)
        let raw = CGPoint(
            x: metrics.center.x + cos(angle) * radius,
            y: metrics.center.y + sin(angle) * radius
        )
        return CGPoint(
            x: min(max(raw.x, 19 * scale), max(19 * scale, metrics.size.width - 19 * scale)),
            y: min(max(raw.y, 12 * scale), max(12 * scale, metrics.size.height - 12 * scale))
        )
    }

    private func mountedDetail(
        _ text: String,
        progress: Double,
        color: Color,
        diameter: CGFloat,
        width: CGFloat,
        metrics: DockMetrics
    ) -> some View {
        let scale = metrics.readoutScale
        return Text(text)
            .font(.system(size: (metrics.position == .floating ? 6.5 : 7) * scale, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundStyle(color.opacity(0.92))
            .frame(maxWidth: (metrics.position == .floating ? 68 : 82) * scale)
            .frame(height: 15 * scale)
            .shadow(color: faceColor.opacity(0.9), radius: 2 * scale)
            .position(detailPosition(progress: progress, diameter: diameter, width: width, metrics: metrics))
            .allowsHitTesting(false)
    }

    private func detailPosition(progress: Double, diameter: CGFloat, width: CGFloat, metrics: DockMetrics) -> CGPoint {
        let fraction = max(0, min(1, progress / 100))
        let scale = metrics.readoutScale
        let angleDegrees: Double
        if metrics.position == .floating {
            angleDegrees = metrics.arc.start + metrics.arc.sweep * fraction + 180
        } else {
            // Use the unoccupied end of the visible arc. This keeps the label
            // opposite the moving percentage without allowing the two pills
            // to meet in the middle of a half- or quarter-circle.
            let detailFraction = fraction <= 0.5 ? 0.88 : 0.12
            angleDegrees = metrics.arc.start + metrics.arc.sweep * detailFraction
        }
        let angle = CGFloat(angleDegrees) * .pi / 180
        let radius = metrics.position == .floating
            ? diameter / 2 - width / 2 - 9
            : max(8, diameter / 2 - width / 2 - 14 * scale)
        let raw = CGPoint(
            x: metrics.center.x + cos(angle) * radius,
            y: metrics.center.y + sin(angle) * radius
        )
        let horizontalInset: CGFloat = (metrics.position == .floating ? 28 : 34) * scale
        return CGPoint(
            x: min(max(raw.x, horizontalInset), max(horizontalInset, metrics.size.width - horizontalInset)),
            y: min(max(raw.y, 10 * scale), max(10 * scale, metrics.size.height - 10 * scale))
        )
    }

    private var palette: (orange: Color, usage: Color, reset: Color) {
        switch theme {
        case .eInk: return (Color(hex: 0xA85D00), Color(hex: 0x2868B2), Color(hex: 0x3A8B62))
        case .marine: return (Color(hex: 0xF1B84B), Color(hex: 0x3B8FEA), Color(hex: 0x83E2AE))
        case .retro: return (Color(hex: 0xFFB21F), Color(hex: 0x3182E8), Color(hex: 0x63E18A))
        case .radar: return (Color(hex: 0xFFC34D), Color(hex: 0x2685E5), Color(hex: 0x6FE0AC))
        case .oled: return (Color(hex: 0xF2AD3E), Color(hex: 0x2F80ED), Color(hex: 0x68D9A0))
        case .current: return (Color(hex: 0xDDA13A), Color(hex: 0x4B7DE8), Color(hex: 0x72C992))
        }
    }

    private var faceColor: Color {
        switch theme {
        case .eInk: return Color(hex: 0xF1EFE8).opacity(0.82)
        case .marine: return Color(hex: 0x171A18).opacity(0.82)
        case .retro: return Color.black.opacity(0.76)
        case .radar: return Color(hex: 0x071319).opacity(0.72)
        case .oled: return Color.black.opacity(0.88)
        case .current: return Color.black.opacity(0.28)
        }
    }

    private var faceBorderColor: Color {
        theme.isLight ? Color.black.opacity(0.28) : Color.white.opacity(theme == .marine ? 0.16 : 0.06)
    }

    private var trackOpacity: Double { theme == .eInk ? 0.34 : (theme == .marine ? 0.22 : 0.15) }
    private var shadowOpacity: Double { theme == .eInk ? 0 : (theme == .marine ? 0.14 : 0.12) }
}

/// Codex Fast-style motion: several low-contrast blue bands flow inside the
/// existing reset fill. The animation is timer-driven at five frames per second.
private enum ResetAlertBar {
    static let highlight = Color(hex: 0xC4F7D8)
    static let flowingGradient = Gradient(stops: [
        .init(color: Color(hex: 0x68D9A0), location: 0.00),
        .init(color: Color(hex: 0x68D9A0), location: 0.07),
        .init(color: Color(hex: 0xC4F7D8), location: 0.12),
        .init(color: Color(hex: 0x68D9A0), location: 0.18),
        .init(color: Color(hex: 0x68D9A0), location: 0.39),
        .init(color: Color(hex: 0xA8EDC5), location: 0.45),
        .init(color: Color(hex: 0x68D9A0), location: 0.51),
        .init(color: Color(hex: 0x68D9A0), location: 0.72),
        .init(color: Color(hex: 0xC4F7D8), location: 0.78),
        .init(color: Color(hex: 0x68D9A0), location: 0.84),
        .init(color: Color(hex: 0x68D9A0), location: 1.00),
    ])

    static func phase(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 1.65) / 1.65
    }

    static func gradient(at phase: Double) -> AngularGradient {
        AngularGradient(
            gradient: flowingGradient,
            center: .center,
            angle: .degrees(phase * -360)
        )
    }

    static func segmentColor(index: Int, count: Int, phase: Double, base: Color) -> Color {
        guard count > 0 else { return base }
        let position = Double(index) / Double(count)
        let cycle = (position * 3 + phase * 3).truncatingRemainder(dividingBy: 1)
        let distance = abs(cycle - 0.5)
        if distance < 0.10 { return highlight }
        if distance < 0.19 { return Color(hex: 0x91E8B8) }
        return base
    }
}

private struct MountedArcShape: Shape {
    let startDegrees: Double
    let sweepDegrees: Double
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(startDegrees),
            endAngle: .degrees(startDegrees + sweepDegrees * max(0, min(1, fraction))),
            clockwise: false
        )
        return path
    }
}

private struct CompactQuotaRings: View {
    let calendarProgress: Double
    let usageProgress: Double
    let resetProgress: Double
    let theme: WidgetTheme

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle()
                    .fill(faceColor)
                    .frame(width: side * 0.94, height: side * 0.94)
                    .overlay(
                        Circle()
                            .stroke(faceBorderColor, lineWidth: theme == .marine ? 2 : 1)
                            .frame(width: side * 0.94, height: side * 0.94)
                    )

                ring(progress: calendarProgress, color: palette.orange, diameter: side * 0.82, width: side * 0.075)
                ring(progress: usageProgress, color: palette.usage, diameter: side * 0.61, width: side * 0.072)
                ring(progress: resetProgress, color: palette.reset, diameter: side * 0.40, width: side * 0.067)

                Circle()
                    .fill(theme.isLight ? Color.black.opacity(0.34) : Color.white.opacity(0.14))
                    .frame(width: max(4, side * 0.035), height: max(4, side * 0.035))
            }
            .frame(width: side, height: side)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quota rings")
        .accessibilityValue("Calendar \(Int(calendarProgress.rounded(.down))) percent, Codex usage \(Int(usageProgress.rounded())) percent, reset estimate \(Int(resetProgress.rounded())) percent")
        .animation(.easeOut(duration: 0.45), value: calendarProgress)
        .animation(.easeOut(duration: 0.45), value: usageProgress)
        .animation(.easeOut(duration: 0.45), value: resetProgress)
    }

    private func ring(progress: Double, color: Color, diameter: CGFloat, width: CGFloat) -> some View {
        let fraction = max(0, min(1, progress / 100))
        let dash = theme == .retro ? [width * 0.72, width * 0.48] : []
        let lineCap: CGLineCap = theme == .retro || theme == .eInk ? .butt : .round
        return ZStack {
            Circle()
                .stroke(
                    color.opacity(trackOpacity),
                    style: StrokeStyle(lineWidth: width, lineCap: lineCap, dash: dash)
                )
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: lineCap, dash: dash))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(shadowOpacity), radius: width * 0.42)
        }
        .frame(width: diameter, height: diameter)
    }

    private var palette: (orange: Color, usage: Color, reset: Color) {
        switch theme {
        case .eInk:
            return (Color(hex: 0xA85D00), Color(hex: 0x2868B2), Color(hex: 0x3A8B62))
        case .marine:
            return (Color(hex: 0xF1B84B), Color(hex: 0x3B8FEA), Color(hex: 0x83E2AE))
        case .retro:
            return (Color(hex: 0xFFB21F), Color(hex: 0x3182E8), Color(hex: 0x63E18A))
        case .radar:
            return (Color(hex: 0xFFC34D), Color(hex: 0x2685E5), Color(hex: 0x6FE0AC))
        case .oled, .current:
            return (Color(hex: 0xF2AD3E), Color(hex: 0x2F80ED), Color(hex: 0x68D9A0))
        }
    }

    private var faceColor: Color {
        switch theme {
        case .eInk: return Color(hex: 0xF1EFE8).opacity(0.82)
        case .marine: return Color(hex: 0x171A18).opacity(0.82)
        case .retro: return Color.black.opacity(0.76)
        case .radar: return Color(hex: 0x071319).opacity(0.72)
        case .oled: return Color.black.opacity(0.88)
        case .current: return Color.black.opacity(0.28)
        }
    }

    private var faceBorderColor: Color {
        theme.isLight ? Color.black.opacity(0.34) : Color.white.opacity(theme == .marine ? 0.2 : 0.1)
    }

    private var trackOpacity: Double {
        switch theme {
        case .eInk: return 0.34
        case .marine: return 0.22
        case .retro: return 0.2
        default: return 0.15
        }
    }

    private var shadowOpacity: Double {
        switch theme {
        case .eInk: return 0
        case .marine: return 0.22
        case .retro: return 0.18
        default: return 0.44
        }
    }
}

private struct CompactRingActionView: NSViewRepresentable {
    let calendarAction: () -> Void
    let usageAction: () -> Void
    let resetAction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(calendarAction: calendarAction, usageAction: usageAction, resetAction: resetAction)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.calendarAction = calendarAction
        context.coordinator.usageAction = usageAction
        context.coordinator.resetAction = resetAction
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var calendarAction: () -> Void
        var usageAction: () -> Void
        var resetAction: () -> Void
        private weak var view: NSView?
        private var monitor: Any?

        init(calendarAction: @escaping () -> Void, usageAction: @escaping () -> Void, resetAction: @escaping () -> Void) {
            self.calendarAction = calendarAction
            self.usageAction = usageAction
            self.resetAction = resetAction
        }

        func attach(to view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                guard let self, let view = self.view, event.window === view.window else { return event }
                let point = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(point) else { return event }
                let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
                let distance = hypot(point.x - center.x, point.y - center.y)
                let normalized = distance / max(1, min(view.bounds.width, view.bounds.height) / 2)
                guard normalized <= 1.05 else { return event }
                if normalized >= 0.72 {
                    self.calendarAction()
                } else if normalized >= 0.49 {
                    self.usageAction()
                } else {
                    self.resetAction()
                }
                return nil
            }
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { detach() }
    }
}

struct ResetCalculatorPopover: View {
    let snapshot: ForecastSnapshot?
    let effectiveScore: Double?
    let announcementActive: Bool
    let status: String
    let lifecycle: ResetLifecycleSnapshot
    let theme: WidgetTheme

    private var palette: PopoverPalette { theme.popoverPalette }

    private var detailProvider: ResetProviderSnapshot? {
        guard let snapshot else { return nil }
        if snapshot.selectedSources.count > 1 {
            return ForecastSource.calculatorCases
                .filter(snapshot.selectedSources.contains)
                .compactMap { source in snapshot.providers.first { $0.source == source } }
                .first
        }
        return snapshot.providers.first { $0.source == snapshot.source }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.reset)
                VStack(alignment: .leading, spacing: 1) {
                    Text("RESET CALCULATOR")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.tertiary)
                    Text(snapshot.map { ForecastSourceSelection.label(for: $0.selectedSources) } ?? "Reset estimate")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.primary.opacity(0.94))
                }
                Spacer()
                Text(updatedLabel)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.tertiary)
            }

            if let snapshot {
                resetScoreHeader(snapshot)

                if let timing = displayedTiming(for: snapshot) {
                    let expectedAt = timing.expectedAt
                    let isConfirmedAnnouncement = timing.confirmed
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        HStack(spacing: 10) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(palette.reset)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(isConfirmedAnnouncement
                                    ? (expectedAt <= context.date ? "RESET DELAYED" : "RESET COUNTDOWN")
                                    : "FORECAST WINDOW")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(palette.tertiary)
                                if isConfirmedAnnouncement && expectedAt <= context.date {
                                    Text("WAITING FOR RESET")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(palette.primary.opacity(0.94))
                                } else {
                                    Text(isConfirmedAnnouncement ? "RESET IN" : "BY")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(palette.tertiary)
                                    Text(expectedAt, style: .timer)
                                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(palette.primary.opacity(0.94))
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(expectedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                Text(Self.timeZoneLabel(for: expectedAt))
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(palette.reset)
                            }
                        }
                        .padding(11)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(palette.reset.opacity(theme == .eInk ? 0.12 : 0.08))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.reset.opacity(0.4), lineWidth: 0.8))
                        )
                    }
                }

                if let headline = effectiveHeadline(for: snapshot), !headline.isEmpty {
                    Text(headline)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let hedge = snapshot.providers.compactMap(\.polymarketForecast).first {
                    polymarketForecastCard(hedge)
                }

                if let provider = detailProvider, !provider.metrics.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                        ForEach(provider.metrics.prefix(4)) { metric in
                            metricTile(metric)
                        }
                    }
                }

                if let provider = detailProvider, !provider.signals.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("ACTIVE SIGNALS")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.tertiary)
                        ForEach(provider.signals.prefix(3)) { signal in
                            HStack(alignment: .top, spacing: 7) {
                                Circle()
                                    .fill(signal.value == "ACTIVE" ? palette.pace : palette.tertiary)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(signal.label)
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(palette.secondary)
                                    if let detail = signal.detail {
                                        Text(detail)
                                            .font(.system(size: 9, weight: .regular, design: .rounded))
                                            .foregroundStyle(palette.tertiary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                }

                Divider().overlay(palette.rule)

                VStack(spacing: 5) {
                    ForEach(ForecastSource.calculatorCases) { source in
                        providerRow(source, provider: snapshot.providers.first { $0.source == source })
                    }
                }
            } else {
                Text(status)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondary)
                    .padding(.vertical, 20)
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous)
                .fill(palette.background)
                .overlay(
                    RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous)
                        .stroke(palette.rule, lineWidth: 1)
                )
        )
        .preferredColorScheme(theme.isLight ? .light : .dark)
    }

    private func resetScoreHeader(_ snapshot: ForecastSnapshot) -> some View {
        let score = max(0, min(100, effectiveScore ?? snapshot.score))
        return ZStack(alignment: .bottom) {
            ZStack {
                Circle()
                    .trim(from: 0.50, to: 1.0)
                    .stroke(palette.rule, style: StrokeStyle(lineWidth: 7, lineCap: .butt, dash: [7, 3]))
                Circle()
                    .trim(from: 0.50, to: 0.50 + 0.50 * score / 100)
                    .stroke(palette.reset, style: StrokeStyle(lineWidth: 7, lineCap: .butt, dash: [7, 3]))
            }
            .frame(width: 176, height: 176)
            .frame(height: 88, alignment: .top)
            .clipped()

            VStack(spacing: 1) {
                Text("\(Int(score.rounded()))%")
                    .font(.system(size: 44, weight: .light, design: palette.numberDesign))
                    .monospacedDigit()
                    .foregroundStyle(palette.primary)
                Text(snapshot.source == .polymarket
                    ? "BY \(snapshot.providers.compactMap(\.polymarketForecast).first?.points.first?.marketLabel.uppercased() ?? "MARKET DEADLINE")"
                    : (snapshot.selectedSources.contains(.polymarket) ? "SELECTED FORECASTS" : "NEXT 24 HOURS"))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(palette.reset)
                if let range = snapshot.range {
                    Text("range \(Int(range.lowerBound.rounded()))–\(Int(range.upperBound.rounded()))%")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.tertiary)
                }
            }
            .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity, minHeight: 108)
        .clipped()
        .accessibilityElement(children: .combine)
    }

    private func metricTile(_ metric: ResetMetric) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.label.uppercased())
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.tertiary)
                .lineLimit(1)
            Text(metric.value)
                .font(.system(size: 14, weight: .semibold, design: palette.numberDesign))
                .foregroundStyle(palette.primary.opacity(0.9))
            if let detail = metric.detail {
                Text(detail)
                    .font(.system(size: 8, weight: .regular, design: .rounded))
                    .foregroundStyle(palette.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 8).fill(palette.surface))
    }

    private func polymarketForecastCard(_ forecast: PolymarketResetForecast) -> some View {
        let firstDeadline = forecast.points.first?.deadline.timeIntervalSince1970 ?? 0
        let lastDeadline = max(forecast.points.last?.deadline.timeIntervalSince1970 ?? 1, firstDeadline + 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RESET OUTLOOK")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.primary)
                Spacer()
                Link("POLYMARKET ↗", destination: forecast.url)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.reset)
            }
            Text("Chance of a reset by each date")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondary)

            Chart(forecast.points) { point in
                LineMark(
                    x: .value("Deadline", point.deadline.timeIntervalSince1970),
                    y: .value("Reset chance", point.yesPrice * 100)
                )
                .foregroundStyle(palette.reset)
                .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(
                    x: .value("Deadline", point.deadline.timeIntervalSince1970),
                    y: .value("Reset chance", point.yesPrice * 100)
                )
                .foregroundStyle(palette.reset)
                .symbolSize(30)
                .annotation(position: .top, spacing: 5) {
                    Text("\(Int((point.yesPrice * 100).rounded()))%\(point.usesLastTrade ? "*" : "")")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.primary)
                }
                .accessibilityLabel("By \(point.marketLabel)")
                .accessibilityValue("Reset: \(Int((point.yesPrice * 100).rounded())) percent. No reset: \(Int((point.noPrice * 100).rounded())) percent.")
            }
            .chartYScale(domain: 0...100)
            .chartXScale(domain: firstDeadline...lastDeadline, range: .plotDimension(padding: 28))
            .chartPlotStyle { plot in plot.padding(.top, 20) }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                    AxisGridLine().foregroundStyle(palette.rule)
                    AxisValueLabel {
                        if let number = value.as(Int.self) {
                            Text("\(number)%").foregroundStyle(palette.tertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                // Numeric timestamps avoid Swift Charts centering date labels in calendar bins.
                // Both marks and ticks share the exact deadline coordinate.
                AxisMarks(values: forecast.points.map { $0.deadline.timeIntervalSince1970 }) { value in
                    AxisTick(length: 4).foregroundStyle(palette.rule)
                    AxisValueLabel(centered: false, anchor: .top, collisionResolution: .disabled) {
                        if let timestamp = value.as(Double.self),
                           let point = forecast.points.first(where: { $0.deadline.timeIntervalSince1970 == timestamp }) {
                            Text(point.axisLabel)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .fixedSize()
                                .foregroundStyle(palette.secondary)
                        }
                    }
                }
            }
            .frame(height: 145)

            Text("Market estimates by each deadline. *Last trade: bid–ask gap exceeds 10¢; the trade may be old.")
                .font(.system(size: 9))
                .foregroundStyle(palette.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.reset.opacity(0.32), lineWidth: 0.8))
        )
    }

    private func providerRow(_ source: ForecastSource, provider: ResetProviderSnapshot?) -> some View {
        Button {
            if let url = source.url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(provider == nil ? palette.rule : palette.reset)
                    .frame(width: 6, height: 6)
                Text(source.displayName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondary)
                Spacer()
                if let score = provider?.score {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.rule)
                            Capsule().fill(palette.reset)
                                .frame(width: geometry.size.width * max(0, min(1, score / 100)))
                        }
                    }
                    .frame(width: 72, height: 2)
                }
                Text(provider?.score.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(provider == nil ? palette.tertiary : palette.primary.opacity(0.78))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(palette.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(source.hostLabel)")
    }

    private var updatedLabel: String {
        guard let date = detailProvider?.updatedAt else { return "LIVE" }
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "NOW" }
        if seconds < 3_600 { return "\(Int(seconds / 60))M AGO" }
        return "\(Int(seconds / 3_600))H AGO"
    }

    private static func timeZoneLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "z"
        return "YOUR TIME · \(formatter.string(from: date).uppercased())"
    }

    private func displayedTiming(for snapshot: ForecastSnapshot) -> (expectedAt: Date, confirmed: Bool)? {
        guard announcementActive else { return nil }
        return lifecycle.activeExpectedAt().map { ($0, true) }
    }

    private func effectiveHeadline(for snapshot: ForecastSnapshot) -> String? {
        if snapshot.announcement?.requiresApplicabilityConfirmation == true && !announcementActive {
            return "This reset does not apply to your account. Showing the selected calculator percentages."
        }
        return snapshot.headline
    }
}

struct TiboTweetsPopover: View {
    let tweets: [TiboTweet]
    @AppStorage(TiboTweetFilter.defaultsKey) private var filterRawValue = TiboTweetFilter.reset.rawValue

    private var selectedFilter: TiboTweetFilter {
        TiboTweetFilter(rawValue: filterRawValue) ?? .reset
    }

    private var visibleTweets: [TiboTweet] {
        selectedFilter == .all ? tweets : tweets.filter(\.isResetOriented)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(Color(hex: 0x58B9F3))
                Text("Tibo posts")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
                Spacer(minLength: 4)
                Text("\(visibleTweets.count) / \(tweets.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.38))
            }

            HStack(spacing: 2) {
                ForEach(TiboTweetFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeOut(duration: 0.14)) {
                            filterRawValue = filter.rawValue
                        }
                    } label: {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Text(filter.label.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(selectedFilter == filter ? Color(hex: 0x0D1115) : Color.white.opacity(0.48))
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 25)
                        .background(
                            Capsule()
                                .fill(selectedFilter == filter ? Color(hex: 0x58B9F3) : Color.clear)
                        )
                        // SwiftUI otherwise uses the Text glyphs as the hit
                        // region for a plain macOS button. Make the full half
                        // of the segmented control clickable.
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
            }
            .padding(2)
            .background(Capsule().fill(Color.white.opacity(0.07)))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if visibleTweets.isEmpty {
                        VStack(spacing: 7) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(Color(hex: 0x58B9F3).opacity(0.65))
                            Text("No reset-oriented posts found")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.55))
                            Text("Switch to All to see every recent post.")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.32))
                        }
                        .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        ForEach(visibleTweets) { tweet in
                            TweetRow(tweet: tweet)
                            if tweet.id != visibleTweets.last?.id {
                                Divider()
                                    .overlay(Color.white.opacity(0.08))
                            }
                        }
                    }
                }
            }
            // Give the popover a real viewport. A max-only ScrollView gets a
            // very small intrinsic height on macOS, which made the newest
            // post look truncated even though the text was still in memory.
            .frame(height: 420)
        }
        .padding(14)
        .frame(width: 370)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: 0x101419))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .preferredColorScheme(.dark)
    }
}

private struct TweetRow: View {
    let tweet: TiboTweet

    var body: some View {
        Button {
            if let url = tweet.url {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 9) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dateLabel)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x58B9F3).opacity(0.9))
                    Text(tweet.text)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let inReplyTo = tweet.inReplyTo, !inReplyTo.isEmpty {
                        HStack(alignment: .top, spacing: 5) {
                            Text("↳")
                                .foregroundStyle(Color.white.opacity(0.42))
                            Text(inReplyTo)
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.54))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 3)
                    }
                }
                Spacer(minLength: 2)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .padding(.top, 2)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dateLabel: String {
        guard let date = tweet.date else { return "TIBO" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
            .uppercased()
    }
}

struct NewTweetAlertPopover: View {
    let tweet: TiboTweet
    let onOpenFeed: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x58B9F3))
                Text("New Tibo post")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
                Spacer(minLength: 8)
                Text(ageLabel)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let reply = tweet.inReplyTo, !reply.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x58B9F3).opacity(0.75))
                            Text(reply)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.5))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.white.opacity(0.045))
                        )
                    }

                    Text(tweet.text)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // A max height alone lets a popover collapse the scroll view to a
            // single line. Size it from the post and reply first, then scroll
            // only when an unusually long thread would take over the screen.
            .frame(height: messageBodyHeight)

            HStack(spacing: 8) {
                Button("View all posts", action: onOpenFeed)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: 0x287EAD))
                Spacer(minLength: 6)
                Button("Clear", action: onClear)
                    .buttonStyle(.bordered)
            }
        }
        .padding(15)
        .frame(width: 380)
        .background(Color(hex: 0x101419))
        .preferredColorScheme(.dark)
    }

    private var messageBodyHeight: CGFloat {
        let tweetHeight = measuredHeight(
            tweet.text,
            font: .systemFont(ofSize: 12, weight: .medium),
            width: 350
        )

        let replyHeight: CGFloat
        if let reply = tweet.inReplyTo, !reply.isEmpty {
            replyHeight = measuredHeight(
                reply,
                font: .systemFont(ofSize: 10, weight: .medium),
                width: 306
            ) + 18
        } else {
            replyHeight = 0
        }

        let spacing = replyHeight > 0 ? CGFloat(8) : 0
        // SwiftUI's rounded fonts and the reply icon can add a little more
        // vertical leading than AppKit reports. Keep a small allowance so an
        // otherwise fully visible post does not get a pointless scrollbar.
        return min(500, max(54, ceil(tweetHeight + replyHeight + spacing + 28)))
    }

    private func measuredHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(bounds.height)
    }

    private var ageLabel: String {
        guard let date = tweet.date else { return "NEW" }
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "<1M AGO" }
        if seconds < 3_600 { return "\(Int(seconds / 60))M AGO" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))H AGO" }
        return "\(Int(seconds / 86_400))D AGO"
    }
}

private struct NewTweetBubble: View {
    let tweet: TiboTweet
    let compact: Bool
    let onOpen: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            HStack(spacing: 6) {
                Button(action: onOpen) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: 0x58B9F3))
                        Text(compact ? "NEW" : "NEW TIBO POST")
                            .font(.system(size: compact ? 7 : 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
                if compact {
                    Text(ageLabel)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .lineLimit(1)
                }
                Button(action: onClear) {
                    Image(systemName: "checkmark")
                        .font(.system(size: compact ? 8 : 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: compact ? 17 : 22, height: compact ? 17 : 22)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Clear new post")
            }

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 6) {
                Text(snippet)
                    .font(.system(size: compact ? 9 : 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .lineLimit(compact ? 1 : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if !compact {
                    HStack(spacing: 5) {
                        Text(ageLabel)
                        Text("·")
                        Text("TAP TO OPEN")
                    }
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, compact ? 7 : 11)
        .padding(.vertical, compact ? 6 : 9)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(hex: 0x101820).opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color(hex: 0x58B9F3).opacity(0.56), lineWidth: 1)
                )
        )
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 3) {
                Circle()
                    .fill(Color(hex: 0x101820))
                    .frame(width: 6, height: 6)
                    .overlay(Circle().stroke(Color(hex: 0x58B9F3).opacity(0.5), lineWidth: 0.7))
                Circle()
                    .fill(Color(hex: 0x101820))
                    .frame(width: 3, height: 3)
                    .overlay(Circle().stroke(Color(hex: 0x58B9F3).opacity(0.45), lineWidth: 0.6))
            }
            .offset(x: 16, y: 6)
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .accessibilityLabel("New Tibo post: \(snippet)")
        .help("Open the new Tibo reset post")
    }

    private var snippet: String {
        let normalized = tweet.text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 150 else { return normalized }
        return String(normalized.prefix(147)) + "…"
    }

    private var ageLabel: String {
        guard let date = tweet.date else { return "NEW" }
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "<1M AGO" }
        if seconds < 3_600 { return "\(Int(seconds / 60))M AGO" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))H AGO" }
        return "\(Int(seconds / 86_400))D AGO"
    }
}

private struct UsagePace {
    let title: String
    let detail: String
    let projectedExhaustion: Date?

    var estimatedRunout: String {
        guard let projectedExhaustion else {
            if title.hasPrefix("Collecting") { return "collecting" }
            if title.hasPrefix("Calibrating") { return "calibrating" }
            if title.hasPrefix("Usage flat") { return "steady" }
            if title == "No recent token burn" { return "idle" }
            if title == "No usage since reset" { return "unused" }
            return "—"
        }
        let remaining = projectedExhaustion.timeIntervalSince(Date())
        guard remaining > 60 else { return "now" }
        return Self.formatDuration(remaining)
    }

    static func calculate(
        usedPercent: Double?,
        windowStartDate: Date?,
        resetAt: Date?,
        usageHistory: [UsageCheckpoint],
        localTokensTotal: Int64?,
        localTokenPace: LocalTokenPaceSnapshot?,
        usageIntelligence: UsageIntelligenceSnapshot? = nil,
        rate: UsagePaceRate,
        now: Date = Date()
    ) -> UsagePace {
        guard let windowStartDate, let resetAt else {
            return UsagePace(
                title: "Usage pace unavailable",
                detail: "Waiting for the Codex usage window.",
                projectedExhaustion: nil
            )
        }

        let windowDuration = resetAt.timeIntervalSince(windowStartDate)
        guard windowDuration > 0 else {
            return UsagePace(
                title: "Usage pace unavailable",
                detail: "The reset window is not available yet.",
                projectedExhaustion: nil
            )
        }

        var readings = usageHistory
            .filter {
                abs($0.windowStart.timeIntervalSince(windowStartDate))
                    < UsageHistoryStore.windowTolerance
                    && $0.recordedAt >= windowStartDate
                    && $0.recordedAt <= now
            }
            .map {
                (
                    date: $0.recordedAt,
                    percent: max(0, min(100, $0.usedPercent)),
                    localTokens: $0.localTokensTotal,
                    quotaCost: $0.quotaWeightedUSD ?? $0.apiEquivalentUSD
                )
            }
            .sorted { $0.date < $1.date }

        if let usedPercent {
            readings.append(
                (
                    date: now,
                    percent: max(0, min(100, usedPercent)),
                    localTokens: localTokensTotal,
                    quotaCost: usageIntelligence?.quotaWeightedUSD
                )
            )
        }

        guard let current = readings.last, current.percent > 0 else {
            return UsagePace(
                title: "No usage since reset",
                detail: "The known reset baseline is 0%.",
                projectedExhaustion: nil
            )
        }

        let observedDuration: TimeInterval
        let observedBurn: Double
        if let interval = rate.interval {
            // Rolling rates use only locally captured checkpoints inside the
            // selected lookback. The reset-time 0% baseline remains visible
            // on the chart but does not influence these recent rates.
            let cutoff = current.date.addingTimeInterval(-interval)
            let trailingReadings = readings.filter { $0.date >= cutoff }
            // Treat the last checkpoint immediately before the boundary as
            // the value at that boundary. Without this, a percentage change
            // in the first five-minute bucket can disappear from the rate for
            // several minutes and leave a misleading flat/dash state.
            let boundaryReading = readings.last {
                $0.date <= cutoff && cutoff.timeIntervalSince($0.date) <= 10 * 60
            }
            if let periodStart = boundaryReading ?? trailingReadings.first,
               readings.filter({ $0.date >= periodStart.date }).count >= 2,
               current.date.timeIntervalSince(periodStart.date) >= min(5 * 60, interval) {
                observedDuration = current.date.timeIntervalSince(periodStart.date)
                observedBurn = current.percent - periodStart.percent
            } else if localTokenPace != nil {
                // Rollout logs provide a precise live rolling token count even
                // before two persisted quota checkpoints exist. This is what
                // makes the five-minute running pace useful immediately after
                // an app or Codex restart.
                observedDuration = min(
                    interval,
                    max(1, current.date.timeIntervalSince(windowStartDate))
                )
                observedBurn = 0
            } else {
                return UsagePace(
                    title: "Collecting " + rate.collectionLabel + " pace",
                    detail: "Waiting for the first rolling token sample.",
                    projectedExhaustion: nil
                )
            }
        } else {
            // Total is the intentional whole-window view: the known reset
            // point is 0%, so elapsed time and current usage define its rate.
            observedDuration = current.date.timeIntervalSince(windowStartDate)
            guard observedDuration >= 5 * 60 else {
                return UsagePace(
                    title: "Collecting total pace",
                    detail: "Need five minutes since the usage reset.",
                    projectedExhaustion: nil
                )
            }
            observedBurn = current.percent
        }

        let percentPerSecond: Double
        let basis: String
        if let interval = rate.interval {
            let elapsedSinceReset = max(5 * 60, current.date.timeIntervalSince(windowStartDate))
            let coveredDuration = max(1, min(interval, observedDuration, elapsedSinceReset))
            let tokenBurn: Int64? = {
                if rate == .fiveMinutes {
                    return localTokenPace?.fiveMinutes
                }
                return cappedObservedTokenBurn(
                    from: readings,
                    duration: coveredDuration,
                    endingAt: current.date
                )
            }()
            let costBurn = observedCostBurn(
                from: readings,
                duration: coveredDuration,
                endingAt: current.date
            )
            if let costBurn, costBurn > 0,
               let percentPerDollar = recentPercentPerDollar(from: readings) {
                percentPerSecond = (costBurn / coveredDuration) * percentPerDollar
                basis = coveredDuration < interval - 30
                    ? "Cost-implied " + formatDuration(coveredDuration) + " pace"
                    : "Cost-implied " + rate.basisLabel.lowercased()
            } else if let tokenBurn, tokenBurn > 0,
               let percentPerToken = recentPercentPerToken(from: readings) {
                // Every rolling rate uses a token burn aligned to the exact
                // covered duration and the same robust recent-step pricing.
                // The polluted whole-window token ratio is never consulted.
                percentPerSecond = (Double(tokenBurn) / coveredDuration) * percentPerToken
                basis = coveredDuration < interval - 30
                    ? "Observed " + formatDuration(coveredDuration) + " pace"
                    : "Recent-step " + rate.basisLabel.lowercased()
            } else if observedBurn > 0.01 {
                percentPerSecond = observedBurn / coveredDuration
                basis = coveredDuration < interval - 30
                    ? "Observed " + formatDuration(coveredDuration) + " pace"
                    : rate.basisLabel
            } else if let tokenBurn, tokenBurn > 0 {
                return UsagePace(
                    title: rate == .fiveMinutes ? "Calibrating running pace" : "Calibrating token pace",
                    detail: "Waiting for two recent quota-percent steps to price the rolling token burn.",
                    projectedExhaustion: nil
                )
            } else {
                return UsagePace(
                    title: "No recent token burn",
                    detail: "No usage moved during the available \(formatDuration(coveredDuration)) sample.",
                    projectedExhaustion: nil
                )
            }
        } else if let localTokenPace,
                  localTokenPace.sinceReset > 0,
                  current.percent > 0 {
            let elapsedSinceReset = max(5 * 60, current.date.timeIntervalSince(windowStartDate))
            percentPerSecond = current.percent / elapsedSinceReset
            basis = rate.basisLabel
        } else if observedBurn > 0.01 {
            percentPerSecond = observedBurn / observedDuration
            basis = rate.basisLabel
        } else {
            return UsagePace(
                title: "No recent token burn",
                detail: "Neither quota percentage nor local token count changed in " + rate.flatScope + ".",
                projectedExhaustion: nil
            )
        }

        let remainingPercent = max(0, 100 - current.percent)
        let projected = current.date.addingTimeInterval(remainingPercent / percentPerSecond)
        let difference = abs(projected.timeIntervalSince(resetAt))
        let formattedDifference = formatDuration(difference)
        let tolerance = max(30 * 60, windowDuration * 0.025)

        if projected < resetAt.addingTimeInterval(-tolerance) {
            return UsagePace(
                title: "On pace to run out too early",
                detail: "\(basis) runs out about \(formattedDifference) early.",
                projectedExhaustion: projected
            )
        }
        if projected > resetAt.addingTimeInterval(tolerance) {
            return UsagePace(
                title: "On pace to run out too late",
                detail: "\(basis) runs out about \(formattedDifference) late.",
                projectedExhaustion: projected
            )
        }
        return UsagePace(
            title: "On pace to run out on time",
            detail: "\(basis) lands within \(formattedDifference) of the reset.",
            projectedExhaustion: projected
        )
    }

    private static func cappedObservedTokenBurn(
        from readings: [(date: Date, percent: Double, localTokens: Int64?, quotaCost: Double?)],
        duration: TimeInterval,
        endingAt end: Date
    ) -> Int64? {
        let cutoff = end.addingTimeInterval(-duration - 1)
        let tokenReadings = readings.filter { $0.date >= cutoff }.compactMap {
            reading -> (date: Date, tokens: Int64)? in
            guard let tokens = reading.localTokens else { return nil }
            return (reading.date, tokens)
        }.sorted { $0.date < $1.date }
        guard tokenReadings.count >= 2 else { return nil }
        let deltas = zip(tokenReadings, tokenReadings.dropFirst()).compactMap { previous, current -> Int64? in
            let delta = current.tokens - previous.tokens
            return delta > 0 ? delta : nil
        }
        guard !deltas.isEmpty else { return 0 }
        let sorted = deltas.sorted()
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2)
            ? sorted[middle - 1] / 2 + sorted[middle] / 2
            : sorted[middle]
        let multiplied = median.multipliedReportingOverflow(by: 4)
        let cap = multiplied.overflow ? Int64.max : max(1, multiplied.partialValue)
        return deltas.reduce(Int64(0)) { total, delta in
            let addition = min(delta, cap)
            let sum = total.addingReportingOverflow(addition)
            return sum.overflow ? Int64.max : sum.partialValue
        }
    }

    private static func recentPercentPerToken(
        from readings: [(date: Date, percent: Double, localTokens: Int64?, quotaCost: Double?)]
    ) -> Double? {
        let tokenReadings = readings.compactMap { reading -> (percent: Double, tokens: Int64)? in
            guard let tokens = reading.localTokens else { return nil }
            return (reading.percent, tokens)
        }
        guard var milestone = tokenReadings.first else { return nil }
        var calibrations: [Double] = []
        for reading in tokenReadings.dropFirst() {
            let percentDelta = reading.percent - milestone.percent
            let tokenDelta = reading.tokens - milestone.tokens
            guard percentDelta >= 0.5, tokenDelta > 0 else { continue }
            calibrations.append(percentDelta / Double(tokenDelta))
            milestone = reading
        }

        // Require at least two completed steps and use at most the latest five.
        // Their median rejects a single cached-token or database-total spike.
        let recent = Array(calibrations.suffix(5)).sorted()
        guard recent.count >= 2 else { return nil }
        let middle = recent.count / 2
        let median = recent.count.isMultiple(of: 2)
            ? (recent[middle - 1] + recent[middle]) / 2
            : recent[middle]
        guard median.isFinite, median > 0 else { return nil }
        return median
    }

    private static func observedCostBurn(
        from readings: [(date: Date, percent: Double, localTokens: Int64?, quotaCost: Double?)],
        duration: TimeInterval,
        endingAt end: Date
    ) -> Double? {
        let cutoff = end.addingTimeInterval(-duration - 1)
        let values = readings.filter { $0.date >= cutoff }.compactMap {
            reading -> (date: Date, cost: Double)? in
            guard let cost = reading.quotaCost, cost.isFinite, cost >= 0 else { return nil }
            return (reading.date, cost)
        }.sorted { $0.date < $1.date }
        guard let first = values.first, let last = values.last, last.date > first.date else { return nil }
        return max(0, last.cost - first.cost)
    }

    private static func recentPercentPerDollar(
        from readings: [(date: Date, percent: Double, localTokens: Int64?, quotaCost: Double?)]
    ) -> Double? {
        let costReadings = readings.compactMap { reading -> (percent: Double, cost: Double)? in
            guard let cost = reading.quotaCost, cost.isFinite, cost >= 0 else { return nil }
            return (reading.percent, cost)
        }
        guard var milestone = costReadings.first else { return nil }
        var calibrations: [Double] = []
        for reading in costReadings.dropFirst() {
            let percentDelta = reading.percent - milestone.percent
            let costDelta = reading.cost - milestone.cost
            guard percentDelta >= 0.5, costDelta > 0.000_001 else { continue }
            calibrations.append(percentDelta / costDelta)
            milestone = reading
        }
        let recent = Array(calibrations.suffix(5)).sorted()
        guard recent.count >= 2 else { return nil }
        let middle = recent.count / 2
        let median = recent.count.isMultiple(of: 2)
            ? (recent[middle - 1] + recent[middle]) / 2
            : recent[middle]
        return median.isFinite && median > 0 ? median : nil
    }

    private static func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(1, Int(interval / 60))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        var pieces: [String] = []
        if days > 0 { pieces.append("\(days)d") }
        if hours > 0 || days > 0 { pieces.append("\(hours)h") }
        pieces.append("\(minutes)m")
        return pieces.joined(separator: " ")
    }
}

struct UsageChartPopover: View {
    let usageDays: [UsageDay]
    let usageHistory: [UsageCheckpoint]
    let weeklyTokens: Int64?
    let localTokensTotal: Int64?
    let localTokenPace: LocalTokenPaceSnapshot?
    let usageIntelligence: UsageIntelligenceSnapshot?
    let secondaryQuota: SecondaryQuotaSnapshot?
    let quotaInventory: [CodexQuotaWindow]
    let creditSummary: CodexCreditSummary?
    let resetCredits: [CodexResetCredit]
    let activeTasks: [CodexTaskSnapshot]
    let weeklyArchives: [WeeklyUsageArchive]
    let usedPercent: Double?
    let windowStartDate: Date?
    let resetAt: Date?
    let paceRate: UsagePaceRate
    let theme: WidgetTheme
    let onRebuildIntelligence: () -> Void
    let onPurgeUsageData: () -> Void
    @State private var hoveredPoint: UsageHoverPoint?
    @State private var chartRange = UsageChartRange.window
    @State private var showingIntelligence = false
    @State private var showingQuotaDetails = false
    @State private var showingHistory = false
    @State private var weekOffset = 0

    private var palette: PopoverPalette { theme.popoverPalette }

    private var pace: UsagePace {
        UsagePace.calculate(
            usedPercent: usedPercent,
            windowStartDate: windowStartDate,
            resetAt: resetAt,
            usageHistory: usageHistory,
            localTokensTotal: localTokensTotal,
            localTokenPace: localTokenPace,
            usageIntelligence: usageIntelligence,
            rate: paceRate
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if weekOffset > 0 {
                weekNavigator
            }

            if let archive = selectedArchive {
                ArchivedUsageWeekView(archive: archive)
            } else {
            HStack(spacing: 8) {
                Circle()
                    .fill(palette.pace)
                    .frame(width: 7, height: 7)
                Text("CODEX / " + paceRate.compactLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(palette.tertiary)
                Spacer()
                if let intelligence = usageIntelligence {
                    Text(intelligence.backfillComplete
                        ? "\(Int((intelligence.pricingCoverage * 100).rounded()))% PRICED"
                        : "INDEXING")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.tertiary)
                }
            }

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(shortPaceTitle)
                        .font(.system(size: 19, weight: .semibold, design: palette.numberDesign))
                        .foregroundStyle(statusColor)
                    Text(pace.detail)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.tertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(pace.estimatedRunout.uppercased())
                        .font(.system(size: 27, weight: .light, design: palette.numberDesign))
                        .monospacedDigit()
                        .foregroundStyle(palette.primary.opacity(0.94))
                    Text("TO EMPTY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(palette.tertiary)
                }
            }

            statusTrack

            if let intelligence = usageIntelligence {
                intelligenceStrip(intelligence)
            }

            HStack(spacing: 0) {
                Button { showingQuotaDetails = true } label: {
                    compactInsight(
                        icon: "gauge.with.dots.needle.67percent",
                        title: "ALLOWANCES",
                        value: quotaInventory.isEmpty ? "GENERAL" : "\(quotaInventory.count) LIVE"
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingQuotaDetails, arrowEdge: .top) {
                    CodexAllowancePanel(
                        windows: quotaInventory,
                        credits: creditSummary,
                        resetCredits: resetCredits,
                        tasks: activeTasks
                    )
                }

                Divider().overlay(palette.rule).padding(.vertical, 8)

                Button { showingHistory = true } label: {
                    compactInsight(
                        icon: "square.grid.3x3.fill",
                        title: "HISTORY",
                        value: weeklyArchives.isEmpty ? "THIS WEEK" : "\(weeklyArchives.count + 1) WEEKS"
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingHistory, arrowEdge: .top) {
                    UsageHistoryOverview(
                        currentHistory: usageHistory,
                        currentWindowStart: windowStartDate,
                        archives: weeklyArchives
                    )
                }

                Divider().overlay(palette.rule).padding(.vertical, 8)
                paceMetric("BURN", value: localTokenPace.map { formatTokens($0.tokens(for: paceRate)).replacingOccurrences(of: " TOKENS", with: "") } ?? "—")
                paceMetric("USED", value: usedPercent.map { "\(Int($0.rounded()))%" } ?? "—")
                paceMetric("SAMPLE", value: UsageHistoryStore.sampleIntervalDescription().uppercased())
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.rule, lineWidth: 0.7))
            )

            HStack(spacing: 14) {
                legend(color: palette.pace, label: "QUOTA + TOKENS")
                if usageIntelligence?.costTimeline.isEmpty == false {
                    legend(color: palette.reset, label: "API COST")
                }
                legend(color: palette.secondary.opacity(0.6), label: "IDEAL", dotted: true)
                Spacer()
                Text("\(savedPointCount) SAVED · DISK")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.tertiary)
            }

            if hoveredPoint != nil {
                UsageHoverReadout(point: hoveredPoint, theme: theme)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            UsageChart(
                usageDays: usageDays,
                usageHistory: usageHistory,
                weeklyTokens: weeklyTokens,
                localTokensTotal: localTokensTotal,
                localTokenPace: localTokenPace,
                usedPercent: usedPercent,
                windowStartDate: windowStartDate,
                resetAt: resetAt,
                usageIntelligence: usageIntelligence,
                theme: theme,
                range: $chartRange,
                hoveredPoint: $hoveredPoint
            )
            .frame(height: 186)

            rangeSelector
            }
        }
        .padding(18)
        .frame(width: 538)
        .background(
            RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous)
                .fill(palette.background)
                .overlay(
                    RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous)
                        .stroke(palette.pace.opacity(0.25), lineWidth: 1)
                )
        )
        .preferredColorScheme(theme.isLight ? .light : .dark)
    }

    private var selectedArchive: WeeklyUsageArchive? {
        guard weekOffset > 0, weeklyArchives.indices.contains(weekOffset - 1) else { return nil }
        return weeklyArchives[weekOffset - 1]
    }

    private func compactInsight(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.pace)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(palette.tertiary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.primary.opacity(0.82))
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(palette.tertiary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(width: 126, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }

    private var weekNavigator: some View {
        HStack(spacing: 8) {
            Button {
                weekOffset = min(weeklyArchives.count, weekOffset + 1)
                hoveredPoint = nil
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(weekOffset >= weeklyArchives.count)

            Text(selectedArchive.map {
                $0.windowStart.formatted(.dateTime.month(.abbreviated).day())
                    + " – "
                    + $0.resetAt.formatted(.dateTime.month(.abbreviated).day())
            } ?? "THIS WEEK")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(palette.secondary.opacity(0.8))
                .frame(maxWidth: .infinity)

            Button {
                weekOffset = max(0, weekOffset - 1)
                hoveredPoint = nil
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(weekOffset == 0)
        }
        .foregroundStyle(palette.secondary)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
    }

    private var statusColor: Color {
        pace.title.contains("early") ? palette.billing : palette.pace
    }

    private var statusTrack: some View {
        GeometryReader { geometry in
            let progress = max(0.08, min(0.92, (usedPercent ?? 0) / 100))
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(statusColor.opacity(0.88))
                    .frame(height: 1)
                Circle()
                    .fill(palette.background)
                    .overlay(Circle().stroke(statusColor, lineWidth: 1.4))
                    .frame(width: 9, height: 9)
                    .offset(x: max(0, geometry.size.width * progress - 4.5))
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private var rangeSelector: some View {
        HStack(spacing: 0) {
            Button {
                weekOffset = weekOffset == 0 ? min(1, weeklyArchives.count) : 0
                hoveredPoint = nil
            } label: {
                Image(systemName: "safari")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 42, height: 30)
                    .foregroundStyle(palette.secondary)
            }
            .buttonStyle(.plain)
            .disabled(weeklyArchives.isEmpty)
            .help(weekOffset == 0 ? "Show previous week" : "Return to this week")

            ForEach(UsageChartRange.allCases) { range in
                Divider().overlay(palette.rule).padding(.vertical, 6)
                Button {
                    hoveredPoint = nil
                    chartRange = range
                } label: {
                    Text(range.label)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .foregroundStyle(chartRange == range ? palette.pace : palette.tertiary)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(chartRange == range ? palette.pace : Color.clear)
                                .frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(palette.rule).frame(height: 1) }
        .help("Choose a range, pinch to zoom, or double-click the chart to reset")
    }

    private var shortPaceTitle: String {
        if pace.title.contains("too early") { return "Running hot" }
        if pace.title.contains("too late") { return "Room to spare" }
        if pace.title.contains("on time") { return "On schedule" }
        return pace.title
    }

    private var savedPointCount: Int {
        guard let windowStartDate else { return 0 }
        return usageHistory.filter {
            abs($0.windowStart.timeIntervalSince(windowStartDate))
                < UsageHistoryStore.windowTolerance
        }.count
    }

    @ViewBuilder
    private func intelligenceStrip(_ intelligence: UsageIntelligenceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(palette.rule, lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: min(1, max(0.08, intelligence.pricingCoverage)))
                        .stroke(palette.pace, style: StrokeStyle(lineWidth: 5, dash: [3, 2]))
                        .rotationEffect(.degrees(-90))
                    Text("$")
                        .font(.system(size: 19, weight: .medium, design: palette.numberDesign))
                        .foregroundStyle(palette.primary)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 1) {
                    Text("API VALUE")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(palette.pace.opacity(0.86))
                    Text(String(format: "$%.2f%@", intelligence.apiEquivalentUSD, intelligence.backfillComplete ? "" : "+"))
                        .font(.system(size: 24, weight: .medium, design: palette.numberDesign))
                        .monospacedDigit()
                        .foregroundStyle(palette.primary.opacity(0.94))
                }

                Spacer(minLength: 4)
                intelligenceMetric("TOKENS", compactTokens(intelligence.tokens.total))
                intelligenceMetric("CACHE", percent(cacheShare(intelligence)))
                intelligenceMetric("FAST", percent(intelligence.fastShare))

                Button { showingIntelligence = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.tertiary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(palette.raisedSurface))
                }
                .buttonStyle(.plain)
                .help("Usage details and data controls")
                .popover(isPresented: $showingIntelligence, arrowEdge: .top) {
                    UsageIntelligencePanel(
                        snapshot: intelligence,
                        secondaryQuota: secondaryQuota,
                        onRebuild: onRebuildIntelligence,
                        onPurge: onPurgeUsageData
                    )
                }
            }

            HStack(spacing: 8) {
                if let model = intelligence.modelSummaries.first {
                    Image(systemName: "cpu")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(palette.pace.opacity(0.8))
                    Text(readableModel(model.model))
                    Text("\(percent(modelShare(model, intelligence))) · \(String(format: "$%.0f", model.apiEquivalentUSD))")
                        .foregroundStyle(palette.secondary)
                }
                if let secondaryQuota {
                    Spacer()
                    Text("SHORT \(Int(secondaryQuota.usedPercent.rounded()))%")
                    Text(relativeReset(secondaryQuota.resetAt))
                        .foregroundStyle(palette.tertiary)
                }
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(palette.secondary)

            gpt6UsageLine(intelligence)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(palette.surface)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(palette.pace.opacity(0.86))
                        .frame(width: 2)
                        .padding(.vertical, 8)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("API equivalent \(String(format: "$%.2f", intelligence.apiEquivalentUSD)), \(percent(cacheShare(intelligence))) cache hit, \(percent(intelligence.fastShare)) fast mode")
    }

    private func intelligenceMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.tertiary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(palette.primary.opacity(0.84))
        }
    }

    private func cacheShare(_ intelligence: UsageIntelligenceSnapshot) -> Double {
        let input = intelligence.tokens.uncachedInput
            + intelligence.tokens.cachedInput
            + intelligence.tokens.cacheWriteInput
        guard input > 0 else { return 0 }
        return Double(intelligence.tokens.cachedInput) / Double(input)
    }

    private func modelShare(_ model: UsageModelSummary, _ intelligence: UsageIntelligenceSnapshot) -> Double {
        guard intelligence.tokens.total > 0 else { return 0 }
        return Double(model.tokens) / Double(intelligence.tokens.total)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((max(0, min(1, value)) * 100).rounded()))%"
    }

    private func compactTokens(_ tokens: Int64) -> String {
        let value = Double(max(0, tokens))
        if value >= 1_000_000_000 { return String(format: "%.2fB", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
        return "\(tokens)"
    }

    private func readableModel(_ model: String) -> String {
        model
            .replacingOccurrences(of: "gpt-", with: "GPT ")
            .replacingOccurrences(of: "-", with: " ")
            .uppercased()
    }

    @ViewBuilder
    private func gpt6UsageLine(_ intelligence: UsageIntelligenceSnapshot) -> some View {
        let models = intelligence.modelSummaries
            .filter { $0.gpt6CodexCredits != nil }
            .map { readableModel($0.model) }
        if let credits = intelligence.gpt6CodexCredits, !models.isEmpty {
            HStack(spacing: 6) {
                Text(models.joined(separator: " / "))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(palette.secondary)
                Spacer(minLength: 4)
                Text(String(format: "Codex %.1f cr", credits))
                    .monospacedDigit()
                    .foregroundStyle(palette.pace)
            }
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("GPT-6 models: \(models.joined(separator: ", ")). Estimated Codex credit usage \(String(format: "%.1f", credits)) credits.")
        }
    }

    private func relativeReset(_ date: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSinceNow / 60))
        if minutes >= 1_440 { return "\(minutes / 1_440)D" }
        if minutes >= 60 { return "\(minutes / 60)H" }
        return "\(minutes)M"
    }

    private func paceMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.primary.opacity(0.88))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        // The two insight buttons have fixed widths. Let these three metrics
        // divide every remaining point evenly so the row has matching left
        // and right breathing room instead of bunching beside History.
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 9)
    }

    private func formatTokens(_ tokens: Int64) -> String {
        let value = Double(max(0, tokens))
        if value >= 1_000_000_000 { return String(format: "%.2fB TOKENS", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM TOKENS", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK TOKENS", value / 1_000) }
        return "\(tokens) TOKENS"
    }

    @ViewBuilder
    private func legend(color: Color, label: String, dotted: Bool = false) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(color)
                .frame(width: 14, height: dotted ? 1 : 3)
                .overlay {
                    if dotted {
                        Capsule()
                            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    }
                }
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.tertiary)
        }
    }
}

private struct UsageHoverPoint: Equatable {
    let date: Date
    let actualPercent: Double
    let idealPercent: Double
    let tokens: Int64
    let tokenLabel: String
    let sourceLabel: String
    let apiEquivalentUSD: Double?
    let isCurrent: Bool
}

private struct UsageHoverReadout: View {
    let point: UsageHoverPoint?
    let theme: WidgetTheme

    private var palette: PopoverPalette { theme.popoverPalette }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(point.map { $0.isCurrent ? "CURRENT WINDOW" : dateLabel($0.date) } ?? "HOVER FOR DAILY DETAIL")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.tertiary)
                Text(point.map { $0.sourceLabel } ?? "Move across the chart · saved every \(UsageHistoryStore.sampleIntervalDescription())")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondary)
            }

            Spacer(minLength: 4)

            if let point {
                HStack(spacing: 10) {
                    metric(label: "USED", value: "\(Int(point.actualPercent.rounded()))%", color: palette.pace)
                    metric(label: "IDEAL", value: "\(Int(point.idealPercent.rounded()))%", color: palette.secondary)
                    metric(
                        label: point.tokenLabel,
                        value: formatTokens(point.tokens),
                        color: palette.reset
                    )
                    if let apiEquivalentUSD = point.apiEquivalentUSD {
                        metric(
                            label: "API",
                            value: String(format: "$%.2f", apiEquivalentUSD),
                            color: palette.reset
                        )
                    }
                }
            } else {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.tertiary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.surface)
        )
    }

    @ViewBuilder
    private func metric(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.tertiary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private func dateLabel(_ date: Date) -> String {
        date.formatted(
            .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                .hour().minute()
        )
            .uppercased()
    }

    private func formatTokens(_ tokens: Int64) -> String {
        let value = Double(max(0, tokens))
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return "\(Int(value))"
    }
}

private struct CodexAllowancePanel: View {
    let windows: [CodexQuotaWindow]
    let credits: CodexCreditSummary?
    let resetCredits: [CodexResetCredit]
    let tasks: [CodexTaskSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("Codex allowances", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                if let credits {
                    Text(credits.unlimited ? "UNLIMITED" : credits.balance.map { "\($0) CREDITS" } ?? (credits.hasCredits ? "CREDITS" : "NO CREDITS"))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.44))
                }
            }

            if windows.isEmpty {
                Text("Codex returned only the general allowance this refresh.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
            } else {
                ForEach(windows) { window in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(window.label.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                Text(window.scope + " · resets " + relative(window.resetAt))
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.42))
                            }
                            Spacer()
                            Text("\(Int(window.usedPercent.rounded()))%")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.07))
                                Capsule().fill(Color(hex: 0x7EE6AE))
                                    .frame(width: geometry.size.width * max(0, min(1, window.usedPercent / 100)))
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }

            if !resetCredits.isEmpty {
                Divider().overlay(Color.white.opacity(0.08))
                ForEach(resetCredits.prefix(3)) { credit in
                    HStack(spacing: 9) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .foregroundStyle(Color(hex: 0x58B9F3))
                        VStack(alignment: .leading, spacing: 2) {
                            Text((credit.description ?? credit.resetType).uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                            Text(credit.expiresAt.map { "Expires " + relative($0) } ?? credit.status)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.42))
                        }
                        Spacer()
                        Text(credit.status.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(hex: 0x58B9F3))
                    }
                }
            }

            if !tasks.isEmpty {
                Divider().overlay(Color.white.opacity(0.08))
                Text("LIVE TASKS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Color.white.opacity(0.34))
                ForEach(tasks.prefix(4)) { task in
                    HStack(spacing: 9) {
                        Circle().fill(Color(hex: 0x7EE6AE)).frame(width: 6, height: 6)
                        Text(task.name).lineLimit(1)
                        Spacer()
                        Text(task.state.replacingOccurrences(of: "camelCase", with: " ").uppercased())
                            .foregroundStyle(Color.white.opacity(0.42))
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
            }
        }
        .padding(18)
        .frame(width: 360)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: 0x101419)))
        .preferredColorScheme(.dark)
    }

    private func relative(_ date: Date) -> String {
        if date <= Date() { return "now" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

private struct UsageHistoryOverview: View {
    private struct DayBurn: Identifiable {
        let date: Date
        let percent: Double
        var id: Date { date }
    }

    let currentHistory: [UsageCheckpoint]
    let currentWindowStart: Date?
    let archives: [WeeklyUsageArchive]

    private var burns: [DayBurn] {
        var result: [DayBurn] = []
        for archive in archives {
            let values = [(archive.windowStart, 0.0)] + archive.points.map { ($0.date, $0.usedPercent) }
            result.append(contentsOf: daily(values))
        }
        if let currentWindowStart {
            let values = [(currentWindowStart, 0.0)] + currentHistory
                .filter { abs($0.windowStart.timeIntervalSince(currentWindowStart)) < UsageHistoryStore.windowTolerance }
                .map { ($0.recordedAt, $0.usedPercent) }
            result.append(contentsOf: daily(values))
        }
        var byDate: [Date: Double] = [:]
        for burn in result { byDate[burn.date] = max(byDate[burn.date] ?? 0, burn.percent) }
        return byDate.map(DayBurn.init).sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("USAGE RHYTHM")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(Color.white.opacity(0.36))
                    Text("Last 26 weeks")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(peak.map { "\(Int($0.percent.rounded()))%" } ?? "—")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(hex: 0x7EE6AE))
                    Text("PEAK DAY")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.34))
                }
            }

            Canvas { context, size in
                let calendar = Calendar.current
                let end = calendar.startOfDay(for: Date())
                let start = calendar.date(byAdding: .day, value: -(26 * 7 - 1), to: end) ?? end
                let cell = min(13, (size.width - 25 * 4) / 26)
                let gap: CGFloat = 4
                let lookup = Dictionary(uniqueKeysWithValues: burns.map { (calendar.startOfDay(for: $0.date), $0.percent) })
                let maxBurn = max(1, burns.map(\.percent).max() ?? 1)
                for offset in 0..<(26 * 7) {
                    guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                    let weekday = calendar.component(.weekday, from: date)
                    let row = (weekday + 5) % 7
                    let column = offset / 7
                    let intensity = min(1, (lookup[date] ?? 0) / maxBurn)
                    let rect = CGRect(x: CGFloat(column) * (cell + gap), y: CGFloat(row) * (cell + gap), width: cell, height: cell)
                    let color = intensity > 0 ? Color(hex: 0x7EE6AE).opacity(0.18 + intensity * 0.82) : Color.white.opacity(0.045)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2.5), with: .color(color))
                }
            }
            .frame(height: 7 * 17)

            HStack(spacing: 0) {
                historyMetric("ACTIVE DAYS", "\(burns.filter { $0.percent > 0.05 }.count)")
                historyMetric("STREAK", "\(currentStreak)d")
                historyMetric("WEEKS SAVED", "\(archives.count)")
            }
        }
        .padding(18)
        .frame(width: 430)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: 0x101419)))
        .preferredColorScheme(.dark)
    }

    private var peak: DayBurn? { burns.max { $0.percent < $1.percent } }

    private var currentStreak: Int {
        let calendar = Calendar.current
        let active = Set(burns.filter { $0.percent > 0.05 }.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: Date())
        if !active.contains(day), let yesterday = calendar.date(byAdding: .day, value: -1, to: day), active.contains(yesterday) { day = yesterday }
        var count = 0
        while active.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    private func daily(_ values: [(Date, Double)]) -> [DayBurn] {
        let calendar = Calendar.current
        let sorted = values.sorted { $0.0 < $1.0 }
        var first: [Date: Double] = [:], last: [Date: Double] = [:]
        for (date, percent) in sorted {
            let day = calendar.startOfDay(for: date)
            if first[day] == nil { first[day] = percent }
            last[day] = percent
        }
        return last.map { day, value in DayBurn(date: day, percent: max(0, value - (first[day] ?? value))) }
    }

    private func historyMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundStyle(Color.white.opacity(0.34))
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Color.white.opacity(0.86))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UsageChartSample {
    let date: Date
    let actualFraction: Double
    let tokens: Int64
    let tokenLabel: String
    let sourceLabel: String
    let isCurrent: Bool
    let isBaseline: Bool
}

private struct UsageTokenPoint {
    let date: Date
    let officialPercent: Double
    let localTokensTotal: Int64?
    let rollingFiveMinuteTokens: Int64?
    let isCurrent: Bool
}

private enum UsageChartRange: String, CaseIterable, Identifiable {
    case window
    case twentyFourHours
    case twelveHours
    case oneHour

    var id: String { rawValue }

    var label: String {
        switch self {
        case .window: return "WINDOW"
        case .twentyFourHours: return "24H"
        case .twelveHours: return "12H"
        case .oneHour: return "1H"
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .window: return nil
        case .twentyFourHours: return 24 * 60 * 60
        case .twelveHours: return 12 * 60 * 60
        case .oneHour: return 60 * 60
        }
    }

    var zoomedIn: UsageChartRange {
        switch self {
        case .window: return .twentyFourHours
        case .twentyFourHours: return .twelveHours
        case .twelveHours, .oneHour: return .oneHour
        }
    }

    var zoomedOut: UsageChartRange {
        switch self {
        case .window, .twentyFourHours: return .window
        case .twelveHours: return .twentyFourHours
        case .oneHour: return .twelveHours
        }
    }
}

private struct UsageChart: View {
    let usageDays: [UsageDay]
    let usageHistory: [UsageCheckpoint]
    let weeklyTokens: Int64?
    let localTokensTotal: Int64?
    let localTokenPace: LocalTokenPaceSnapshot?
    let usedPercent: Double?
    let windowStartDate: Date?
    let resetAt: Date?
    let usageIntelligence: UsageIntelligenceSnapshot?
    let theme: WidgetTheme
    @Binding var range: UsageChartRange
    @Binding var hoveredPoint: UsageHoverPoint?

    private var palette: PopoverPalette { theme.popoverPalette }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                draw(context: &context, size: size)
            }
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    hoveredPoint = hoverPoint(at: location, size: geometry.size)
                case .ended:
                    hoveredPoint = nil
                }
            }
            .onTapGesture(count: 2) {
                hoveredPoint = nil
                range = .window
            }
            .gesture(
                MagnificationGesture().onEnded { amount in
                    hoveredPoint = nil
                    if amount > 1.08 {
                        range = range.zoomedIn
                    } else if amount < 0.92 {
                        range = range.zoomedOut
                    }
                }
            )
        }
        .accessibilityLabel("Weekly Codex usage chart")
        .accessibilityValue("Solid line is observed usage; white dotted line is ideal pacing. Pinch to zoom and double-click to show the full window.")
        .onDisappear { hoveredPoint = nil }
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        guard let start = windowStartDate, let reset = resetAt else {
            drawUnavailable(context: &context, size: size)
            return
        }

        let plot = plotRect(for: size)
        let totalDuration = max(1, reset.timeIntervalSince(start))
        let domain = visibleDomain(start: start, reset: reset)
        let domainDuration = max(1, domain.end.timeIntervalSince(domain.start))
        let samples = visibleSamples(
            chartSamples(start: start, reset: reset),
            from: domain.start,
            through: domain.end
        )
        let idealStart = idealFraction(at: domain.start, windowStart: start, duration: totalDuration)
        let idealEnd = idealFraction(at: domain.end, windowStart: start, duration: totalDuration)
        let costSamples = visibleCostSamples(from: domain.start, through: domain.end)
        let yDomain = verticalDomain(
            samples: samples,
            costFractions: costSamples.map(\.fraction),
            idealStart: idealStart,
            idealEnd: idealEnd
        )

        for step in 0...4 {
            let fraction = CGFloat(step) / 4
            let y = plot.maxY - plot.height * fraction
            let value = yDomain.lowerBound
                + (yDomain.upperBound - yDomain.lowerBound) * Double(fraction)
            var grid = Path()
            grid.move(to: CGPoint(x: plot.minX, y: y))
            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(
                grid,
                with: .color(palette.rule.opacity(step == 0 ? 1 : 0.65)),
                style: StrokeStyle(lineWidth: step == 0 ? 1 : 0.7)
            )
            context.draw(
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(palette.tertiary),
                at: CGPoint(x: plot.minX - 6, y: y),
                anchor: .trailing
            )
        }

        let ideal = Path { path in
            path.move(to: CGPoint(
                x: plot.minX,
                y: yPosition(idealStart, domain: yDomain, plot: plot)
            ))
            path.addLine(to: CGPoint(
                x: plot.maxX,
                y: yPosition(idealEnd, domain: yDomain, plot: plot)
            ))
        }
        context.stroke(
            ideal,
            with: .color(palette.secondary.opacity(0.72)),
            style: StrokeStyle(lineWidth: 1.4, dash: [3, 3])
        )

        let costPoints = costSamples.map { sample in
            point(
                for: sample.date,
                value: sample.fraction,
                start: domain.start,
                duration: domainDuration,
                yDomain: yDomain,
                plot: plot
            )
        }
        if costPoints.count > 1 {
            var costPath = Path()
            costPath.move(to: costPoints[0])
            for point in costPoints.dropFirst() { costPath.addLine(to: point) }
            context.stroke(
                costPath,
                with: .color(palette.reset.opacity(0.72)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }

        let baselineSample = samples.first(where: { $0.isBaseline })
        let observedSamples = samples.filter { !$0.isBaseline }
        let observedPoints = observedSamples.map { sample in
            point(
                for: sample.date,
                value: sample.actualFraction,
                start: domain.start,
                duration: domainDuration,
                yDomain: yDomain,
                plot: plot
            )
        }

        if range == .window, let baselineSample, let firstObserved = observedPoints.first {
            let baseline = point(
                for: baselineSample.date,
                value: baselineSample.actualFraction,
                start: domain.start,
                duration: domainDuration,
                yDomain: yDomain,
                plot: plot
            )
            var gap = Path()
            gap.move(to: baseline)
            gap.addLine(to: firstObserved)
            context.stroke(
                gap,
                with: .color(palette.pace.opacity(0.28)),
                style: StrokeStyle(lineWidth: 1.2, dash: [2, 5])
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: baseline.x - 3, y: baseline.y - 3, width: 6, height: 6)),
                with: .color(palette.pace.opacity(0.72)),
                style: StrokeStyle(lineWidth: 1.2)
            )
        }

        if observedPoints.count > 1 {
            var actual = Path()
            actual.move(to: observedPoints[0])
            for point in observedPoints.dropFirst() {
                actual.addLine(to: point)
            }
            context.stroke(
                actual,
                with: .color(palette.pace),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
            )
        }

        if let current = observedPoints.last {
            context.fill(
                Path(ellipseIn: CGRect(x: current.x - 3.5, y: current.y - 3.5, width: 7, height: 7)),
                with: .color(palette.pace)
            )
        }

        if let hoveredPoint {
            let hoverX = plot.minX + plot.width * xFraction(
                for: hoveredPoint.date,
                start: domain.start,
                duration: domainDuration
            )
            var guide = Path()
            guide.move(to: CGPoint(x: hoverX, y: plot.minY))
            guide.addLine(to: CGPoint(x: hoverX, y: plot.maxY))
            context.stroke(
                guide,
                with: .color(palette.reset.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1, dash: [2, 3])
            )

            let actualY = yPosition(hoveredPoint.actualPercent / 100, domain: yDomain, plot: plot)
            let idealY = yPosition(hoveredPoint.idealPercent / 100, domain: yDomain, plot: plot)
            context.fill(
                Path(ellipseIn: CGRect(x: hoverX - 4, y: actualY - 4, width: 8, height: 8)),
                with: .color(palette.pace)
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: hoverX - 4, y: idealY - 4, width: 8, height: 8)),
                with: .color(palette.secondary),
                style: StrokeStyle(lineWidth: 1, dash: [2, 2])
            )
        }

        context.draw(
            Text(axisLabel(domain.start))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(palette.tertiary),
            at: CGPoint(x: plot.minX, y: plot.maxY + 12),
            anchor: .leading
        )
        context.draw(
            Text(axisLabel(domain.end))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(palette.tertiary),
            at: CGPoint(x: plot.maxX, y: plot.maxY + 12),
            anchor: .trailing
        )
    }

    private func chartSamples(start: Date, reset: Date) -> [UsageChartSample] {
        let totalTokens = max(
            localTokenPace?.sinceReset ?? 0,
            max(
                weeklyTokens ?? 0,
                usageDays.reduce(Int64(0)) { $0 + max(0, $1.tokens) }
            )
        )
        let localWindowBaseline: Int64? = {
            guard let localTokensTotal, let localTokenPace else { return nil }
            return max(0, localTokensTotal - localTokenPace.sinceReset)
        }()

        let tracked = usageHistory
            .filter {
                abs($0.windowStart.timeIntervalSince(start))
                    < UsageHistoryStore.windowTolerance
                    && $0.recordedAt >= start
                    && $0.recordedAt <= Date()
            }
            .sorted { $0.recordedAt < $1.recordedAt }

        // The solid line contains only readings the app actually observed.
        // The reset itself is a known 0% anchor. The span between that anchor
        // and the first locally observed reading is kept separate so it does
        // not masquerade as measured usage history.
        var samples: [UsageChartSample] = [
            UsageChartSample(
                date: start,
                actualFraction: 0,
                tokens: 0,
                tokenLabel: "TOKENS",
                sourceLabel: "Known reset baseline",
                isCurrent: false,
                isBaseline: true
            )
        ]
        var tokenPoints = tracked.map { checkpoint in
            UsageTokenPoint(
                date: min(reset, max(start, checkpoint.recordedAt)),
                officialPercent: max(0, min(100, checkpoint.usedPercent)),
                localTokensTotal: checkpoint.localTokensTotal,
                rollingFiveMinuteTokens: checkpoint.rollingFiveMinuteTokens,
                isCurrent: false
            )
        }
        if let usedPercent {
            tokenPoints.append(
                UsageTokenPoint(
                    date: min(Date(), reset),
                    officialPercent: max(0, min(100, usedPercent)),
                    localTokensTotal: localTokensTotal,
                    rollingFiveMinuteTokens: localTokenPace?.fiveMinutes,
                    isCurrent: true
                )
            )
        }
        let smoothed = tokenSmoothedPercents(for: tokenPoints)
        let effectiveBurns = cappedTokenBurns(for: tokenPoints)

        samples.append(contentsOf: tokenPoints.enumerated().map { index, point in
            let checkpoint = index < tracked.count ? tracked[index] : nil
            let checkpointTokens: Int64
            if let localTotal = point.localTokensTotal, let localWindowBaseline {
                checkpointTokens = max(0, localTotal - localWindowBaseline)
            } else {
                checkpointTokens = max(0, checkpoint?.weeklyTokens ?? totalTokens)
            }
            // Every range, including Window, is anchored to the persisted
            // official quota percentages. Token deltas only interpolate
            // between those anchors. The previous Window-only formula scaled
            // all lifetime tokens against the current 46%, which fabricated
            // the large early jump visible in the chart.
            let trackedFraction = smoothed.indices.contains(index)
                ? max(0, min(1, smoothed[index] / 100))
                : max(0, min(1, point.officialPercent / 100))
            return UsageChartSample(
                date: point.date,
                actualFraction: trackedFraction,
                tokens: range == .window ? checkpointTokens : effectiveBurns[index],
                tokenLabel: range == .window ? "TOKENS" : "5M BURN",
                sourceLabel: range == .window
                    ? (localWindowBaseline == nil
                        ? "Saved quota checkpoint"
                        : "Saved quota · token-smoothed")
                    : "Token-smoothed quota progress",
                isCurrent: point.isCurrent,
                isBaseline: false
            )
        })
        // A malformed or delayed bucket should never make the line travel
        // backward across the chart.
        return samples.sorted {
            if $0.date == $1.date { return !$0.isCurrent && $1.isCurrent }
            return $0.date < $1.date
        }
    }

    private func cappedTokenBurns(for points: [UsageTokenPoint]) -> [Int64] {
        guard !points.isEmpty else { return [] }
        var raw = Array(repeating: Int64(0), count: points.count)
        for index in points.indices {
            if let rolling = points[index].rollingFiveMinuteTokens, rolling > 0 {
                raw[index] = rolling
            } else if index > 0,
                      let current = points[index].localTokensTotal,
                      let previous = points[index - 1].localTokensTotal {
                raw[index] = max(0, current - previous)
            }
        }
        let positive = raw.filter { $0 > 0 }.sorted()
        guard let median = medianValue(positive) else { return raw }
        // Local thread totals occasionally jump by billions because cached
        // context is rewritten. Preserve real bursts while preventing one
        // bookkeeping spike from becoming a vertical wall in a zoomed graph.
        let cap = max(Int64(1), median.multipliedReportingOverflow(by: 4).overflow ? Int64.max : median * 4)
        return raw.map { min($0, cap) }
    }

    private func tokenSmoothedPercents(for points: [UsageTokenPoint]) -> [Double] {
        guard !points.isEmpty else { return [] }
        let burns = cappedTokenBurns(for: points)
        var adjusted = points.map(\.officialPercent)
        var segmentStart = 0
        var tokensPerPercent: [Double] = []

        for milestone in points.indices.dropFirst() {
            let percentDelta = points[milestone].officialPercent
                - points[segmentStart].officialPercent
            guard percentDelta >= 0.5 else { continue }
            let totalBurn = burns[(segmentStart + 1)...milestone].reduce(Int64(0), +)
            if totalBurn > 0 {
                var cumulative: Int64 = 0
                for index in (segmentStart + 1)...milestone {
                    cumulative += burns[index]
                    let progress = min(1, Double(cumulative) / Double(totalBurn))
                    adjusted[index] = points[segmentStart].officialPercent + percentDelta * progress
                }
                tokensPerPercent.append(Double(totalBurn) / percentDelta)
            } else {
                let duration = max(1, points[milestone].date.timeIntervalSince(points[segmentStart].date))
                for index in (segmentStart + 1)...milestone {
                    let progress = max(0, min(
                        1,
                        points[index].date.timeIntervalSince(points[segmentStart].date) / duration
                    ))
                    adjusted[index] = points[segmentStart].officialPercent + percentDelta * progress
                }
            }
            segmentStart = milestone
        }

        // After the last official integer step, keep the detailed graph moving
        // fractionally with tokens instead of waiting for the next 1% jump.
        let recentCalibration = Array(tokensPerPercent.suffix(5)).sorted()
        if segmentStart < points.count - 1,
           let tokensForOnePercent = medianDouble(recentCalibration),
           tokensForOnePercent > 0 {
            var cumulative: Int64 = 0
            for index in (segmentStart + 1)..<points.count {
                cumulative += burns[index]
                let fractionalStep = min(0.95, Double(cumulative) / tokensForOnePercent)
                adjusted[index] = points[segmentStart].officialPercent + fractionalStep
            }
        }

        for index in adjusted.indices {
            adjusted[index] = max(0, min(100, adjusted[index]))
            if index > 0 { adjusted[index] = max(adjusted[index], adjusted[index - 1]) }
        }
        return adjusted
    }

    private func medianValue(_ values: [Int64]) -> Int64? {
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return values[middle - 1] / 2 + values[middle] / 2
        }
        return values[middle]
    }

    private func medianDouble(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2)
            ? (values[middle - 1] + values[middle]) / 2
            : values[middle]
    }

    private func hoverPoint(at location: CGPoint, size: CGSize) -> UsageHoverPoint? {
        guard let start = windowStartDate, let reset = resetAt else { return nil }
        let plot = plotRect(for: size)
        let domain = visibleDomain(start: start, reset: reset)
        let duration = max(1, domain.end.timeIntervalSince(domain.start))
        let samples = visibleSamples(
            chartSamples(start: start, reset: reset),
            from: domain.start,
            through: domain.end
        )
        let x = max(plot.minX, min(plot.maxX, location.x))
        let fraction = max(0, min(1, (x - plot.minX) / plot.width))
        guard let sample = samples.min(by: {
            abs(xFraction(for: $0.date, start: domain.start, duration: duration) - fraction)
                < abs(xFraction(for: $1.date, start: domain.start, duration: duration) - fraction)
        }) else { return nil }
        return UsageHoverPoint(
            date: sample.date,
            actualPercent: sample.actualFraction * 100,
            idealPercent: idealFraction(
                at: sample.date,
                windowStart: start,
                duration: max(1, reset.timeIntervalSince(start))
            ) * 100,
            tokens: sample.tokens,
            tokenLabel: sample.tokenLabel,
            sourceLabel: sample.sourceLabel,
            apiEquivalentUSD: nearestCost(to: sample.date)?.apiEquivalentUSD,
            isCurrent: sample.isCurrent
        )
    }

    private func plotRect(for size: CGSize) -> CGRect {
        CGRect(x: 35, y: 9, width: max(1, size.width - 45), height: max(1, size.height - 24))
    }

    private func xFraction(for date: Date, start: Date, duration: TimeInterval) -> CGFloat {
        CGFloat(max(0, min(1, date.timeIntervalSince(start) / duration)))
    }

    private func point(
        for date: Date,
        value: Double,
        start: Date,
        duration: TimeInterval,
        yDomain: ClosedRange<Double>,
        plot: CGRect
    ) -> CGPoint {
        let xFraction = xFraction(for: date, start: start, duration: duration)
        return CGPoint(
            x: plot.minX + plot.width * xFraction,
            y: yPosition(value, domain: yDomain, plot: plot)
        )
    }

    private func visibleDomain(start: Date, reset: Date) -> (start: Date, end: Date) {
        guard let duration = range.duration else { return (start, reset) }
        let end = min(Date(), reset)
        // Keep zoom ranges honest and visually distinct. If the active quota
        // window is only eight hours old, 12H shows four hours of empty
        // pre-reset time and 24H shows sixteen instead of collapsing both
        // controls onto the same eight-hour domain.
        return (end.addingTimeInterval(-duration), end)
    }

    private func visibleSamples(
        _ samples: [UsageChartSample],
        from start: Date,
        through end: Date
    ) -> [UsageChartSample] {
        let sorted = samples.sorted { $0.date < $1.date }
        var visible = sorted.filter { $0.date >= start && $0.date <= end }
        if let preceding = sorted.last(where: { $0.date < start }) {
            visible.insert(
                UsageChartSample(
                    date: start,
                    actualFraction: preceding.actualFraction,
                    tokens: preceding.tokens,
                    tokenLabel: preceding.tokenLabel,
                    sourceLabel: "Value at zoom boundary",
                    isCurrent: false,
                    isBaseline: preceding.isBaseline
                ),
                at: 0
            )
        }
        return visible
    }

    private func verticalDomain(
        samples: [UsageChartSample],
        costFractions: [Double],
        idealStart: Double,
        idealEnd: Double
    ) -> ClosedRange<Double> {
        guard range != .window else { return 0...1 }
        let values = samples.map(\.actualFraction) + costFractions + [idealStart, idealEnd]
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        let span = max(0.05, maximum - minimum)
        var lower = floor(max(0, minimum - span * 0.18) * 20) / 20
        var upper = ceil(min(1, maximum + span * 0.18) * 20) / 20
        if upper - lower < 0.10 {
            lower = max(0, lower - 0.05)
            upper = min(1, upper + 0.05)
        }
        return lower...max(lower + 0.05, upper)
    }

    private func visibleCostSamples(from start: Date, through end: Date) -> [(date: Date, fraction: Double)] {
        guard let intelligence = usageIntelligence,
              intelligence.apiEquivalentUSD > 0,
              let usedPercent,
              usedPercent > 0
        else { return [] }
        let currentFraction = min(1, usedPercent / 100)
        let all = intelligence.costTimeline.map {
            (
                date: $0.date,
                fraction: min(1, max(0, ($0.apiEquivalentUSD / intelligence.apiEquivalentUSD) * currentFraction))
            )
        }.sorted { $0.date < $1.date }
        var visible = all.filter { $0.date >= start && $0.date <= end }
        if let preceding = all.last(where: { $0.date < start }) {
            visible.insert((date: start, fraction: preceding.fraction), at: 0)
        }
        return visible
    }

    private func nearestCost(to date: Date) -> UsageCostPoint? {
        usageIntelligence?.costTimeline.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private func idealFraction(at date: Date, windowStart: Date, duration: TimeInterval) -> Double {
        max(0, min(1, date.timeIntervalSince(windowStart) / duration))
    }

    private func yPosition(
        _ value: Double,
        domain: ClosedRange<Double>,
        plot: CGRect
    ) -> CGFloat {
        let span = max(0.000_1, domain.upperBound - domain.lowerBound)
        let fraction = max(0, min(1, (value - domain.lowerBound) / span))
        return plot.maxY - plot.height * CGFloat(fraction)
    }

    private func axisLabel(_ date: Date) -> String {
        if range == .window {
            return date.formatted(.dateTime.weekday(.abbreviated).hour())
                .uppercased()
        }
        return date.formatted(.dateTime.hour().minute()).uppercased()
    }

    private func drawUnavailable(context: inout GraphicsContext, size: CGSize) {
        context.draw(
            Text("Usage data unavailable")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(Color.white.opacity(0.42)),
            at: CGPoint(x: size.width / 2, y: size.height / 2)
        )
    }
}

struct RightClickActionView: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var action: () -> Void
        private weak var view: NSView?
        private var monitor: Any?

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func attach(to view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                guard let self, let view = self.view,
                      event.window === view.window else { return event }
                let location = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(location) else { return event }
                self.action()
                return nil
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit {
            detach()
        }
    }
}

struct DoubleClickActionView: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var action: () -> Void
        private weak var view: NSView?
        private var monitor: Any?

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func attach(to view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard
                    event.clickCount == 2,
                    let self,
                    let view = self.view,
                    event.window === view.window
                else { return event }
                let location = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(location) else { return event }
                self.action()
                return nil
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit {
            detach()
        }
    }
}

enum DialSymbol {
    case system(String)
    case codex
    case resetDate(day: String, time: String)
}

struct ThemeShell: View {
    let theme: WidgetTheme

    var body: some View {
        ZStack {
            switch theme {
            case .current:
                RoundedRectangle(cornerRadius: 31, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x171A1E), Color(hex: 0x090B0E)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 31, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            case .marine:
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x333533), Color(hex: 0x111310), Color(hex: 0x292B29)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(ThemeShellPattern(theme: theme).opacity(0.32))
                    .overlay(
                        RoundedRectangle(cornerRadius: 27, style: .continuous)
                            .stroke(Color(hex: 0x686A65).opacity(0.65), lineWidth: 1.2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .inset(by: 5)
                            .stroke(Color.black.opacity(0.75), lineWidth: 2)
                    )
            case .oled:
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .fill(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 27, style: .continuous)
                            .stroke(Color(hex: 0x41433F), lineWidth: 1)
                    )
            case .radar:
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x121A1E), Color(hex: 0x080D10)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(ThemeShellPattern(theme: theme).opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 27, style: .continuous)
                            .stroke(Color(hex: 0x7395A1).opacity(0.45), lineWidth: 1)
                    )
            case .eInk:
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(Color(hex: 0xD4D2CA))
                    .overlay(ThemeShellPattern(theme: theme).opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                            .stroke(Color(hex: 0x343434), lineWidth: 1.4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .inset(by: 4)
                            .stroke(Color.white.opacity(0.55), lineWidth: 1)
                    )
            case .retro:
                RoundedRectangle(cornerRadius: 29, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x32332F), Color(hex: 0x10110F)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 29, style: .continuous)
                            .stroke(Color(hex: 0x73736D).opacity(0.65), lineWidth: 1.2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 23, style: .continuous)
                            .inset(by: 5)
                            .stroke(Color.black.opacity(0.9), lineWidth: 2)
                    )
            }
        }
    }
}

private struct ThemeShellPattern: View {
    let theme: WidgetTheme

    var body: some View {
        Canvas { context, size in
            switch theme {
            case .radar:
                for x in stride(from: 0.0, through: size.width, by: 18) {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(Color(hex: 0x5AAFC8).opacity(0.12)), lineWidth: 0.5)
                }
                for y in stride(from: 0.0, through: size.height, by: 18) {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(Color(hex: 0x5AAFC8).opacity(0.12)), lineWidth: 0.5)
                }
            case .eInk:
                for y in stride(from: 2.0, through: size.height, by: 4) {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(Color.black.opacity(0.035)), lineWidth: 0.5)
                }
            case .marine:
                for y in stride(from: 1.0, through: size.height, by: 3) {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(Color.white.opacity(0.025)), lineWidth: 0.5)
                }
            default:
                break
            }
        }
        .allowsHitTesting(false)
    }
}

struct ThemedInstrumentDial: View {
    let theme: WidgetTheme
    let progress: Double?
    let color: Color
    let symbol: DialSymbol
    let detail: String?
    let themeFooter: String?
    let accessibilityLabel: String
    let valueLabel: String?
    let roundsPercentDown: Bool
    var alerting = false

    var body: some View {
        Group {
            if theme == .current {
                InstrumentDial(
                    progress: progress,
                    color: color,
                    symbol: symbol,
                    detail: detail,
                    footer: themeFooter,
                    accessibilityLabel: accessibilityLabel,
                    valueLabel: valueLabel,
                    roundsPercentDown: roundsPercentDown,
                    alerting: alerting
                )
            } else {
                AlternativeInstrumentDial(
                    theme: theme,
                    progress: progress,
                    color: color,
                    symbol: symbol,
                    detail: detail,
                    themeFooter: themeFooter,
                    accessibilityLabel: accessibilityLabel,
                    valueLabel: valueLabel,
                    roundsPercentDown: roundsPercentDown,
                    alerting: alerting
                )
            }
        }
    }
}

private struct AlternativeInstrumentDial: View {
    let theme: WidgetTheme
    let progress: Double?
    let color: Color
    let symbol: DialSymbol
    let detail: String?
    let themeFooter: String?
    let accessibilityLabel: String
    let valueLabel: String?
    let roundsPercentDown: Bool
    let alerting: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let scale = max(0.48, min(1.5, size / 202))

            ZStack {
                AlternativeDialPanel(theme: theme, accent: color)
                ThemeGaugeCanvas(theme: theme, progress: progress ?? 0, color: color, alerting: alerting)
                    .padding(gaugePadding * scale)
                AlternativeDialReadout(
                    theme: theme,
                    symbol: symbol,
                    percentText: percentText,
                    detail: detail,
                    themeFooter: themeFooter,
                    accent: color,
                    scale: scale
                )
                    .padding(16 * scale)
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(percentText)
        .help(detail.map { "\(accessibilityLabel): \(percentText) · \($0)" } ?? "\(accessibilityLabel): \(percentText)")
    }

    private var gaugePadding: CGFloat {
        switch theme {
        case .marine: return 20
        case .oled: return 13
        case .radar: return 13
        case .eInk: return 12
        case .retro: return 15
        case .current: return 10
        }
    }

    private var percentText: String {
        if let valueLabel { return valueLabel }
        guard let progress else { return "—" }
        let visible = roundsPercentDown ? progress.rounded(.down) : progress.rounded()
        return "\(Int(visible))%"
    }
}

private struct AlternativeDialPanel: View {
    let theme: WidgetTheme
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                switch theme {
                case .marine:
                    RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x3A3B37), Color(hex: 0x181A18), Color(hex: 0x30312E)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: 0x171914), .black], center: .center, startRadius: 4, endRadius: size * 0.42))
                        .padding(size * 0.075)
                        .overlay(Circle().stroke(Color(hex: 0x666760), lineWidth: max(1, size * 0.018)).padding(size * 0.075))
                        .overlay(Circle().stroke(Color.black, lineWidth: max(1, size * 0.035)).padding(size * 0.09))
                    MarineBolts().padding(size * 0.035)
                case .oled:
                    Color.black
                case .radar:
                    RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                        .fill(Color(hex: 0x0A1013).opacity(0.94))
                        .overlay(
                            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                                .stroke(accent.opacity(0.18), lineWidth: 0.8)
                        )
                case .eInk:
                    RoundedRectangle(cornerRadius: size * 0.055, style: .continuous)
                        .fill(Color(hex: 0xCFCDC5))
                        .overlay(ThemeShellPattern(theme: .eInk))
                        .overlay(
                            RoundedRectangle(cornerRadius: size * 0.055, style: .continuous)
                                .stroke(Color(hex: 0x505050), lineWidth: 1)
                        )
                case .retro:
                    RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.black, Color(hex: 0x10110F)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                                .stroke(Color(hex: 0x4A4B47), lineWidth: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
                                .inset(by: 5)
                                .stroke(Color.black, lineWidth: 2)
                        )
                case .current:
                    Color.clear
                }
            }
        }
    }
}

private struct MarineBolts: View {
    var body: some View {
        GeometryReader { geometry in
            let d = max(10, min(geometry.size.width, geometry.size.height) * 0.09)
            ForEach(0..<4, id: \.self) { index in
                let x = index % 2 == 0 ? d * 0.7 : geometry.size.width - d * 0.7
                let y = index < 2 ? d * 0.7 : geometry.size.height - d * 0.7
                ZStack {
                    Circle().fill(RadialGradient(colors: [Color(hex: 0x62635D), Color(hex: 0x111210)], center: .topLeading, startRadius: 1, endRadius: d))
                    Capsule().fill(Color.black.opacity(0.75)).frame(width: d * 0.55, height: 1)
                    Capsule().fill(Color.black.opacity(0.55)).frame(width: 1, height: d * 0.55)
                }
                .frame(width: d, height: d)
                .position(x: x, y: y)
            }
        }
    }
}

private struct AlternativeDialReadout: View {
    let theme: WidgetTheme
    let symbol: DialSymbol
    let percentText: String
    let detail: String?
    let themeFooter: String?
    let accent: Color
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 2 * scale) {
            Spacer(minLength: 2 * scale)
            symbolView
                .frame(minHeight: 28 * scale)
            valueView
            Spacer(minLength: 4 * scale)
            statusView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var valueView: some View {
        Text(percentText)
            .font(valueFont)
            .monospacedDigit()
            .foregroundStyle(valueColor)
            .shadow(color: glowColor, radius: theme == .oled || theme == .retro ? 3 * scale : 0)
    }

    @ViewBuilder private var statusView: some View {
        if let statusText {
            Text(statusText)
                .font(.system(size: max(8.5, 9 * scale), weight: .medium, design: .monospaced))
                .foregroundStyle(theme.isLight ? Color.black.opacity(0.65) : accent.opacity(0.72))
                .lineLimit(1)
        }
    }

    private var statusText: String? {
        themeFooter ?? detail
    }

    @ViewBuilder private var symbolView: some View {
        switch symbol {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 26 * scale, weight: .medium))
                .foregroundStyle(symbolColor)
        case .codex:
            Text(">_")
                .font(.system(size: 30 * scale, weight: .medium, design: .monospaced))
                .tracking(-3 * scale)
                .foregroundStyle(symbolColor)
        case .resetDate:
            Image(systemName: "calendar")
                .font(.system(size: 23 * scale, weight: .medium))
                .foregroundStyle(accent)
        }
    }

    private var contentSpacing: CGFloat {
        theme == .eInk ? 6 * scale : 3 * scale
    }

    private var valueFont: Font {
        switch theme {
        case .marine: return .system(size: 34 * scale, weight: .medium, design: .rounded)
        case .oled: return .system(size: 38 * scale, weight: .light, design: .monospaced)
        case .radar: return .system(size: 35 * scale, weight: .light, design: .rounded)
        case .eInk: return .system(size: 34 * scale, weight: .regular, design: .monospaced)
        case .retro: return .system(size: 39 * scale, weight: .light, design: .monospaced)
        case .current: return .system(size: 38 * scale, weight: .medium, design: .rounded)
        }
    }

    private var valueColor: Color {
        switch theme {
        case .marine: return Color.white.opacity(0.92)
        case .eInk: return Color(hex: 0x383838)
        default: return accent
        }
    }

    private var symbolColor: Color {
        theme.isLight ? Color(hex: 0x3D3D3D) : (theme == .marine ? Color.white.opacity(0.86) : accent)
    }

    private var glowColor: Color {
        theme == .oled || theme == .retro ? accent.opacity(0.35) : .clear
    }
}

private struct ThemeGaugeCanvas: View {
    let theme: WidgetTheme
    let progress: Double
    let color: Color
    let alerting: Bool

    var body: some View {
        Group {
            if alerting {
                TimelineView(.periodic(from: .now, by: 0.8)) { context in
                    gaugeCanvas(highlightPhase: ResetAlertBar.phase(at: context.date))
                }
            } else {
                gaugeCanvas()
            }
        }
        .animation(.easeOut(duration: 0.5), value: progress)
        .allowsHitTesting(false)
    }

    private func gaugeCanvas(highlightPhase: Double? = nil) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            let clamped = max(0, min(100, progress))
            switch theme {
            case .marine:
                drawSegments(context: &context, center: center, radius: radius, start: 140, sweep: 260, count: 41, progress: clamped, inactive: Color(hex: 0xBDBD9B).opacity(0.32), active: color, width: 2.2, highlightPhase: highlightPhase)
                drawNeedle(context: &context, center: center, radius: radius * 0.76, degrees: 140 + clamped * 2.6, color: color)
                for value in stride(from: 0, through: 100, by: 25) {
                    let degrees = 140 + Double(value) * 2.6
                    let point = polar(center: center, radius: radius * 0.66, degrees: degrees)
                    context.draw(
                        Text("\(value)").font(.system(size: max(7, radius * 0.09), weight: .bold, design: .monospaced)).foregroundColor(color.opacity(0.85)),
                        at: point
                    )
                }
            case .oled:
                drawSegments(context: &context, center: center, radius: radius * 0.9, start: 135, sweep: 270, count: 58, progress: clamped, inactive: Color.white.opacity(0.12), active: color, width: 2.5, highlightPhase: highlightPhase)
            case .radar:
                for fraction in [0.28, 0.52, 0.76, 0.96] {
                    context.stroke(Path(ellipseIn: CGRect(x: center.x - radius * fraction, y: center.y - radius * fraction, width: radius * fraction * 2, height: radius * fraction * 2)), with: .color(color.opacity(0.22)), lineWidth: 0.7)
                }
                var vertical = Path(); vertical.move(to: CGPoint(x: center.x, y: center.y - radius)); vertical.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                var horizontal = Path(); horizontal.move(to: CGPoint(x: center.x - radius, y: center.y)); horizontal.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                context.stroke(vertical, with: .color(color.opacity(0.18)), lineWidth: 0.6)
                context.stroke(horizontal, with: .color(color.opacity(0.18)), lineWidth: 0.6)
                drawArc(context: &context, center: center, radius: radius * 0.9, start: -90, sweep: clamped * 3.6, color: color, width: 1.4, highlightPhase: highlightPhase)
                let endpoint = polar(center: center, radius: radius * 0.9, degrees: -90 + clamped * 3.6)
                context.fill(Path(ellipseIn: CGRect(x: endpoint.x - 8, y: endpoint.y - 8, width: 16, height: 16)), with: .color(color.opacity(0.08)))
                context.fill(Path(ellipseIn: CGRect(x: endpoint.x - 4, y: endpoint.y - 4, width: 8, height: 8)), with: .color(color.opacity(0.28)))
                context.fill(Path(ellipseIn: CGRect(x: endpoint.x - 2, y: endpoint.y - 2, width: 4, height: 4)), with: .color(color))
            case .eInk:
                drawSegments(context: &context, center: center, radius: radius * 0.9, start: 205, sweep: 130, count: 30, progress: clamped, inactive: Color.black.opacity(0.48), active: color, width: 2.1, highlightPhase: highlightPhase)
                let dot = CGPoint(x: center.x, y: center.y + radius * 0.66)
                context.fill(Path(ellipseIn: CGRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)), with: .color(color.opacity(0.8)))
            case .retro:
                drawSegments(context: &context, center: center, radius: radius * 0.92, start: -92, sweep: 184, count: 36, progress: clamped, inactive: Color.white.opacity(0.08), active: color, width: 3, highlightPhase: highlightPhase)
            case .current:
                break
            }
        }
    }

    private func drawSegments(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, start: Double, sweep: Double, count: Int, progress: Double, inactive: Color, active: Color, width: CGFloat, highlightPhase: Double? = nil) {
        let activeCount = Int((progress / 100 * Double(count)).rounded())
        for index in 0..<count {
            let fraction = count > 1 ? Double(index) / Double(count - 1) : 0
            let degrees = start + sweep * fraction
            let major = index % 5 == 0
            let outer = polar(center: center, radius: radius, degrees: degrees)
            let inner = polar(center: center, radius: radius - (major ? radius * 0.11 : radius * 0.07), degrees: degrees)
            var path = Path(); path.move(to: inner); path.addLine(to: outer)
            let animated = highlightPhase.map { ResetAlertBar.segmentColor(index: index, count: count, phase: $0, base: active) } ?? active
            let segmentColor = index < activeCount ? animated : inactive
            context.stroke(path, with: .color(segmentColor), style: StrokeStyle(lineWidth: major ? width * 1.3 : width, lineCap: .butt))
        }
    }

    private func drawNeedle(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, degrees: Double, color: Color) {
        let end = polar(center: center, radius: radius, degrees: degrees)
        var path = Path(); path.move(to: center); path.addLine(to: end)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        context.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)), with: .color(Color(hex: 0x11120F)))
        context.stroke(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)), with: .color(color), lineWidth: 1.4)
    }

    private func drawArc(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, start: Double, sweep: Double, color: Color, width: CGFloat, highlightPhase: Double? = nil) {
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(start + max(0.8, sweep)), clockwise: false)
        let shading: GraphicsContext.Shading
        if let highlightPhase {
            shading = .conicGradient(
                ResetAlertBar.flowingGradient,
                center: center,
                angle: .degrees(highlightPhase * -360)
            )
        } else {
            shading = .color(color)
        }
        context.stroke(path, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func polar(center: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let radians = CGFloat(degrees * Double.pi / 180)
        return CGPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
    }
}

struct InstrumentDial: View {
    let progress: Double?
    let color: Color
    let symbol: DialSymbol
    let detail: String?
    let footer: String?
    let accessibilityLabel: String
    let valueLabel: String?
    let roundsPercentDown: Bool
    let alerting: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let scale = max(0.5, min(1.45, size / 202))

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: 0x171A1E), Color(hex: 0x090B0D)],
                            center: .center,
                            startRadius: 18 * scale,
                            endRadius: size * 0.51
                        )
                    )
                    .overlay(Circle().stroke(Color.black.opacity(0.9), lineWidth: 6 * scale))
                    .overlay(Circle().stroke(Color.white.opacity(0.09), lineWidth: 1))
                    .shadow(color: .black.opacity(0.75), radius: 9 * scale, y: 5 * scale)

                DialTicks(
                    color: color,
                    progress: progress ?? 0,
                    endpointOnly: roundsPercentDown,
                    alerting: alerting
                )
                    .padding(10 * scale)

                VStack(spacing: 8 * scale) {
                    dialSymbol(scale: scale)
                        .frame(height: 42 * scale)

                    Text(percentText)
                        .font(.system(size: 39 * scale, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.94))

                    if let footer, size >= 118 {
                        Text(footer)
                            .font(.system(size: max(8, 10 * scale), weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.64))
                            .lineLimit(1)
                    } else {
                        Color.clear.frame(height: size >= 118 ? 12 * scale : 4 * scale)
                    }
                }
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(percentText)
        .help(helpText)
    }

    @ViewBuilder private func dialSymbol(scale: CGFloat) -> some View {
        switch symbol {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 32 * scale, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.white.opacity(0.9))
        case .codex:
            Text(">_")
                .font(.system(size: 37 * scale, weight: .semibold, design: .monospaced))
                .tracking(-4 * scale)
                .foregroundStyle(Color.white.opacity(0.94))
        case .resetDate:
            Image(systemName: "calendar")
                .font(.system(size: 29 * scale, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(color)
        }
    }

    private var percentText: String {
        if let valueLabel { return valueLabel }
        guard let progress else { return "—" }
        let visibleProgress = roundsPercentDown
            ? progress.rounded(.down)
            : progress.rounded()
        return "\(Int(visibleProgress))%"
    }

    private var helpText: String {
        (footer ?? detail).map { "\(accessibilityLabel): \(percentText) · \($0)" }
            ?? "\(accessibilityLabel): \(percentText)"
    }
}

struct ResizeHandleView: NSViewRepresentable {
    let lineColor: NSColor

    func makeNSView(context: Context) -> ResizeHandleNSView {
        let view = ResizeHandleNSView()
        view.lineColor = lineColor
        return view
    }

    func updateNSView(_ nsView: ResizeHandleNSView, context: Context) {
        nsView.lineColor = lineColor
        nsView.needsDisplay = true
    }
}

final class ResizeHandleNSView: NSView {
    private var startMouse: NSPoint?
    private var startFrame: NSRect?
    var lineColor = NSColor.white

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        lineColor.withAlphaComponent(0.34).setStroke()
        for offset in stride(from: 7.0, through: 19.0, by: 5.0) {
            let path = NSBezierPath()
            path.lineWidth = 1
            path.move(to: NSPoint(x: bounds.maxX - offset, y: bounds.minY))
            path.line(to: NSPoint(x: bounds.maxX, y: bounds.minY + offset))
            path.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        WindowDockController.shared.beginResizeInteraction()
        startMouse = NSEvent.mouseLocation
        startFrame = window.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let startMouse, let startFrame else { return }
        let current = NSEvent.mouseLocation
        let deltaX = current.x - startMouse.x
        let deltaY = current.y - startMouse.y
        let size = FloatingLayoutGeometry.resized(from: startFrame.size, deltaX: deltaX, deltaY: deltaY)
        let frame = NSRect(
            x: startFrame.minX,
            y: startFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        window.setFrame(frame, display: true, animate: false)
    }

    override func mouseUp(with event: NSEvent) {
        startMouse = nil
        startFrame = nil
        WindowDockController.shared.endResizeInteraction()
    }
}

struct DialTicks: View {
    let color: Color
    let progress: Double
    let endpointOnly: Bool
    let alerting: Bool

    var body: some View {
        Group {
            if alerting {
                TimelineView(.periodic(from: .now, by: 0.8)) { context in
                    canvas(highlightPhase: ResetAlertBar.phase(at: context.date))
                }
            } else {
                canvas()
            }
        }
        .animation(.spring(response: 0.8, dampingFraction: 0.85), value: progress)
    }

    private func canvas(highlightPhase: Double? = nil) -> some View {
        Canvas { context, size in
            draw(context: &context, size: size, highlightPhase: highlightPhase)
        }
    }

    private func draw(context: inout GraphicsContext, size: CGSize, highlightPhase: Double?) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2
        let tickCount = 44
        let clampedProgress = max(0, min(progress, 100))
        let activeCount = endpointOnly
            ? Int((clampedProgress / 100 * Double(tickCount)).rounded(.down))
            : Int((clampedProgress / 100 * Double(tickCount)).rounded())

        for index in 0..<tickCount {
            let degrees = Double(index) / Double(tickCount) * 360 - 90
            let angle = CGFloat(degrees * Double.pi / 180)
            let major = index % 5 == 0
            let outer = radius - 5
            let inner = outer - (major ? 12 : 7)
            let start = CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner)
            let end = CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer)
            var tick = Path()
            tick.move(to: start)
            tick.addLine(to: end)
            let inactive = Color.white.opacity(major ? 0.42 : 0.2)
            let animated = highlightPhase.map { ResetAlertBar.segmentColor(index: index, count: tickCount, phase: $0, base: color) } ?? color
            let tickColor = index < activeCount ? animated : inactive
            let tickWidth: CGFloat = major ? 3 : 1.4
            context.stroke(tick, with: .color(tickColor), style: StrokeStyle(lineWidth: tickWidth, lineCap: .round))
        }

        var arc = Path()
        let endDegrees = -90 + max(0.8, clampedProgress) * 3.6
        arc.addArc(
            center: center,
            radius: radius - 20,
            startAngle: .degrees(-90),
            endAngle: .degrees(endDegrees),
            clockwise: false
        )
        let arcShading: GraphicsContext.Shading
        if let highlightPhase {
            arcShading = .conicGradient(
                ResetAlertBar.flowingGradient,
                center: center,
                angle: .degrees(highlightPhase * -360)
            )
        } else {
            arcShading = .color(color.opacity(0.92))
        }
        context.stroke(arc, with: arcShading, style: StrokeStyle(lineWidth: 5, lineCap: .round))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
