import SwiftUI
import UIKit

/// Every movable piece of the on-screen GamePad.
enum TouchControl: String, CaseIterable, Codable {
    case dpad, face, leftStick, rightStick, l, r, zl, zr, plus, minus, home, l3, r3, screen

    /// default centers in a landscape layout, normalized 0...1
    var defaultPosition: CGPoint {
        switch self {
        case .leftStick: return CGPoint(x: 0.13, y: 0.42)
        case .dpad: return CGPoint(x: 0.22, y: 0.76)
        case .face: return CGPoint(x: 0.87, y: 0.42)
        case .rightStick: return CGPoint(x: 0.78, y: 0.76)
        case .l: return CGPoint(x: 0.08, y: 0.11)
        case .zl: return CGPoint(x: 0.19, y: 0.11)
        case .r: return CGPoint(x: 0.92, y: 0.11)
        case .zr: return CGPoint(x: 0.81, y: 0.11)
        case .minus: return CGPoint(x: 0.42, y: 0.92)
        case .plus: return CGPoint(x: 0.58, y: 0.92)
        case .home: return CGPoint(x: 0.5, y: 0.92)
        case .l3: return CGPoint(x: 0.04, y: 0.66)
        case .r3: return CGPoint(x: 0.96, y: 0.66)
        case .screen: return CGPoint(x: 0.5, y: 0.08)
        }
    }

    var title: String {
        switch self {
        case .dpad: return "D-Pad"
        case .face: return "A B X Y"
        case .leftStick: return "Left stick"
        case .rightStick: return "Right stick"
        case .l: return "L"
        case .r: return "R"
        case .zl: return "ZL"
        case .zr: return "ZR"
        case .plus: return "+"
        case .minus: return "−"
        case .home: return "Home"
        case .l3: return "L3"
        case .r3: return "R3"
        case .screen: return "TV / GamePad"
        }
    }
}

struct TouchLayout: Codable, Equatable {
    var positions: [String: CGPoint] = [:]
    var hidden: Set<String> = []
    var scale: Double = 1.0
    var opacity: Double = 0.55

    func position(_ c: TouchControl) -> CGPoint { positions[c.rawValue] ?? c.defaultPosition }
    func isHidden(_ c: TouchControl) -> Bool { hidden.contains(c.rawValue) }

    static func load() -> TouchLayout {
        guard let data = UserDefaults.standard.data(forKey: "touchLayout"),
              let l = try? JSONDecoder().decode(TouchLayout.self, from: data) else { return TouchLayout() }
        return l
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "touchLayout") }
    }
}

struct TouchControlsView: View {
    @Binding var layout: TouchLayout
    var editing: Bool
    var onToggleScreen: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(TouchControl.allCases, id: \.self) { control in
                    if !layout.isHidden(control) || editing {
                        controlView(control)
                            .scaleEffect(layout.scale)
                            .opacity(layout.isHidden(control) ? 0.2 : layout.opacity)
                            .overlay(editing ? RoundedRectangle(cornerRadius: 8).stroke(Color.yellow.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4])) : nil)
                            .position(x: layout.position(control).x * geo.size.width,
                                      y: layout.position(control).y * geo.size.height)
                            .gesture(moveGesture(control, size: geo.size), including: editing ? .all : .subviews)
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    if layout.hidden.contains(control.rawValue) { layout.hidden.remove(control.rawValue) }
                                    else { layout.hidden.insert(control.rawValue) }
                                },
                                including: editing ? .all : .subviews)
                    }
                }
            }
        }
        .onDisappear { InputHub.shared.releaseAllTouch() }
    }

    private func moveGesture(_ control: TouchControl, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let x = min(max(v.location.x / size.width, 0.03), 0.97)
                let y = min(max(v.location.y / size.height, 0.03), 0.97)
                layout.positions[control.rawValue] = CGPoint(x: x, y: y)
            }
    }

    @ViewBuilder
    private func controlView(_ c: TouchControl) -> some View {
        switch c {
        case .dpad: DPadView(enabled: !editing)
        case .face: FaceButtonsView(enabled: !editing)
        case .leftStick: StickView(right: false, enabled: !editing)
        case .rightStick: StickView(right: true, enabled: !editing)
        case .l: PadButton(label: "L", button: CemuButton_L, shape: .pill, enabled: !editing)
        case .r: PadButton(label: "R", button: CemuButton_R, shape: .pill, enabled: !editing)
        case .zl: PadButton(label: "ZL", button: CemuButton_ZL, shape: .pill, enabled: !editing)
        case .zr: PadButton(label: "ZR", button: CemuButton_ZR, shape: .pill, enabled: !editing)
        case .plus: PadButton(label: "+", button: CemuButton_Plus, shape: .small, enabled: !editing)
        case .minus: PadButton(label: "−", button: CemuButton_Minus, shape: .small, enabled: !editing)
        case .home: PadButton(label: "⌂", button: CemuButton_Home, shape: .small, enabled: !editing)
        case .l3: PadButton(label: "L3", button: CemuButton_StickL, shape: .small, enabled: !editing)
        case .r3: PadButton(label: "R3", button: CemuButton_StickR, shape: .small, enabled: !editing)
        case .screen:
            Button(action: { if !editing { onToggleScreen() } }) {
                Image(systemName: "rectangle.2.swap")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 32)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
            }
            .disabled(editing)
        }
    }
}

// MARK: - pieces

