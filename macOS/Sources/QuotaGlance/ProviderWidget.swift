import AppKit
import SwiftUI

enum ProviderSelection: String, CaseIterable, Identifiable {
    case codex, claude, both
    static let defaultsKey = "QuotaGlance.providers.selection"
    var id: String { rawValue }
    var title: String { self == .both ? "Both" : self == .codex ? "Codex" : "Claude" }
    var providers: [DisplayProvider] { self == .both ? [.codex, .claude] : self == .codex ? [.codex] : [.claude] }
    var windowTitle: String { providers.map(\.name).joined(separator: " + ") }
    func contains(_ provider: DisplayProvider) -> Bool { providers.contains(provider) }
    func filter(_ readings: [ProviderReading]) -> [ProviderReading] { readings.filter { contains($0.provider) } }
    static func resolved(_ raw: String?) -> Self { raw.flatMap(Self.init(rawValue:)) ?? .both }
    static var current: Self { resolved(UserDefaults.standard.string(forKey: defaultsKey)) }
}

enum ProviderDisplayStyle: String, CaseIterable, Identifiable {
    case edgeWings, twinDials, stackedSlate, metricMatrix, cornerBlade
    case cornerDials, cornerPerches, cornerArcs
    case screenBuddies, peekaboo, flyBy, balloonRide, skateParade
    static let defaultsKey = "QuotaGlance.providerDisplayStyle"
    var id: String { rawValue }

    static func resolved(_ raw: String?) -> Self {
        if let raw, let style = Self(rawValue: raw) { return style }
        switch raw {
        case "notch": return .edgeWings
        case "rail": return .cornerBlade
        default: return .stackedSlate
        }
    }

    static var current: Self { resolved(UserDefaults.standard.string(forKey: defaultsKey)) }
    var title: String {
        switch self {
        case .edgeWings: return "Edge wings"
        case .twinDials: return "Twin dials"
        case .stackedSlate: return "Stacked slate"
        case .metricMatrix: return "Metric matrix"
        case .cornerBlade: return "Corner blade"
        case .cornerDials: return "Split corner dials"
        case .cornerPerches: return "Dock perches"
        case .cornerArcs: return "Corner arcs"
        case .screenBuddies: return "Screen buddies"
        case .peekaboo: return "Peekaboo"
        case .flyBy: return "Fly-by"
        case .balloonRide: return "Balloon ride"
        case .skateParade: return "Skateboard parade"
        }
    }
    var isDark: Bool { self != .stackedSlate }
    func title(for selection: ProviderSelection) -> String {
        guard selection != .both else { return title }
        switch self {
        case .twinDials: return "Pet dial"
        case .stackedSlate: return "Quota ticket"
        case .screenBuddies: return "Screen buddy"
        case .cornerDials: return "Corner dial"
        default: return title
        }
    }
    var isCompanion: Bool { self == .screenBuddies || self == .peekaboo || travelKind != nil }
    var isCorner: Bool { self == .cornerDials || self == .cornerPerches || self == .cornerArcs }
    var canDrag: Bool { !isCorner && self != .edgeWings && !isCompanion }
    var group: ProviderLayoutGroup {
        switch self {
        case .twinDials, .stackedSlate, .metricMatrix: return .floating
        case .edgeWings, .cornerBlade, .screenBuddies: return .edges
        case .cornerDials, .cornerPerches, .cornerArcs: return .corners
        case .peekaboo, .flyBy, .balloonRide, .skateParade: return .motion
        }
    }
    var travelKind: ProviderTravelKind? {
        switch self { case .flyBy: return .plane; case .balloonRide: return .balloon; case .skateParade: return .skateboard; default: return nil }
    }
    var caption: String {
        switch self {
        case .edgeWings: return "Live meters along the top edge."
        case .twinDials: return "Pet portholes. Float them anywhere."
        case .stackedSlate: return "Quota tickets resting above the Dock."
        case .metricMatrix: return "A tiny quota arcade for your desktop."
        case .cornerBlade: return "A bookmark clipped to the right edge."
        case .cornerDials: return "Three rings, one little pet in each bottom corner."
        case .cornerPerches: return "Pet shelves in the bottom corners beside the Dock."
        case .cornerArcs: return "Three curved meters tucked into the bottom corners."
        case .screenBuddies: return "Pets hang from the edge. Click for a wave + stats."
        case .peekaboo: return "A pet drops by on your schedule, then tucks away."
        case .flyBy: return "Catch the plane. Toss it back into flight."
        case .balloonRide: return "A floating pet basket. Tug it through the clouds."
        case .skateParade: return "A pet skate crew. Flick, drop, and roll."
        }
    }
}

