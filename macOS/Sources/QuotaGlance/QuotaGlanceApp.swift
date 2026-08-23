import AppKit
import ServiceManagement
import SwiftUI
import WebKit

@main
struct QuotaGlanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DashboardModel()

    var body: some Scene {
        WindowGroup {
            DashboardView(model: model)
                .frame(
                    minWidth: 128,
                    idealWidth: 680,
                    maxWidth: .infinity,
                    minHeight: 128,
                    idealHeight: 230,
                    maxHeight: .infinity
                )
                .background(WindowConfigurator())
                .onReceive(NotificationCenter.default.publisher(for: .quotaGlanceRefresh)) { _ in
                    model.refresh()
                }
                .onReceive(NotificationCenter.default.publisher(for: .quotaGlanceResetCalculatorChanged)) { notification in
                    if let rawValue = notification.object as? String {
                        model.selectForecastSource(rawValue)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .quotaGlanceBillingUpdated)) { _ in
                    model.publishMobileSnapshot()
                }
        }
        .defaultSize(width: 680, height: 230)
        .commands {
            CommandGroup(replacing: .newItem) { }
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
        case .left, .right, .top, .bottom:
            switch self {
            case .left, .right: return NSSize(width: 148, height: 280)
            case .top, .bottom: return NSSize(width: 280, height: 148)
            default: return .zero
            }
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
        sideFraction: CGFloat
    ) -> NSRect {
        guard position.isMounted else { return .zero }
        let size = position.mountedSize
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
    }

    private weak var window: NSWindow?
    private var moveObserver: NSObjectProtocol?
    private var localMouseUpMonitor: Any?
    private var globalMouseUpMonitor: Any?
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
        restoreDock(on: window)
    }

    func restoreDock(on window: NSWindow) {
        guard position.isMounted, let screen = persistedScreen() ?? window.screen ?? NSScreen.main else { return }
        let fraction = UserDefaults.standard.object(forKey: Key.sideFraction) as? Double ?? 0.5
        applyMountedFrame(position, to: window, screen: screen, sideFraction: fraction, animated: false)
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
        let frame = DockingGeometry.mountedFrame(for: position, in: screen.visibleFrame, sideFraction: sideFraction)
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
        moveObserver = nil
        localMouseUpMonitor = nil
        globalMouseUpMonitor = nil
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
    case average

    static let defaultsKey = "QuotaGlance.resetCalculatorSource"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lunarWerx: return "LunarWerx"
        case .codexResets: return "Codex Resets"
        case .willCodexQuotaReset: return "Will Codex Reset?"
        case .gussuri: return "Reset Observatory"
        case .average: return "Average of All"
        }
    }

    var hostLabel: String {
        switch self {
        case .lunarWerx: return "codex.lunarwerx.com"
        case .codexResets: return "codex-resets.com"
        case .willCodexQuotaReset: return "willcodexquotareset.com"
        case .gussuri: return "codex.gussuriworks.com"
        case .average: return "4 calculators"
        }
    }

    var url: URL? {
        switch self {
        case .lunarWerx: return URL(string: "https://codex.lunarwerx.com")
        case .codexResets: return URL(string: "https://codex-resets.com")
        case .willCodexQuotaReset: return URL(string: "https://www.willcodexquotareset.com")
        case .gussuri: return URL(string: "https://codex.gussuriworks.com/en")
        case .average: return nil
        }
    }

    static var calculatorCases: [ForecastSource] {
        [.lunarWerx, .codexResets, .willCodexQuotaReset, .gussuri]
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var shouldExitForExistingInstance = false

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

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "Quota Glance")
        item.button?.target = self
        item.button?.action = #selector(openStatusMenu)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.enableLaunchAtLoginIfNeeded()
            // SwiftUI can restore the borderless window to a stale Space or
            // an off-screen frame after a restart. Bring it back to a known,
            // glanceable position whenever the app is launched.
            self?.revealDashboard(attempt: 0)
            BillingSyncCoordinator.runAutomaticSyncIfNeeded()
        }
    }

    @objc private func openStatusMenu() {
        showMenu()
    }

    private var dashboardWindow: NSWindow? {
        NSApp.windows.first { $0.title == "Quota Glance" || $0.contentView != nil }
    }

    private func show(_ window: NSWindow) {
        if WindowDockController.shared.position.isMounted {
            WindowDockController.shared.restoreDock(on: window)
        } else {
        // Prefer the display whose Cocoa frame contains the global origin;
        // that is the stable primary display even when a restored window is
        // pointing at a monitor that is no longer connected.
        let primaryScreen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: 0, y: 0)) }
        if let screen = primaryScreen ?? NSScreen.main ?? window.screen ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            let size = WindowDockController.shared.savedFloatingSize ?? NSSize(width: 680, height: 230)
            let origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            )
            WindowDockController.shared.setFrame(
                NSRect(origin: origin, size: size),
                on: window,
                animated: false
            )
        }
        }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showMenu() {
        let menu = NSMenu()
        let dashboardIsVisible = dashboardWindow?.isVisible == true
        menu.addItem(
            withTitle: dashboardIsVisible ? "Hide Quota Glance" : "Show Quota Glance",
            action: #selector(toggleDashboardVisibility),
            keyEquivalent: ""
        )
        menu.addItem(withTitle: "Refresh now", action: #selector(refresh), keyEquivalent: "r")
        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        switch SMAppService.mainApp.status {
        case .enabled:
            loginItem.state = .on
        case .requiresApproval:
            loginItem.state = .mixed
        default:
            loginItem.state = .off
        }
        menu.addItem(loginItem)
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: "Theme")
        let selectedTheme = WidgetTheme(
            rawValue: UserDefaults.standard.string(forKey: WidgetTheme.defaultsKey) ?? ""
        ) ?? .current
        let themeOrder: [WidgetTheme] = [.current, .marine, .retro, .oled, .radar, .eInk]
        for theme in themeOrder {
            let item = NSMenuItem(
                title: theme.displayName,
                action: #selector(selectTheme(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = theme.rawValue
            item.state = theme == selectedTheme ? .on : .off
            themeMenu.addItem(item)
        }
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)
        let paceRateItem = NSMenuItem(title: "Pace Rate", action: nil, keyEquivalent: "")
        let paceRateMenu = NSMenu(title: "Pace Rate")
        let selectedPaceRate = UsagePaceRate(
            rawValue: UserDefaults.standard.string(forKey: UsagePaceRate.defaultsKey) ?? ""
        ) ?? .oneHour
        for paceRate in UsagePaceRate.allCases {
            let item = NSMenuItem(
                title: paceRate.displayName,
                action: #selector(selectPaceRate(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = paceRate.rawValue
            item.state = paceRate == selectedPaceRate ? .on : .off
            paceRateMenu.addItem(item)
        }
        paceRateItem.submenu = paceRateMenu
        menu.addItem(paceRateItem)
        let resetCalculatorItem = NSMenuItem(title: "Reset Calculator", action: nil, keyEquivalent: "")
        let resetCalculatorMenu = NSMenu(title: "Reset Calculator")
        let selectedResetCalculator = ForecastSource(
            rawValue: UserDefaults.standard.string(forKey: ForecastSource.defaultsKey) ?? ""
        ) ?? .lunarWerx
        for source in ForecastSource.allCases {
            let item = NSMenuItem(
                title: source.displayName,
                action: #selector(selectResetCalculator(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = source.rawValue
            item.state = source == selectedResetCalculator ? .on : .off
            resetCalculatorMenu.addItem(item)
        }
        resetCalculatorItem.submenu = resetCalculatorMenu
        menu.addItem(resetCalculatorItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func toggleDashboardVisibility() {
        guard let window = dashboardWindow else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            show(window)
        }
    }

    private func revealDashboard(attempt: Int) {
        guard let window = dashboardWindow else {
            guard attempt < 12 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.revealDashboard(attempt: attempt + 1)
            }
            return
        }
        show(window)
    }

    @objc private func refresh() {
        NotificationCenter.default.post(name: .quotaGlanceRefresh, object: nil)
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

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            WidgetTheme(rawValue: rawValue) != nil
        else { return }
        UserDefaults.standard.set(rawValue, forKey: WidgetTheme.defaultsKey)
        NotificationCenter.default.post(name: .quotaGlanceThemeChanged, object: rawValue)
    }

    @objc private func selectPaceRate(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            UsagePaceRate(rawValue: rawValue) != nil
        else { return }
        UserDefaults.standard.set(rawValue, forKey: UsagePaceRate.defaultsKey)
        NotificationCenter.default.post(name: .quotaGlancePaceRateChanged, object: rawValue)
    }

    @objc private func selectResetCalculator(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            ForecastSource(rawValue: rawValue) != nil
        else { return }
        UserDefaults.standard.set(rawValue, forKey: ForecastSource.defaultsKey)
        NotificationCenter.default.post(name: .quotaGlanceResetCalculatorChanged, object: rawValue)
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

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.title = "Quota Glance"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // A non-resizable window never enters macOS's edge-tiling preview.
        // Quota Glance temporarily enables the flag only while its own resize
        // handle or dock transition is actively changing the frame.
        window.styleMask = WindowDockController.shared.requiresResizableStyle
            ? [.borderless, .resizable]
            : [.borderless]
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
        window.tabbingMode = .disallowed
        // Let AppKit handle moving from the empty widget background. Keeping
        // this outside SwiftUI's gesture system prevents moves and resizes
        // from fighting each other.
        window.isMovableByWindowBackground = true
        window.isRestorable = false
        _ = window.setFrameAutosaveName("")
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        // The widget can collapse into a square three-ring face below the
        // normal three-dial strip size, so both axes must remain resizable.
        let minimumSize = NSSize(width: 118, height: 118)
        let maximumSize = NSSize(width: 1200, height: 1200)
        window.contentMinSize = minimumSize
        window.contentMaxSize = maximumSize
        window.minSize = minimumSize
        window.maxSize = maximumSize

        if window.frame.width < minimumSize.width || window.frame.height < minimumSize.height {
            window.setContentSize(minimumSize)
        }
        WindowDockController.shared.attach(to: window)
    }
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published var usedPercent: Double?
    @Published var weekElapsedPercent: Double?
    @Published var resetAt: Date?
    @Published var resetDeadlineIsCredit = false
    @Published var planName = "Codex"
    @Published var weeklyTokens: Int64?
    @Published var localTokensTotal: Int64?
    @Published var localTokenPace: LocalTokenPaceSnapshot?
    @Published var usageDays: [UsageDay] = []
    @Published var usageHistory: [UsageCheckpoint] = UsageHistoryStore.load()
    @Published var usageWindowStart: Date?
    @Published var usageWindowDurationMinutes: Double?
    @Published var forecastPercent: Double?
    @Published var forecastLabel: String?
    @Published var resetAnnouncement: ResetAnnouncement?
    @Published var resetIntel: ResetIntelSnapshot?
    @Published var newTweetAlert: TiboTweet?
    @Published var forecastSnapshot: ForecastSnapshot?
    @Published var forecastURL = URL(string: "https://codex-resets.com")!
    @Published var codexStatus = "Connecting to Codex…"
    @Published var forecastStatus = "Checking reset signals…"
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false

    private var usageTimer: Timer?
    private var forecastTimer: Timer?
    private var progressTimer: Timer?
    private var forecastRefreshGeneration = 0
    private let observedTweetKey = "QuotaGlance.observedTiboTweetID"
    private let clearedTweetKey = "QuotaGlance.clearedTiboTweetID"
    init() {
        restoreCachedCodexState()
        refresh()
        // Reading local rollout logs is the expensive part of the widget and
        // history itself is stored in five-minute buckets. Do that work once
        // per bucket instead of pointlessly rescanning the same files 5 times.
        usageTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshCodex() }
        }
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
        usageTimer?.invalidate()
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

    private func refreshCodex() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            do {
                let liveSnapshot = try await CodexService.fetch()
                let cached = CodexSnapshotStore.save(liveSnapshot)
                applyCodexSnapshot(cached.snapshot, recordedAt: cached.savedAt, isLive: true)
            } catch {
                codexStatus = error.localizedDescription
            }

            lastUpdated = Date()
            isRefreshing = false
        }
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

    func selectForecastSource(_ rawValue: String) {
        guard let source = ForecastSource(rawValue: rawValue) else { return }

        // Every provider result is already retained in forecastSnapshot.
        // Recompose from that cache synchronously so the dial changes during
        // the menu click itself, then verify all sources in the background.
        if let providers = forecastSnapshot?.providers,
           let cached = try? ForecastService.snapshot(from: providers, selected: source) {
            applyForecast(cached, statusPrefix: "Cached")
        }
        refreshForecast()
    }

    private func applyForecast(_ forecast: ForecastSnapshot, statusPrefix: String) {
        forecastPercent = forecast.score
        forecastLabel = forecast.displayLabel
        resetAnnouncement = forecast.announcement
        updateTweetAlert(from: forecast.intel?.tweets ?? [])
        resetIntel = forecast.intel
        forecastSnapshot = forecast
        forecastURL = forecast.source.url
            ?? forecast.providers.first?.source.url
            ?? URL(string: "https://codex.lunarwerx.com")!
        forecastStatus = "\(statusPrefix) · \(forecast.source.hostLabel)"
        lastUpdated = Date()
        publishMobileSnapshot()
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
        resetAt = snapshot.resetAt
        resetDeadlineIsCredit = snapshot.resetDeadlineIsCredit
        planName = snapshot.planName
        BillingSyncCoordinator.noteLocalPlan(snapshot.planName)
        weeklyTokens = snapshot.weeklyTokens
        localTokensTotal = snapshot.localTokensTotal
        localTokenPace = snapshot.localTokenPace
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
                    rollingFiveMinuteTokens: snapshot.localTokenPace?.fiveMinutes
                )
            )
        }
        // Keep the graph axis tied to Codex's current authoritative window.
        // Older builds reused the first near-matching start time; small reset
        // deadline corrections then stretched the axis and visually shifted
        // every saved percentage checkpoint.
        usageWindowStart = snapshot.usageWindowStart
        usageWindowDurationMinutes = snapshot.windowDurationMinutes
        usedPercent = max(
            snapshot.usedPercent,
            usageHistory.last(where: {
                abs($0.windowStart.timeIntervalSince(snapshot.usageWindowStart))
                    < UsageHistoryStore.windowTolerance
            })?.usedPercent ?? 0
        )
        weekElapsedPercent = snapshot.weekElapsedPercent
        lastUpdated = recordedAt
        codexStatus = isLive
            ? "Live · \(snapshot.planName) plan"
            : "Cached · \(snapshot.planName) plan"
        publishMobileSnapshot()
    }

    func publishMobileSnapshot() {
        let defaults = UserDefaults.standard
        let renewalTimestamp = defaults.double(forKey: BillingDefaults.renewalTimestamp)
        let renewalDate = renewalTimestamp > 0 ? Date(timeIntervalSince1970: renewalTimestamp) : nil
        let selectedSource = ForecastSource(
            rawValue: defaults.string(forKey: ForecastSource.defaultsKey) ?? ""
        ) ?? forecastSnapshot?.source ?? .average
        let pace = UsagePace.calculate(
            usedPercent: usedPercent,
            windowStartDate: usageWindowStart,
            resetAt: resetAt,
            usageHistory: usageHistory,
            localTokensTotal: localTokensTotal,
            localTokenPace: localTokenPace,
            rate: .oneHour
        )
        let announcement = resetAnnouncement
        let mobileHistory = mobileUsageHistory(now: Date())
        let snapshot = MobileQuotaSnapshot(
            capturedAt: Date(),
            weekElapsedPercent: weekElapsedPercent,
            usagePercent: usedPercent,
            resetChancePercent: forecastPercent,
            resetAt: resetAt,
            usageWindowStart: usageWindowStart,
            windowDurationMinutes: usageWindowDurationMinutes,
            weeklyTokens: weeklyTokens,
            planName: defaults.string(forKey: BillingDefaults.webPlanName) ?? planName,
            renewalDate: renewalDate,
            selectedSource: selectedSource.rawValue,
            providers: (forecastSnapshot?.providers ?? []).map {
                MobileProviderReading(
                    source: $0.source.rawValue,
                    percent: $0.score,
                    updatedAt: $0.updatedAt
                )
            },
            resetAnnounced: announcement?.isActive() == true,
            announcementID: announcement?.id,
            announcementText: announcement?.text,
            announcementDate: announcement?.detectedAt,
            announcementExpectedAt: forecastSnapshot?.scheduledReset?.expectedAt ?? announcement?.expectedAt,
            announcementURL: announcement?.url,
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
        return result
    }

    func clearNewTweetAlert() {
        guard let newTweetAlert else { return }
        UserDefaults.standard.set(newTweetAlert.alertIdentity, forKey: clearedTweetKey)
        self.newTweetAlert = nil
    }

    private func updateTweetAlert(from tweets: [TiboTweet]) {
        guard let newest = tweets.first else { return }

        let defaults = UserDefaults.standard
        let observedID = defaults.string(forKey: observedTweetKey)
            .map(TiboTweet.canonicalizeStoredIdentity)
        let clearedID = defaults.string(forKey: clearedTweetKey)
            .map(TiboTweet.canonicalizeStoredIdentity)
        let identity = newest.alertIdentity

        if observedID == nil {
            // Seed the baseline silently on first launch. The bubble is for a
            // tweet that arrives after the widget has started watching.
            defaults.set(identity, forKey: observedTweetKey)
            defaults.set(identity, forKey: clearedTweetKey)
            return
        }

        if observedID != identity {
            defaults.set(identity, forKey: observedTweetKey)
        }

        // Do not clear this automatically when the source refreshes or the
        // app relaunches. It remains visible until the user taps the check.
        if clearedID != identity {
            newTweetAlert = newest
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
    let usageDays: [UsageDay]
    let usageWindowStart: Date
    let windowDurationMinutes: Double?
    let weekElapsedPercent: Double
    let planName: String
}

struct UsageDay: Codable, Identifiable, Sendable {
    let date: Date
    let tokens: Int64

    var id: Date { date }
}

struct LocalTokenPaceSnapshot: Codable, Sendable {
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

    var id: Date { recordedAt }
}

private enum UsageHistoryStore {
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
            rollingFiveMinuteTokens: checkpoint.rollingFiveMinuteTokens
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
            rollingFiveMinuteTokens: nil
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
            rollingFiveMinuteTokens: nil
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
            #"{"method":"account/usage/read","id":2}"#
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
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard
                let lineData = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let id = object["id"] as? Int,
                let result = object["result"] as? [String: Any]
            else { continue }
            if id == 1 { rateResult = result }
            if id == 2 { usageResult = result }
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
        let localTokenPace = localTokenPaceSnapshot(
            windowStart: windowStartDate,
            now: Date(),
            currentTotal: localTokensTotal
        )
        let plan = displayPlanName(rateLimits["planType"] as? String)

        return CodexSnapshot(
            usedPercent: usedPercent,
            resetAt: resetDate,
            resetDeadlineIsCredit: resetCreditExpiry != nil,
            weeklyTokens: weeklyTokens,
            localTokensTotal: localTokensTotal,
            localTokenPace: localTokenPace,
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
        currentTotal: Int64?
    ) -> LocalTokenPaceSnapshot? {
        guard let currentTotal else { return nil }
        let intervals: [TimeInterval] = [5 * 60, 60 * 60, 12 * 60 * 60, 24 * 60 * 60]
        let totals = intervals.map {
            UsageHistoryStore.localTokenBurn(
                currentTotal: currentTotal,
                windowStart: windowStart,
                now: now,
                interval: $0
            )
        }

        let sinceReset: Int64 = {
            if let persisted = LocalTokenBaselineStore.tokensSinceReset(
                    windowStart: windowStart,
                    currentTotal: currentTotal
               ) {
                return persisted
            }
            // On the first sample of a new quota window, seed from the oldest
            // retained checkpoint. Future five-minute samples remain exact.
            return totals[3]
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
    let displayLabel: String?
    let source: ForecastSource
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

        if let relative = relativeExpectedDate(in: normalized, postedAt: postedAt) {
            return relative
        }

        guard
            let expression = try? NSRegularExpression(
                pattern: #"\b([0-2]?\d)(?::([0-5]\d))?\s*(am|pm)?\s*(PST|PDT|PT|MST|MDT|MT|CST|CDT|CT|EST|EDT|ET|UTC|GMT)?\b"#,
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
            guard var hour = normalizedHour(rawHour, meridiem: meridiem) else { continue }
            hour = min(23, hour)
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
            var components = calendar.dateComponents([.year, .month, .day], from: targetDay)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard var candidate = calendar.date(from: components) else { continue }
            if dayOffset == 0, !lower.contains("today"), !lower.contains("tonight"), candidate < postedAt {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            return candidate
        }
        return nil
    }

    private static func relativeExpectedDate(in text: String, postedAt: Date) -> Date? {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?:in|within|over(?:\s+the)?|next)\s+(?:(\d+)\s*)?(minutes?|mins?|hours?|hrs?)"#,
            options: [.caseInsensitive]
        ), let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let unitRange = Range(match.range(at: 2), in: text)
        else { return nil }
        let amount = Range(match.range(at: 1), in: text).flatMap { Double(text[$0]) } ?? 1
        let unit = text[unitRange].lowercased()
        return postedAt.addingTimeInterval(amount * (unit.hasPrefix("h") ? 3_600 : 60))
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
        case "MST", "MDT", "MT": identifier = "America/Denver"
        case "CST", "CDT", "CT": identifier = "America/Chicago"
        case "EST", "EDT", "ET": identifier = "America/New_York"
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
    let announcement: ResetAnnouncement?
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

enum ForecastService {
    static func fetch() async throws -> ForecastSnapshot {
        let selected = ForecastSource(
            rawValue: UserDefaults.standard.string(forKey: ForecastSource.defaultsKey) ?? ""
        ) ?? .lunarWerx

        async let lunar = optionalProvider(.lunarWerx)
        async let current = optionalProvider(.codexResets)
        async let original = optionalProvider(.willCodexQuotaReset)
        async let fallback = optionalProvider(.gussuri)
        let providers = await [lunar, current, original, fallback].compactMap { $0 }
        return try snapshot(from: providers, selected: selected)
    }

    static func snapshot(
        from providers: [ResetProviderSnapshot],
        selected: ForecastSource
    ) throws -> ForecastSnapshot {
        guard !providers.isEmpty else { throw DashboardError.forecastUnavailable }
        let scored = providers.filter { $0.score != nil }
        let chosen = providers.first { $0.source == selected }
        let averageScore = scored.compactMap(\.score).reduce(0, +) / Double(max(1, scored.count))
        let estimatedScore = selected == .average ? averageScore : (chosen?.score ?? averageScore)
        let ranges = selected == .average ? scored.compactMap(\.range) : chosen.map { [$0.range].compactMap { $0 } } ?? []
        let lowerAverage = ranges.map(\.lowerBound).reduce(0, +) / Double(max(1, ranges.count))
        let upperAverage = ranges.map(\.upperBound).reduce(0, +) / Double(max(1, ranges.count))
        let combinedRange: ClosedRange<Double>? = ranges.isEmpty ? nil : lowerAverage...upperAverage

        let tweets = aggregateTweets(from: providers)
        let lastBlessing = providers.compactMap(\.lastBlessingAt).max()
        let providerAnnouncement = providers
            .compactMap(\.announcement)
            .filter { $0.isActive() }
            .max { $0.detectedAt < $1.detectedAt }
        let structuredSchedules = providers.compactMap { provider -> ResetSchedule? in
            guard let item = provider.announcement, let expectedAt = item.expectedAt else { return nil }
            return ResetSchedule(
                id: item.id,
                source: item.source,
                announcedAt: item.detectedAt,
                expectedAt: expectedAt,
                text: item.text,
                url: item.url
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
        let scheduledReset = (structuredSchedules + textSchedules)
            .filter { $0.expectedAt > Date().addingTimeInterval(-5 * 60) }
            .min { $0.expectedAt < $1.expectedAt }
        let announcement: ResetAnnouncement? = {
            if let providerAnnouncement {
                guard let scheduledReset else { return providerAnnouncement }
                return ResetAnnouncement(
                    id: providerAnnouncement.id,
                    source: providerAnnouncement.source,
                    detectedAt: providerAnnouncement.detectedAt,
                    expectedAt: scheduledReset.expectedAt,
                    text: providerAnnouncement.text,
                    url: providerAnnouncement.url
                )
            }
            guard let scheduledReset else { return nil }
            return ResetAnnouncement(
                id: "scheduled:\(scheduledReset.id)",
                source: scheduledReset.source,
                detectedAt: scheduledReset.announcedAt,
                expectedAt: scheduledReset.expectedAt,
                text: scheduledReset.text,
                url: scheduledReset.url
            )
        }()
        let score = announcement == nil ? estimatedScore : 100
        let headline: String?
        if let scheduledReset {
            headline = "Reset expected \(scheduledReset.expectedAt.formatted(date: .abbreviated, time: .shortened))"
        } else if announcement != nil {
            headline = "Reset announced · use your quota now"
        } else if selected == .average {
            headline = "Four independent reset estimates"
        } else if chosen?.score == nil {
            headline = "\(selected.displayName) has no live percentage · showing the available mean"
        } else {
            headline = chosen?.headline
        }
        return ForecastSnapshot(
            score: score,
            displayLabel: announcement == nil && selected != .average ? chosen?.displayLabel : nil,
            source: selected,
            announcement: announcement,
            scheduledReset: scheduledReset,
            intel: ResetIntelSnapshot(lastBlessingAt: lastBlessing, tweets: tweets),
            providers: providers,
            headline: headline,
            range: combinedRange
        )
    }

    private static func optionalProvider(_ source: ForecastSource) async -> ResetProviderSnapshot? {
        do {
            switch source {
            case .lunarWerx: return try await fetchLunarWerx()
            case .codexResets: return try await fetchCodexResets()
            case .willCodexQuotaReset: return try await fetchWillCodexQuotaReset()
            case .gussuri: return try await fetchGussuri()
            case .average: return nil
            }
        } catch {
            NSLog("Quota Glance reset source %@ failed: %@", source.hostLabel, error.localizedDescription)
            return nil
        }
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

        let intel = ResetIntelSnapshot(
            lastBlessingAt: lastBlessingDate(in: html),
            tweets: tiboTweets(in: html)
        )

        return ResetProviderSnapshot(
            source: .codexResets,
            score: parseChance(in: html)?.score,
            displayLabel: parseChance(in: html)?.displayLabel,
            headline: "Confirmed reset history",
            range: nil,
            lastBlessingAt: intel.lastBlessingAt,
            tweets: intel.tweets,
            metrics: [],
            signals: [],
            updatedAt: Date(),
            announcement: codexResetsAnnouncement(in: html, tweets: intel.tweets)
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
            announcement: announcement
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
            announcement: announcement
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
            announcement: announcement
        )
    }

    private static func announcementFromTweets(
        _ tweets: [TiboTweet],
        source: ForecastSource,
        explicitlyAnnounced: Bool
    ) -> ResetAnnouncement? {
        guard explicitlyAnnounced else { return nil }
        let tweet = tweets
            .filter(\.isResetOriented)
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

    private static func parseChance(in html: String) -> (score: Double, displayLabel: String?)? {
        // The current site presents the signal in its reset-watch/Tibo banner.
        // Prefer the accessible label because it survives small markup changes
        // such as “Reset chance” replacing “24h reset chance”.
        if let watch = firstCapture(
            #"(<section\s+class="[^"]*\bwatch-card\b[^"]*"[\s\S]*?</section>)"#,
            in: html
        ) {
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
        if let watchTweet = tiboWatchTweet(in: html) {
            parsed.append(watchTweet)
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

    private static func tiboWatchTweet(in html: String) -> TiboTweet? {
        guard
            let section = firstCapture(
                #"(<section\s+class="[^"]*\bwatch-card\b[^"]*"[\s\S]*?</section>)"#,
                in: html
            ),
            let textHTML = firstCapture(#"<blockquote[^>]*>([\s\S]*?)</blockquote>"#, in: section),
            let dateText = firstAttribute("data-datetime", in: section),
            let urlText = firstXURL(in: section)
        else { return nil }

        let text = plainText(from: textHTML)
        guard !text.isEmpty else { return nil }

        let replyText = firstCapture(
            #"<p\s+class="[^"]*\bwatch-context\b[^"]*"[^>]*>([\s\S]*?)</p>"#,
            in: section
        )
        .map(plainText(from:))
        .flatMap { value -> String? in
            let cleaned = value.replacingOccurrences(
                of: #"^\s*in\s+reply\s+to\s*"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return TiboTweet(
            id: urlText,
            date: parseISODate(dateText),
            text: text,
            inReplyTo: replyText,
            url: URL(string: decodeHTMLEntities(urlText))
        )
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
            "&#39;": "'", "&middot;": "·", "&nbsp;": " "
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
            "&#39;": "'", "&middot;": "·", "&nbsp;": " "
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

}

struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    @AppStorage(WidgetTheme.defaultsKey) private var themeRawValue = WidgetTheme.current.rawValue
    @AppStorage(UsagePaceRate.defaultsKey) private var paceRateRawValue = UsagePaceRate.oneHour.rawValue
    @AppStorage(ForecastSource.defaultsKey) private var resetCalculatorRawValue = ForecastSource.lunarWerx.rawValue
    @AppStorage(DockPosition.defaultsKey) private var dockPositionRawValue = DockPosition.floating.rawValue
    @State private var showingTweets = false
    @State private var showingNewTweetAlert = false
    @State private var showingUsageChart = false
    @State private var showingSubscription = false
    @State private var showingResetDetails = false

    private var theme: WidgetTheme {
        WidgetTheme(rawValue: themeRawValue) ?? .current
    }

    private var paceRate: UsagePaceRate {
        UsagePaceRate(rawValue: paceRateRawValue) ?? .oneHour
    }

    private var dockPosition: DockPosition {
        DockPosition(rawValue: dockPositionRawValue) ?? .floating
    }

    var body: some View {
        GeometryReader { geometry in
            let isVertical = geometry.size.height > geometry.size.width
            let crossAxis = isVertical ? geometry.size.width : geometry.size.height
            let mainAxis = isVertical ? geometry.size.height : geometry.size.width
            let padding = max(6, min(12, crossAxis * 0.055))
            let spacing = max(4, min(12, mainAxis * 0.017))
            let interfaceScale = max(0.62, min(1.25, crossAxis / 220))
            let compactRings = FloatingLayoutGeometry.isCompact(
                NSSize(width: geometry.size.width, height: geometry.size.height)
            )
            let dialLayout = isVertical
                ? AnyLayout(VStackLayout(spacing: spacing))
                : AnyLayout(HStackLayout(spacing: spacing))

            Group {
                if dockPosition.isMounted {
                    mountedRingView(position: dockPosition)
                } else if compactRings {
                    compactRingView
                        .padding(max(7, min(14, crossAxis * 0.07)))
                } else {
                    dialLayout {
                        dials(interfaceScale: interfaceScale)
                    }
                    .padding(padding)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .help(isVertical ? "Click for horizontal layout" : "Click for vertical layout")
        }
        .background {
            if !dockPosition.isMounted {
                ThemeShell(theme: theme)
            }
        }
        .background {
            DoubleClickActionView {
                toggleOrientation()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !dockPosition.isMounted {
                ResizeHandleView(lineColor: theme.isLight ? NSColor.black : NSColor.white)
                    .frame(width: 32, height: 32)
                    .padding(2)
            }
        }
        .clipShape(DockClipShape(position: dockPosition))
        .contentShape(DockClipShape(position: dockPosition))
        .preferredColorScheme(theme.isLight ? .light : .dark)
        .animation(.easeInOut(duration: 0.22), value: theme)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: dockPosition)
        .onReceive(NotificationCenter.default.publisher(for: .quotaGlanceThemeChanged)) { notification in
            if let rawValue = notification.object as? String {
                themeRawValue = rawValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quotaGlancePaceRateChanged)) { notification in
            if let rawValue = notification.object as? String {
                paceRateRawValue = rawValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quotaGlanceResetCalculatorChanged)) { notification in
            if let rawValue = notification.object as? String {
                resetCalculatorRawValue = rawValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quotaGlanceDockChanged)) { notification in
            if let rawValue = notification.object as? String {
                dockPositionRawValue = rawValue
            }
        }
        // The alert belongs to the persistent window, not to a particular
        // dial layout. Keeping it here prevents dock/undock and orientation
        // changes from presenting the same tweet again.
        .popover(isPresented: $showingNewTweetAlert, arrowEdge: .top) {
            if let tweet = model.newTweetAlert {
                NewTweetAlertPopover(
                    tweet: tweet,
                    onOpenFeed: {
                        showingNewTweetAlert = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            showingTweets = true
                        }
                    },
                    onClear: {
                        model.clearNewTweetAlert()
                        showingNewTweetAlert = false
                    }
                )
            }
        }
        .onAppear {
            showingNewTweetAlert = model.newTweetAlert != nil
        }
        .onChange(of: model.newTweetAlert?.id) { newID in
            showingNewTweetAlert = newID != nil
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.newTweetAlert?.id)
    }

    @ViewBuilder private func dials(interfaceScale: CGFloat) -> some View {
        ThemedInstrumentDial(
            theme: theme,
            progress: model.weekElapsedPercent,
            color: Color(hex: 0xF2AD3E),
            symbol: .resetDate(day: resetDay, time: resetClock),
            detail: nil,
            themeFooter: "\(resetDay) · \(resetClock)",
            accessibilityLabel: resetAccessibilityLabel,
            valueLabel: nil,
            roundsPercentDown: true
        )
        .background(
            RightClickActionView {
                showingSubscription = true
            }
        )
        .popover(isPresented: $showingSubscription, arrowEdge: .bottom) {
            SubscriptionInfoPopover(planName: model.planName)
        }
        ThemedInstrumentDial(
            theme: theme,
            progress: model.usedPercent,
            color: Color(hex: 0x7EE6AE),
            symbol: .codex,
            detail: nil,
            themeFooter: "⏱ \(usagePace.estimatedRunout.uppercased())",
            accessibilityLabel: "Codex usage",
            valueLabel: nil,
            roundsPercentDown: false
        )
        .background(
            RightClickActionView {
                showingUsageChart = true
            }
        )
        .popover(isPresented: $showingUsageChart, arrowEdge: .bottom) {
            UsageChartPopover(
                usageDays: model.usageDays,
                usageHistory: model.usageHistory,
                weeklyTokens: model.weeklyTokens,
                localTokensTotal: model.localTokensTotal,
                localTokenPace: model.localTokenPace,
                usedPercent: model.usedPercent,
                windowStartDate: model.usageWindowStart,
                resetAt: model.resetAt,
                paceRate: paceRate
            )
        }
        ZStack(alignment: .topTrailing) {
            ThemedInstrumentDial(
                theme: theme,
                progress: model.forecastPercent ?? 0,
                color: Color(hex: 0x58B9F3),
                symbol: .system("arrow.triangle.2.circlepath"),
                detail: resetScheduleFooter ?? (model.resetAnnouncement == nil ? model.resetIntel?.compactLabel : "🔥 USE IT NOW"),
                themeFooter: resetScheduleFooter ?? (model.resetAnnouncement == nil ? model.resetIntel?.compactLabel : "🔥 USE IT NOW"),
                accessibilityLabel: "24-hour quota reset chance",
                // A custom label is only needed for values such as “>70%”.
                // Otherwise let the dial render its live numeric progress;
                // forcing the fallback string here made every provider read 0%.
                valueLabel: model.forecastLabel,
                roundsPercentDown: false,
                alerting: model.resetAnnouncement != nil
            )

            if !(model.resetIntel?.tweets.isEmpty ?? true) {
                Button {
                    showingTweets = true
                } label: {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: max(8, 11 * interfaceScale), weight: .semibold))
                        .foregroundStyle(Color(hex: 0x58B9F3))
                        .frame(width: max(16, 25 * interfaceScale), height: max(16, 25 * interfaceScale))
                        .background(
                            Circle()
                                .fill(Color(hex: 0x0D1115).opacity(0.9))
                                .overlay(Circle().stroke(Color(hex: 0x58B9F3).opacity(0.42), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .padding(max(4, 8 * interfaceScale))
                .help("Tibo reset posts")
                // Open above the blue dial in the compact vertical layout so
                // the feed gets room to show full post text instead of being
                // squeezed against the bottom of the screen.
                .popover(isPresented: $showingTweets, arrowEdge: .top) {
                    TiboTweetsPopover(tweets: model.resetIntel?.tweets ?? [])
                }
            }
        }
        .background(
            RightClickActionView {
                showingResetDetails = true
            }
        )
        .popover(isPresented: $showingResetDetails, arrowEdge: .bottom) {
            ResetCalculatorPopover(
                snapshot: model.forecastSnapshot,
                status: model.forecastStatus
            )
        }
    }

    private var compactRingView: some View {
        ZStack {
            MountedQuotaRings(
                calendarProgress: model.weekElapsedPercent ?? 0,
                usageProgress: model.usedPercent ?? 0,
                resetProgress: model.forecastPercent ?? 0,
                resetAnnounced: model.resetAnnouncement != nil,
                theme: theme,
                position: .floating
            )

            if !(model.resetIntel?.tweets.isEmpty ?? true) {
                Button {
                    showingTweets = true
                } label: {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0x58B9F3))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(theme.isLight ? Color.white.opacity(0.92) : Color(hex: 0x0D1115).opacity(0.94))
                                .overlay(Circle().stroke(Color(hex: 0x58B9F3).opacity(0.48), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .help("Tibo reset posts")
                .popover(isPresented: $showingTweets, arrowEdge: .top) {
                    TiboTweetsPopover(tweets: model.resetIntel?.tweets ?? [])
                }
            }

            if let expectedAt = activeScheduledResetAt {
                VStack {
                    Spacer()
                    ResetCountdownBadge(expectedAt: expectedAt, compact: true, minimal: true)
                        .padding(.bottom, 3)
                }
                .allowsHitTesting(false)
            }
        }
        .background(
            CompactRingActionView(
                calendarAction: { showingSubscription = true },
                usageAction: { showingUsageChart = true },
                resetAction: { showingResetDetails = true }
            )
        )
        .popover(isPresented: $showingSubscription, arrowEdge: .bottom) {
            SubscriptionInfoPopover(planName: model.planName)
        }
        .popover(isPresented: $showingUsageChart, arrowEdge: .bottom) {
            UsageChartPopover(
                usageDays: model.usageDays,
                usageHistory: model.usageHistory,
                weeklyTokens: model.weeklyTokens,
                localTokensTotal: model.localTokensTotal,
                localTokenPace: model.localTokenPace,
                usedPercent: model.usedPercent,
                windowStartDate: model.usageWindowStart,
                resetAt: model.resetAt,
                paceRate: paceRate
            )
        }
        .popover(isPresented: $showingResetDetails, arrowEdge: .bottom) {
            ResetCalculatorPopover(
                snapshot: model.forecastSnapshot,
                status: model.forecastStatus
            )
        }
        .help("Orange: calendar · Green: Codex usage · Blue: reset estimate")
    }

    private func mountedRingView(position: DockPosition) -> some View {
        GeometryReader { geometry in
            let metrics = DockMetrics(position: position, size: geometry.size)
            ZStack {
                MountedQuotaRings(
                    calendarProgress: model.weekElapsedPercent ?? 0,
                    usageProgress: model.usedPercent ?? 0,
                    resetProgress: model.forecastPercent ?? 0,
                    resetAnnounced: model.resetAnnouncement != nil,
                    theme: theme,
                    position: position
                )

                if !(model.resetIntel?.tweets.isEmpty ?? true) {
                    Button {
                        showingTweets = true
                    } label: {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: 0x58B9F3))
                            .frame(width: 27, height: 27)
                            .background(
                                Circle()
                                    .fill(theme.isLight ? Color.white.opacity(0.94) : Color(hex: 0x0D1115).opacity(0.95))
                                    .overlay(Circle().stroke(Color(hex: 0x58B9F3).opacity(0.52), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .position(metrics.controlPoint)
                    .help("Tibo reset posts")
                    .popover(isPresented: $showingTweets, arrowEdge: metrics.popoverEdge) {
                        TiboTweetsPopover(tweets: model.resetIntel?.tweets ?? [])
                    }
                }

                if let expectedAt = activeScheduledResetAt {
                    ResetCountdownBadge(expectedAt: expectedAt, compact: true, minimal: true)
                        .position(metrics.countdownPoint)
                        .allowsHitTesting(false)
                }
            }
            .background(
                MountedRingActionView(
                    position: position,
                    calendarAction: { showingSubscription = true },
                    usageAction: { showingUsageChart = true },
                    resetAction: { showingResetDetails = true }
                )
            )
        }
        .popover(isPresented: $showingSubscription, arrowEdge: .bottom) {
            SubscriptionInfoPopover(planName: model.planName)
        }
        .popover(isPresented: $showingUsageChart, arrowEdge: .bottom) {
            UsageChartPopover(
                usageDays: model.usageDays,
                usageHistory: model.usageHistory,
                weeklyTokens: model.weeklyTokens,
                localTokensTotal: model.localTokensTotal,
                localTokenPace: model.localTokenPace,
                usedPercent: model.usedPercent,
                windowStartDate: model.usageWindowStart,
                resetAt: model.resetAt,
                paceRate: paceRate
            )
        }
        .popover(isPresented: $showingResetDetails, arrowEdge: .bottom) {
            ResetCalculatorPopover(snapshot: model.forecastSnapshot, status: model.forecastStatus)
        }
        .help("Drag away to unmount · Orange: calendar · Green: usage · Blue: reset")
    }

    private func toggleOrientation() {
        guard let window = NSApp.windows.first(where: { $0.title == "Quota Glance" }) else { return }

        if dockPosition.isMounted {
            WindowDockController.shared.undock(window)
            return
        }

        let oldFrame = window.frame
        let center = CGPoint(x: oldFrame.midX, y: oldFrame.midY)
        let isCompact = max(oldFrame.width, oldFrame.height) < 340
            && oldFrame.width * oldFrame.height < 50_000
        let newVertical = oldFrame.width >= oldFrame.height
        let minimumSize = newVertical
            ? NSSize(width: 140, height: 420)
            : NSSize(width: 420, height: 140)
        let maximumSize = newVertical
            ? NSSize(width: 400, height: 1200)
            : NSSize(width: 1200, height: 400)

        // A three-dial strip has the same area in either orientation. Derive
        // one dial side from the current window area so rotating never causes
        // the dramatic growth produced by independent width/height minimums.
        let oldArea = max(1, oldFrame.width * oldFrame.height)
        let unclampedDialSide = isCompact ? 140 : sqrt(oldArea / 3)
        let dialSide = min(400, max(140, unclampedDialSide))
        let newSize = newVertical
            ? NSSize(width: dialSide, height: dialSide * 3)
            : NSSize(width: dialSide * 3, height: dialSide)

        window.contentMinSize = minimumSize
        window.contentMaxSize = maximumSize
        window.minSize = minimumSize
        window.maxSize = maximumSize

        let newFrame = NSRect(
            x: center.x - newSize.width / 2,
            y: center.y - newSize.height / 2,
            width: newSize.width,
            height: newSize.height
        )
        window.setFrame(newFrame, display: true, animate: true)
    }

    private var resetDay: String {
        guard let date = model.resetAt else { return "—" }
        return date.formatted(.dateTime.weekday(.abbreviated).day()).uppercased()
    }

    private var resetClock: String {
        guard let date = model.resetAt else { return "—" }
        return date.formatted(.dateTime.hour().minute()).uppercased()
    }

    private var usagePace: UsagePace {
        UsagePace.calculate(
            usedPercent: model.usedPercent,
            windowStartDate: model.usageWindowStart,
            resetAt: model.resetAt,
            usageHistory: model.usageHistory,
            localTokensTotal: model.localTokensTotal,
            localTokenPace: model.localTokenPace,
            rate: paceRate
        )
    }

    private var resetAccessibilityLabel: String {
        if model.resetDeadlineIsCredit {
            return "Reset credit expires \(resetDay) at \(resetClock)"
        }
        return "Week elapsed, resets \(resetDay) at \(resetClock)"
    }

    private var activeScheduledResetAt: Date? {
        guard let expectedAt = model.forecastSnapshot?.scheduledReset?.expectedAt,
              expectedAt > Date().addingTimeInterval(-5 * 60)
        else { return nil }
        return expectedAt
    }

    private var resetScheduleFooter: String? {
        guard let expectedAt = activeScheduledResetAt else { return nil }
        return "⏳ \(Self.countdown(to: expectedAt)) · \(Self.localTime(expectedAt))"
    }

    private static func countdown(to date: Date, now: Date = Date()) -> String {
        let totalMinutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)D \(hours)H" }
        if hours > 0 { return "\(hours)H \(minutes)M" }
        return "\(minutes)M"
    }

    private static func localTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "h:mm a z"
        return formatter.string(from: date).uppercased()
    }
}

private struct ResetCountdownBadge: View {
    let expectedAt: Date
    let compact: Bool
    let minimal: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: compact ? 4 : 6) {
                Image(systemName: "hourglass")
                Text(countdown(at: context.date, includesLabel: !minimal))
                if !minimal {
                    Text("·").foregroundStyle(Color.white.opacity(0.28))
                    Text(localTime)
                }
            }
            .font(.system(size: compact ? 7 : 9, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Color(hex: 0x8BD2FF))
            .padding(.horizontal, compact ? 6 : 8)
            .frame(height: compact ? 18 : 22)
            .background(
                Capsule()
                    .fill(Color(hex: 0x07121A).opacity(0.92))
                    .overlay(Capsule().stroke(Color(hex: 0x58B9F3).opacity(0.42), lineWidth: 0.8))
            )
        }
    }

    private func countdown(at now: Date, includesLabel: Bool) -> String {
        let totalMinutes = max(0, Int(ceil(expectedAt.timeIntervalSince(now) / 60)))
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60
        let value: String
        if days > 0 { value = "\(days)D \(hours)H" }
        else if hours > 0 { value = "\(hours)H \(minutes)M" }
        else { value = "\(minutes)M" }
        return includesLabel ? "RESET \(value)" : value
    }

    private var localTime: String {
        let formatter = DateFormatter()
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "h:mm a z"
        return formatter.string(from: expectedAt).uppercased()
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
    @AppStorage(BillingDefaults.renewalTimestamp) private var renewalTimestamp = 0.0
    @AppStorage(BillingDefaults.webPlanName) private var webPlanName = ""
    @AppStorage(BillingDefaults.dateLabel) private var dateLabel = "NEXT RENEWAL"
    @AppStorage(BillingDefaults.lastSuccessfulSync) private var lastSuccessfulSync = 0.0
    @State private var isSyncing = false
    @State private var syncMessage: String?
    @State private var showingDateEditor = false
    @State private var isConnected = BillingKeychain.hasConnectedSession

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
                        .foregroundStyle(Color.white.opacity(0.38))
                    Text((webPlanName.isEmpty ? planName : webPlanName).uppercased())
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                Spacer()
                Circle()
                    .fill(isConnected ? Color(hex: 0x7EE6AE) : Color.white.opacity(0.2))
                    .frame(width: 7, height: 7)
                Text(isConnected ? verificationLabel : "LOCAL ONLY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.46))
            }
            .padding(.bottom, 18)

            if let renewalDate {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(dateLabel.replacingOccurrences(of: "PLAN ", with: ""))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(hex: 0xF2AD3E).opacity(0.8))
                        Text(renewalDate.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.system(size: 38, weight: .light, design: .rounded))
                            .tracking(-1.4)
                        Text(renewalDate.formatted(.dateTime.year()))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.38))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(countdownNumber(to: renewalDate))
                            .font(.system(size: 34, weight: .light, design: .rounded))
                            .monospacedDigit()
                        Text(countdownUnit(to: renewalDate))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }

                Rectangle()
                    .fill(Color(hex: 0xF2AD3E))
                    .frame(height: 2)
                    .padding(.vertical, 14)

                HStack(spacing: 9) {
                    Image(systemName: dateLabel.contains("CHANGES TO PLUS") ? "arrow.down.right" : "bell")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0xF2AD3E))
                    Text(dateLabel.contains("CHANGES TO PLUS") ? "$20 PLAN SCHEDULED" : "DOWNGRADE BEFORE RENEWAL")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    Spacer()
                    Button {
                        showingDateEditor.toggle()
                    } label: {
                        Image(systemName: "pencil")
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.white.opacity(0.07)))
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
                    .foregroundStyle(Color.white.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 18)
            }

            Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 14)

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
                    .foregroundStyle(Color.white.opacity(0.44))
                    .padding(.top, 10)
            }
        }
        .padding(18)
        .frame(width: 334)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: 0x101419))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(hex: 0xF2AD3E).opacity(0.28), lineWidth: 1)
                )
        )
        .preferredColorScheme(.dark)
        .onAppear {
            rollRenewalForwardIfNeeded()
            isConnected = BillingKeychain.hasConnectedSession
        }
        .onReceive(NotificationCenter.default.publisher(for: .quotaGlanceBillingUpdated)) { _ in
            isConnected = true
        }
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
            .foregroundStyle(Color.white.opacity(0.72))
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
        case .left: return CGPoint(x: inset, y: size.height / 2)
        case .right: return CGPoint(x: size.width - inset, y: size.height / 2)
        case .top: return CGPoint(x: size.width / 2, y: inset)
        case .bottom: return CGPoint(x: size.width / 2, y: size.height - inset)
        case .floating: return center
        }
    }

    var countdownPoint: CGPoint {
        let inward: CGFloat = 48
        let cross: CGFloat = 38
        switch position {
        case .topLeft, .topRight:
            return CGPoint(x: size.width / 2, y: size.height * 0.76)
        case .bottomLeft, .bottomRight:
            return CGPoint(x: size.width / 2, y: size.height * 0.24)
        case .left: return CGPoint(x: inward + 20, y: size.height / 2 + cross)
        case .right: return CGPoint(x: size.width - inward - 20, y: size.height / 2 + cross)
        case .top: return CGPoint(x: size.width / 2 + cross, y: inward + 14)
        case .bottom: return CGPoint(x: size.width / 2 + cross, y: size.height - inward - 14)
        case .floating: return CGPoint(x: size.width / 2, y: size.height - 16)
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
    let resetAnnounced: Bool
    let theme: WidgetTheme
    let position: DockPosition

    var body: some View {
        GeometryReader { geometry in
            let metrics = DockMetrics(position: position, size: geometry.size)
            let strokeBasis = min(geometry.size.width, geometry.size.height)
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
                    width: strokeBasis * 0.075,
                    metrics: metrics
                )
                mountedPercentage(
                    progress: calendarProgress,
                    color: palette.orange,
                    diameter: metrics.diameter * 0.82,
                    width: strokeBasis * 0.075,
                    metrics: metrics,
                    roundsDown: true
                )
                mountedRing(
                    progress: usageProgress,
                    color: palette.green,
                    diameter: metrics.diameter * 0.61,
                    width: strokeBasis * 0.072,
                    metrics: metrics
                )
                mountedPercentage(
                    progress: usageProgress,
                    color: palette.green,
                    diameter: metrics.diameter * 0.61,
                    width: strokeBasis * 0.072,
                    metrics: metrics,
                    roundsDown: false
                )
                mountedRing(
                    progress: resetProgress,
                    color: palette.blue,
                    diameter: metrics.diameter * 0.40,
                    width: strokeBasis * 0.067,
                    metrics: metrics,
                    alerting: resetAnnounced
                )
                mountedPercentage(
                    progress: resetProgress,
                    color: palette.blue,
                    diameter: metrics.diameter * 0.40,
                    width: strokeBasis * 0.067,
                    metrics: metrics,
                    roundsDown: false
                )
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
        return Text("\(Int(max(0, min(100, visibleValue))))%")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(theme.isLight ? Color.white.opacity(0.82) : Color(hex: 0x080B0E).opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(color.opacity(0.22), lineWidth: 0.7)
                    )
            )
            .position(percentagePosition(progress: progress, diameter: diameter, width: width, metrics: metrics))
            .allowsHitTesting(false)
    }

    private func percentagePosition(progress: Double, diameter: CGFloat, width: CGFloat, metrics: DockMetrics) -> CGPoint {
        let fraction = max(0, min(1, progress / 100))
        let angle = CGFloat(metrics.arc.start + metrics.arc.sweep * fraction) * .pi / 180
        // Pull the number just inside its live endpoint, then clamp it away
        // from the clipped screen boundary so every value remains legible.
        let radius = metrics.position == .floating
            ? diameter / 2 + width / 2 + 8
            : max(8, diameter / 2 - width / 2 - 14)
        let raw = CGPoint(
            x: metrics.center.x + cos(angle) * radius,
            y: metrics.center.y + sin(angle) * radius
        )
        return CGPoint(
            x: min(max(raw.x, 19), max(19, metrics.size.width - 19)),
            y: min(max(raw.y, 12), max(12, metrics.size.height - 12))
        )
    }

    private var palette: (orange: Color, green: Color, blue: Color) {
        switch theme {
        case .eInk: return (Color(hex: 0xA85D00), Color(hex: 0x18704B), Color(hex: 0x17658F))
        case .marine: return (Color(hex: 0xF1B84B), Color(hex: 0x83E2AE), Color(hex: 0x5DAFE5))
        case .retro: return (Color(hex: 0xFFB21F), Color(hex: 0x63E18A), Color(hex: 0x3EA9F5))
        case .radar: return (Color(hex: 0xFFC34D), Color(hex: 0x71E3AC), Color(hex: 0x46B8F4))
        case .oled, .current: return (Color(hex: 0xF2AD3E), Color(hex: 0x7EE6AE), Color(hex: 0x58B9F3))
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

    private var trackOpacity: Double { theme == .eInk ? 0.34 : (theme == .marine ? 0.22 : 0.15) }
    private var shadowOpacity: Double { theme == .eInk ? 0 : (theme == .marine ? 0.22 : 0.44) }
}

/// Codex Fast-style motion: several low-contrast blue bands flow inside the
/// existing reset fill. The animation is timer-driven at five frames per second.
private enum ResetAlertBar {
    static let highlight = Color(hex: 0xBCE8FF)
    static let flowingGradient = Gradient(stops: [
        .init(color: Color(hex: 0x58B9F3), location: 0.00),
        .init(color: Color(hex: 0x58B9F3), location: 0.07),
        .init(color: Color(hex: 0xBCE8FF), location: 0.12),
        .init(color: Color(hex: 0x58B9F3), location: 0.18),
        .init(color: Color(hex: 0x58B9F3), location: 0.39),
        .init(color: Color(hex: 0xA6DFFF), location: 0.45),
        .init(color: Color(hex: 0x58B9F3), location: 0.51),
        .init(color: Color(hex: 0x58B9F3), location: 0.72),
        .init(color: Color(hex: 0xBCE8FF), location: 0.78),
        .init(color: Color(hex: 0x58B9F3), location: 0.84),
        .init(color: Color(hex: 0x58B9F3), location: 1.00),
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
        if distance < 0.19 { return Color(hex: 0x83CEF7) }
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
                ring(progress: usageProgress, color: palette.green, diameter: side * 0.61, width: side * 0.072)
                ring(progress: resetProgress, color: palette.blue, diameter: side * 0.40, width: side * 0.067)

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

    private var palette: (orange: Color, green: Color, blue: Color) {
        switch theme {
        case .eInk:
            return (Color(hex: 0xA85D00), Color(hex: 0x18704B), Color(hex: 0x17658F))
        case .marine:
            return (Color(hex: 0xF1B84B), Color(hex: 0x83E2AE), Color(hex: 0x5DAFE5))
        case .retro:
            return (Color(hex: 0xFFB21F), Color(hex: 0x63E18A), Color(hex: 0x3EA9F5))
        case .radar:
            return (Color(hex: 0xFFC34D), Color(hex: 0x71E3AC), Color(hex: 0x46B8F4))
        case .oled, .current:
            return (Color(hex: 0xF2AD3E), Color(hex: 0x7EE6AE), Color(hex: 0x58B9F3))
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
    let status: String

    private var detailProvider: ResetProviderSnapshot? {
        guard let snapshot else { return nil }
        if snapshot.source == .average {
            return snapshot.providers.first { $0.source == .lunarWerx } ?? snapshot.providers.first
        }
        return snapshot.providers.first { $0.source == snapshot.source }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: 0x58B9F3))
                VStack(alignment: .leading, spacing: 1) {
                    Text("RESET CALCULATOR")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.48))
                    Text(snapshot?.source.displayName ?? "Reset estimate")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.94))
                }
                Spacer()
                Text(updatedLabel)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.38))
            }

            if let snapshot {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(Int(snapshot.score.rounded()))%")
                        .font(.system(size: 40, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.95))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NEXT 24 HOURS")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(hex: 0x58B9F3))
                        if let range = snapshot.range {
                            Text("range \(Int(range.lowerBound.rounded()))–\(Int(range.upperBound.rounded()))%")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                    }
                }

                if let schedule = snapshot.scheduledReset, schedule.expectedAt > Date().addingTimeInterval(-5 * 60) {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        HStack(spacing: 10) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x58B9F3))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("RESET COUNTDOWN")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.42))
                                Text(schedule.expectedAt, style: .timer)
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.white.opacity(0.94))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(schedule.expectedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                Text(Self.timeZoneLabel(for: schedule.expectedAt))
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color(hex: 0x58B9F3))
                            }
                        }
                        .padding(11)
                        .background(RoundedRectangle(cornerRadius: 11).fill(Color(hex: 0x58B9F3).opacity(0.09)))
                    }
                }

                if let headline = snapshot.headline, !headline.isEmpty {
                    Text(headline)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
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
                            .foregroundStyle(Color.white.opacity(0.38))
                        ForEach(provider.signals.prefix(3)) { signal in
                            HStack(alignment: .top, spacing: 7) {
                                Circle()
                                    .fill(signal.value == "ACTIVE" ? Color(hex: 0x7EE6AE) : Color.white.opacity(0.28))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(signal.label)
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.white.opacity(0.78))
                                    if let detail = signal.detail {
                                        Text(detail)
                                            .font(.system(size: 9, weight: .regular, design: .rounded))
                                            .foregroundStyle(Color.white.opacity(0.44))
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                }

                Divider().overlay(Color.white.opacity(0.09))

                VStack(spacing: 5) {
                    ForEach(ForecastSource.calculatorCases) { source in
                        providerRow(source, provider: snapshot.providers.first { $0.source == source })
                    }
                }
            } else {
                Text(status)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.vertical, 20)
            }
        }
        .padding(15)
        .frame(width: 380)
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

    private func metricTile(_ metric: ResetMetric) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.label.uppercased())
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.36))
                .lineLimit(1)
            Text(metric.value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.86))
            if let detail = metric.detail {
                Text(detail)
                    .font(.system(size: 8, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.045)))
    }

    private func providerRow(_ source: ForecastSource, provider: ResetProviderSnapshot?) -> some View {
        Button {
            if let url = source.url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(provider == nil ? Color.white.opacity(0.16) : Color(hex: 0x58B9F3))
                    .frame(width: 6, height: 6)
                Text(source.displayName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.72))
                Spacer()
                Text(provider?.score.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(provider == nil ? Color.white.opacity(0.28) : Color.white.opacity(0.78))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.28))
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

