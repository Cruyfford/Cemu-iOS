import SwiftUI

/// Living menu background: slowly drifting colour fields, soft waves and rising bubbles.
/// Drawn cheaply (radial gradients instead of blur filters, ~24 fps) so menus stay smooth.
struct AnimatedBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("animatedBackground") private var animated = true
    @AppStorage("accent") private var accentRaw = AppAccent.aqua.rawValue
    @ObservedObject private var playState = PlayState.shared

    private var accent: Color { (AppAccent(rawValue: accentRaw) ?? .aqua).color }

    private struct Bubble {
        let x: Double, size: Double, speed: Double, phase: Double, wobble: Double, depth: Double
    }

    private static let bubbles: [Bubble] = {
        var g = SystemRandomNumberGenerator()
        return (0..<14).map { _ in
            Bubble(x: .random(in: 0...1, using: &g), size: .random(in: 8...30, using: &g),
                   speed: .random(in: 0.012...0.035, using: &g), phase: .random(in: 0...1, using: &g),
                   wobble: .random(in: 0.005...0.02, using: &g), depth: .random(in: 0.35...1, using: &g))
        }
    }()

    var body: some View {
        let isPaused = !animated || reduceMotion || playState.inGame || scenePhase != .active
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: isPaused)) { timeline in
            let t = isPaused ? 12.0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas(opaque: true) { ctx, size in
                draw(&ctx, size: size, t: t)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let dark = scheme == .dark
        let w = size.width, h = size.height
        let minSide = min(w, h)

        // base
        let top = dark ? Color(red: 0.05, green: 0.06, blue: 0.10) : Color(red: 0.96, green: 0.97, blue: 0.99)
        let bottom = dark ? Color(red: 0.02, green: 0.02, blue: 0.05) : Color(red: 0.88, green: 0.92, blue: 0.97)
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

        // drifting colour fields: radial gradients are naturally soft, no blur pass needed
        let fields: [(Color, Double, Double, Double)] = [
            (accent, 0.20, 0.18, 0.0),
            (Color(red: 0.55, green: 0.45, blue: 1.0), 0.85, 0.35, 2.1),
            (Color(red: 0.25, green: 0.85, blue: 0.75), 0.35, 0.85, 4.2),
        ]
        let fieldAlpha = dark ? 0.30 : 0.22
        for (color, fx, fy, ph) in fields {
            let cx: Double = w * (fx + 0.12 * sin(t * 0.07 + ph))
            let cy: Double = h * (fy + 0.10 * cos(t * 0.05 + ph * 1.3))
            let c = CGPoint(x: cx, y: cy)
            let r: Double = minSide * (0.75 + 0.08 * sin(t * 0.11 + ph))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(colors: [color.opacity(fieldAlpha), color.opacity(0)]),
                                           center: c, startRadius: 0, endRadius: r))
        }

        // soft waves
        for i in 0..<2 {
            var p = Path()
            let baseY = h * (0.66 + Double(i) * 0.1)
            let amp = 16.0 + Double(i) * 8
            let speed = 0.35 + Double(i) * 0.12
            p.move(to: CGPoint(x: 0, y: h))
            var x = 0.0
            while x <= w + 16 {
                let freq: Double = (1.0 + Double(i) * 0.3) * 2 * Double.pi
                let phase: Double = t * speed + Double(i)
                let y: Double = baseY + amp * sin(x / w * freq + phase)
                p.addLine(to: CGPoint(x: x, y: y))
                x += 16
            }
            p.addLine(to: CGPoint(x: w, y: h))
            p.closeSubpath()
            ctx.fill(p, with: .color(dark ? Color.white.opacity(0.03) : Color.white.opacity(0.32 - 0.1 * Double(i))))
        }

        // rising bubbles
        let bubbleAlpha = dark ? 0.2 : 0.45
        for b in Self.bubbles {
            let progress = (b.phase + t * b.speed).truncatingRemainder(dividingBy: 1)
            let y = h * (1.1 - progress * 1.25)
            let wob: Double = b.wobble * sin(t * 0.8 + b.phase * 10)
            let x: Double = w * (b.x + wob)
            let s = b.size * (0.6 + 0.4 * b.depth)
            let fadeIn: Double = min(progress / 0.15, 1)
            let fadeOut: Double = min((1 - progress) / 0.2, 1)
            let fade: Double = fadeIn * fadeOut
            let alpha = bubbleAlpha * b.depth * fade
            let r = CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
            ctx.fill(Path(ellipseIn: r), with: .color(accent.opacity(alpha * 0.25)))
            ctx.stroke(Path(ellipseIn: r), with: .color(Color.white.opacity(alpha)), lineWidth: 0.8)
            ctx.fill(Path(ellipseIn: CGRect(x: r.minX + s * 0.22, y: r.minY + s * 0.18, width: s * 0.22, height: s * 0.16)),
                     with: .color(Color.white.opacity(alpha)))
        }
    }
}

/// Tiny shared flag so menu decorations can pause while a game runs,
/// without observing the whole emulator core (which publishes the frame rate).
@MainActor
final class PlayState: ObservableObject {
    static let shared = PlayState()
    @Published var inGame = false
}