enum ProviderLayoutGroup: String, CaseIterable, Identifiable {
    case floating, edges, corners, motion
    var id: String { rawValue }
    var title: String {
        switch self { case .floating: "Floating"; case .edges: "Screen edges"; case .corners: "Dock corners"; case .motion: "In motion" }
    }
    var symbol: String {
        switch self { case .floating: "rectangle.on.rectangle"; case .edges: "rectangle.topthird.inset.filled"; case .corners: "rectangle.bottomthird.inset.filled"; case .motion: "paperplane" }
    }
    var caption: String {
        switch self {
        case .floating: "Drag these views anywhere on your screen."
        case .edges: "Keep your companions along the screen’s edges."
        case .corners: "Codex on the left. Claude on the right. Anchored to the bottom corners."
        case .motion: "Companions that drop in, fly past, or roll through."
        }
    }
    var styles: [ProviderDisplayStyle] { ProviderDisplayStyle.allCases.filter { $0.group == self } }
}

enum ProviderDisplayGeometry {
    static let edgeCellWidth: CGFloat = 226
    static let edgeHeight: CGFloat = 40
    static let cornerWidth: CGFloat = 100

    static func size(style: ProviderDisplayStyle, providerCount: Int = 2) -> NSSize {
        let solo = providerCount == 1
        switch style {
        case .edgeWings: return NSSize(width: edgeCellWidth * (solo ? 1 : 2), height: edgeHeight)
        case .twinDials: return NSSize(width: solo ? 140 : 284, height: 166)
        case .stackedSlate: return NSSize(width: 296, height: solo ? 84 : 158)
        case .metricMatrix: return NSSize(width: solo ? 134 : 242, height: 200)
        case .cornerBlade: return NSSize(width: 142, height: solo ? 124 : 228)
        case .cornerDials: return NSSize(width: solo ? cornerWidth : cornerWidth * 2 + 40, height: 110)
        case .cornerPerches: return NSSize(width: solo ? cornerWidth : cornerWidth * 2 + 40, height: 114)
        case .cornerArcs: return NSSize(width: solo ? cornerWidth : cornerWidth * 2 + 40, height: 106)
        case .screenBuddies: return NSSize(width: solo ? 176 : 260, height: 128)
        case .peekaboo: return NSSize(width: 272, height: 116)
        case .flyBy: return NSSize(width: 533, height: 144)
        case .balloonRide: return NSSize(width: 314, height: solo ? 333 : 344)
        case .skateParade: return NSSize(width: 551, height: solo ? 147 : 158)
        }
    }

    /// Use the physical screen corners. The Dock's visibleFrame inset spans
    /// the entire display, so it must not lift these widgets above the Dock.
    /// Their fixed footprint does not change with the user's Dock size.
    static func cornerFrames(style: ProviderDisplayStyle, screen: NSRect,
                             selection: ProviderSelection) -> [NSRect] {
        let size = size(style: style, providerCount: 1)
        return selection.providers.map { provider in
            NSRect(x: provider == .codex ? screen.minX : screen.maxX - size.width,
                   y: screen.minY, width: size.width, height: size.height)
        }
    }

    /// A context menu's origin is its top-left corner in screen coordinates.
    /// Corner widgets may sit below visibleFrame in the physical Dock gaps,
    /// so place the entire menu inside the usable screen before tracking it.
    static func menuOrigin(size: NSSize, at point: NSPoint, in visible: NSRect) -> NSPoint {
        let inset = visible.insetBy(dx: 6, dy: 6)
        return NSPoint(x: max(inset.minX, min(point.x, inset.maxX - size.width)),
                       y: min(inset.maxY, max(point.y, inset.minY + size.height)))
    }

