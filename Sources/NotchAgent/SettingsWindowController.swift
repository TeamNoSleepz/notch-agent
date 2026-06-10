import AppKit
import AVFoundation
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
    @Published var autoCheckUpdates: Bool {
        didSet { UserDefaults.standard.set(autoCheckUpdates, forKey: "notchagent.autoCheckUpdates") }
    }

    private init() {
        let ud = UserDefaults.standard
        interruptSoundName = ud.string(forKey: "notchagent.interruptSoundName") ?? "Ping"
        finishSoundName    = ud.string(forKey: "notchagent.finishSoundName")    ?? "Glass"
        soundEnabled    = ud.object(forKey: "notchagent.soundEnabled")    != nil ? ud.bool(forKey: "notchagent.soundEnabled")    : true
        soundVolume     = ud.object(forKey: "notchagent.soundVolume")     != nil ? ud.double(forKey: "notchagent.soundVolume")   : 0.3
        hideWhenIdle    = ud.object(forKey: "notchagent.hideWhenIdle")    != nil ? ud.bool(forKey: "notchagent.hideWhenIdle")    : false
        autoCheckUpdates = ud.object(forKey: "notchagent.autoCheckUpdates") != nil ? ud.bool(forKey: "notchagent.autoCheckUpdates") : true
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

// MARK: - Update Progress Sheet

struct UpdateProgressView: View {
    let version: String
    @Binding var isPresented: Bool

    @State private var log = ""
    @State private var isRunning = true
    @State private var succeeded = false
    @State private var started = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if isRunning {
                    ProgressView().scaleEffect(0.75)
                    Text("Installing v\(version)…")
                } else if succeeded {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Update complete!")
                } else {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    Text("Update failed")
                }
                Spacer()
            }
            .font(.headline)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(log.isEmpty ? " " : log)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .id("end")
                }
                .frame(height: 140)
                .background(Color(.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onChange(of: log) { _ in
                    withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                }
            }

            HStack {
                Spacer()
                if succeeded {
                    Button("Relaunch Now") { UpdateChecker.relaunch() }
                        .buttonStyle(.borderedProminent)
                } else if !isRunning {
                    Button("Close") { isPresented = false }
                    Button("View on GitHub") {
                        NSWorkspace.shared.open(UpdateChecker.releasesURL)
                        isPresented = false
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            guard !started else { return }
            started = true
            UpdateChecker.install(version: version) { chunk in
                log += chunk
            } completion: { ok in
                isRunning = false
                succeeded = ok
            }
        }
    }
}

// MARK: - Settings Tab Enum

private enum SettingsTab: String, CaseIterable {
    case general = "General"
    case sound   = "Sound"
    case about   = "About"

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .sound:   return "speaker.wave.2.fill"
        case .about:   return "info.circle.fill"
        }
    }

    var iconBackground: Color {
        switch self {
        case .general: return Color(white: 0.45)
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
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var checkingUpdate = false
    @State private var availableVersion: String? = nil
    @State private var upToDate = false
    @State private var showUpdateSheet = false
    @State private var showClearHooksConfirm = false
    private let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func checkForUpdates() {
        guard !checkingUpdate else { return }
        if availableVersion != nil { showUpdateSheet = true; return }
        checkingUpdate = true
        upToDate = false
        UpdateChecker.check { version in
            checkingUpdate = false
            if let version {
                availableVersion = version
            } else {
                upToDate = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { upToDate = false }
            }
        }
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
                        Button(action: checkForUpdates) {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13))
                                    .frame(width: 16)
                                Text(checkingUpdate ? "Checking…"
                                     : upToDate ? "Up to date ✓"
                                     : availableVersion != nil ? "Update to v\(availableVersion!)"
                                     : "Check for updates")
                                    .font(.system(size: 13))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            .modifier(RowBackground())
                        }
                        .buttonStyle(.plain)
                        .disabled(checkingUpdate)

                        RowDivider()

                        HStack(spacing: 10) {
                            Image(systemName: "arrow.clockwise.circle")
                                .font(.system(size: 13))
                                .frame(width: 16)
                            Text("Automatically check for updates")
                                .font(.system(size: 13))
                            Spacer()
                            Toggle("", isOn: $prefs.autoCheckUpdates)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        .modifier(RowBackground())
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
        .sheet(isPresented: $showUpdateSheet) {
            if let version = availableVersion {
                UpdateProgressView(version: version, isPresented: $showUpdateSheet)
                    .onDisappear { availableVersion = nil }
            }
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

// MARK: - Update Checker

final class UpdateChecker {
    static let releasesURL = URL(string: "https://github.com/TeamNoSleepz/notch-agent/releases")!
    private static let apiURL = URL(string: "https://api.github.com/repos/TeamNoSleepz/notch-agent/releases/latest")!

    static func check(completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            DispatchQueue.main.async {
                completion(isNewer(remote, than: current) ? remote : nil)
            }
        }.resume()
    }

    static func install(version: String, progress: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        let tmpDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("notchagent-update")
        let script = """
        set -e
        rm -rf '\(tmpDir)'
        git clone --depth 1 --branch 'v\(version)' https://github.com/TeamNoSleepz/notch-agent.git '\(tmpDir)'
        bash '\(tmpDir)/scripts/bundle.sh'
        rm -rf '\(tmpDir)'
        """

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-c", script]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/usr/bin:/usr/local/bin:/opt/homebrew/bin:/bin:/sbin:/usr/sbin"
            task.environment = env

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { fh in
                let data = fh.availableData
                if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                    DispatchQueue.main.async { progress(str) }
                }
            }

            do {
                try task.run()
                task.waitUntilExit()
                pipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async { completion(task.terminationStatus == 0) }
            } catch {
                DispatchQueue.main.async {
                    progress("Error: \(error.localizedDescription)\n")
                    completion(false)
                }
            }
        }
    }

    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5 && open /Applications/NotchAgent.app"]
        try? task.run()
        NSApp.terminate(nil)
    }

    private static func isNewer(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").compactMap { Int($0) }
        let bv = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(av.count, bv.count) {
            let ai = i < av.count ? av[i] : 0
            let bi = i < bv.count ? bv[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
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
