import AppKit
import SwiftUI

@MainActor
private final class ProviderTravelPresentation: ObservableObject {
    @Published var physics: ProviderTravelPhysics
    @Published var greeting: Date?
    init(_ physics: ProviderTravelPhysics) { self.physics = physics }
}

/// Only the visible vehicle and its banner catch the mouse. The native window
/// follows their bounding box; it never occupies an invisible screen-wide strip.
@MainActor
final class ProviderTravelController: NSObject, NSPopoverDelegate {
    private(set) var panel: ProviderPanel?
    private var physics: ProviderTravelPhysics
    private let presentation: ProviderTravelPresentation
    private let selection: ProviderSelection
    private let reducedMotion: Bool
    private weak var owner: ProviderDisplayController?
    private var surface: ProviderTravelSurface?
    private var hosting: NSHostingView<ProviderTravelScene>?
    private var frameTimer: Timer?
    private var nextVisit: Task<Void, Never>?
    private var popover: NSPopover?
    private var stopped = false
    private var menuOpen = false
    private var visitStarted: TimeInterval = 0
    private var lastFrame: TimeInterval = 0
    private var nextFromLeft = true
    private var grabOffset = CGPoint.zero
    private var lastDragPoint = CGPoint.zero
    private var lastDragTime: TimeInterval = 0
    private var frequency: ProviderTravelFrequency
    var isInteracting: Bool { physics.isHeld || menuOpen || popover?.isShown == true }

    init(kind: ProviderTravelKind, screen: NSScreen, owner: ProviderDisplayController) {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let pose = ProviderTravelPhysics(kind: kind, bounds: screen.visibleFrame, parked: reduced, providerCount: owner.selection.providers.count)
        physics = pose; presentation = ProviderTravelPresentation(pose)
        selection = owner.selection; reducedMotion = reduced; self.owner = owner; frequency = owner.travelFrequency
        super.init()
    }

    func start() {
        let window = ProviderPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Quota Glance · " + (physics.kind == .plane ? "Fly-by" : physics.kind == .balloon ? "Balloon ride" : "Skateboard parade")
        window.identifier = NSUserInterfaceItemIdentifier("QuotaGlance.Travel")
        window.isReleasedWhenClosed = false; window.isRestorable = false
        window.isFloatingPanel = true; window.hidesOnDeactivate = false
        window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
        let surface = ProviderTravelSurface()
        surface.setAccessibilityLabel(selection.windowTitle + " ride. Drag to steer, click for stats.")
        surface.wantsLayer = true; surface.layer?.masksToBounds = true
        surface.onGrab = { [weak self] point, time in self?.grab(at: point, time: time) }
        surface.onDrag = { [weak self] point, time in self?.drag(to: point, time: time) }
        surface.onRelease = { [weak self] moved, point in self?.release(moved: moved, point: point) }
        surface.onMenu = { [weak self] event in self?.showMenu(event) }
        surface.onPress = { [weak self] in self?.showDetails(at: self?.physics.position ?? .zero) }
        let host = NSHostingView(rootView: ProviderTravelScene(presentation: presentation, codex: .shared,
                                                             claude: ClaudeBarController.shared.model, selection: selection, reducedMotion: reducedMotion))
        host.sizingOptions = []
        surface.addSubview(host)
        window.contentView = surface
        self.surface = surface; hosting = host; panel = window
        beginVisit()
    }

    func stop() {
        stopped = true
        nextVisit?.cancel(); nextVisit = nil
        frameTimer?.invalidate(); frameTimer = nil
        popover?.close(); popover = nil
        panel?.contentView = nil; panel?.close(); panel = nil
        hosting = nil; surface = nil
    }

    func setFrequency(_ value: ProviderTravelFrequency) {
        frequency = value
        if frameTimer == nil { scheduleVisit() }
    }