    static func floatingFrame(size: NSSize, origin: NSPoint, in visible: NSRect) -> NSRect {
        let fitted = NSSize(width: min(size.width, visible.width), height: min(size.height, visible.height))
        return NSRect(x: min(max(origin.x, visible.minX), visible.maxX - fitted.width),
                      y: min(max(origin.y, visible.minY), visible.maxY - fitted.height),
                      width: fitted.width, height: fitted.height)
    }

    static func initialOrigin(style: ProviderDisplayStyle, in visible: NSRect, providerCount: Int = 2) -> NSPoint {
        let size = size(style: style, providerCount: providerCount)
        switch style {
        case .stackedSlate: return NSPoint(x: visible.minX + 24, y: visible.minY + 16)
        case .metricMatrix: return NSPoint(x: visible.maxX - size.width - 24, y: visible.minY + 24)
        case .cornerBlade: return NSPoint(x: visible.maxX - size.width, y: visible.maxY - size.height - 44)
        default: return NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 24)
        }
    }

    /// A camera gets two independent windows, so the cutout and the space below
    /// it never receive the widget's mouse events. Height does not add safeTop.
    static func edgeFrames(screen: NSRect, safeTop: CGFloat,
                           leftArea: NSRect?, rightArea: NSRect?, selection: ProviderSelection = .both) -> [NSRect] {
        let height = edgeHeight
        guard safeTop > 0 else {
            let width = edgeCellWidth * CGFloat(selection.providers.count)
            return [NSRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height)]
        }
        let leftEdge = leftArea?.maxX ?? (screen.midX - 89)
        let rightEdge = rightArea?.minX ?? (screen.midX + 89)
        return selection.providers.map { provider in
            NSRect(x: provider == .codex ? leftEdge - 4 - edgeCellWidth : rightEdge + 4,
                   y: screen.maxY - height, width: edgeCellWidth, height: height)
        }
    }
}

enum DisplayProvider: String, Identifiable, CaseIterable {
    case codex, claude
    var id: String { rawValue }
    var name: String { self == .codex ? "Codex" : "Claude" }
    var tint: Color {
        self == .codex ? Color(red: 0.44, green: 0.74, blue: 0.83) : Color(red: 0.85, green: 0.60, blue: 0.47)
    }
}

struct ProviderReading {
    let provider: DisplayProvider
    let usage: Double?
    let calendar: Double?
    let deadline: Date?
    let status: String
    let live: Bool
    var resetChance: Double? = nil
    var fiveHourUsage: Double? = nil
    var fiveHourRemaining: String? = nil
    var thirdValue: Double? { provider == .codex ? resetChance : fiveHourUsage }
    var name: String { provider.name }
    var tint: Color { provider.tint }
    var help: String {
        "\(name): \(Self.percent(usage)) weekly usage, \(Self.percent(calendar, calendar: true)) week elapsed. "
        + (provider == .codex ? "\(Self.percent(resetChance)) reset forecast. " : "\(Self.percent(fiveHourUsage)) five-hour usage, \(fiveHourRemaining ?? "unknown time") remaining. ")
        + "\(status). Click for details; drag to move."
    }
    static func fraction(_ value: Double?) -> CGFloat {
        guard let value, value.isFinite else { return 0 }
        return CGFloat(min(100, max(0, value)) / 100)
    }
    static func percent(_ value: Double?, calendar: Bool = false) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(min(100, max(0, value)).rounded(calendar ? .down : .toNearestOrAwayFromZero)))%"
    }

    static func remainingTime(until deadline: Date?, at now: Date) -> String? {
        guard let deadline else { return nil }
        let seconds = deadline.timeIntervalSince(now)
        guard seconds.isFinite else { return nil }
        // Round up until the deadline; 30 seconds remaining is still one minute.
        // Never roll an expired, cached window forward without a new reading.
        let minutes = Int(min(Double(Int.max / 60), max(0, ceil(seconds / 60))))
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }
    static let samples = [
        Self(provider: .codex, usage: 15, calendar: 7, deadline: nil, status: "Captured sample", live: true, resetChance: 56),
        Self(provider: .claude, usage: 82, calendar: 57, deadline: nil, status: "Captured sample", live: true, fiveHourUsage: 31, fiveHourRemaining: "2h 18m")
    ]
}

