import SwiftUI

enum ScreenMode: Int, CaseIterable, Identifiable {
    case tv = 0, gamepad, tvWithGamePad
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .tv: return "TV"
        case .gamepad: return "GamePad"
        case .tvWithGamePad: return "TV + GamePad"
        }
    }
}

struct EmulationView: View {
    @EnvironmentObject var core: EmulatorCore
    @ObservedObject var input = InputHub.shared
    @AppStorage("showFPS") private var showFPS = true
    @AppStorage("screenMode") private var screenModeRaw = ScreenMode.tv.rawValue
    @AppStorage("hideTouchWithController") private var hideTouchWithController = true
    @State private var layout = TouchLayout.load()
    @State private var editingControls = false
    @State private var showMenu = false
    @State private var confirmStop = false

    private var screenMode: ScreenMode { ScreenMode(rawValue: screenModeRaw) ?? .tv }
    private var showTouch: Bool { !(hideTouchWithController && input.controllerConnected) || editingControls }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                screens(in: geo.size)

                if showTouch {
                    TouchControlsView(layout: $layout, editing: editingControls, onToggleScreen: cycleScreenMode)
                        .ignoresSafeArea()
                }

                VStack {
                    HStack {
                        if showFPS && !editingControls {
                            Text(String(format: "%.0f FPS", core.fps))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.black.opacity(0.5), in: Capsule())
                        }
                        Spacer()
                        if editingControls {
                            editToolbar
                        } else {
                            Button { showMenu = true } label: {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 32)
                                    .background(Color.black.opacity(0.5), in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { applyScreenMode() }
        .confirmationDialog(core.runningGame?.name ?? "Game", isPresented: $showMenu, titleVisibility: .visible) {
            ForEach(ScreenMode.allCases) { mode in
                Button("Screen: \(mode.title)\(mode == screenMode ? " ✓" : "")") { setScreenMode(mode) }
            }
            Button(showFPS ? "Hide FPS" : "Show FPS") { showFPS.toggle() }
            Button("Edit touch controls") { editingControls = true }
            Button("Stop game", role: .destructive) { confirmStop = true }
            Button("Resume", role: .cancel) {}
        }
        .alert("Stop the game?", isPresented: $confirmStop) {
            Button("Stop", role: .destructive) { core.stopGame() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unsaved progress will be lost.")
        }
    }

    @ViewBuilder
    private func screens(in size: CGSize) -> some View {
        let surfaces = RenderSurfaces.shared
        switch screenMode {
        case .tv, .gamepad:
            MetalSurface(view: surfaces.tv)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .tvWithGamePad:
            if size.width > size.height {
                // landscape: TV fills, GamePad as a picture-in-picture in the bottom center
                ZStack(alignment: .bottom) {
                    MetalSurface(view: surfaces.tv)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    MetalSurface(view: surfaces.pad)
                        .aspectRatio(854.0 / 480.0, contentMode: .fit)
                        .frame(width: size.width * 0.28)
                        .border(Color.white.opacity(0.3), width: 1)
                        .padding(.bottom, 8)
                }
            } else {
                // portrait: TV on top, GamePad below, like holding the real GamePad
                VStack(spacing: 4) {
                    MetalSurface(view: surfaces.tv).aspectRatio(16.0 / 9.0, contentMode: .fit)
                    MetalSurface(view: surfaces.pad).aspectRatio(854.0 / 480.0, contentMode: .fit)
                    Spacer(minLength: 0)
                }
                .padding(.top, 40)
            }
        }
    }

    private var editToolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "minus.magnifyingglass").foregroundColor(.white)
            Slider(value: $layout.scale, in: 0.6...1.6).frame(width: 110)
            Image(systemName: "circle.lefthalf.filled").foregroundColor(.white)
            Slider(value: $layout.opacity, in: 0.15...1.0).frame(width: 90)
            Button("Reset") { layout = TouchLayout() }
                .foregroundColor(.orange)
            Button("Done") {
                layout.save()
                editingControls = false
            }
            .font(.headline)
            .foregroundColor(.yellow)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.black.opacity(0.7), in: Capsule())
    }

    private func cycleScreenMode() {
        // the swap button toggles which screen is primary (like the Wii U's TV/GamePad swap)
        core.showGamePadOnTV.toggle()
    }

    private func setScreenMode(_ mode: ScreenMode) {
        screenModeRaw = mode.rawValue
        applyScreenMode()
    }

    private func applyScreenMode() {
        // the GamePad surface needs the renderer to know about it; it's registered before launch,
        // so switching into TV + GamePad takes effect on the next game launch
        core.showGamePadOnTV = (screenMode == .gamepad)
    }
}
