import SwiftUI
import UIKit
import CoreImage

// MARK: - Accent colors

enum AppAccent: Int, CaseIterable, Identifiable {
    case aqua, violet, sunset, lime, rose, mono
    var id: Int { rawValue }

    var color: Color {
        switch self {
        case .aqua: return Color(red: 0.16, green: 0.78, blue: 0.92)
        case .violet: return Color(red: 0.55, green: 0.42, blue: 1.0)
        case .sunset: return Color(red: 1.0, green: 0.55, blue: 0.25)
        case .lime: return Color(red: 0.45, green: 0.88, blue: 0.38)
        case .rose: return Color(red: 1.0, green: 0.36, blue: 0.52)
        case .mono: return Color(white: 0.92)
        }
    }

    var name: String {
        switch self {
        case .aqua: return "Aqua"
        case .violet: return "Violet"
        case .sunset: return "Sunset"
        case .lime: return "Lime"
        case .rose: return "Rose"
        case .mono: return "Mono"
        }
    }
}

// MARK: - Liquid Glass with a material fallback for iOS 16–25

extension View {
    /// iOS 26 Liquid Glass; falls back to a translucent material on older systems.
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Self.makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill((tint ?? .clear).opacity(0.25)))
                .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 0.6))
        }
    }

    @available(iOS 26.0, *)
    private static func makeGlass(tint: Color?, interactive: Bool) -> Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }

    /// Prominent call-to-action button style (glass on iOS 26).
    @ViewBuilder
    func prominentButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func secondaryButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func minimizingTabBar() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

/// Groups glass shapes so they blend into each other on iOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Artwork

/// Loads a game's icon and its dominant color once, shared by every view.
@MainActor
final class ArtworkStore: ObservableObject {
    static let shared = ArtworkStore()

    struct Art {
        let image: UIImage
        let color: Color
    }

    @Published private(set) var art: [String: Art] = [:]
    private var loading = Set<String>()

    func art(for game: GameEntry) -> Art? {
        if let a = art[game.titleId] { return a }
        load(game)
        return nil
    }

    private func load(_ game: GameEntry) {
        guard !loading.contains(game.titleId) else { return }
        loading.insert(game.titleId)
        let core = EmulatorCore.shared
        Task.detached(priority: .utility) {
            guard let url = core.iconURL(for: game), let img = TGAImage.load(url) else { return }
            let color = Self.dominantColor(of: img)
            await MainActor.run {
                ArtworkStore.shared.enqueue(game.titleId, Art(image: img, color: color))
            }
        }
    }

    // icons arrive one by one; publish them in batches so the grid redraws a few times, not once per icon
    private var pending: [String: Art] = [:]
    private var flushScheduled = false

    fileprivate func enqueue(_ id: String, _ a: Art) {
        pending[id] = a
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.flushScheduled = false
            guard !self.pending.isEmpty else { return }
            self.art.merge(self.pending) { _, new in new }
            self.pending.removeAll()
        }
    }

    nonisolated static func dominantColor(of image: UIImage) -> Color {
        guard let cg = image.cgImage else { return .gray }
        let input = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage") else { return .gray }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: input.extent), forKey: kCIInputExtentKey)
        guard let out = filter.outputImage else { return .gray }
        var px = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()])
            .render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        // lift dark colors a bit so tinted backgrounds stay readable
        var r = Double(px[0]) / 255, g = Double(px[1]) / 255, b = Double(px[2]) / 255
        let maxC = max(r, g, b, 0.001)
        if maxC < 0.45 { let k = 0.45 / maxC; r *= k; g *= k; b *= k }
        return Color(red: min(r, 1), green: min(g, 1), blue: min(b, 1))
    }
}

struct GameArtwork: View {
    @ObservedObject private var store = ArtworkStore.shared
    let game: GameEntry
    var corner: CGFloat = 22

    var body: some View {
        let art = store.art(for: game)
        ZStack {
            if let art {
                Image(uiImage: art.image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(String(game.name.prefix(1)))
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
        )
    }
}

/// Blurred, color-washed backdrop built from a game's artwork.
struct ArtworkBackdrop: View {
    @ObservedObject private var store = ArtworkStore.shared
    let game: GameEntry
    var blur: CGFloat = 60

    var body: some View {
        let art = store.art(for: game)
        ZStack {
            (art?.color ?? Color(white: 0.2)).opacity(0.55)
            if let art {
                Image(uiImage: art.image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: blur)
                    .opacity(0.85)
                    .saturation(1.4)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
    }
}

// MARK: - Small pieces

struct Chip: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint ?? .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((tint ?? Color.secondary).opacity(0.14), in: Capsule())
    }
}

struct SettingsIcon: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(
                LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

extension TimeInterval {
    /// "3h 12m", "45m", "under a minute"
    var playTimeString: String {
        let mins = Int(self / 60)
        if mins < 1 { return self > 0 ? "<1m" : "Never" }
        let h = mins / 60, m = mins % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

extension Date {
    var relativeString: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}
