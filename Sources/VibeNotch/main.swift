import AppKit
import SwiftUI
import Combine
import ServiceManagement

// MARK: - Panel

final class NotchPanel: NSPanel {
    // Prevents the panel from stealing focus from whatever app the user is in
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Indicator

enum IndicatorPattern: Equatable {
    case idle, working, awaiting

    var color: Color {
        switch self {
        case .idle:     return Color(white: 0.35)
        case .working:  return Color(red: 1, green: 0.4, blue: 0)
        case .awaiting: return Color(red: 1, green: 0.2, blue: 0.2)
        }
    }

    var nsColor: NSColor {
        switch self {
        case .idle:     return .tertiaryLabelColor
        case .working:  return NSColor(red: 1, green: 0.4, blue: 0, alpha: 1)
        case .awaiting: return NSColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)
        }
    }
}

struct IndicatorView: View {
    let pattern: IndicatorPattern

    var body: some View {
        Circle()
            .fill(pattern.color)
            .frame(width: 8, height: 8)
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
    // Only observes $pattern — agentCount isn't shown in the button, only in the menu on open
    private var stateObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hides the app from the Dock and Cmd+Tab switcher
        NSApp.setActivationPolicy(.accessory)
        buildPanel()
        centerOverNotch()
        panel.orderFrontRegardless()

        ClaudeState.shared.start()
        setupStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refreshStatusButton()
        buildStatusMenu()

        stateObserver = ClaudeState.shared.$pattern
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusButton() }
    }

    private func refreshStatusButton() {
        guard let button = statusItem?.button else { return }
        button.attributedTitle = NSAttributedString(
            string: "●",
            attributes: [
                .foregroundColor: ClaudeState.shared.pattern.nsColor,
                .font: NSFont.systemFont(ofSize: 14, weight: .regular)
            ]
        )
        button.toolTip = "VibeNotch"
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
            menu.addItem(.separator())
        }

        menu.addItem(NSMenuItem(
            title: "Quit VibeNotch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
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
