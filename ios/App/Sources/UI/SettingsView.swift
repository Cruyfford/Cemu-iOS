import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Cemu core settings (settings.xml) shared by the settings pages.
@MainActor
final class CoreSettingsModel: ObservableObject {
    @Published var values: [String: Any] = [:]

    func load() { values = EmulatorCore.shared.loadSettings() }

    func int(_ key: String, _ def: Int) -> Binding<Int> {
        Binding(get: { (self.values[key] as? NSNumber)?.intValue ?? def },
                set: { v in
                    self.values[key] = v
                    EmulatorCore.shared.saveSettings([key: v])
                    SoundManager.shared.play(.toggle)
                })
    }

    func bool(_ key: String, _ def: Bool) -> Binding<Bool> {
        Binding(get: { (self.values[key] as? NSNumber)?.boolValue ?? def },
                set: { v in
                    self.values[key] = v
                    EmulatorCore.shared.saveSettings([key: v])
                    SoundManager.shared.play(.toggle)
                })
    }
}

struct SettingsView: View {
    @EnvironmentObject var core: EmulatorCore
    @ObservedObject private var jit = JITManager.shared
    @StateObject private var model = CoreSettingsModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    headerCard
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                Section {
                    link("Appearance", "paintbrush.fill", .pink) { AppearanceSettings() }
                    link("Sound & Music", "music.note", .red) { SoundSettings() }
                }

                Section {
                    link("General", "gearshape.fill", .gray) { GeneralSettings(model: model) }
                    link("Graphics", "sparkles.tv.fill", .blue) { GraphicsSettings(model: model) }
                    link("Audio", "speaker.wave.2.fill", .orange) { AudioSettings(model: model) }
                    link("Controls", "gamecontroller.fill", .green) { ControlSettings() }
                }

                Section {
                    link("JIT", "bolt.fill", .yellow, badge: jit.isEnabled ? "On" : "Off") { JITSettings() }
                    link("Keys & Files", "key.fill", .teal, badge: core.hasKeys ? nil : "Missing") { FilesSettings() }
                }

