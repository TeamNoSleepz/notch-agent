import AppKit
import SwiftUI
import ServiceManagement
import TelemetryClient

// MARK: - Panel

final class NotchPanel: NSPanel {
    // Prevents the panel from stealing focus from whatever app the user is in
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// Transparent container that only accepts hit-tests within the visible notch area.
// Used so ignoresMouseEvents=false (needed when expanded) doesn't also swallow
// clicks in the transparent region around the notch.
final class NotchContentView: NSView {
    var hitRect: NSRect = .zero

    override var wantsLayer: Bool { get { true } set {} }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        layer?.contentsScale = scale
        subviews.forEach { $0.layer?.contentsScale = scale }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        hitRect.contains(point) ? super.hitTest(point) : nil
    }

    override var isOpaque: Bool { false }
}

// MARK: - Visual Effect Blur

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

// MARK: - Hover State

final class NotchHoverState: ObservableObject {
    static let shared = NotchHoverState()
    @Published var expanded = false
    @Published var hoveredAgentIndex: Int? = nil
    var visibleListHeight: CGFloat = 256
}

// MARK: - Indicator

// 3×3 grid of cells, row-major: index 0 = top-left, 8 = bottom-right.
// true = lit with the pattern's active color, false = dim background.
struct CellMask {
    let cells: [Bool]  // exactly 9 elements

    init(_ c0: Bool, _ c1: Bool, _ c2: Bool,
         _ c3: Bool, _ c4: Bool, _ c5: Bool,
         _ c6: Bool, _ c7: Bool, _ c8: Bool) {
        cells = [c0, c1, c2, c3, c4, c5, c6, c7, c8]
    }

    subscript(idx: Int) -> Bool { cells[idx] }
}

enum WorkingAnimation: CaseIterable, Equatable {
    case snake
    case singleHorizontal
    case singleVertical
    case staggeringHorizontal
    case staggeringVertical

    var path: [Int] {
        switch self {
        case .snake:                return [0, 1, 2, 5, 4, 3, 6, 7, 8, 5, 4, 3]
        case .singleHorizontal:     return [3, 4, 5]
        case .singleVertical:       return [1, 4, 7]
        case .staggeringHorizontal: return [0, 1, 2, 3, 4, 5, 6, 7, 8]
        case .staggeringVertical:   return [6, 3, 0, 7, 4, 1, 8, 5, 2]
        }
    }

    var trailLength: Int {
        switch self {
        case .snake:                return 4
        case .singleHorizontal:     return 2
        case .singleVertical:       return 2
        case .staggeringHorizontal: return 3
        case .staggeringVertical:   return 3
        }
    }
}

enum IndicatorPattern: Equatable {
    case idle, working, awaiting

    var color: Color {
        let p = AppPreferences.shared.selectedPalette
        switch self {
        case .idle:     return p.idle
        case .working:  return p.working
        case .awaiting: return p.awaiting
        }
    }

    var nsColor: NSColor {
        let p = AppPreferences.shared.selectedPalette
        switch self {
        case .idle:     return NSColor(p.idle)
        case .working:  return NSColor(p.working)
        case .awaiting: return NSColor(p.awaiting)
        }
    }

    func mask() -> CellMask {
        switch self {
        case .idle:
            return CellMask(false, false, false,
                            false, true,  false,
                            false, false, false)
        case .working:
            return CellMask(false, false, false,
                            false, false, false,
                            false, false, false)
        case .awaiting:
            return CellMask(true,  false, true,
                            false, false, false,
                            true,  false, true)
        }
    }
}

struct IndicatorView: View {
    let pattern: IndicatorPattern
    @State private var workingAnimation: WorkingAnimation = WorkingAnimation.allCases.randomElement()!
    @State private var headIdx: Int = 0
    @State private var awaitingIdx: Int = 0

