import AppKit
import AVFoundation
import SwiftUI
import ServiceManagement

// MARK: - Color Palette

struct ColorPalette {
    let name: String
    let idle: Color
    let working: Color
    let awaiting: Color
}

// MARK: - App Preferences

final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    static let presets: [ColorPalette] = [
        ColorPalette(
            name: "Default",
            idle: Color(white: 0.35),
            working: Color(red: 1, green: 0.4, blue: 0),
            awaiting: Color(red: 1, green: 0.2, blue: 0.2)
        ),
    ]

    static let systemSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
        "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    @Published var paletteIndex: Int {
        didSet { UserDefaults.standard.set(paletteIndex, forKey: "notchagent.paletteIndex") }
    }

    @Published var interruptSoundEnabled: Bool {
        didSet { UserDefaults.standard.set(interruptSoundEnabled, forKey: "notchagent.interruptSoundEnabled") }
    }

    @Published var interruptSoundName: String {
        didSet { UserDefaults.standard.set(interruptSoundName, forKey: "notchagent.interruptSoundName") }
    }

    @Published var finishSoundEnabled: Bool {
        didSet { UserDefaults.standard.set(finishSoundEnabled, forKey: "notchagent.finishSoundEnabled") }
    }

    @Published var finishSoundName: String {
        didSet { UserDefaults.standard.set(finishSoundName, forKey: "notchagent.finishSoundName") }
    }

    var selectedPalette: ColorPalette { Self.presets[paletteIndex] }

    private init() {
        let saved = UserDefaults.standard.integer(forKey: "notchagent.paletteIndex")
        paletteIndex = saved < Self.presets.count ? saved : 0

        let ud = UserDefaults.standard

        if ud.object(forKey: "notchagent.interruptSoundEnabled") != nil {
            interruptSoundEnabled = ud.bool(forKey: "notchagent.interruptSoundEnabled")
        } else {
            interruptSoundEnabled = true
        }
        interruptSoundName = ud.string(forKey: "notchagent.interruptSoundName") ?? "Ping"

        if ud.object(forKey: "notchagent.finishSoundEnabled") != nil {
            finishSoundEnabled = ud.bool(forKey: "notchagent.finishSoundEnabled")
        } else {
            finishSoundEnabled = true
        }
        finishSoundName = ud.string(forKey: "notchagent.finishSoundName") ?? "Glass"

    }
}

// MARK: - Palette Swatch

struct PaletteSwatchView: View {
    let palette: ColorPalette
    let isSelected: Bool
    let comingSoon: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.12))
                    .frame(width: 64, height: 52)
                VStack(spacing: 5) {
                    Circle().fill(palette.idle).frame(width: 9, height: 9)
                    Circle().fill(palette.working).frame(width: 9, height: 9)
                    Circle().fill(palette.awaiting).frame(width: 9, height: 9)
                }
                .opacity(comingSoon ? 0.35 : 1)
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    .frame(width: 64, height: 52)
                if comingSoon {
                    Text("Soon")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            Text(palette.name)
                .font(.caption)
                .foregroundColor(comingSoon ? Color(white: 0.4) : (isSelected ? .primary : .secondary))
        }
        .onTapGesture { if !comingSoon { onTap() } }
    }
}

// MARK: - Coming Soon Swatch

struct ComingSoonSwatchView: View {
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.12))
                    .frame(width: 64, height: 52)
                Text("Soon")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(white: 0.35))
            }
            Text("—")
                .font(.caption)
                .foregroundColor(Color(white: 0.3))
        }
    }
}

// MARK: - Sound Row

struct SoundRowView: View {
    let label: String
    @Binding var enabled: Bool
    @Binding var soundName: String
    @State private var previewPlayer: AVAudioPlayer?

    private func preview(_ name: String) {
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        previewPlayer = try? AVAudioPlayer(contentsOf: url)
        previewPlayer?.play()
    }

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 70, alignment: .leading)
            Toggle("", isOn: $enabled)
                .toggleStyle(.switch)
                .labelsHidden()
            Picker("", selection: $soundName) {
                ForEach(AppPreferences.systemSounds, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
            .disabled(!enabled)
            .onChange(of: soundName) { newName in
                preview(newName)
            }
            Button(action: { preview(soundName) }) {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
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
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Update complete!")
                } else {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.red)
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
                .cornerRadius(6)
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

// MARK: - General Settings

struct GeneralSettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var launchAtLogin = false
    @State private var checkingUpdate = false
    @State private var availableVersion: String? = nil
    @State private var upToDate = false
    @State private var showUpdateSheet = false
    private let hasBundle = Bundle.main.bundleIdentifier != nil
    private let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Color Palette")
                    .font(.headline)
                HStack(spacing: 12) {
                    ForEach(Array(AppPreferences.presets.enumerated()), id: \.offset) { index, palette in
                        PaletteSwatchView(
                            palette: palette,
                            isSelected: prefs.paletteIndex == index,
                            comingSoon: false,
                            onTap: { prefs.paletteIndex = index }
                        )
                    }
                    ComingSoonSwatchView()
                    ComingSoonSwatchView()
                }
            }

            if hasBundle {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("General")
                        .font(.headline)
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                launchAtLogin = !newValue
                            }
                        }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Sound")
                    .font(.headline)
                SoundRowView(
                    label: "Interrupt",
                    enabled: $prefs.interruptSoundEnabled,
                    soundName: $prefs.interruptSoundName
                )
                SoundRowView(
                    label: "Finish",
                    enabled: $prefs.finishSoundEnabled,
                    soundName: $prefs.finishSoundName
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("About")
                    .font(.headline)
                HStack {
                    Text("v\(currentVersion)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Spacer()
                    if let version = availableVersion {
                        Button("Update to v\(version)") { showUpdateSheet = true }
                            .buttonStyle(.borderedProminent)
                    } else if upToDate {
                        Text("Up to date ✓")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Button(checkingUpdate ? "Checking…" : "Check for Updates") {
                            checkingUpdate = true
                            availableVersion = nil
                            upToDate = false
                            UpdateChecker.check { version in
                                checkingUpdate = false
                                if let version {
                                    availableVersion = version
                                } else {
                                    upToDate = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        upToDate = false
                                    }
                                }
                            }
                        }
                        .disabled(checkingUpdate)
                    }
                }
            }
            .sheet(isPresented: $showUpdateSheet) {
                if let version = availableVersion {
                    UpdateProgressView(version: version, isPresented: $showUpdateSheet)
                        .onDisappear { availableVersion = nil }
                }
            }

        }
        .padding(20)
        .frame(width: 340)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
}

// MARK: - Settings Root

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
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
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 340),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "Preferences"
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
