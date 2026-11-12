import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var core: EmulatorCore
    @ObservedObject var jit = JITManager.shared
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var search = ""
    @State private var pendingDelete: GameEntry?
    var onLaunch: (GameEntry) -> Void

    private let columns = [GridItem(.adaptive(minimum: 112, maximum: 150), spacing: 16)]

    var filtered: [GameEntry] {
        search.isEmpty ? core.games : core.games.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusBanner
                    if core.games.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(filtered) { game in
                                GameTile(game: game)
                                    .onTapGesture { onLaunch(game) }
                                    .contextMenu {
                                        Button { onLaunch(game) } label: { Label("Play", systemImage: "play.fill") }
                                        Button {
                                            UIPasteboard.general.string = game.titleId
                                        } label: { Label("Copy title ID", systemImage: "doc.on.doc") }
                                        Button(role: .destructive) { pendingDelete = game } label: { Label("Delete", systemImage: "trash") }
                                    }
                            }
                        }
                    }
                }
                .padding()
            }
            .refreshable { core.refreshGames() }
            .searchable(text: $search, prompt: "Search games")
            .navigationTitle("Cemu")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if core.isScanning { ProgressView() }
                    Button { showImporter = true } label: { Image(systemName: "plus") }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.gameTypes, allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { core.importGames(urls) }
            }
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(core) }
            .alert("Delete \(pendingDelete?.name ?? "")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                Button("Delete", role: .destructive) { if let g = pendingDelete { core.deleteGame(g) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The game files are removed from the games folder.")
            }
        }
    }

    static var gameTypes: [UTType] {
        var types: [UTType] = [.folder, .data]
        for ext in ["wua", "wux", "wud", "rpx", "elf", "wuhb"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }

    @ViewBuilder
    private var statusBanner: some View {
        if !core.hasKeys || !jit.isEnabled {
            VStack(alignment: .leading, spacing: 8) {
                if !core.hasKeys {
                    Label("keys.txt is missing — encrypted games (WUD/WUX/NUS) need it.", systemImage: "key.fill")
                        .font(.footnote)
                }
                if !jit.isEnabled {
                    HStack {
                        Label("JIT: \(jit.statusText)", systemImage: "bolt.slash.fill")
                            .font(.footnote)
                        Spacer()
                        if jit.state != .waitingForDebugger {
                            Button("Enable JIT") { jit.requestJIT() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        } else {
                            ProgressView()
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No games yet").font(.title3.bold())
            Text("Tap + to import .wua, .wux, .wud or .rpx files, or copy game folders into Files › On My iPhone › Cemu › games. Updates and DLC go in the same folder.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { showImporter = true } label: { Label("Import games", systemImage: "square.and.arrow.down") }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

struct GameTile: View {
    @EnvironmentObject var core: EmulatorCore
    let game: GameEntry
    @State private var icon: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground))
                if let icon {
                    Image(uiImage: icon).resizable().interpolation(.high).scaledToFit()
                } else {
                    Image(systemName: "opticaldisc").font(.system(size: 34)).foregroundStyle(.secondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

            Text(game.name)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
            HStack(spacing: 4) {
                Text(game.region)
                Text("·")
                Text(game.format)
                if game.hasUpdate { Text("· v\(game.version)") }
                if game.hasDLC { Image(systemName: "puzzlepiece.extension.fill") }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .task(id: game.id) {
            let c = core
            let g = game
            icon = await Task.detached { c.iconURL(for: g).flatMap { TGAImage.load($0) } }.value
        }
    }
}