/// Shared by the live widget, layout picker, and production preview renderer.
struct ProviderWidgetFace: View {
    let style: ProviderDisplayStyle
    let readings: [ProviderReading]
    var panelProvider: DisplayProvider? = nil
    var onSelect: ((DisplayProvider) -> Void)? = nil
    var onDrag: (() -> Void)? = nil
    var menu: (() -> NSMenu)? = nil
    var animatePets = true
    var greetingProvider: DisplayProvider? = nil
    var greetingAt: Date? = nil

    private var size: NSSize {
        if style == .edgeWings, panelProvider != nil {
            return NSSize(width: ProviderDisplayGeometry.edgeCellWidth, height: ProviderDisplayGeometry.edgeHeight)
        }
        return ProviderDisplayGeometry.size(style: style, providerCount: visibleReadings.count)
    }
    private var visibleReadings: [ProviderReading] { readings.filter { panelProvider == nil || $0.provider == panelProvider } }
    private func greeting(_ provider: DisplayProvider) -> Date? { greetingProvider == provider ? greetingAt : nil }

    var body: some View {
        Group {
            if style == .edgeWings {
                content.background(Color(red: 0.065, green: 0.09, blue: 0.10))
                    .clipShape(ProviderWidgetShell(edge: true, radius: 15))
            } else { content }
        }
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(style.isDark ? .dark : .light)
    }

    @ViewBuilder private var content: some View {
        switch style {
        case .edgeWings:
            HStack(spacing: 0) {
                ForEach(visibleReadings, id: \.provider) { reading in
                    action(reading) { ProviderPetWing(reading: reading, animatePet: animatePets, solo: readings.count == 1) }
                }
            }
        case .twinDials:
            HStack(spacing: 4) {
                ForEach(readings, id: \.provider) { reading in
                    action(reading) { ProviderOrbitDial(reading: reading, animated: animatePets, greeting: greeting(reading.provider)) }
                }
            }
        case .cornerDials, .cornerPerches, .cornerArcs:
            HStack(spacing: 40) {
                ForEach(visibleReadings, id: \.provider) { reading in
                    action(reading) {
                        if style == .cornerDials {
                            ProviderCornerDial(reading: reading, animated: animatePets, greeting: greeting(reading.provider))
                        } else if style == .cornerPerches {
                            ProviderCornerPerch(reading: reading, animated: animatePets, greeting: greeting(reading.provider))
                        } else {
                            ProviderCornerArc(reading: reading, animated: animatePets, greeting: greeting(reading.provider))
                        }
                    }
                }
            }
        case .stackedSlate:
            VStack(spacing: 5) {
                ForEach(readings, id: \.provider) { reading in
                    action(reading) { ProviderTicket(reading: reading, animated: animatePets, greeting: greeting(reading.provider)) }
                        .rotationEffect(.degrees(readings.count == 1 ? 0 : reading.provider == .codex ? -2 : 2))
                        .offset(x: readings.count == 1 ? 0 : reading.provider == .codex ? -5 : 5)
                }
            }
        case .metricMatrix:
            HStack(spacing: 0) {
                ForEach(readings, id: \.provider) { reading in
                    action(reading) { ProviderArcadeColumn(reading: reading, animated: animatePets, greeting: greeting(reading.provider)) }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.075, green: 0.11, blue: 0.14)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.13), lineWidth: 1))
            .padding(3)
        case .cornerBlade:
            VStack(spacing: 6) {
                ForEach(readings, id: \.provider) { reading in
                    action(reading) { ProviderBookmark(reading: reading, animated: animatePets, greeting: greeting(reading.provider)) }
                }
            }.padding(.top, 2).padding(.bottom, 17)
                .background(alignment: .trailing) {
                    BookmarkShape().fill(Color(red: 0.10, green: 0.15, blue: 0.17)).frame(width: 105)
                        .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1) }
                }
        case .screenBuddies:
            HStack {
                if let first = readings.first, first.provider == .codex { ProviderHangingPet(reading: first, left: true, animated: animatePets) }
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "hand.tap").font(.system(size: 18))
                    Text("wave + stats").font(.system(size: 9, weight: .medium))
                }.foregroundStyle(Color.white.opacity(0.48))
                Spacer()
                if let last = readings.last, last.provider == .claude { ProviderHangingPet(reading: last, left: false, animated: animatePets) }
            }
        case .peekaboo:
            if let first = readings.first { ProviderPeekCard(reading: first, left: first.provider == .codex, animated: animatePets) }
        case .flyBy:
            ProviderFlyby(readings: readings, animated: animatePets)
        case .balloonRide:
            ProviderTravelPreview(kind: .balloon, readings: readings)
        case .skateParade:
            ProviderTravelPreview(kind: .skateboard, readings: readings)
        }
    }

    @ViewBuilder private func action<Content: View>(_ reading: ProviderReading, @ViewBuilder content: () -> Content) -> some View {
        let help = style.canDrag ? reading.help : reading.help.replacingOccurrences(of: "; drag to move", with: "")
        if let onSelect {
            content()
                .contentShape(Rectangle())
                .overlay {
                    ProviderInteraction(help: help, canDrag: style.canDrag,
                                        onClick: { onSelect(reading.provider) }, onDrag: onDrag, menu: menu)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(help)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onSelect(reading.provider) }
        } else {
            content().accessibilityElement(children: .ignore)
                .accessibilityLabel(reading.help.components(separatedBy: ". Click for details")[0])
        }
    }
}

