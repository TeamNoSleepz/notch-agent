import AppKit
import SwiftUI
import Combine
import ServiceManagement

// MARK: - Panel

final class NotchPanel: NSPanel {
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

// MARK: - Notch View

struct NotchView: View {
    @ObservedObject var state = ClaudeState.shared

    var body: some View {
        HStack(spacing: 0) {
            IndicatorView(pattern: state.pattern)
                .frame(width: 32, height: 32)

            Spacer()

            Text("\(state.agentCount)")
                .font(.custom("IBMPlexMono-SemiBold", size: 13))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.black)
                )
                .padding(.trailing, 8)
        }
        .frame(width: 248)
        .frame(maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 0,
                    bottomLeading: 10,
                    bottomTrailing: 10,
                    topTrailing: 0
                )
            )
            .fill(Color.black)
        )
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel!
    private let panelWidth: CGFloat = 248
    private var statusItem: NSStatusItem!
    private var stateObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        menu.delegate = self

        let header = NSMenuItem(title: "VibeNotch", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())

        let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        stateItem.tag = 1
        menu.addItem(stateItem)

        let agentItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        agentItem.isEnabled = false
        agentItem.tag = 2
        menu.addItem(agentItem)

        menu.addItem(.separator())

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
        return h > 0 ? h : screen.frame.maxY - screen.visibleFrame.maxY
    }

    private func buildPanel() {
        let screen = NSScreen.main
        let height = screen.map { notchHeight(for: $0) } ?? 32
        let size = NSSize(width: panelWidth, height: height)

        panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(NSWindow.Level.mainMenu.rawValue) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.sharingType = .none
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
        let height = notchHeight(for: screen)
        let sf = screen.frame
        let x = sf.origin.x + (sf.width - panelWidth) / 2
        let y = sf.origin.y + sf.height - height
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: height), display: false)
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