    private static let creamColor   = Color(red: 1.0, green: 0.80, blue: 0.608)
    private static let glowColor    = Color(red: 0.80, green: 0.55, blue: 0.25)
    private static let ticker       = Timer.publish(every: 0.20, on: .main, in: .common).autoconnect()
    private static let idleTicker   = Timer.publish(every: 0.38, on: .main, in: .common).autoconnect()
    private static let awaitTicker  = Timer.publish(every: 0.40, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            if pattern == .working {
                Circle()
                    .fill(Self.glowColor.opacity(0.55))
                    .blur(radius: 9)
                    .frame(width: 18, height: 18)
            }

            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { col in
                            let idx = row * 3 + col
                            Rectangle()
                                .fill(pattern == .working ? Self.creamColor : pattern.color)
                                .opacity(cellOpacity(idx: idx))
                                .frame(width: 5, height: 5)
                                .animation(.easeInOut(duration: 0.22), value: headIdx)
                                .animation(.easeInOut(duration: 0.22), value: awaitingIdx)
                        }
                    }
                }
            }
            .frame(width: 15, height: 15)
        }
        .onReceive(Self.ticker) { _ in
            guard pattern == .working else { return }
            headIdx = (headIdx + 1) % workingAnimation.path.count
        }
        .onReceive(Self.idleTicker) { _ in
            guard pattern == .idle else { return }
            headIdx = (headIdx + 1) % workingAnimation.path.count
        }
        .onReceive(Self.awaitTicker) { _ in
            guard pattern == .awaiting else { return }
            awaitingIdx = (awaitingIdx + 1) % 3
        }
        .onChange(of: pattern) { newPattern in
            if newPattern == .working {
                workingAnimation = WorkingAnimation.allCases.randomElement()!
                headIdx = 0
            }
            if newPattern == .awaiting {
                awaitingIdx = 0
            }
        }
    }

    private func cellOpacity(idx: Int) -> Double {
        switch pattern {
        case .awaiting:
            let path = [1, 4, 7]
            let trailLen = 2
            for i in 0..<trailLen {
                let pi = (awaitingIdx - i + path.count) % path.count
                if path[pi] == idx {
                    let t = Double(trailLen - 1 - i) / Double(trailLen - 1)
                    return 0.35 + t * 0.65
                }
            }
            return 0.0
        case .idle, .working:
            let path = workingAnimation.path
            let len  = workingAnimation.trailLength
            for i in 0..<len {
                let pi = (headIdx - i + path.count) % path.count
                if path[pi] == idx {
                    let t = Double(len - 1 - i) / Double(len - 1)
                    return 0.30 + t * 0.70
                }
            }
            return 0.0
        }
    }
}

// MARK: - Agent List

struct AgentListView: View {
    @ObservedObject private var state = ClaudeState.shared
    @ObservedObject private var hover = NotchHoverState.shared
    @Binding var measuredHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            // Hidden VStack at natural height — unconstrained so GeometryReader
            // sees true content height. Uses .task(id:) which fires reliably on
            // the main actor whenever the measured height changes.
            VStack(spacing: 0) { rows }
                .padding(.vertical, 8)
                .background(GeometryReader { g in
                    Color.clear.task(id: g.size.height) {
                        measuredHeight = g.size.height
                    }
                })
                .hidden()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) { rows }
                    .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        ForEach(Array(state.agents.enumerated()), id: \.element.id) { index, agent in
            AgentRowView(agent: agent, index: index)
                .opacity(hover.expanded ? 1 : 0)
                .offset(y: hover.expanded ? 0 : 6)
                .animation(
                    .spring(response: 0.38, dampingFraction: 0.88)
                        .delay(hover.expanded ? 0.08 + Double(index) * 0.05 : 0),
                    value: hover.expanded
                )
        }
    }
}

private struct AgentRowView: View {
    let agent: AgentEntry
    let index: Int
    @ObservedObject private var hover = NotchHoverState.shared
    @ObservedObject private var state = ClaudeState.shared
    @State private var bgOpacity: Double = 0

    var isHovered: Bool { hover.hoveredAgentIndex == index }
    var isPinned: Bool  { state.pinnedAgentId == agent.id }

    private var subtitleText: String {
        let dir = URL(fileURLWithPath: agent.cwd).lastPathComponent
        return dir.isEmpty ? "Claude Code" : "Claude Code · \(dir)"
    }

    private var stateText: String {
        switch agent.pattern {
        case .working:
            if let tool = agent.tool, !tool.isEmpty { return tool }
            return "Working"
        case .awaiting:
            return "Awaiting input"
        case .idle:
            return "Waiting"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            IndicatorView(pattern: agent.pattern)
                .frame(width: 15, height: 15)

            VStack(alignment: .leading, spacing: 5) {
                Text(subtitleText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                Text(stateText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(red: 0.98, green: 0.98, blue: 0.98))
            }
            Spacer()
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isPinned ? .white.opacity(0.9) : .white.opacity(0.35))
                .opacity(isHovered || isPinned ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
                .animation(.easeInOut(duration: 0.15), value: isPinned)
                .padding(.trailing, 4)
        }
        .padding(.top, 11)
        .padding(.bottom, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 31/255, green: 31/255, blue: 31/255))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(red: 48/255, green: 48/255, blue: 48/255), lineWidth: 1)
                )
                .opacity(bgOpacity)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 8)
        .onTapGesture {
            state.pinnedAgentId = isPinned ? nil : agent.id
        }
        .onAppear { bgOpacity = isHovered ? 1 : 0 }
        .onChange(of: hover.hoveredAgentIndex) { newIndex in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                bgOpacity = (newIndex == index) ? 1 : 0
            }
        }
    }
}

