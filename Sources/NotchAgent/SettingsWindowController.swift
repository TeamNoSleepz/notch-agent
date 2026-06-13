import AppKit
import AVFoundation
import CoreGraphics
import SwiftUI
import ServiceManagement

// MARK: - Color Palette (used by IndicatorPattern for dot colors)

struct ColorPalette {
    let name: String
    let idle: Color
    let working: Color
    let awaiting: Color
}

// MARK: - App Preferences

final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    static let defaultPalette = ColorPalette(
        name: "Default",
        idle: Color(white: 0.35),
        working: Color(red: 1, green: 0.4, blue: 0),
        awaiting: Color(red: 1, green: 0.2, blue: 0.2)
    )

    static let systemSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
        "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    var selectedPalette: ColorPalette { Self.defaultPalette }

    @Published var interruptSoundName: String {
        didSet { UserDefaults.standard.set(interruptSoundName, forKey: "notchagent.interruptSoundName") }
    }
    @Published var finishSoundName: String {
        didSet { UserDefaults.standard.set(finishSoundName, forKey: "notchagent.finishSoundName") }
    }
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "notchagent.soundEnabled") }
    }
    @Published var soundVolume: Double {
        didSet { UserDefaults.standard.set(soundVolume, forKey: "notchagent.soundVolume") }
    }
    @Published var hideWhenIdle: Bool {
        didSet { UserDefaults.standard.set(hideWhenIdle, forKey: "notchagent.hideWhenIdle") }
    }
    @Published var selectedDisplayID: CGDirectDisplayID {
        didSet { UserDefaults.standard.set(Int(selectedDisplayID), forKey: "notchagent.selectedDisplayID") }
    }
    private init() {
        let ud = UserDefaults.standard
        interruptSoundName = ud.string(forKey: "notchagent.interruptSoundName") ?? "Ping"
        finishSoundName    = ud.string(forKey: "notchagent.finishSoundName")    ?? "Glass"
        soundEnabled    = ud.object(forKey: "notchagent.soundEnabled")    != nil ? ud.bool(forKey: "notchagent.soundEnabled")    : true
        soundVolume     = ud.object(forKey: "notchagent.soundVolume")     != nil ? ud.double(forKey: "notchagent.soundVolume")   : 0.3
        hideWhenIdle    = ud.object(forKey: "notchagent.hideWhenIdle")    != nil ? ud.bool(forKey: "notchagent.hideWhenIdle")    : false
        selectedDisplayID = CGDirectDisplayID(ud.integer(forKey: "notchagent.selectedDisplayID"))
    }
}

// MARK: - Hook Manager

final class HookManager {
    static func clearCLIHooks(completion: @escaping (Bool) -> Void) {
        let settingsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json").path
        // Inline python to remove all notch-agent-hook entries from hooks dict
        let script = """
        import sys, json, os
        p = sys.argv[1]
        if not os.path.exists(p): sys.exit(0)
        with open(p) as f: s = json.load(f)
        h = s.get('hooks', {})
        for e in list(h.keys()):
            h[e] = [r for r in h[e] if not any('notch-agent-hook' in hk.get('command','') for hk in r.get('hooks',[]))]
            if not h[e]: del h[e]
        with open(p, 'w') as f: json.dump(s, f, indent=2)
        """
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            task.arguments = ["-c", script, settingsPath]
            do {
                try task.run()
                task.waitUntilExit()
                DispatchQueue.main.async { completion(task.terminationStatus == 0) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
}

// MARK: - Settings Tab Enum

private enum SettingsTab: String, CaseIterable {
    case general = "General"
    case display = "Display"
    case sound   = "Sound"
    case about   = "About"

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .display: return "display.2"
        case .sound:   return "speaker.wave.2.fill"
        case .about:   return "info.circle.fill"
        }
    }

    var iconBackground: Color {
        switch self {
        case .general: return Color(white: 0.45)
        case .display: return .purple
        case .sound:   return .orange
        case .about:   return .blue
        }
    }
}

// MARK: - Sidebar Item

private struct SidebarItem: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(tab.iconBackground)
                        .frame(width: 26, height: 26)
                    Image(systemName: tab.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(tab.rawValue)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color(white: 0.26) : (isHovered ? Color(white: 0.18) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Settings UI Helpers

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RowDivider: View {
    var body: some View { Color(white: 0.24).frame(height: 0.5) }
}

private struct RowBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(white: 0.165))
    }
}