private struct NewTweetAlertPopover: View {
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
            .frame(maxHeight: 240)

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
        .frame(width: 350)
        .background(Color(hex: 0x101419))
        .preferredColorScheme(.dark)
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
                    localTokens: $0.localTokensTotal
                )
            }
            .sorted { $0.date < $1.date }

        if let usedPercent {
            readings.append(
                (
                    date: now,
                    percent: max(0, min(100, usedPercent)),
                    localTokens: localTokensTotal
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
            if let tokenBurn, tokenBurn > 0,
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
        from readings: [(date: Date, percent: Double, localTokens: Int64?)],
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
        from readings: [(date: Date, percent: Double, localTokens: Int64?)]
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
    let usedPercent: Double?
    let windowStartDate: Date?
    let resetAt: Date?
    let paceRate: UsagePaceRate
    @State private var hoveredPoint: UsageHoverPoint?
    @State private var chartRange = UsageChartRange.window

    private var pace: UsagePace {
        UsagePace.calculate(
            usedPercent: usedPercent,
            windowStartDate: windowStartDate,
            resetAt: resetAt,
            usageHistory: usageHistory,
            localTokensTotal: localTokensTotal,
            localTokenPace: localTokenPace,
            rate: paceRate
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: 0x7EE6AE))
                    .frame(width: 7, height: 7)
                Text("CODEX / " + paceRate.compactLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(Color.white.opacity(0.48))
                Spacer()
                Text("LIVE TOKENS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x7EE6AE).opacity(0.7))
            }

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(shortPaceTitle)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(statusColor)
                    Text(pace.detail)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.48))
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(pace.estimatedRunout.uppercased())
                        .font(.system(size: 27, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.94))
                    Text("TO EMPTY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Color.white.opacity(0.34))
                }
            }

            Rectangle().fill(statusColor).frame(height: 2)

            HStack(spacing: 0) {
                paceMetric("BURN", value: localTokenPace.map { formatTokens($0.tokens(for: paceRate)).replacingOccurrences(of: " TOKENS", with: "") } ?? "—")
                paceMetric("USED", value: usedPercent.map { "\(Int($0.rounded()))%" } ?? "—")
                paceMetric("SAMPLE", value: UsageHistoryStore.sampleIntervalDescription().uppercased())
            }

            HStack(spacing: 14) {
                legend(color: Color(hex: 0x7EE6AE), label: "SAVED QUOTA + TOKENS")
                legend(color: Color.white.opacity(0.5), label: "IDEAL", dotted: true)
                Spacer()
                Text("\(savedPointCount) SAVED · DISK")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.3))
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.34))
                ForEach(UsageChartRange.allCases) { range in
                    Button {
                        hoveredPoint = nil
                        chartRange = range
                    } label: {
                        Text(range.label)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .foregroundStyle(
                                chartRange == range
                                    ? Color(hex: 0x101419)
                                    : Color.white.opacity(0.48)
                            )
                            .background(
                                Capsule().fill(
                                    chartRange == range
                                        ? Color(hex: 0x7EE6AE)
                                        : Color.white.opacity(0.05)
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .help("Choose a range, pinch to zoom, or double-click the chart to reset")

            if hoveredPoint != nil {
                UsageHoverReadout(point: hoveredPoint)
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
                range: $chartRange,
                hoveredPoint: $hoveredPoint
            )
            .frame(height: 186)
        }
        .padding(18)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: 0x101419))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(hex: 0x7EE6AE).opacity(0.22), lineWidth: 1)
                )
        )
        .preferredColorScheme(.dark)
    }

    private var statusColor: Color {
        pace.title.contains("early") ? Color(hex: 0xF2AD3E) : Color(hex: 0x7EE6AE)
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

    private func paceMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.3))
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
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
                .foregroundStyle(Color.white.opacity(0.48))
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
    let isCurrent: Bool
}