// MARK: - Notch Shape
//
// Mimics the real MacBook notch geometry:
//   • outerRadius — concave anti-corners where the notch sides meet the screen top
//   • innerRadius — convex rounded corners at the bottom where the notch meets the menu bar
//
// The concave corners taper the visible notch width by outerRadius on each side,
// matching the hardware transition from the full-width bezel into the notch body.

struct NotchShape: Shape {
    var outerRadius: CGFloat  // concave corners at screen-top edge
    var innerRadius: CGFloat  // convex corners at menu-bar edge

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(outerRadius, innerRadius) }
        set { outerRadius = newValue.first; innerRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // concave outer corner — top-left
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + outerRadius, y: rect.minY + outerRadius),
            control: CGPoint(x: rect.minX + outerRadius, y: rect.minY)
        )

        // left inner wall → convex bottom-left corner
        p.addLine(to: CGPoint(x: rect.minX + outerRadius, y: rect.maxY - innerRadius))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + outerRadius + innerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + outerRadius, y: rect.maxY)
        )

        // bottom
        p.addLine(to: CGPoint(x: rect.maxX - outerRadius - innerRadius, y: rect.maxY))

        // convex bottom-right corner → right inner wall
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - outerRadius, y: rect.maxY - innerRadius),
            control: CGPoint(x: rect.maxX - outerRadius, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - outerRadius, y: rect.minY + outerRadius))

        // concave outer corner — top-right
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - outerRadius, y: rect.minY)
        )

        p.closeSubpath()
        return p
    }
}

// MARK: - Notch View

struct NotchView: View {
    @ObservedObject var state = ClaudeState.shared
    @ObservedObject var prefs = AppPreferences.shared
    @ObservedObject var hover = NotchHoverState.shared

    let barHeight: CGFloat
    let collapsedWidth: CGFloat
    private let expandedWidth: CGFloat = 480
    private let maxListHeight: CGFloat = 256
    @State private var listContentHeight: CGFloat = 0

    var listHeight: CGFloat    { listContentHeight > 0 ? min(listContentHeight, maxListHeight) : maxListHeight }
    var currentWidth: CGFloat  { hover.expanded ? expandedWidth  : collapsedWidth }
    var currentHeight: CGFloat { hover.expanded ? barHeight + listHeight : barHeight }

    private var displayPattern: IndicatorPattern {
        if let id = state.pinnedAgentId, let agent = state.agents.first(where: { $0.id == id }) {
            return agent.pattern
        }
        return state.pattern
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Shape animates width, height, and corner radii together
            NotchShape(outerRadius: hover.expanded ? 0 : 8,
                       innerRadius: hover.expanded ? 18 : 10)
                .fill(Color.black)
                .frame(width: currentWidth, height: currentHeight)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    IndicatorView(pattern: displayPattern)
                        .frame(width: 32, height: 32)
                        .padding(.leading, 8)

                    Spacer()

                    Text("\(state.agentCount)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.black)
                        )
                        .frame(width: 32, height: 32)
                        .padding(.trailing, 8)
                }
                .frame(width: currentWidth, height: barHeight)

