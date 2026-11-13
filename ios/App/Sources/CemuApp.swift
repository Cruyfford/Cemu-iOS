import SwiftUI

@main
struct CemuApp: App {
    @StateObject private var core = EmulatorCore.shared
    @AppStorage("appearance") private var appearance = 0
    @AppStorage("accent") private var accentRaw = AppAccent.aqua.rawValue

    private var scheme: ColorScheme? {
        switch appearance {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(core)
                .preferredColorScheme(scheme)
                .tint((AppAccent(rawValue: accentRaw) ?? .aqua).color)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var core: EmulatorCore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @AppStorage("screenMode") private var screenModeRaw = ScreenMode.tv.rawValue
    @State private var launching: GameEntry?
    @State private var showEmulation = false
    @State private var launchError: String?
    @State private var showInterpreterWarning = false
    @State private var pendingGame: GameEntry?

    var body: some View {
        TabView(selection: $tab) {
            LibraryView(onLaunch: requestLaunch)
                .tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }
                .tag(0)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(1)
        }
            .minimizingTabBar()
            .onChange(of: tab) { _ in
                SoundManager.shared.play(.select)
                Haptics.tap()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    if !showEmulation { SoundManager.shared.startMusic() }
                } else if phase == .background {
                    SoundManager.shared.enterBackground()
                }
            }
            .onAppear {
                SoundManager.shared.startMusic()
                core.start()
                // JIT must be ready before the recompiler runs. If StikDebug already attached this
                // prepares the arena right away, otherwise it asks StikDebug to attach.
                JITManager.shared.checkOnLaunch()
            }
            .fullScreenCover(isPresented: $showEmulation, onDismiss: {
                if core.runningGame != nil { core.stopGame() }
                launching = nil
                PlayState.shared.inGame = false
                SoundManager.shared.resumeAfterGame()
            }) {
                EmulationContainer(game: launching, onFailed: { msg in
                    showEmulation = false
                    launchError = msg
                    SoundManager.shared.play(.error)
                })
                .environmentObject(core)
            }
            .onChange(of: core.runningGame) { game in
                if game == nil && showEmulation { showEmulation = false }
            }
            .alert("Cemu", isPresented: Binding(get: { launchError != nil || core.errorMessage != nil },
                                                set: { if !$0 { launchError = nil; core.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(launchError ?? core.errorMessage ?? "")
            }
            .alert("JIT is not enabled", isPresented: $showInterpreterWarning) {
                Button("Enable JIT") { JITManager.shared.requestJIT() }
                Button("Play anyway") { if let g = pendingGame { startEmulation(g) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Without JIT the game runs on the interpreter and will be extremely slow.")
            }
    }

    private func requestLaunch(_ game: GameEntry) {
        if JITManager.shared.isEnabled {
            startEmulation(game)
        } else {
            pendingGame = game
            showInterpreterWarning = true
        }
    }

    private func startEmulation(_ game: GameEntry) {
        let mode = ScreenMode(rawValue: screenModeRaw) ?? .tv
        RenderSurfaces.shared.register(withGamePadScreen: mode == .tvWithGamePad)
        SoundManager.shared.play(.launch)
        Haptics.success()
        SoundManager.shared.suspendForGame()
        PlayState.shared.inGame = true
        launching = game
        showEmulation = true
    }
}

/// Shows the render surfaces first and launches the title once they have a size.
struct EmulationContainer: View {
    @EnvironmentObject var core: EmulatorCore
    let game: GameEntry?
    var onFailed: (String) -> Void
    @State private var started = false

    var body: some View {
        EmulationView()
            .task {
                guard !started, let game else { return }
                started = true
                // give UIKit one layout pass so the CAMetalLayer has its final size
                try? await Task.sleep(nanoseconds: 150_000_000)
                do {
                    try core.launch(game)
                } catch {
                    onFailed(error.localizedDescription)
                }
            }
    }
}