private struct GroupBox<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(spacing: 0) { content }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(white: 0.27), lineWidth: 0.5))
    }
}

private struct LinkRow: View {
    let icon: String
    let label: String
    var subtitle: String? = nil
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13))
                Spacer()
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                }
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .modifier(RowBackground())
            .background(isHovered ? Color(white: 0.20) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - General Settings

private struct GeneralSettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var launchAtLogin = false
    private let hasBundle = Bundle.main.bundleIdentifier != nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if hasBundle {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "System")
                        GroupBox {
                            HStack {
                                Text("Launch at Startup")
                                    .font(.system(size: 13))
                                Spacer()
                                Toggle("", isOn: $launchAtLogin)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                                    .onChange(of: launchAtLogin) { newValue in
                                        do {
                                            if newValue { try SMAppService.mainApp.register() }
                                            else        { try SMAppService.mainApp.unregister() }
                                        } catch { launchAtLogin = !newValue }
                                    }
                            }
                            .modifier(RowBackground())
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Visibility")
                    GroupBox {
                        HStack {
                            Text("Hide when no active sessions")
                                .font(.system(size: 13))
                            Spacer()
                            Toggle("", isOn: $prefs.hideWhenIdle)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        .modifier(RowBackground())
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
}

// MARK: - Display Settings

private struct DisplaySettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var screens: [NSScreen] = NSScreen.screens

    private func screenLabel(_ screen: NSScreen) -> String {
        screen.hasNotch ? "\(screen.localizedName) (notch)" : screen.localizedName
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Monitor")
                    GroupBox {
                        HStack {
                            Text("Show notch on")
                                .font(.system(size: 13))
                            Spacer()
                            if screens.count > 1 {
                                Picker("", selection: $prefs.selectedDisplayID) {
                                    ForEach(screens, id: \.displayID) { screen in
                                        Text(screenLabel(screen)).tag(screen.displayID)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 200)
                                .onChange(of: prefs.selectedDisplayID) { _ in
                                    NotificationCenter.default.post(
                                        name: NSApplication.didChangeScreenParametersNotification,
                                        object: nil
                                    )
                                }
                            } else {
                                Text(screens.first.map { screenLabel($0) } ?? "Built-in Display")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .modifier(RowBackground())
                    }

                    if screens.count == 1 {
                        Text("Connect an external display to choose where the notch appears.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
    }
}

// MARK: - Sound Settings

private struct SoundSettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var previewPlayer: AVAudioPlayer?

    private func preview(_ name: String) {
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        previewPlayer = try? AVAudioPlayer(contentsOf: url)
        previewPlayer?.volume = Float(prefs.soundVolume)
        previewPlayer?.play()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox {
                    HStack {
                        Text("Enable sounds")
                            .font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: $prefs.soundEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .modifier(RowBackground())

                    RowDivider()

                    HStack(spacing: 10) {
                        Text("Volume")
                            .font(.system(size: 13))
                        Spacer()
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Slider(value: $prefs.soundVolume, in: 0...1)
                            .frame(width: 150)
                            .disabled(!prefs.soundEnabled)
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("\(Int(prefs.soundVolume * 100))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    .modifier(RowBackground())
                    .opacity(prefs.soundEnabled ? 1 : 0.45)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Sounds")
                    GroupBox {
                        HStack(spacing: 10) {
                            Text("Interruption")
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $prefs.interruptSoundName) {
                                ForEach(AppPreferences.systemSounds, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 110)
                            .disabled(!prefs.soundEnabled)
                            .onChange(of: prefs.interruptSoundName) { preview($0) }
                            Button(action: { preview(prefs.interruptSoundName) }) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(prefs.soundEnabled ? .primary : .tertiary)
                            }
                            .buttonStyle(.plain)
                            .disabled(!prefs.soundEnabled)
                        }
                        .modifier(RowBackground())

                        RowDivider()

                        HStack(spacing: 10) {
                            Text("Task finish")
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $prefs.finishSoundName) {
                                ForEach(AppPreferences.systemSounds, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 110)
                            .disabled(!prefs.soundEnabled)
                            .onChange(of: prefs.finishSoundName) { preview($0) }
                            Button(action: { preview(prefs.finishSoundName) }) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(prefs.soundEnabled ? .primary : .tertiary)
                            }
                            .buttonStyle(.plain)
                            .disabled(!prefs.soundEnabled)
                        }
                        .modifier(RowBackground())
                    }
                    .opacity(prefs.soundEnabled ? 1 : 0.55)
                }

                Spacer()
            }
            .padding(24)
        }
    }
}

// MARK: - About Settings

private struct AboutSettingsView: View {
    @State private var showClearHooksConfirm = false
    private let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // App identity
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        if let img = NSImage(named: "AppIcon") {
                            Image(nsImage: img)
                                .resizable()
                                .frame(width: 64, height: 64)
                                .cornerRadius(14)
                        }
                        Text("Notch Agent")
                            .font(.system(size: 15, weight: .semibold))
                        Text("v\(currentVersion)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.bottom, 24)

                // Updates
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Updates")
                    GroupBox {
                        Button(action: { UpdaterManager.shared.controller?.checkForUpdates(nil) }) {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13))
                                    .frame(width: 16)
                                Text("Check for updates")
                                    .font(.system(size: 13))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            .modifier(RowBackground())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 16)

                // Links
                GroupBox {
                    LinkRow(icon: "paperplane", label: "Send feedback", subtitle: "nikpavic9@gmail.com") {
                        open("mailto:nikpavic9@gmail.com")
                    }
                    RowDivider()
                    LinkRow(icon: "ant", label: "Report a bug") {
                        open("https://github.com/TeamNoSleepz/notch-agent/issues/new")
                    }
                    RowDivider()
                    LinkRow(icon: "bubble.left.and.bubble.right", label: "Join Discord community") {
                        open("https://discord.gg/notch-agent")
                    }
                    RowDivider()
                    LinkRow(icon: "person", label: "Creator", subtitle: "Nik Pavic") {
                        open("https://github.com/TeamNoSleepz")
                    }
                }
                .padding(.bottom, 16)

                // Destructive
                GroupBox {
                    Button(action: { showClearHooksConfirm = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                                .frame(width: 16)
                            Text("Clear CLI hooks")
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .modifier(RowBackground())
                    }
                    .buttonStyle(.plain)
                }

                Text("Removes NotchAgent hooks from ~/.claude/settings.json. The status changes will stop updating.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 6)

                Spacer()
            }
            .padding(24)
        }
        .alert("Clear CLI Hooks", isPresented: $showClearHooksConfirm) {
            Button("Clear Hooks", role: .destructive) {
                HookManager.clearCLIHooks { _ in }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove NotchAgent hooks from ~/.claude/settings.json. The status indicator will stop updating until hooks are reinstalled.")
        }
    }
}

// MARK: - Settings Root

struct SettingsView: View {
    @State private var selectedTab = SettingsTab.general

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsTab.allCases, id: \.rawValue) { tab in
                    SidebarItem(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
                Spacer()
            }
            .padding(.top, 20)
            .frame(width: 192)
            .background(Color(white: 0.105))

            Color(white: 0.22).frame(width: 0.5)

            // Content
            Group {
                switch selectedTab {
                case .general: GeneralSettingsView()
                case .display: DisplaySettingsView()
                case .sound:   SoundSettingsView()
                case .about:   AboutSettingsView()
                }
            }
            .frame(width: 447.5)
            .background(Color(white: 0.118))
        }
        .frame(height: 608)
    }
}

// MARK: - Window Controller

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func showWindow() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 608),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "Settings"
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.center()
            w.contentView = NSHostingView(rootView: SettingsView())
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
