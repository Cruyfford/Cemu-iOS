import SwiftUI
import UIKit

struct GameDetailView: View {
    @ObservedObject private var stats = GameStats.shared
    @ObservedObject private var jit = JITManager.shared
    @Environment(\.dismiss) private var dismiss
    let game: GameEntry
    var onPlay: () -> Void
    var onDelete: () -> Void
    @State private var appeared = false
    @State private var copied = false

    var body: some View {
        let e = stats.entry(game)
        ScrollView {
            VStack(spacing: 22) {
                hero
                // play
                VStack(spacing: 10) {
                    SoundButton(effect: .launch, action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .prominentButton()
                    .controlSize(.large)
                    if !jit.isEnabled {
                        Label("JIT is off — the game will run on the slow interpreter", systemImage: "bolt.slash.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 20)

                // stats
                HStack(spacing: 12) {
                    statTile("Play time", e.playSeconds.playTimeString, "hourglass")
                    statTile("Last played", e.lastPlayed?.relativeString ?? "Never", "clock")
                    statTile("Sessions", "\(e.launches)", "play.circle")
                }
                .padding(.horizontal, 20)

                // info
                VStack(spacing: 0) {
                    infoRow("Title ID", game.titleId, mono: true, copy: true)
                    Divider().padding(.leading, 16)
                    infoRow("Version", "v\(game.version)")
                    Divider().padding(.leading, 16)
                    infoRow("Region", game.region)
                    Divider().padding(.leading, 16)
                    infoRow("Format", game.format)
                    Divider().padding(.leading, 16)
                    infoRow("Update", game.hasUpdate ? "Installed" : "None")
                    Divider().padding(.leading, 16)
                    infoRow("DLC", game.hasDLC ? "Installed" : "None")
                    Divider().padding(.leading, 16)
                    infoRow("File", (game.path as NSString).lastPathComponent)
                }
                .glassSurface(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 20)

                SoundButton(effect: .back, role: .destructive, action: onDelete) {
                    Label("Delete Game", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .secondaryButton()
                .tint(.red)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(AnimatedBackground())
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { stats.toggleFavorite(game) }
                    SoundManager.shared.play(.toggle)
                    Haptics.tap()
                } label: {
                    Image(systemName: stats.isFavorite(game) ? "heart.fill" : "heart")
                        .foregroundStyle(stats.isFavorite(game) ? Color.pink : Color.primary)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.05)) { appeared = true }
        }
        .onDisappear { SoundManager.shared.play(.back) }
    }

    private var hero: some View {
        ZStack(alignment: .bottom) {
            ArtworkBackdrop(game: game, blur: 50)
                .frame(height: 380)
                .mask(LinearGradient(colors: [.black, .black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 14) {
                GameArtwork(game: game, corner: 34)
                    .frame(width: 168)
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 14)
                    .scaleEffect(appeared ? 1 : 0.85)
                    .rotation3DEffect(.degrees(appeared ? 0 : 12), axis: (x: 1, y: 0, z: 0))
                Text(game.name)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                HStack(spacing: 6) {
                    Chip(text: game.region, systemImage: "globe")
                    Chip(text: game.format, systemImage: "opticaldisc")
                    if game.hasUpdate { Chip(text: "Update", systemImage: "arrow.down.circle", tint: .green) }
                    if game.hasDLC { Chip(text: "DLC", systemImage: "puzzlepiece.extension", tint: .purple) }
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .padding(.bottom, 6)
        }
    }

    private func statTile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func infoRow(_ title: String, _ value: String, mono: Bool = false, copy: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(mono ? .system(.subheadline, design: .monospaced) : .subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
            if copy {
                Button {
                    UIPasteboard.general.string = value
                    SoundManager.shared.play(.tap)
                    Haptics.success()
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { copied = false } }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}
