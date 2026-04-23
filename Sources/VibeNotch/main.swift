import AppKit
import SwiftUI
import ServiceManagement

// MARK: - Panel

final class NotchPanel: NSPanel {
    // Prevents the panel from stealing focus from whatever app the user is in
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
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

    var body: some View {
        HStack(spacing: 0) {
            IndicatorView(pattern: state.pattern)
                .frame(width: 32, height: 32)
                .padding(.leading, 8)

            Spacer()

            Text("\(state.agentCount)")
                .font(.custom("IBMPlexMono-SemiBold", size: 13))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.black)
                )
                .frame(width: 32, height: 32)
                .padding(.trailing, 8)
        }
        .frame(maxHeight: .infinity)
        .background(
            NotchShape(outerRadius: 8, innerRadius: 10)
                .fill(Color.black)
        )
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel!
    private let sideSlotWidth: CGFloat = 40  // 32pt item + 8pt inward padding
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hides the app from the Dock and Cmd+Tab switcher
        NSApp.setActivationPolicy(.accessory)
        buildPanel()
        centerOverNotch()
        panel.orderFrontRegardless()

        ClaudeState.shared.start()
        setupStatusItem()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            UpdateChecker.check { version in
                guard let version,
                      let menu = self?.statusItem?.menu,
                      let item = menu.item(withTag: 10) else { return }
                item.title = "  Update available: v\(version)"
                item.isHidden = false
            }
        }

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
            let img = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "VibeNotch")
            img?.isTemplate = true
            button.image = img
            button.toolTip = "VibeNotch"
        }

        buildStatusMenu()
    }

    private func buildStatusMenu() {
        let menu = NSMenu()
        // menuWillOpen refreshes dynamic items on demand rather than rebuilding every 300ms
        menu.delegate = self

        let header = NSMenuItem(title: "VibeNotch", action: nil, keyEquivalent: "")
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

        let updateItem = NSMenuItem(
            title: "  Update available",
            action: #selector(openReleasesPage),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.tag = 10
        updateItem.isHidden = true
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit VibeNotch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    @objc private func openPreferences() {
        SettingsWindowController.shared.showWindow()
    }

    @objc private func openReleasesPage() {
        NSWorkspace.shared.open(UpdateChecker.releasesURL)
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

    // Returns the panel frame in screen coordinates: indicator slot | physical notch | badge slot.
    // Falls back to a centered 64-pt panel on displays without a notch.
    private func panelFrame(for screen: NSScreen) -> NSRect {
        let height = notchHeight(for: screen)
        let sf = screen.frame
        let y = sf.origin.y + sf.height - height

        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchLeft  = left.maxX
            let notchRight = right.minX
            let x = notchLeft - sideSlotWidth
            let w = (notchRight - notchLeft) + sideSlotWidth * 2
            return NSRect(x: x, y: y, width: w, height: height)
        }

        // Non-notch fallback
        let w = sideSlotWidth * 2
        let x = sf.origin.x + (sf.width - w) / 2
        return NSRect(x: x, y: y, width: w, height: height)
    }

    private func buildPanel() {
        let screen = NSScreen.main
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

        let hosting = NSHostingView(rootView: NotchView())
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    @objc private func screensChanged() {
        centerOverNotch()
    }

    private func centerOverNotch() {
        guard let screen = NSScreen.main else { return }
        panel.setFrame(panelFrame(for: screen), display: false)
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