                AgentListView(measuredHeight: $listContentHeight)
                    .frame(width: currentWidth)
                    .frame(height: hover.expanded ? listHeight : 0, alignment: .top)
                    .clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.45, dampingFraction: 0.92), value: hover.expanded)
        .onChange(of: listHeight) { NotchHoverState.shared.visibleListHeight = $0 }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel!
    private var contentWrapper: NotchContentView!
    private let sideSlotWidth: CGFloat = 40  // 32pt item + 8pt inward padding
    private var statusItem: NSStatusItem!
    private let expandedHeight: CGFloat = 320
    private let expandedWidth: CGFloat = 480
    private var notchBarHeight: CGFloat = 37
    private var collapsedNotchWidth: CGFloat = 80
    private var notchCenterX: CGFloat = 0
    private var mouseMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hides the app from the Dock and Cmd+Tab switcher
        NSApp.setActivationPolicy(.accessory)

        var telemetryConfig = TelemetryDeck.Config(appID: "8740D36A-560E-4E5B-82B2-6EEDD49952FF")
        #if DEBUG
        telemetryConfig.testMode = true
        #endif
        TelemetryDeck.initialize(config: telemetryConfig)
        TelemetryDeck.signal("appLaunched", parameters: [
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "macOSVersion": ProcessInfo.processInfo.operatingSystemVersionString,
        ])

        buildPanel()
        centerOverNotch()
        panel.orderFrontRegardless()

        ClaudeState.shared.start()
        setupStatusItem()
        startMouseTracking()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            if let iconURL = Bundle.main.url(forResource: "StatusBarIconTemplate", withExtension: "png"),
               let img = NSImage(contentsOf: iconURL) {
                img.isTemplate = true
                button.image = img
            } else {
                let img = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "NotchAgent")
                img?.isTemplate = true
                button.image = img
            }
            button.toolTip = "NotchAgent"
        }

        buildStatusMenu()
    }

    private func buildStatusMenu() {
        let menu = NSMenu()
        // menuWillOpen refreshes dynamic items on demand rather than rebuilding every 300ms
        menu.delegate = self

        let header = NSMenuItem(title: "NotchAgent", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())

        // Tags 1–3 are looked up by menuWillOpen to refresh their titles
        let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        stateItem.tag = 1
        menu.addItem(stateItem)

        let agentItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        agentItem.isEnabled = false
        agentItem.tag = 2
        menu.addItem(agentItem)

        menu.addItem(.separator())

        // SMAppService.mainApp requires a CFBundleIdentifier — unavailable when running as a raw SPM executable
        if Bundle.main.bundleIdentifier != nil {
            let launchItem = NSMenuItem(
                title: "Launch at Login",
                action: #selector(toggleLaunchAtLogin),
                keyEquivalent: ""
            )
            launchItem.target = self
            launchItem.tag = 3
            menu.addItem(launchItem)
        }

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(
            title: "Settings",
            action: #selector(openPreferences),
            keyEquivalent: ""
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let feedbackItem = NSMenuItem(
            title: "Submit Feedback",
            action: #selector(openFeedback),
            keyEquivalent: ""
        )
        feedbackItem.target = self
        menu.addItem(feedbackItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit NotchAgent",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    @objc private func openFeedback() {
        if let url = URL(string: "https://github.com/TeamNoSleepz/notch-agent/issues/new") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openPreferences() {
        SettingsWindowController.shared.showWindow()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - Panel

    private func notchHeight(for screen: NSScreen) -> CGFloat {
        let h = screen.safeAreaInsets.top
        // safeAreaInsets.top is 0 on non-notch displays; fall back to menu bar height
        return h > 0 ? h : screen.frame.maxY - screen.visibleFrame.maxY
    }

    // Panel is pre-allocated wide and tall enough for full expansion.
    // Stores geometry for mouse-hit testing. Top edge pinned to screen top.
    private func updateGeometry(for screen: NSScreen) {
        notchBarHeight = notchHeight(for: screen)
        let sf = screen.frame
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchLeft  = left.maxX
            let notchRight = right.minX
            collapsedNotchWidth = (notchRight - notchLeft) + sideSlotWidth * 2
            notchCenterX = sf.origin.x + (notchLeft + notchRight) / 2
        } else {
            collapsedNotchWidth = sideSlotWidth * 2
            notchCenterX = sf.origin.x + sf.width / 2
        }
    }

    private func panelFrame(for screen: NSScreen) -> NSRect {
        let panelW = max(collapsedNotchWidth, expandedWidth)
        let panelH = notchBarHeight + expandedHeight
        let sf = screen.frame
        let x = notchCenterX - panelW / 2
        let y = sf.origin.y + sf.height - panelH
        return NSRect(x: x, y: y, width: panelW, height: panelH)
    }

    private func buildPanel() {
        let screen = NSScreen.main
        if let s = screen { updateGeometry(for: s) }
        let frame = screen.map { panelFrame(for: $0) } ?? NSRect(x: 0, y: 0, width: 64, height: 32)
        let size = frame.size

        panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // .mainMenu alone sits below full-screen app overlays; +3 clears all system UI layers
        panel.level = NSWindow.Level(rawValue: Int(NSWindow.Level.mainMenu.rawValue) + 3)
        // canJoinAllSpaces — visible on every Space, not just the one it was born on
        // fullScreenAuxiliary — survives when another app goes full-screen
        // stationary — excluded from Exposé/Mission Control reshuffling
        // ignoresCycle — excluded from Cmd+` window cycling
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        // NSPanel default is true — would hide the overlay the moment the user clicks another app
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.sharingType = .readOnly
        panel.appearance = NSAppearance(named: .darkAqua)

        contentWrapper = NotchContentView(frame: NSRect(origin: .zero, size: size))
        contentWrapper.autoresizingMask = [.width, .height]
        let hosting = NSHostingView(rootView: NotchView(barHeight: notchBarHeight, collapsedWidth: collapsedNotchWidth))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        contentWrapper.addSubview(hosting)
        panel.contentView = contentWrapper
    }

    @objc private func screensChanged() {
        if let s = NSScreen.main { updateGeometry(for: s) }
        centerOverNotch()
    }

    private func centerOverNotch() {
        guard let screen = NSScreen.main else { return }
        panel.setFrame(panelFrame(for: screen), display: false)
    }

    // MARK: - Mouse Tracking
    //
    // panel.ignoresMouseEvents stays true so the transparent expanded area never
    // swallows clicks meant for apps below. We use a global monitor instead to
    // compare the raw mouse position against the notch bar zone.

    private func startMouseTracking() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.updateHoverState()
        }
    }

    private func updateHoverState() {
        guard let screen = NSScreen.main else { return }
        let loc = NSEvent.mouseLocation
        let pf = panelFrame(for: screen)
        let screenTop = pf.maxY

        // Narrow bar zone triggers the expand
        let barZone = NSRect(
            x: notchCenterX - collapsedNotchWidth / 2,
            y: screenTop - notchBarHeight,
            width: collapsedNotchWidth,
            height: notchBarHeight
        )

        // Full expanded pill — sized to the visible shape only
        let visibleH = NotchHoverState.shared.visibleListHeight
        let expandedZone = NSRect(
            x: notchCenterX - expandedWidth / 2,
            y: screenTop - notchBarHeight - visibleH,
            width: expandedWidth,
            height: notchBarHeight + visibleH
        )

        let isExpanded = NotchHoverState.shared.expanded
        let hovering = barZone.contains(loc) || (isExpanded && expandedZone.contains(loc))

        // Shrink by the outer 8pt horizontal padding and 8pt vertical list padding
        // so hover only triggers over the actual card, not the whitespace around it.
        let listZone = NSRect(
            x: notchCenterX - expandedWidth / 2 + 8,
            y: screenTop - notchBarHeight - visibleH + 8,
            width: expandedWidth - 16,
            height: visibleH - 16
        )
        let newHoveredIndex: Int?
        let agentCount = ClaudeState.shared.agents.count
        if isExpanded && listZone.contains(loc) && agentCount > 0 {
            let distanceFromTop = listZone.maxY - loc.y
            let rowHeight = listZone.height / CGFloat(agentCount)
            let idx = Int(distanceFromTop / rowHeight)
            newHoveredIndex = min(idx, agentCount - 1)
        } else {
            newHoveredIndex = nil
        }
        if NotchHoverState.shared.hoveredAgentIndex != newHoveredIndex {
            DispatchQueue.main.async { NotchHoverState.shared.hoveredAgentIndex = newHoveredIndex }
        }

        // Hit rect covers only the visible black notch area in panel view coordinates
        // (y=0 at panel bottom). When expanded, this blocks clicks on content underneath.
        let panelH = notchBarHeight + expandedHeight
        let newHitRect: NSRect = hovering
            ? NSRect(x: 0, y: panelH - notchBarHeight - visibleH,
                     width: expandedWidth, height: notchBarHeight + visibleH)
            : .zero

        let stateChanged = isExpanded != hovering
        let hitRectChanged = contentWrapper.hitRect != newHitRect
        guard stateChanged || hitRectChanged else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if stateChanged {
                NotchHoverState.shared.expanded = hovering
                self.panel.ignoresMouseEvents = !hovering
            }
            if hitRectChanged {
                self.contentWrapper.hitRect = newHitRect
            }
        }
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        if let item = menu.item(withTag: 1) {
            switch ClaudeState.shared.pattern {
            case .idle:     item.title = "  Idle"
            case .working:  item.title = "  Working..."
            case .awaiting: item.title = "  Awaiting input"
            }
        }
        if let item = menu.item(withTag: 2) {
            let n = ClaudeState.shared.agentCount
            item.title = "  \(n) agent\(n == 1 ? "" : "s") running"
        }
        if let item = menu.item(withTag: 3) {
            item.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