private struct UsageHoverReadout: View {
    let point: UsageHoverPoint?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(point.map { $0.isCurrent ? "CURRENT WINDOW" : dateLabel($0.date) } ?? "HOVER FOR DAILY DETAIL")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.48))
                Text(point.map { $0.sourceLabel } ?? "Move across the chart · saved every \(UsageHistoryStore.sampleIntervalDescription())")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.72))
            }

            Spacer(minLength: 4)

            if let point {
                HStack(spacing: 10) {
                    metric(label: "USED", value: "\(Int(point.actualPercent.rounded()))%", color: Color(hex: 0x7EE6AE))
                    metric(label: "IDEAL", value: "\(Int(point.idealPercent.rounded()))%", color: Color.white.opacity(0.72))
                    metric(
                        label: point.tokenLabel,
                        value: formatTokens(point.tokens),
                        color: Color(hex: 0x58B9F3)
                    )
                }
            } else {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.32))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    @ViewBuilder
    private func metric(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.36))
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
    @Binding var range: UsageChartRange
    @Binding var hoveredPoint: UsageHoverPoint?

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
        let yDomain = verticalDomain(samples: samples, idealStart: idealStart, idealEnd: idealEnd)

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
                with: .color(Color.white.opacity(step == 0 ? 0.2 : 0.08)),
                style: StrokeStyle(lineWidth: step == 0 ? 1 : 0.7)
            )
            context.draw(
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.34)),
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
            with: .color(Color.white.opacity(0.52)),
            style: StrokeStyle(lineWidth: 1.4, dash: [3, 3])
        )

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
                with: .color(Color(hex: 0x7EE6AE).opacity(0.28)),
                style: StrokeStyle(lineWidth: 1.2, dash: [2, 5])
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: baseline.x - 3, y: baseline.y - 3, width: 6, height: 6)),
                with: .color(Color(hex: 0x7EE6AE).opacity(0.72)),
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
                with: .color(Color(hex: 0x7EE6AE)),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
            )
        }

        if let current = observedPoints.last {
            context.fill(
                Path(ellipseIn: CGRect(x: current.x - 3.5, y: current.y - 3.5, width: 7, height: 7)),
                with: .color(Color(hex: 0x7EE6AE))
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
                with: .color(Color(hex: 0x58B9F3).opacity(0.7)),
                style: StrokeStyle(lineWidth: 1, dash: [2, 3])
            )

            let actualY = yPosition(hoveredPoint.actualPercent / 100, domain: yDomain, plot: plot)
            let idealY = yPosition(hoveredPoint.idealPercent / 100, domain: yDomain, plot: plot)
            context.fill(
                Path(ellipseIn: CGRect(x: hoverX - 4, y: actualY - 4, width: 8, height: 8)),
                with: .color(Color(hex: 0x7EE6AE))
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: hoverX - 4, y: idealY - 4, width: 8, height: 8)),
                with: .color(Color.white.opacity(0.8)),
                style: StrokeStyle(lineWidth: 1, dash: [2, 2])
            )
        }

        context.draw(
            Text(axisLabel(domain.start))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.34)),
            at: CGPoint(x: plot.minX, y: plot.maxY + 12),
            anchor: .leading
        )
        context.draw(
            Text(axisLabel(domain.end))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.34)),
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
        idealStart: Double,
        idealEnd: Double
    ) -> ClosedRange<Double> {
        guard range != .window else { return 0...1 }
        let values = samples.map(\.actualFraction) + [idealStart, idealEnd]
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
