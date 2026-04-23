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
        ColorPalette(
            name: "Neon",
            idle: Color(white: 0.4),
            working: Color(red: 0, green: 1, blue: 0.4),
            awaiting: Color(red: 0.4, green: 0.4, blue: 1)
        ),
        ColorPalette(
            name: "Pastel",
            idle: Color(white: 0.5),
            working: Color(red: 1, green: 0.75, blue: 0.5),
            awaiting: Color(red: 0.8, green: 0.6, blue: 1)
        ),
    ]

    static let systemSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
        "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    @Published var paletteIndex: Int {
        didSet { UserDefaults.standard.set(paletteIndex, forKey: "vibenotch.paletteIndex") }
    }

    @Published var interruptSoundEnabled: Bool {
        didSet { UserDefaults.standard.set(interruptSoundEnabled, forKey: "vibenotch.interruptSoundEnabled") }
    }

    @Published var interruptSoundName: String {
        didSet { UserDefaults.standard.set(interruptSoundName, forKey: "vibenotch.interruptSoundName") }
    }

    @Published var finishSoundEnabled: Bool {
        didSet { UserDefaults.standard.set(finishSoundEnabled, forKey: "vibenotch.finishSoundEnabled") }
    }

    @Published var finishSoundName: String {
        didSet { UserDefaults.standard.set(finishSoundName, forKey: "vibenotch.finishSoundName") }
    }

    var selectedPalette: ColorPalette { Self.presets[paletteIndex] }

    private init() {
        let saved = UserDefaults.standard.integer(forKey: "vibenotch.paletteIndex")
        paletteIndex = saved < Self.presets.count ? saved : 0

        let ud = UserDefaults.standard

        if ud.object(forKey: "vibenotch.interruptSoundEnabled") != nil {
            interruptSoundEnabled = ud.bool(forKey: "vibenotch.interruptSoundEnabled")
        } else {
            interruptSoundEnabled = true
        }
        interruptSoundName = ud.string(forKey: "vibenotch.interruptSoundName") ?? "Ping"

        if ud.object(forKey: "vibenotch.finishSoundEnabled") != nil {
            finishSoundEnabled = ud.bool(forKey: "vibenotch.finishSoundEnabled")
        } else {
            finishSoundEnabled = true
        }
        finishSoundName = ud.string(forKey: "vibenotch.finishSoundName") ?? "Glass"
    }
}

// MARK: - Palette Swatch

struct PaletteSwatchView: View {
    let palette: ColorPalette
    let isSelected: Bool
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
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    .frame(width: 64, height: 52)
            }
            Text(palette.name)
                .font(.caption)
                .foregroundColor(isSelected ? .primary : .secondary)
        }
        .onTapGesture(perform: onTap)
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

// MARK: - General Settings

struct GeneralSettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var launchAtLogin = false
    private let hasBundle = Bundle.main.bundleIdentifier != nil

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
                            onTap: { prefs.paletteIndex = index }
                        )
                    }
                }
            }

            if hasBundle {
                Divider()
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

            Spacer()
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
        .frame(width: 380, height: 340)
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
