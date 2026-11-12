import SwiftUI
import UIKit
import QuartzCore
import Metal

/// A UIView backed by a CAMetalLayer that Cemu renders into.
final class MetalSurfaceUIView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    var isGamePad = false
    var onTouch: ((Bool, CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .black
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = UIScreen.main.nativeScale
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.nativeScale ?? UIScreen.main.nativeScale
        metalLayer.contentsScale = scale
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        CemuBridge_SetSurfaceSize(isGamePad, Int32(size.width), Int32(size.height), Double(scale))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { report(touches, down: true) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { report(touches, down: true) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { report(touches, down: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { report(touches, down: false) }

    private func report(_ touches: Set<UITouch>, down: Bool) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        CemuBridge_SetTouch(isGamePad, down, Float(p.x), Float(p.y))
        onTouch?(down, p)
    }
}

/// Holds the two render surfaces for the lifetime of the app so the core keeps valid layers.
@MainActor
final class RenderSurfaces {
    static let shared = RenderSurfaces()
    let tv = MetalSurfaceUIView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
    let pad = MetalSurfaceUIView(frame: CGRect(x: 0, y: 0, width: 854, height: 480))

    private init() {
        pad.isGamePad = true
    }

    func register(withGamePadScreen: Bool) {
        let tvPtr = Unmanaged.passUnretained(tv.metalLayer).toOpaque()
        let padPtr = withGamePadScreen ? Unmanaged.passUnretained(pad.metalLayer).toOpaque() : nil
        CemuBridge_SetRenderSurfaces(tvPtr, padPtr)
    }
}

struct MetalSurface: UIViewRepresentable {
    let view: MetalSurfaceUIView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        view.removeFromSuperview()
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if view.superview !== uiView {
            view.removeFromSuperview()
            uiView.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: uiView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: uiView.trailingAnchor),
                view.topAnchor.constraint(equalTo: uiView.topAnchor),
                view.bottomAnchor.constraint(equalTo: uiView.bottomAnchor),
            ])
        }
    }
}
