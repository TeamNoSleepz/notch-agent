import AppKit
import WebKit

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosts the WKWebView and tracks cursor enter/exit explicitly so we can drive
/// hover state in CSS via a body class (more reliable than `:hover` in a
/// nonactivating panel).
final class HoverContainerView: NSView {
    weak var webView: WKWebView?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        setHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHover(false)
    }

    private func setHover(_ on: Bool) {
        let js = on
            ? "document.body.classList.add('hovered')"
            : "document.body.classList.remove('hovered')"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel!
    private var webView: WKWebView!

    // Panel is sized to the maximum pill footprint. The rest of the notch area
    // (outside this panel) passes clicks through to the menu bar.
    private let panelSize = NSSize(width: 248, height: 32)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildPanel()
        loadWebView()
        positionOverNotch()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func buildPanel() {
        let frame = NSRect(origin: .zero, size: panelSize)
        panel = NotchPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
    }

    private func loadWebView() {
        let config = WKWebViewConfiguration()
        let bounds = NSRect(origin: .zero, size: panelSize)
        let container = HoverContainerView(frame: bounds)
        container.autoresizingMask = [.width, .height]

        webView = WKWebView(frame: bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(webView)
        container.webView = webView
        panel.contentView = container

        guard let htmlURL = Bundle.module.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "Resources"
        ) else {
            fputs("[vibe-notch] index.html missing from bundle\n", stderr)
            return
        }
        webView.navigationDelegate = navDelegate
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }

    /// Measures the physical notch width from the screen's auxiliary top areas
    /// (the menu-bar strips flanking the notch). Falls back to a sensible default
    /// when running on a Mac without a notch.
    private func notchWidth(for screen: NSScreen) -> CGFloat {
        let leftW  = screen.auxiliaryTopLeftArea?.width  ?? 0
        let rightW = screen.auxiliaryTopRightArea?.width ?? 0
        guard leftW > 0, rightW > 0 else { return 200 }
        return screen.frame.width - leftW - rightW
    }

    /// Pushes the measured notch width into the WebView as a CSS custom
    /// property so `--pill-width-idle` matches the hardware exactly.
    fileprivate func syncNotchSizeToWebView() {
        guard let screen = NSScreen.main, webView != nil else { return }
        let w = notchWidth(for: screen)
        let js = "document.documentElement.style.setProperty('--pill-width-idle', '\(w)px');"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func positionOverNotch() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.frame
        let wf = panel.frame
        let x = sf.origin.x + (sf.width - wf.width) / 2
        let y = sf.origin.y + sf.height - wf.height
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func screensChanged() {
        positionOverNotch()
        syncNotchSizeToWebView()
    }

    private lazy var navDelegate: WebNavDelegate = WebNavDelegate(owner: self)
}

/// Fires once the HTML is parsed so we can inject the measured notch width.
final class WebNavDelegate: NSObject, WKNavigationDelegate {
    weak var owner: AppDelegate?
    init(owner: AppDelegate) { self.owner = owner }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        owner?.syncNotchSizeToWebView()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
