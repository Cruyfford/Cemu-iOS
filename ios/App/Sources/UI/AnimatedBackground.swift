import SwiftUI

/// Living menu background: slowly drifting colour fields, soft waves and rising bubbles.
struct AnimatedBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("animatedBackground") private var animated = true
    @AppStorage("accent") private var accentRaw = AppAccent.aqua.rawValue
    @ObservedObject private var core = EmulatorCore.shared
    var paused = false

    private var accent: Color { (AppAccent(rawValue: accentRaw) ?? .aqua).color }

    private struct Bubble {
        let x: Double, size: Double, speed: Double, phase: Double, wobble: Double, depth: Double
    }

    private static let bubbles: [Bubble] = {
        var g = SystemRandomNumberGenerator()
        return (0..<26).map { _ in
            Bubble(x: .random(in: 0...1, using: &g), size: .random(in: 6...34, using: &g),
                   speed: .random(in: 0.012...0.04, using: &g), phase: .random(in: 0...1, using: &g),
                   wobble: .random(in: 0.005...0.025, using: &g), depth: .random(in: 0.3...1, using: &g))
        }
    }()

    var body: some View {
        let isPaused = paused || !animated || reduceMotion || core.runningGame != nil
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isPaused)) { timeline in
            let t = isPaused ? 12.0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas(opaque: true, rendersAsynchronously: true) { ctx, size in
                draw(&ctx, size: size, t: t)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let dark = scheme == .dark
        let w = size.width, h = size.height
        let rect = CGRect(origin: .zero, size: size)

        // base
        let top = dark ? Color(red: 0.05, green: 0.06, blue: 0.10) : Color(red: 0.96, green: 0.97, blue: 0.99)
        let bottom = dark ? Color(red: 0.02, green: 0.02, blue: 0.05) : Color(red: 0.88, green: 0.92, blue: 0.97)
        ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

        // drifting colour fields
        let fields: [(Color, Double, Double, Double)] = [
            (accent, 0.25, 0.20, 0.0),
            (Color(red: 0.55, green: 0.45, blue: 1.0), 0.80, 0.35, 2.1),
            (Color(red: 0.25, green: 0.85, blue: 0.75), 0.40, 0.85, 4.2),
            (accent, 0.90, 0.80, 5.7),
        ]
        var blurred = ctx
        blurred.addFilter(.blur(radius: min(w, h) * 0.12))
        for (color, fx, fy, ph) in fields {
            let cx = w * (fx + 0.12 * sin(t * 0.07 + ph))
            let cy = h * (fy + 0.10 * cos(t * 0.05 + ph * 1.3))
            let r = min(w, h) * (0.42 + 0.06 * sin(t * 0.11 + ph))
            blurred.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                         with: .color(color.opacity(dark ? 0.32 : 0.22)))
        }

        // soft waves
        for i in 0..<3 {
            var p = Path()
            let baseY = h * (0.62 + Double(i) * 0.09)
            let amp = 18.0 + Double(i) * 8
            p.move(to: CGPoint(x: 0, y: h))
            var x = 0.0
            while x <= w + 8 {
                let y = baseY + amp * sin(x / w * .pi * 2 * (1.0 + Double(i) * 0.3) + t * (0.35 + Double(i) * 0.12) + Double(i))
                p.addLine(to: CGPoint(x: x, y: y))
                x += 8
            }
            p.addLine(to: CGPoint(x: w, y: h))
            p.closeSubpath()
            let c = dark ? Color.white.opacity(0.025 + 0.01 * Double(i)) : Color.white.opacity(0.35 - 0.08 * Double(i))
            ctx.fill(p, with: .color(c))
        }

        // rising bubbles
        for b in Self.bubbles {
            let progress = (b.phase + t * b.speed).truncatingRemainder(dividingBy: 1)
            let y = h * (1.1 - progress * 1.25)
            let x = w * (b.x + b.wobble * sin(t * 0.8 + b.phase * 10))
            let s = b.size * (0.6 + 0.4 * b.depth)
            let fadeIn = min(progress / 0.15, 1), fadeOut = min((1 - progress) / 0.2, 1)
            let alpha = (dark ? 0.18 : 0.45) * b.depth * fadeIn * fadeOut
            let r = CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
            ctx.fill(Path(ellipseIn: r), with: .radialGradient(
                Gradient(colors: [Color.white.opacity(alpha * 0.2), accent.opacity(alpha * 0.5)]),
                center: CGPoint(x: r.midX - s * 0.15, y: r.midY - s * 0.15), startRadius: 0, endRadius: s * 0.7))
            ctx.stroke(Path(ellipseIn: r), with: .color(Color.white.opacity(alpha)), lineWidth: 0.8)
            // highlight
            let hl = CGRect(x: r.minX + s * 0.22, y: r.minY + s * 0.18, width: s * 0.22, height: s * 0.16)
            ctx.fill(Path(ellipseIn: hl), with: .color(Color.white.opacity(alpha * 1.4)))
        }
    }
}