struct PadButton: View {
    enum Shape { case round, pill, small }
    let label: String
    let button: CemuButton
    var shape: Shape = .round
    var enabled = true
    @State private var pressed = false

    var body: some View {
        let size: CGSize = {
            switch shape {
            case .round: return CGSize(width: 54, height: 54)
            case .pill: return CGSize(width: 64, height: 34)
            case .small: return CGSize(width: 38, height: 38)
            }
        }()
        Text(label)
            .font(.system(size: shape == .small ? 15 : 18, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: size.width, height: size.height)
            .background(
                Group {
                    if shape == .pill { Capsule().fill(pressed ? Color.white.opacity(0.55) : Color.black.opacity(0.45)) }
                    else { Circle().fill(pressed ? Color.white.opacity(0.55) : Color.black.opacity(0.45)) }
                }
            )
            .overlay(
                Group {
                    if shape == .pill { Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1.5) }
                    else { Circle().stroke(Color.white.opacity(0.7), lineWidth: 1.5) }
                }
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard enabled, !pressed else { return }
                        pressed = true
                        InputHub.shared.setTouchButton(button, pressed: true)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .onEnded { _ in
                        guard pressed else { return }
                        pressed = false
                        InputHub.shared.setTouchButton(button, pressed: false)
                    },
                including: enabled ? .all : .subviews
            )
    }
}

struct FaceButtonsView: View {
    var enabled = true
    var body: some View {
        let d: CGFloat = 50
        ZStack {
            PadButton(label: "X", button: CemuButton_X, enabled: enabled).offset(y: -d)
            PadButton(label: "B", button: CemuButton_B, enabled: enabled).offset(y: d)
            PadButton(label: "Y", button: CemuButton_Y, enabled: enabled).offset(x: -d)
            PadButton(label: "A", button: CemuButton_A, enabled: enabled).offset(x: d)
        }
        .frame(width: 160, height: 160)
    }
}

struct DPadView: View {
    var enabled = true
    @State private var active = Set<UInt32>()

    var body: some View {
        let size: CGFloat = 140
        ZStack {
            Image(systemName: "dpad.fill")
                .resizable()
                .foregroundColor(.black.opacity(0.45))
            Image(systemName: "dpad")
                .resizable()
                .foregroundColor(.white.opacity(0.75))
            directionHighlight(size: size)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard enabled else { return }
                    update(dx: v.location.x - size / 2, dy: v.location.y - size / 2, size: size)
                }
                .onEnded { _ in set([]) },
            including: enabled ? .all : .subviews
        )
    }

    private func directionHighlight(size: CGFloat) -> some View {
        ZStack {
            if active.contains(CemuButton_Up.rawValue) { Circle().fill(Color.white.opacity(0.5)).frame(width: 30).offset(y: -size / 3) }
            if active.contains(CemuButton_Down.rawValue) { Circle().fill(Color.white.opacity(0.5)).frame(width: 30).offset(y: size / 3) }
            if active.contains(CemuButton_Left.rawValue) { Circle().fill(Color.white.opacity(0.5)).frame(width: 30).offset(x: -size / 3) }
            if active.contains(CemuButton_Right.rawValue) { Circle().fill(Color.white.opacity(0.5)).frame(width: 30).offset(x: size / 3) }
        }
    }

    private func update(dx: CGFloat, dy: CGFloat, size: CGFloat) {
        let dead = size * 0.12
        var s = Set<UInt32>()
        if hypot(dx, dy) > dead {
            let angle = atan2(-dy, dx) // 0 = right, counter-clockwise
            let deg = angle * 180 / .pi
            // 8 sectors of 45 degrees, diagonals press two directions
            if deg > -67.5 && deg < 67.5 { s.insert(CemuButton_Right.rawValue) }
            if deg > 22.5 && deg < 157.5 { s.insert(CemuButton_Up.rawValue) }
            if deg > 112.5 || deg < -112.5 { s.insert(CemuButton_Left.rawValue) }
            if deg < -22.5 && deg > -157.5 { s.insert(CemuButton_Down.rawValue) }
        }
        set(s)
    }

    private func set(_ s: Set<UInt32>) {
        guard s != active else { return }
        for b in active.subtracting(s) { InputHub.shared.setTouchButton(CemuButton(rawValue: b), pressed: false) }
        for b in s.subtracting(active) { InputHub.shared.setTouchButton(CemuButton(rawValue: b), pressed: true) }
        if !s.isEmpty && s != active { UISelectionFeedbackGenerator().selectionChanged() }
        active = s
    }
}

struct StickView: View {
    let right: Bool
    var enabled = true
    @State private var knob = CGSize.zero

    var body: some View {
        let radius: CGFloat = 62
        ZStack {
            Circle().fill(Color.black.opacity(0.4))
            Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5)
            Circle()
                .fill(Color.white.opacity(0.75))
                .frame(width: radius, height: radius)
                .offset(knob)
        }
        .frame(width: radius * 2, height: radius * 2)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard enabled else { return }
                    var dx = v.location.x - radius, dy = v.location.y - radius
                    let len = hypot(dx, dy)
                    if len > radius { dx = dx / len * radius; dy = dy / len * radius }
                    knob = CGSize(width: dx, height: dy)
                    InputHub.shared.setTouchStick(right: right, value: CGPoint(x: dx / radius, y: -dy / radius))
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) { knob = .zero }
                    InputHub.shared.setTouchStick(right: right, value: .zero)
                },
            including: enabled ? .all : .subviews
        )
    }
}