struct ProviderWidgetShell: Shape {
    let edge: Bool
    var radius: CGFloat = 12
    func path(in rect: CGRect) -> Path {
        guard edge else { return Path(roundedRect: rect, cornerRadius: radius) }
        return Path { p in
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: rect.maxX, y: 0))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: radius, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - radius), control: CGPoint(x: 0, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

struct ProviderInteraction: NSViewRepresentable {
    let help: String
    let canDrag: Bool
    let onClick: () -> Void
    var onDrag: (() -> Void)?
    var menu: (() -> NSMenu)?
    func makeNSView(context: Context) -> ProviderInteractionView { ProviderInteractionView() }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ProviderInteractionView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
    func updateNSView(_ view: ProviderInteractionView, context: Context) {
        view.toolTip = help
        view.setAccessibilityLabel(help)
        view.canDrag = canDrag
        view.onClick = onClick
        view.onDrag = onDrag
        view.makeMenu = menu
    }
}

final class ProviderInteractionView: NSView {
    var canDrag = true
    var onClick: (() -> Void)?
    var onDrag: (() -> Void)?
    var makeMenu: (() -> NSMenu)?
    private var downEvent: NSEvent?
    private var dragged = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { downEvent = event; dragged = false }
    override func mouseDragged(with event: NSEvent) {
        guard canDrag, !dragged, let downEvent,
              hypot(event.locationInWindow.x - downEvent.locationInWindow.x,
                    event.locationInWindow.y - downEvent.locationInWindow.y) >= 3 else { return }
        dragged = true
        window?.performDrag(with: downEvent)
        onDrag?()
    }
    override func mouseUp(with event: NSEvent) {
        if !dragged, bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
        downEvent = nil
    }
    override func menu(for event: NSEvent) -> NSMenu? { makeMenu?() }
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = makeMenu?() else { super.rightMouseDown(with: event); return }
        guard let window, let screen = window.screen else {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        menu.update()
        let point = ProviderDisplayGeometry.menuOrigin(size: menu.size,
            at: window.convertPoint(toScreen: event.locationInWindow), in: screen.visibleFrame)
        menu.popUp(positioning: nil, at: point, in: nil)
    }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}
