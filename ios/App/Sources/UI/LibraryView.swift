import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent = "Recently Played", name = "Name", playTime = "Play Time", region = "Region"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .recent: return "clock"
        case .name: return "textformat"
        case .playTime: return "hourglass"
        case .region: return "globe"
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var core: EmulatorCore
    @ObservedObject private var jit = JITManager.shared
    @ObservedObject private var stats = GameStats.shared
    @AppStorage("librarySort") private var sortRaw = LibrarySort.recent.rawValue
    @AppStorage("libraryList") private var listMode = false
    @AppStorage("tileSize") private var tileSize = 1.0
    @State private var showImporter = false
    @State private var showKeysImporter = false
    @State private var search = ""
    @State private var pendingDelete: GameEntry?
    @State private var path: [GameEntry] = []
    @Namespace private var zoom
    var onLaunch: (GameEntry) -> Void

    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .recent }

    private var sorted: [GameEntry] {
        let base = search.isEmpty ? core.games : core.games.filter { $0.name.localizedCaseInsensitiveContains(search) }
        switch sort {
        case .name: return base
        case .region: return base.sorted { ($0.region, $0.name) < ($1.region, $1.name) }
        case .playTime: return base.sorted { stats.entry($0).playSeconds > stats.entry($1).playSeconds }
        case .recent:
            return base.sorted {
                (stats.entry($0).lastPlayed ?? .distantPast) > (stats.entry($1).lastPlayed ?? .distantPast)
            }
        }
    }

    private var lastPlayed: GameEntry? {
        core.games
            .filter { stats.entry($0).lastPlayed != nil }
            .max { (stats.entry($0).lastPlayed ?? .distantPast) < (stats.entry($1).lastPlayed ?? .distantPast) }
    }

    private var favorites: [GameEntry] { core.games.filter { stats.isFavorite($0) } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    HomeHeader()
                    statusPills
                    if core.games.isEmpty {
                        emptyState
                    } else {
                        if search.isEmpty, let hero = lastPlayed {
                            ContinueCard(game: hero, onPlay: { onLaunch(hero) }, onOpen: { open(hero) })
                                .zoomSource(hero.id, zoom)
                        }
                        if search.isEmpty && !favorites.isEmpty {
                            section("Favorites", systemImage: "heart.fill") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 14) {
                                        ForEach(favorites) { g in
                                            Button { open(g) } label: { GameCard(game: g, width: 120) }
                                                .buttonStyle(PressableStyle())
                                                .zoomSource(g.id, zoom)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 4)
                                }
                                .padding(.horizontal, -20)
                            }
                        }
                        section(search.isEmpty ? "All Games" : "Results", systemImage: "square.grid.2x2.fill", trailing: "\(sorted.count)") {
                            if listMode { listContent } else { gridContent }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: sortRaw)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: listMode)
            }
            .scrollContentBackground(.hidden)
            .background(AnimatedBackground())
            .refreshable { core.refreshGames() }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search your library")
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .navigationDestination(for: GameEntry.self) { game in
                GameDetailView(game: game, onPlay: { onLaunch(game) }, onDelete: { pendingDelete = game })
                    .zoomDestination(game.id, zoom)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.gameTypes, allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    SoundManager.shared.play(.open)
                    core.importGames(urls)
                }
            }
            .alert("Delete \(pendingDelete?.name ?? "")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                Button("Delete", role: .destructive) {
                    if let g = pendingDelete {
                        path.removeAll { $0 == g }
                        core.deleteGame(g)
                        SoundManager.shared.play(.back)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The game files are removed from the games folder.")
            }
        }
        .background(
            Color.clear.fileImporter(isPresented: $showKeysImporter, allowedContentTypes: [.plainText, .text, .data]) { result in
                if case .success(let url) = result { core.importKeys(from: url); SoundManager.shared.play(.select) }
            }
        )
    }

    private func open(_ game: GameEntry) {
        SoundManager.shared.play(.open)
        Haptics.tap()
        path.append(game)
    }

    // MARK: toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if core.isScanning {
                ProgressView()
            }
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Menu {
                Picker("Sort by", selection: $sortRaw) {
                    ForEach(LibrarySort.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0.rawValue) }
                }
                Divider()
                Picker("Layout", selection: $listMode) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(false)
                    Label("List", systemImage: "list.bullet").tag(true)
                }
                if !listMode {
                    Picker("Tile size", selection: $tileSize) {
                        Text("Small").tag(0.8)
                        Text("Medium").tag(1.0)
                        Text("Large").tag(1.3)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .onChange(of: sortRaw) { _ in SoundManager.shared.play(.toggle) }
            .onChange(of: listMode) { _ in SoundManager.shared.play(.toggle) }

            Menu {
                Button { showImporter = true } label: { Label("Import games", systemImage: "square.and.arrow.down") }
                Button { showKeysImporter = true } label: { Label("Import keys.txt", systemImage: "key") }
                Button { core.refreshGames() } label: { Label("Rescan library", systemImage: "arrow.clockwise") }
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    // MARK: sections

    private func section<C: View>(_ title: String, systemImage: String, trailing: String? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.subheadline.weight(.bold)).foregroundStyle(.tint)
                Text(title).font(.title3.weight(.bold))
                Spacer()
                if let trailing { Text(trailing).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) }
            }
            content()
        }
    }

    private var gridContent: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104 * tileSize, maximum: 170 * tileSize), spacing: 16)], spacing: 20) {
            ForEach(sorted) { game in
                Button { open(game) } label: { GameCard(game: game) }
                    .buttonStyle(PressableStyle())
                    .zoomSource(game.id, zoom)
                    .contextMenu { contextMenu(game) } preview: { GamePreview(game: game) }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
    }

    private var listContent: some View {
        VStack(spacing: 10) {
            ForEach(sorted) { game in
                Button { open(game) } label: { GameRow(game: game, onPlay: { onLaunch(game) }) }
                    .buttonStyle(PressableStyle())
                    .zoomSource(game.id, zoom)
                    .contextMenu { contextMenu(game) }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func contextMenu(_ game: GameEntry) -> some View {
        Button { onLaunch(game) } label: { Label("Play", systemImage: "play.fill") }
        Button { stats.toggleFavorite(game); SoundManager.shared.play(.toggle) } label: {
            if stats.isFavorite(game) {
                Label("Remove from Favorites", systemImage: "heart.slash")
            } else {
                Label("Add to Favorites", systemImage: "heart")
            }
        }
        Button { UIPasteboard.general.string = game.titleId } label: { Label("Copy Title ID", systemImage: "doc.on.doc") }
        Divider()
        Button(role: .destructive) { pendingDelete = game } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: status

    @ViewBuilder
    private var statusPills: some View {
        if !core.hasKeys || !jit.isEnabled {
            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    if !jit.isEnabled {
                        SoundButton(effect: .select, action: { jit.requestJIT() }) {
                            HStack(spacing: 8) {
                                if jit.state == .waitingForDebugger {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Enable JIT").font(.subheadline.weight(.semibold))
                                    Text(jit.state == .waitingForDebugger ? "Waiting for StikDebug…" : "Needed for full speed")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), tint: .yellow.opacity(0.18), interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                    if !core.hasKeys {
                        SoundButton(effect: .select, action: { showKeysImporter = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "key.fill").foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Add keys.txt").font(.subheadline.weight(.semibold))
                                    Text("For WUD / WUX / NUS").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), tint: .orange.opacity(0.18), interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.18)).frame(width: 120, height: 120)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolEffectBounce()
            }
            Text("Your library is empty").font(.title2.weight(.bold))
            Text("Import .wua, .wux, .wud or .rpx files, or copy game folders to\nFiles › On My iPhone › Cemu › games.\nUpdates and DLC go in the same folder.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SoundButton(effect: .open, action: { showImporter = true }) {
                Label("Import Games", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .padding(.horizontal, 10).padding(.vertical, 4)
            }
            .prominentButton()
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .glassSurface(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(.top, 20)
    }

    static var gameTypes: [UTType] {
        var types: [UTType] = [.folder, .data]
        for ext in ["wua", "wux", "wud", "rpx", "elf", "wuhb"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }
}

// MARK: - Header

struct HomeHeader: View {
    @ObservedObject private var input = InputHub.shared
    @ObservedObject private var jit = JITManager.shared

    var body: some View {
        TimelineView(.everyMinute) { tl in
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting(tl.date).uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)
                    Text(tl.date, format: .dateTime.hour().minute())
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(tl.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    statusDot(icon: "gamecontroller.fill", on: input.controllerConnected)
                    statusDot(icon: "bolt.fill", on: jit.isEnabled)
                }
            }
        }
        .padding(.top, 8)
    }

    private func statusDot(icon: String, on: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(width: 38, height: 38)
            .glassSurface(Circle())
    }

    private func greeting(_ d: Date) -> String {
        switch Calendar.current.component(.hour, from: d) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Late night session"
        }
    }
}

// MARK: - Cards

struct ContinueCard: View {
    @ObservedObject private var stats = GameStats.shared
    let game: GameEntry
    var onPlay: () -> Void
    var onOpen: () -> Void

    var body: some View {
        let e = stats.entry(game)
        let subtitle = [e.lastPlayed?.relativeString, e.playSeconds > 0 ? e.playSeconds.playTimeString : nil]
            .compactMap { $0 }.joined(separator: " · ")
        ZStack(alignment: .bottomLeading) {
            ArtworkBackdrop(game: game, blur: 40)
                .onTapGesture { onOpen() }
            HStack(alignment: .bottom, spacing: 16) {
                GameArtwork(game: game, corner: 20)
                    .frame(width: 104)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                    .onTapGesture { onOpen() }
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONTINUE PLAYING")
                        .font(.caption2.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(game.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                    SoundButton(effect: .launch, action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 6)
                    }
                    .prominentButton()
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
    }
}

struct GameCard: View {
    @ObservedObject private var stats = GameStats.shared
    let game: GameEntry
    var width: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GameArtwork(game: game, corner: 24)
                .overlay(alignment: .topTrailing) {
                    if stats.isFavorite(game) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.pink)
                            .padding(6)
                            .glassSurface(Circle())
                            .padding(6)
                    }
                }
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
            Text(game.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            HStack(spacing: 4) {
                Text(game.region)
                if game.hasUpdate { Text("· v\(game.version)") }
                if game.hasDLC { Image(systemName: "puzzlepiece.extension.fill") }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .frame(width: width)
    }
}

struct GameRow: View {
    @ObservedObject private var stats = GameStats.shared
    let game: GameEntry
    var onPlay: () -> Void

    var body: some View {
        let e = stats.entry(game)
        HStack(spacing: 14) {
            GameArtwork(game: game, corner: 14).frame(width: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text(game.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                HStack(spacing: 6) {
                    Chip(text: game.region)
                    Chip(text: game.format)
                    if e.playSeconds > 0 { Chip(text: e.playSeconds.playTimeString, systemImage: "hourglass") }
                }
            }
            Spacer()
            SoundButton(effect: .launch, action: onPlay) {
                Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .secondaryButton()
        }
        .padding(10)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct GamePreview: View {
    let game: GameEntry
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkBackdrop(game: game, blur: 30)
            VStack(alignment: .leading, spacing: 8) {
                GameArtwork(game: game).frame(width: 120)
                Text(game.name).font(.headline).foregroundStyle(.white)
            }
            .padding()
        }
        .frame(width: 300, height: 240)
    }
}

// MARK: - transitions (iOS 18 zoom, no-op before)

extension View {
    @ViewBuilder
    func zoomSource(_ id: String, _ ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: ns)
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomDestination(_ id: String, _ ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: id, in: ns))
        } else {
            self
        }
    }

    @ViewBuilder
    func symbolEffectBounce() -> some View {
        if #available(iOS 18.0, *) {
            self.symbolEffect(.bounce, options: .repeat(.periodic(delay: 2.5)))
        } else {
            self
        }
    }
}
