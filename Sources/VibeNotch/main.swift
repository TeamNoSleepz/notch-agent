import AppKit
import SwiftUI

// MARK: - Panel

final class NotchPanel: NSPanel {
    // Returning false prevents the panel from stealing focus from the active app
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Indicator

enum IndicatorPattern: Equatable {
    case idle, thinking, tool, awaiting, done, off

    var color: Color {
        switch self {
        case .idle:     return Color(white: 0.2)
        case .thinking: return Color(white: 1)
        case .tool:     return Color(red: 1, green: 0.4, blue: 0)
        case .awaiting: return Color(red: 0.3, green: 0.6, blue: 1)
        case .done:     return Color(red: 0, green: 1, blue: 0.4)
        case .off:      return .clear
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

// MARK: - Claude Logo

struct ClaudeLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 18.0
        let sy = rect.height / 18.0
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

        var path = Path()
        path.move(to: p(3.51787, 11.9295))
        path.addLine(to: p(7.04475, 9.9495))
        path.addLine(to: p(7.10437, 9.77737))
        path.addLine(to: p(7.04475, 9.68175))
        path.addLine(to: p(6.87375, 9.68175))
        path.addLine(to: p(6.28312, 9.64575))
        path.addLine(to: p(4.26825, 9.59175))
        path.addLine(to: p(2.52, 9.51863))
        path.addLine(to: p(0.826875, 9.42862))
        path.addLine(to: p(0.399375, 9.3375))
        path.addLine(to: p(0, 8.811))
        path.addLine(to: p(0.0405, 8.54775))
        path.addLine(to: p(0.4005, 8.307))
        path.addLine(to: p(0.912375, 8.352))
        path.addLine(to: p(2.0475, 8.42963))
        path.addLine(to: p(3.74962, 8.54775))
        path.addLine(to: p(4.98375, 8.61975))
        path.addLine(to: p(6.813, 8.811))
        path.addLine(to: p(7.10437, 8.811))
        path.addLine(to: p(7.14487, 8.69288))
        path.addLine(to: p(7.04475, 8.61975))
        path.addLine(to: p(6.96825, 8.54775))
        path.addLine(to: p(5.2065, 7.353))
        path.addLine(to: p(3.29962, 6.09187))
        path.addLine(to: p(2.30175, 5.36513))
        path.addLine(to: p(1.76175, 4.99725))
        path.addLine(to: p(1.48837, 4.653))
        path.addLine(to: p(1.37137, 3.89925))
        path.addLine(to: p(1.86075, 3.35925))
        path.addLine(to: p(2.51887, 3.40425))
        path.addLine(to: p(2.68762, 3.44925))
        path.addLine(to: p(3.35475, 3.96225))
        path.addLine(to: p(4.78012, 5.06587))
        path.addLine(to: p(6.64087, 6.43613))
        path.addLine(to: p(6.91312, 6.66337))
        path.addLine(to: p(7.02225, 6.58688))
        path.addLine(to: p(7.03575, 6.53175))
        path.addLine(to: p(6.91312, 6.32812))
        path.addLine(to: p(5.90062, 4.49888))
        path.addLine(to: p(4.82062, 2.637))
        path.addLine(to: p(4.33912, 1.86525))
        path.addLine(to: p(4.212, 1.40287))
        path.addCurve(
            to: p(4.1355, 0.858375),
            control1: p(4.16433, 1.22519),
            control2: p(4.13864, 1.04232)
        )
        path.addLine(to: p(4.6935, 0.100125))
        path.addLine(to: p(5.00175, 0))
        path.addLine(to: p(5.7465, 0.100125))
        path.addLine(to: p(6.06037, 0.372375))
        path.addLine(to: p(6.52275, 1.42988))
        path.addLine(to: p(7.272, 3.09487))
        path.addLine(to: p(8.43412, 5.36062))
        path.addLine(to: p(8.77387, 6.03225))
        path.addLine(to: p(8.95612, 6.65437))
        path.addLine(to: p(9.02362, 6.84563))
        path.addLine(to: p(9.14175, 6.84563))
        path.addLine(to: p(9.14175, 6.7365))
        path.addLine(to: p(9.23737, 5.46075))
        path.addLine(to: p(9.414, 3.89475))
        path.addLine(to: p(9.58725, 1.87875))
        path.addLine(to: p(9.64575, 1.31175))
        path.addLine(to: p(9.927, 0.631125))
        path.addLine(to: p(10.4861, 0.26325))
        path.addLine(to: p(10.9215, 0.4725))
        path.addLine(to: p(11.2804, 0.9855))
        path.addLine(to: p(11.2297, 1.31625))
        path.addLine(to: p(11.016, 2.7))
        path.addLine(to: p(10.5997, 4.87125))
        path.addLine(to: p(10.3264, 6.3225))
        path.addLine(to: p(10.4861, 6.3225))
        path.addLine(to: p(10.6672, 6.1425))
        path.addLine(to: p(11.403, 5.166))
        path.addLine(to: p(12.6371, 3.6225))
        path.addLine(to: p(13.1816, 3.00937))
        path.addLine(to: p(13.8172, 2.33325))
        path.addLine(to: p(14.2256, 2.01037))
        path.addLine(to: p(14.9974, 2.01037))
        path.addLine(to: p(15.5655, 2.85525))
        path.addLine(to: p(15.3112, 3.72712))
        path.addLine(to: p(14.5159, 4.734))
        path.addLine(to: p(13.8577, 5.58788))
        path.addLine(to: p(12.9139, 6.85913))
        path.addLine(to: p(12.3244, 7.87612))
        path.addLine(to: p(12.3784, 7.95712))
        path.addLine(to: p(12.519, 7.94362))
        path.addLine(to: p(14.6531, 7.49025))
        path.addLine(to: p(15.8051, 7.281))
        path.addLine(to: p(17.181, 7.04475))
        path.addLine(to: p(17.8031, 7.335))
        path.addLine(to: p(17.8706, 7.63087))
        path.addLine(to: p(17.6254, 8.23387))
        path.addLine(to: p(16.155, 8.59725))
        path.addLine(to: p(14.4304, 8.94262))
        path.addLine(to: p(11.8609, 9.55013))
        path.addLine(to: p(11.8294, 9.57262))
        path.addLine(to: p(11.8654, 9.61762))
        path.addLine(to: p(13.023, 9.72788))
        path.addLine(to: p(13.518, 9.75487))
        path.addLine(to: p(14.7296, 9.75487))
        path.addLine(to: p(16.9852, 9.92363))
        path.addLine(to: p(17.5759, 10.3129))
        path.addLine(to: p(17.9302, 10.7899))
        path.addLine(to: p(17.8706, 11.1532))
        path.addLine(to: p(16.9627, 11.6156))
        path.addLine(to: p(12.8779, 10.6447))
        path.addLine(to: p(11.8969, 10.3995))
        path.addLine(to: p(11.7619, 10.3995))
        path.addLine(to: p(11.7619, 10.4816))
        path.addLine(to: p(12.5786, 11.2804))
        path.addLine(to: p(14.076, 12.6326))
        path.addLine(to: p(15.9514, 14.3764))
        path.addLine(to: p(16.0459, 14.8072))
        path.addLine(to: p(15.8051, 15.147))
        path.addLine(to: p(15.5509, 15.111))
        path.addLine(to: p(13.9039, 13.8724))
        path.addLine(to: p(13.2682, 13.3132))
        path.addLine(to: p(11.8282, 12.1016))
        path.addLine(to: p(11.7337, 12.1016))
        path.addLine(to: p(11.7337, 12.2287))
        path.addLine(to: p(12.0656, 12.7148))
        path.addLine(to: p(13.8172, 15.3473))
        path.addLine(to: p(13.9072, 16.155))
        path.addLine(to: p(13.7812, 16.4182))
        path.addLine(to: p(13.3267, 16.5769))
        path.addLine(to: p(12.8272, 16.4869))
        path.addLine(to: p(11.8024, 15.0469))
        path.addLine(to: p(10.7449, 13.4269))
        path.addLine(to: p(9.891, 11.9745))
        path.addLine(to: p(9.78637, 12.0341))
        path.addLine(to: p(9.28237, 17.4577))
        path.addLine(to: p(9.04612, 17.7345))
        path.addLine(to: p(8.50162, 17.9437))
        path.addLine(to: p(8.04825, 17.5984))
        path.addLine(to: p(7.8075, 17.0404))
        path.addLine(to: p(8.04825, 15.9379))
        path.addLine(to: p(8.3385, 14.4979))
        path.addLine(to: p(8.57475, 13.3549))
        path.addLine(to: p(8.7885, 11.934))
        path.addLine(to: p(8.9145, 11.4615))
        path.addLine(to: p(8.9055, 11.43))
        path.addLine(to: p(8.802, 11.4435))
        path.addLine(to: p(7.72987, 12.9139))
        path.addLine(to: p(6.10087, 15.1155))
        path.addLine(to: p(4.81162, 16.4959))
        path.addLine(to: p(4.50337, 16.6185))
        path.addLine(to: p(3.96675, 16.3406))
        path.addLine(to: p(4.01737, 15.8456))
        path.addLine(to: p(4.31662, 15.4069))
        path.addLine(to: p(6.10087, 13.1366))
        path.addLine(to: p(7.17637, 11.7304))
        path.addLine(to: p(7.8705, 10.917))
        path.addLine(to: p(7.866, 10.7989))
        path.addLine(to: p(7.8255, 10.7989))
        path.addLine(to: p(3.087, 13.8769))
        path.addLine(to: p(2.24325, 13.9849))
        path.addLine(to: p(1.87875, 13.6451))
        path.addLine(to: p(1.92375, 13.0871))
        path.addLine(to: p(2.097, 12.9049))
        path.addLine(to: p(3.52237, 11.925))
        path.addLine(to: p(3.51787, 11.9295))
        path.closeSubpath()
        return path
    }
}

// MARK: - Notch View

struct NotchView: View {
    @ObservedObject var state = ClaudeState.shared

    var body: some View {
        HStack(spacing: 0) {
            ClaudeLogoShape()
                .fill(Color(white: 0.424))
                .frame(width: 18, height: 18)
                .padding(7)

            Spacer()

            IndicatorView(pattern: state.pattern)
                .frame(width: 32, height: 32)
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildPanel()
        centerOverNotch()
        panel.orderFrontRegardless()

        ClaudeState.shared.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func notchHeight(for screen: NSScreen) -> CGFloat {
        let h = screen.safeAreaInsets.top
        // safeAreaInsets.top is 0 on non-notch displays; fall back to menu bar height
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
        // Sit above full-screen apps (mainMenu) and system overlays (+3)
        panel.level = NSWindow.Level(rawValue: Int(NSWindow.Level.mainMenu.rawValue) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        // Let all clicks pass through to whatever is underneath
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