    private func beginVisit() {
        guard !stopped else { return }
        nextVisit = nil
        physics = ProviderTravelPhysics(kind: physics.kind, bounds: physics.bounds, fromLeft: nextFromLeft, parked: reducedMotion, providerCount: selection.providers.count)
        nextFromLeft.toggle()
        visitStarted = ProcessInfo.processInfo.systemUptime; lastFrame = visitStarted
        presentation.greeting = .now
        draw()
        let timer = Timer(timeInterval: reducedMotion ? 1.0 / 15 : 1.0 / 30, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    @objc private func tick() {
        guard !stopped else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastFrame; lastFrame = now
        let pointer = NSEvent.mouseLocation
        let underPointer = physics.vehicleRect.insetBy(dx: -6, dy: -6).contains(pointer) || physics.bannerRect.contains(pointer)
        physics.isPaused = menuOpen || popover?.isShown == true
        panel?.ignoresMouseEvents = !underPointer && !physics.isHeld && !menuOpen && popover?.isShown != true
        physics.step(elapsed, parked: reducedMotion)
        draw()
        if physics.hasExited || (reducedMotion && now - visitStarted > 12 && !physics.isHeld && !physics.isPaused) {
            frameTimer?.invalidate(); frameTimer = nil
            panel?.orderOut(nil)
            scheduleVisit()
        }
    }

    private func scheduleVisit() {
        nextVisit?.cancel()
        guard !stopped else { return }
        let delay = frequency.rest(after: ProcessInfo.processInfo.systemUptime - visitStarted)
        nextVisit = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.beginVisit()
        }
    }

    private func draw() {
        guard let panel, let surface, let hosting else { return }
        let full = physics.renderBounds.integral
        let visible = full.intersection(physics.bounds)
        guard !visible.isNull, visible.width > 0, visible.height > 0 else {
            panel.orderOut(nil); return
        }
        presentation.physics = physics
        panel.setFrame(visible, display: false)
        hosting.frame = CGRect(x: full.minX - visible.minX, y: full.minY - visible.minY, width: full.width, height: full.height)
        surface.vehicle = physics.vehicleRect.offsetBy(dx: -visible.minX, dy: -visible.minY)
        surface.banner = physics.bannerRect.offsetBy(dx: -visible.minX, dy: -visible.minY)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func grab(at point: CGPoint, time: TimeInterval) {
        popover?.close()
        grabOffset = CGPoint(x: point.x - physics.position.x, y: point.y - physics.position.y)
        lastDragPoint = point; lastDragTime = time
        physics.grab(); presentation.greeting = .now
        panel?.ignoresMouseEvents = false
    }

    private func drag(to point: CGPoint, time: TimeInterval) {
        let delta = max(1.0 / 120, time - lastDragTime)
        let measured = CGVector(dx: (point.x - lastDragPoint.x) / delta, dy: (point.y - lastDragPoint.y) / delta)
        let velocity = CGVector(dx: physics.velocity.dx * 0.3 + measured.dx * 0.7,
                                dy: physics.velocity.dy * 0.3 + measured.dy * 0.7)
        physics.drag(to: CGPoint(x: point.x - grabOffset.x, y: point.y - grabOffset.y), velocity: velocity)
        lastDragPoint = point; lastDragTime = time
        draw()
    }

    private func release(moved: Bool, point: CGPoint) {
        // Holding still before release should drop the ride, not replay an old throw.
        if ProcessInfo.processInfo.systemUptime - lastDragTime > 0.15 { physics.velocity = .zero }
        physics.release()
        if !moved { showDetails(at: point) }
    }

    private func showDetails(at point: CGPoint) {
        guard let surface, let panel else { return }
        if popover?.isShown == true { popover?.close(); return }
        let selected: DisplayProvider = selection == .both && physics.bannerRect.contains(point) && point.y < physics.bannerPosition.y ? .claude : selection.providers[0]
        let popover = NSPopover()
        popover.behavior = .transient; popover.animates = !reducedMotion; popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: ProviderTravelDetails(selection: selected, providers: selection.providers))
        self.popover = popover
        physics.isPaused = true
        presentation.greeting = .now
        let anchor = CGRect(x: min(surface.bounds.maxX - 2, max(0, point.x - panel.frame.minX - 1)),
                            y: min(surface.bounds.maxY - 2, max(0, point.y - panel.frame.minY - 1)), width: 2, height: 2)
        popover.show(relativeTo: anchor.intersection(surface.bounds), of: surface,
                     preferredEdge: physics.kind == .skateboard ? .maxY : .minY)
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
    }

    private func showMenu(_ event: NSEvent) {
        guard let surface, let owner else { return }
        menuOpen = true
        NSMenu.popUpContextMenu(owner.contextMenu(), with: event, for: surface)
        menuOpen = false
    }
}

private struct ProviderTravelScene: View {
    @ObservedObject var presentation: ProviderTravelPresentation
    @ObservedObject var codex: MenuBarSummaryModel
    @ObservedObject var claude: ClaudeUsageModel
    let selection: ProviderSelection
    let reducedMotion: Bool
    var body: some View {
        ProviderTravelComposition(physics: presentation.physics, readings: selection.filter([.codex(codex, at: .now), .claude(claude, at: .now)]),
                                  animated: !reducedMotion, greeting: presentation.greeting)
            .preferredColorScheme(.light)
    }
}

private struct ProviderTravelDetails: View {
    @State var selection: DisplayProvider
    let providers: [DisplayProvider]
    var body: some View {
        VStack(spacing: 0) {
            if providers.count > 1 {
                Picker("Provider", selection: $selection) {
                    ForEach(providers) { Text($0.name).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 18).padding(.top, 14)
            }
            ProviderDetailView(provider: selection, codex: .shared, claude: ClaudeBarController.shared.model)
            Text("Drag to steer. Release to send them on their way.")
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 12)
        }.frame(width: 346)
    }
}

@MainActor
private final class ProviderTravelSurface: NSView {
    var vehicle = CGRect.zero
    var banner = CGRect.zero
    var onGrab: ((CGPoint, TimeInterval) -> Void)?
    var onDrag: ((CGPoint, TimeInterval) -> Void)?
    var onRelease: ((Bool, CGPoint) -> Void)?
    var onMenu: ((NSEvent) -> Void)?
    var onPress: (() -> Void)?
    private var down = CGPoint.zero
    private var dragged = false
    private var trackingDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Quota ride. Drag to steer, click for Codex and Claude stats.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return vehicle.insetBy(dx: -6, dy: -6).contains(local) || banner.contains(local) ? self : nil
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { onMenu?(event); return }
        down = NSEvent.mouseLocation; dragged = false
        trackingDrag = true
        NSCursor.closedHand.push()
        onGrab?(down, event.timestamp)
    }
    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        if hypot(point.x - down.x, point.y - down.y) > 3 { dragged = true }
        if dragged { onDrag?(point, event.timestamp) }
    }
    override func mouseUp(with event: NSEvent) {
        guard trackingDrag else { return }
        trackingDrag = false
        NSCursor.pop()
        onRelease?(dragged, NSEvent.mouseLocation)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil && trackingDrag { NSCursor.pop(); trackingDrag = false }
        super.viewWillMove(toWindow: newWindow)
    }
    override func rightMouseDown(with event: NSEvent) { onMenu?(event) }
    override func accessibilityPerformPress() -> Bool { onPress?(); return true }
}
