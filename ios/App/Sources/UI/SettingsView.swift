import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var core: EmulatorCore
    @ObservedObject var jit = JITManager.shared
    @ObservedObject var input = InputHub.shared
    @Environment(\.dismiss) private var dismiss

    @State private var s: [String: Any] = [:]
    @State private var showKeysImporter = false
    @State private var keysText = ""
    @State private var editingKeys = false

    @AppStorage("showFPS") private var showFPS = true
    @AppStorage("screenMode") private var screenModeRaw = ScreenMode.tv.rawValue
    @AppStorage("hideTouchWithController") private var hideTouchWithController = true

    private let languages = ["Japanese", "English", "French", "German", "Italian", "Spanish", "Chinese", "Korean", "Dutch", "Portuguese", "Russian", "Taiwanese"]

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    Picker("Console language", selection: intBinding("consoleLanguage", 1)) {
                        ForEach(languages.indices, id: \.self) { Text(languages[$0]).tag($0) }
                    }
                    Toggle("Online play (needs your console files)", isOn: boolBinding("onlineEnabled", false))
                }

                Section {
                    Picker("Default screen", selection: $screenModeRaw) {
                        ForEach(ScreenMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("Scaling", selection: intBinding("scaling", 0)) {
                        Text("Keep aspect ratio").tag(0)
                        Text("Stretch").tag(1)
                    }
                    Picker("Upscale filter", selection: intBinding("upscaleFilter", 1)) {
                        Text("Bilinear").tag(0)
                        Text("Bicubic").tag(1)
                        Text("Hermite").tag(2)
                        Text("Nearest").tag(3)
                    }
                    Picker("Downscale filter", selection: intBinding("downscaleFilter", 0)) {
                        Text("Bilinear").tag(0)
                        Text("Bicubic").tag(1)
                        Text("Hermite").tag(2)
                        Text("Nearest").tag(3)
                    }
                    Picker("VSync", selection: intBinding("vsync", 0)) {
                        Text("Off").tag(0)
                        Text("On").tag(1)
                    }
                    Toggle("Async shader compile", isOn: boolBinding("asyncCompile", true))
                    Toggle("Full sync at GX2DrawDone", isOn: boolBinding("gx2DrawdoneSync", true))
                    Toggle("Framebuffer fetch", isOn: boolBinding("framebufferFetch", true))
                    Toggle("Show FPS", isOn: $showFPS)
                    Toggle("Notifications overlay", isOn: boolBinding("notifications", true))
                } header: {
                    Text("Graphics (Metal)")
                } footer: {
                    Text("Shader caches build up while playing; the first run of a game stutters more.")
                }

                Section("Audio") {
                    Stepper("TV volume: \(int("tvVolume", 50))%", value: intBinding("tvVolume", 50), in: 0...100, step: 5)
                    Stepper("GamePad volume: \(int("padVolume", 0))%", value: intBinding("padVolume", 0), in: 0...100, step: 5)
                    Stepper("Latency: \(int("audioDelay", 2) * 12) ms", value: intBinding("audioDelay", 2), in: 1...8)
                    Picker("TV channels", selection: intBinding("tvChannels", 1)) {
                        Text("Mono").tag(0)
                        Text("Stereo").tag(1)
                        Text("Surround").tag(2)
                    }
                }

                Section("Controls") {
                    LabeledContent("Controller", value: input.controllerName ?? "None")
                    Toggle("Hide touch controls when a controller is connected", isOn: $hideTouchWithController)
                    Toggle("Use controller's A/B labels (not positions)", isOn: $input.swapFaceButtons)
                    Text("Touch controls can be moved and resized from the in-game menu › Edit touch controls. Double-tap a control while editing to hide it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("Status", value: jit.statusText)
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
                    if !jit.isEnabled {
                        Button("Enable JIT with StikDebug") { jit.requestJIT() }
                    }
                } header: {
                    Text("JIT")
                } footer: {
                    Text("JIT lets the PowerPC recompiler run; without it Cemu uses the interpreter and games are very slow. Mode and cache size apply the next time JIT is enabled.")
                }

                Section("Files") {
                    LabeledContent("keys.txt", value: core.hasKeys ? "Found" : "Missing")
                    Button("Import keys.txt") { showKeysImporter = true }
                    Button("Edit keys.txt") {
                        keysText = (try? String(contentsOf: core.keysURL)) ?? ""
                        editingKeys = true
                    }
                    Button("Rescan games") { core.refreshGames() }
                    Text("Games: Files › On My iPhone › Cemu › games\nSaves and system files: Cemu › mlc01")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Core", value: String(cString: CemuBridge_Version()))
                    Text("Cemu is licensed under the MPL 2.0. Use games and keys you dumped from your own console.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { s = core.loadSettings() }
            .fileImporter(isPresented: $showKeysImporter, allowedContentTypes: [.plainText, .text, .data]) { result in
                if case .success(let url) = result { core.importKeys(from: url) }
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
                                    core.refreshGames()
                                }
                            }
                        }
                }
            }
        }
    }

    private func int(_ key: String, _ def: Int) -> Int { (s[key] as? NSNumber)?.intValue ?? def }

    private func intBinding(_ key: String, _ def: Int) -> Binding<Int> {
        Binding(get: { int(key, def) }, set: { v in
            s[key] = v
            core.saveSettings([key: v])
        })
    }

    private func boolBinding(_ key: String, _ def: Bool) -> Binding<Bool> {
        Binding(get: { (s[key] as? NSNumber)?.boolValue ?? def }, set: { v in
            s[key] = v
            core.saveSettings([key: v])
        })
    }
}
