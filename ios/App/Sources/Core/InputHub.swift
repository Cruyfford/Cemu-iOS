import Foundation
import GameController
import UIKit

/// Merges touch controls and physical controllers into the emulated Wii U GamePad.
@MainActor
final class InputHub: ObservableObject {
    static let shared = InputHub()

    @Published private(set) var controllerConnected = false
    @Published private(set) var controllerName: String?
    // false = Nintendo positional layout
    @Published var swapFaceButtons: Bool = UserDefaults.standard.bool(forKey: "swapFaceButtons") {
        didSet { UserDefaults.standard.set(swapFaceButtons, forKey: "swapFaceButtons") }
    }

    private var touchButtons = Set<UInt32>()
    private var padButtons = Set<UInt32>()
    private var touchLeft = CGPoint.zero, touchRight = CGPoint.zero
    private var padLeft = CGPoint.zero, padRight = CGPoint.zero
    private var lastSent = Set<UInt32>()

    private init() {
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.attach(note.object as? GCController) }
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshControllers() }
        }
        GCController.startWirelessControllerDiscovery {}
        refreshControllers()
    }

    private func refreshControllers() {
        let current = GCController.controllers().first { $0.extendedGamepad != nil }
        controllerConnected = current != nil
        controllerName = current?.vendorName
        if let current { attach(current) } else {
            padButtons.removeAll(); padLeft = .zero; padRight = .zero; flush()
        }
    }

    private func attach(_ controller: GCController?) {
        guard let controller, let pad = controller.extendedGamepad else { return }
        controllerConnected = true
        controllerName = controller.vendorName
        pad.valueChangedHandler = { [weak self] gamepad, _ in
            let snapshot = Self.read(gamepad)
            Task { @MainActor in self?.applyController(snapshot) }
        }
    }

    private struct PadSnapshot {
        var a, b, x, y, l, r, zl, zr, plus, minus, up, down, left, right, ls, rs, home: Bool
        var lx, ly, rx, ry: Float
    }

    nonisolated private static func read(_ g: GCExtendedGamepad) -> PadSnapshot {
        PadSnapshot(a: g.buttonA.isPressed, b: g.buttonB.isPressed, x: g.buttonX.isPressed, y: g.buttonY.isPressed,
                    l: g.leftShoulder.isPressed, r: g.rightShoulder.isPressed,
                    zl: g.leftTrigger.isPressed, zr: g.rightTrigger.isPressed,
                    plus: g.buttonMenu.isPressed, minus: g.buttonOptions?.isPressed ?? false,
                    up: g.dpad.up.isPressed, down: g.dpad.down.isPressed, left: g.dpad.left.isPressed, right: g.dpad.right.isPressed,
                    ls: g.leftThumbstickButton?.isPressed ?? false, rs: g.rightThumbstickButton?.isPressed ?? false,
                    home: g.buttonHome?.isPressed ?? false,
                    lx: g.leftThumbstick.xAxis.value, ly: g.leftThumbstick.yAxis.value,
                    rx: g.rightThumbstick.xAxis.value, ry: g.rightThumbstick.yAxis.value)
    }

    private func applyController(_ s: PadSnapshot) {
        var set = Set<UInt32>()
        func add(_ on: Bool, _ b: CemuButton) { if on { set.insert(b.rawValue) } }
        // GameController reports positions Xbox-style: A bottom, B right, X left, Y top.
        // Wii U: B bottom, A right, Y left, X top.
        if swapFaceButtons {
            add(s.a, CemuButton_A); add(s.b, CemuButton_B); add(s.x, CemuButton_X); add(s.y, CemuButton_Y)
        } else {
            add(s.a, CemuButton_B); add(s.b, CemuButton_A); add(s.x, CemuButton_Y); add(s.y, CemuButton_X)
        }
        add(s.l, CemuButton_L); add(s.r, CemuButton_R); add(s.zl, CemuButton_ZL); add(s.zr, CemuButton_ZR)
        add(s.plus, CemuButton_Plus); add(s.minus, CemuButton_Minus)
        add(s.up, CemuButton_Up); add(s.down, CemuButton_Down); add(s.left, CemuButton_Left); add(s.right, CemuButton_Right)
        add(s.ls, CemuButton_StickL); add(s.rs, CemuButton_StickR); add(s.home, CemuButton_Home)
        padButtons = set
        padLeft = CGPoint(x: CGFloat(s.lx), y: CGFloat(s.ly))
        padRight = CGPoint(x: CGFloat(s.rx), y: CGFloat(s.ry))
        flush()
    }

    // MARK: touch overlay

    func setTouchButton(_ button: CemuButton, pressed: Bool) {
        if pressed { touchButtons.insert(button.rawValue) } else { touchButtons.remove(button.rawValue) }
        flush()
    }

    /// y up is positive
    func setTouchStick(right: Bool, value: CGPoint) {
        if right { touchRight = value } else { touchLeft = value }
        flush()
    }

    func releaseAllTouch() {
        touchButtons.removeAll(); touchLeft = .zero; touchRight = .zero
        flush()
    }

    private func flush() {
        let all = touchButtons.union(padButtons)
        for b in lastSent.subtracting(all) { CemuBridge_SetButton(CemuButton(rawValue: b), false) }
        for b in all.subtracting(lastSent) { CemuBridge_SetButton(CemuButton(rawValue: b), true) }
        lastSent = all
        func pick(_ a: CGPoint, _ b: CGPoint) -> CGPoint { hypot(a.x, a.y) >= hypot(b.x, b.y) ? a : b }
        let l = pick(touchLeft, padLeft), r = pick(touchRight, padRight)
        CemuBridge_SetSticks(Float(l.x), Float(l.y), Float(r.x), Float(r.y))
    }
}