                Section {
                    link("About", "info.circle.fill", .indigo) { AboutSettings() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AnimatedBackground())
            .navigationTitle("Settings")
            .onAppear { model.load() }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 16) {
            Image("AppIconPreview")
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text("Cemu").font(.title2.weight(.bold))
                Text("Wii U emulator for iOS").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Chip(text: jit.isEnabled ? "JIT on" : "JIT off", systemImage: "bolt.fill", tint: jit.isEnabled ? .green : .orange)
                    Chip(text: core.hasKeys ? "Keys" : "No keys", systemImage: "key.fill", tint: core.hasKeys ? .green : .orange)
                    Chip(text: "\(core.games.count) games", systemImage: "square.grid.2x2.fill")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassSurface(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func link<D: View>(_ title: String, _ icon: String, _ color: Color, badge: String? = nil, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink {
            destination()
                .scrollContentBackground(.hidden)
                .background(AnimatedBackground())
                .onAppear { SoundManager.shared.play(.open) }
        } label: {
            HStack(spacing: 14) {
                SettingsIcon(systemImage: icon, color: color)
                Text(title)
                Spacer()
                if let badge {
                    Text(badge).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @AppStorage("appearance") private var appearance = 0 // 0 system, 1 light, 2 dark
    @AppStorage("accent") private var accentRaw = AppAccent.aqua.rawValue
    @AppStorage("animatedBackground") private var animated = true
    @AppStorage("tileSize") private var tileSize = 1.0

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            Section("Accent color") {
                HStack(spacing: 0) {
                    ForEach(AppAccent.allCases) { a in
                        Button {
                            withAnimation(.spring(response: 0.3)) { accentRaw = a.rawValue }
                            SoundManager.shared.play(.toggle)
                            Haptics.tap()
                        } label: {
                            ZStack {
                                Circle().fill(a.color).frame(width: 34, height: 34)
                                if accentRaw == a.rawValue {
                                    Circle().stroke(a.color, lineWidth: 2.5).frame(width: 44, height: 44)
                                    Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section {
                Toggle("Animated background", isOn: $animated)
                Picker("Library tile size", selection: $tileSize) {
                    Text("Small").tag(0.8)
                    Text("Medium").tag(1.0)
                    Text("Large").tag(1.3)
                }
            } footer: {
                Text("The animated background pauses automatically while a game is running and when Reduce Motion is on.")
            }
        }
        .navigationTitle("Appearance")
        .onChange(of: appearance) { _ in SoundManager.shared.play(.toggle) }
        .onChange(of: animated) { _ in SoundManager.shared.play(.toggle) }
    }
}

// MARK: - Sound

struct SoundSettings: View {
    @ObservedObject private var sound = SoundManager.shared
    private static let previews: [(String, SoundManager.Effect)] = [("Tap", .tap), ("Open", .open), ("Back", .back), ("Launch", .launch)]

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $sound.musicEnabled) { Label("Menu music", systemImage: "music.note.list") }
                if sound.musicEnabled {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $sound.musicVolume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("A relaxed original soundtrack plays in the menus and fades out when a game starts.")
            }
            Section {
                Toggle(isOn: $sound.effectsEnabled) { Label("Interface sounds", systemImage: "hand.tap.fill") }
                if sound.effectsEnabled {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $sound.effectsVolume, in: 0...1, onEditingChanged: { editing in
                            if !editing { sound.play(.select) }
                        })
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                    HStack {
                        ForEach(Self.previews, id: \.0) { item in
                            Button(item.0) { sound.play(item.1) }
                                .secondaryButton()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sound & Music")
    }
}

// MARK: - Core settings pages

struct GeneralSettings: View {
    @ObservedObject var model: CoreSettingsModel
    private let languages = ["Japanese", "English", "French", "German", "Italian", "Spanish", "Chinese", "Korean", "Dutch", "Portuguese", "Russian", "Taiwanese"]

    var body: some View {
        Form {
            Section {
                Picker("Console language", selection: model.int("consoleLanguage", 1)) {
                    ForEach(languages.indices, id: \.self) { Text(languages[$0]).tag($0) }
                }
            } footer: {
                Text("Games use this as the system language when they support it.")
            }
            Section {
                Toggle("Online features", isOn: model.bool("onlineEnabled", false))
            } footer: {
                Text("Requires your own console's online files in the mlc folder.")
            }
        }
        .navigationTitle("General")
    }
}

struct GraphicsSettings: View {
    @ObservedObject var model: CoreSettingsModel
    @AppStorage("screenMode") private var screenModeRaw = ScreenMode.tv.rawValue

    var body: some View {
        Form {
            Section("Display") {
                Picker("Default screen", selection: $screenModeRaw) {
                    ForEach(ScreenMode.allCases) { Label($0.title, systemImage: $0.icon).tag($0.rawValue) }
                }
                Picker("Scaling", selection: model.int("scaling", 0)) {
                    Text("Keep aspect ratio").tag(0)
                    Text("Stretch").tag(1)
                }
                Picker("VSync", selection: model.int("vsync", 0)) {
                    Text("Off").tag(0)
                    Text("On").tag(1)
                }
            }
            Section("Filters") {
                Picker("Upscale", selection: model.int("upscaleFilter", 1)) {
                    Text("Bilinear").tag(0)
                    Text("Bicubic").tag(1)
                    Text("Hermite").tag(2)
                    Text("Nearest").tag(3)
                }
                Picker("Downscale", selection: model.int("downscaleFilter", 0)) {
                    Text("Bilinear").tag(0)
                    Text("Bicubic").tag(1)
                    Text("Hermite").tag(2)
                    Text("Nearest").tag(3)
                }
            }
            Section {
                Toggle("Async shader compile", isOn: model.bool("asyncCompile", true))
                Toggle("Full sync at GX2DrawDone", isOn: model.bool("gx2DrawdoneSync", true))
                Toggle("Framebuffer fetch", isOn: model.bool("framebufferFetch", true))
            } header: {
                Text("Metal")
            } footer: {
                Text("Async shader compile reduces stutter while caches build; disable it if a game shows missing graphics.")
            }
            Section("Overlay") {
                Toggle("FPS counter (in-game)", isOn: model.bool("overlayFPS", false))
                Toggle("Notifications", isOn: model.bool("notifications", true))
            }
        }
        .navigationTitle("Graphics")
    }
}

struct AudioSettings: View {
    @ObservedObject var model: CoreSettingsModel

    var body: some View {
        Form {
            Section("Volume") {
                volume("TV", key: "tvVolume", def: 50)
                volume("GamePad", key: "padVolume", def: 0)
            }
            Section {
                Stepper("Latency \(model.int("audioDelay", 2).wrappedValue * 12) ms", value: model.int("audioDelay", 2), in: 1...8)
                Picker("TV channels", selection: model.int("tvChannels", 1)) {
                    Text("Mono").tag(0)
                    Text("Stereo").tag(1)
                    Text("Surround").tag(2)
                }
            } footer: {
                Text("Raise the latency if you hear crackling.")
            }
        }
        .navigationTitle("Audio")
    }

    private func volume(_ title: String, key: String, def: Int) -> some View {
        let b = model.int(key, def)
        return VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text("\(b.wrappedValue)%").foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: Binding(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = Int($0.rounded()) }), in: 0...100, step: 5)
        }
    }
}

struct ControlSettings: View {
    @ObservedObject private var input = InputHub.shared
    @AppStorage("hideTouchWithController") private var hideTouchWithController = true

    var body: some View {
        Form {
            Section("Controller") {
                HStack {
                    Image(systemName: input.controllerConnected ? "gamecontroller.fill" : "gamecontroller")
                        .foregroundStyle(input.controllerConnected ? Color.green : Color.secondary)
                    Text(input.controllerName ?? "No controller connected")
                    Spacer()
                    if input.controllerConnected { Chip(text: "Connected", tint: .green) }
                }
                Toggle("Use controller's A/B labels", isOn: $input.swapFaceButtons)
            }
            Section {
                Toggle("Hide touch controls with a controller", isOn: $hideTouchWithController)
            } header: {
                Text("Touch")
            } footer: {
                Text("Move, resize and hide on-screen buttons from the pause menu › Controls. Double-tap a button while editing to hide it.")
            }
        }
        .navigationTitle("Controls")
    }
}

struct JITSettings: View {
    @ObservedObject private var jit = JITManager.shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: jit.isEnabled ? "bolt.fill" : "bolt.slash.fill")
                        .font(.title2)
                        .foregroundStyle(jit.isEnabled ? Color.yellow : Color.secondary)
                        .frame(width: 44, height: 44)
                        .glassSurface(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(jit.isEnabled ? "JIT is active" : "JIT is off").font(.headline)
                        Text(jit.statusText).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !jit.isEnabled {
                    SoundButton(effect: .select, action: { jit.requestJIT() }) {
                        Label("Enable with StikDebug", systemImage: "bolt.badge.automatic")
                            .frame(maxWidth: .infinity)
                    }
                    .prominentButton()
                }
            }
            Section("Options") {
                LabeledContent("Protocol", value: jit.usesTXM ? "TXM (iOS 26+)" : "Legacy")
                Picker("Mode", selection: $jit.jitMode) {
                    Text("Automatic").tag(0)
                    Text("TXM / universal.js").tag(1)
                    Text("Legacy").tag(2)
                }
                Picker("Code cache", selection: $jit.arenaMB) {
                    Text("256 MB").tag(256)
                    Text("512 MB").tag(512)
                    Text("1 GB").tag(1024)
                }
                Toggle("Request JIT on launch", isOn: $jit.autoRequest)
            }
        }
        .navigationTitle("JIT")
    }
}

struct FilesSettings: View {
    @EnvironmentObject var core: EmulatorCore
    @State private var showKeysImporter = false
    @State private var editingKeys = false
    @State private var keysText = ""

    var body: some View {
        Form {
            Section("Keys") {
                LabeledContent("keys.txt") {
                    Chip(text: core.hasKeys ? "Found" : "Missing", tint: core.hasKeys ? .green : .orange)
                }
                Button { showKeysImporter = true } label: { Label("Import keys.txt", systemImage: "square.and.arrow.down") }
                Button {
                    keysText = (try? String(contentsOf: core.keysURL)) ?? ""
                    editingKeys = true
                } label: { Label("Edit keys.txt", systemImage: "pencil") }
            }
            Section {
                Button { core.refreshGames(); SoundManager.shared.play(.select) } label: { Label("Rescan games", systemImage: "arrow.clockwise") }
            } header: {
                Text("Library")
            } footer: {
                Text("Games: Files › On My iPhone › Cemu › games\nSaves and system files: Cemu › mlc01")
            }
        }
        .navigationTitle("Keys & Files")
        .fileImporter(isPresented: $showKeysImporter, allowedContentTypes: [.plainText, .text, .data]) { result in
            if case .success(let url) = result { core.importKeys(from: url); SoundManager.shared.play(.select) }
        }
        .sheet(isPresented: $editingKeys) {
            NavigationStack {
                TextEditor(text: $keysText)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal)
                    .navigationTitle("keys.txt")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingKeys = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                try? keysText.write(to: core.keysURL, atomically: true, encoding: .utf8)
                                editingKeys = false
                                SoundManager.shared.play(.select)
                                core.refreshGames()
                            }
                        }
                    }
            }
        }
    }
}

struct AboutSettings: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image("AppIconPreview")
                        .resizable()
                        .frame(width: 90, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                    Text("Cemu for iOS").font(.title3.weight(.bold))
                    Text(String(cString: CemuBridge_Version())).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section {
                Text("Cemu is licensed under the Mozilla Public License 2.0. Menu music and sounds are original works made for this app.")
                Text("Use games and keys dumped from your own console.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("About")
    }
}
