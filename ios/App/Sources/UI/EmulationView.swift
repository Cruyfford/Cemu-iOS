import SwiftUI
import UIKit

enum ScreenMode: Int, CaseIterable, Identifiable {
    case tv = 0, gamepad, tvWithGamePad
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .tv: return "TV"
        case .gamepad: return "GamePad"
        case .tvWithGamePad: return "Both"
        }
    }
    var icon: String {
        switch self {
        case .tv: return "tv"
        case .gamepad: return "ipad.landscape"
        case .tvWithGamePad: return "rectangle.on.rectangle"
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
    @State private var booting = true

    private var screenMode: ScreenMode { ScreenMode(rawValue: screenModeRaw) ?? .tv }
    private var showTouch: Bool { !(hideTouchWithController && input.controllerConnected) || editingControls }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                screens(in: geo.size)

                if showTouch && !showMenu {
                    TouchControlsView(layout: $layout, editing: editingControls, onToggleScreen: { core.showGamePadOnTV.toggle() })
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                topBar

                if booting, let game = core.runningGame {
                    BootSplash(game: game)
                        .transition(.opacity.combined(with: .scale(scale: 1.05)))
                }

                if showMenu {
                    PauseMenu(
                        screenMode: Binding(get: { screenMode }, set: { setScreenMode($0) }),
                        showFPS: $showFPS,
                        hideTouchWithController: $hideTouchWithController,
                        onResume: { closeMenu() },
                        onEditControls: { closeMenu(); editingControls = true },
                        onStop: { confirmStop = true }
                    )
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { applyScreenMode() }
        .onChange(of: core.fps) { fps in
            if booting && fps > 1 { withAnimation(.easeOut(duration: 0.6)) { booting = false } }
        }
        .task {
            // never keep the splash forever, some titles take a while before reporting a frame rate
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            withAnimation(.easeOut(duration: 0.6)) { booting = false }
        }
        .alert("Quit the game?", isPresented: $confirmStop) {
            Button("Quit", role: .destructive) {
                SoundManager.shared.play(.back)
                core.stopGame()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unsaved progress will be lost.")
        }
    }

    private var topBar: some View {
        VStack {
            HStack(spacing: 8) {
                if showFPS && !editingControls && !booting {
                    HStack(spacing: 4) {
                        Circle().fill(fpsColor).frame(width: 6, height: 6)
                        Text(String(format: "%.0f", core.fps))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("FPS").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.black.opacity(0.45), in: Capsule())
                }
                Spacer()
                if editingControls {
                    editToolbar
                } else if !showMenu {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showMenu = true }
                        Haptics.tap()
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 34)
                            .background(Color.black.opacity(0.45), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 14)
            Spacer()
        }
        .padding(.top, 6)
    }

    private var fpsColor: Color {
        core.fps >= 28 ? .green : (core.fps >= 18 ? .yellow : .red)
    }

    private func closeMenu() {
        SoundManager.shared.play(.back)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { showMenu = false }
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
                ZStack(alignment: .bottom) {
                    MetalSurface(view: surfaces.tv)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    MetalSurface(view: surfaces.pad)
                        .aspectRatio(854.0 / 480.0, contentMode: .fit)
                        .frame(width: size.width * 0.28)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .padding(.bottom, 8)
                }
            } else {
                VStack(spacing: 6) {
                    MetalSurface(view: surfaces.tv).aspectRatio(16.0 / 9.0, contentMode: .fit)
                    MetalSurface(view: surfaces.pad).aspectRatio(854.0 / 480.0, contentMode: .fit)
                    Spacer(minLength: 0)
                }
                .padding(.top, 44)
            }
        }
    }

    private var editToolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(.white)
            Slider(value: $layout.scale, in: 0.6...1.6).frame(width: 100)
            Image(systemName: "circle.lefthalf.filled").foregroundStyle(.white)
            Slider(value: $layout.opacity, in: 0.15...1.0).frame(width: 80)
            Button("Reset") { withAnimation { layout = TouchLayout() } }
                .foregroundStyle(.orange)
            Button("Done") {
                layout.save()
                SoundManager.shared.play(.select)
                editingControls = false
            }
            .font(.headline)
            .foregroundStyle(.yellow)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.black.opacity(0.7), in: Capsule())
    }

    private func setScreenMode(_ mode: ScreenMode) {
        screenModeRaw = mode.rawValue
        applyScreenMode()
    }

    private func applyScreenMode() {
        // TV + GamePad needs the second surface registered before launch, so "Both" applies to the next launch
        core.showGamePadOnTV = (screenMode == .gamepad)
    }
}

// MARK: - Boot splash

struct BootSplash: View {
    let game: GameEntry
    @State private var pulse = false

    var body: some View {
        ZStack {
            ArtworkBackdrop(game: game, blur: 70).ignoresSafeArea()
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 22) {
                GameArtwork(game: game, corner: 36)
                    .frame(width: 170)
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
                    .scaleEffect(pulse ? 1.03 : 0.97)
                Text(game.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Starting… shaders are compiled on first run")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glassSurface(Capsule())
            }
            .padding(30)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// MARK: - Pause menu

struct PauseMenu: View {
    @EnvironmentObject var core: EmulatorCore
    @Binding var screenMode: ScreenMode
    @Binding var showFPS: Bool
    @Binding var hideTouchWithController: Bool
    var onResume: () -> Void
    var onEditControls: () -> Void
    var onStop: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onResume() }

            VStack(spacing: 18) {
                if let game = core.runningGame {
                    HStack(spacing: 14) {
                        GameArtwork(game: game, corner: 14).frame(width: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(game.name).font(.headline).lineLimit(1)
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                Text("\(String(format: "%.0f", core.fps)) FPS · Session \(GameStats.shared.currentSessionLength.playTimeString)")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        Spacer()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("SCREEN").font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(ScreenMode.allCases) { mode in
                            Button {
                                SoundManager.shared.play(.toggle)
                                Haptics.tap()
                                withAnimation(.spring(response: 0.3)) { screenMode = mode }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: mode.icon).font(.system(size: 18, weight: .semibold))
                                    Text(mode.title).font(.caption.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(screenMode == mode ? Color.white : Color.primary)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(screenMode == mode ? Color.accentColor : Color.primary.opacity(0.06))
                                )
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    if screenMode == .tvWithGamePad {
                        Text("Both screens take effect the next time you start a game.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 0) {
                    Toggle(isOn: $showFPS) { Label("Show FPS", systemImage: "speedometer") }
                        .padding(.vertical, 8)
                    Divider()
                    Toggle(isOn: $hideTouchWithController) { Label("Hide touch with controller", systemImage: "gamecontroller") }
                        .padding(.vertical, 8)
                }
                .font(.subheadline)
                .onChange(of: showFPS) { _ in SoundManager.shared.play(.toggle) }
                .onChange(of: hideTouchWithController) { _ in SoundManager.shared.play(.toggle) }

                GlassGroup(spacing: 10) {
                    VStack(spacing: 10) {
                        Button(action: onResume) {
                            Label("Resume", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .prominentButton()
                        HStack(spacing: 10) {
                            Button(action: { SoundManager.shared.play(.select); onEditControls() }) {
                                Label("Controls", systemImage: "hand.tap")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .secondaryButton()
                            Button(role: .destructive, action: { SoundManager.shared.play(.error); onStop() }) {
                                Label("Quit", systemImage: "xmark")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .secondaryButton()
                            .tint(.red)
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 420)
            .glassSurface(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .padding(20)
            .scaleEffect(appeared ? 1 : 0.92)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            SoundManager.shared.play(.open)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { appeared = true }
        }
    }
}
