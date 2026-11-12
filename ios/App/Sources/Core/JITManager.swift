import Foundation
import UIKit

/// Gets executable memory for Cemu's ARM64 recompiler.
///
/// iOS only allows JIT while a debugger is attached (CS_DEBUGGED). StikDebug attaches,
/// and on iOS 26+ (TXM devices like iPhone 17) runs its universal script that serves
/// the app's `brk #0xf00d` requests to map the JIT region. Without JIT Cemu falls
/// back to the (very slow) interpreter.
@MainActor
final class JITManager: ObservableObject {
    static let shared = JITManager()

    enum State: Equatable {
        case disabled
        case waitingForDebugger
        case enabled
        case failed(String)
    }

    @Published private(set) var state: State = .disabled
    @AppStorage("jitMode") var jitMode: Int = 0          // 0 auto, 1 TXM, 2 legacy
    @AppStorage("jitArenaMB") var arenaMB: Int = 512
    @AppStorage("jitAutoRequest") var autoRequest: Bool = true

    private var pollTask: Task<Void, Never>?

    var isEnabled: Bool { state == .enabled }
    var usesTXM: Bool { CemuBridge_JitUsesTXM() }

    /// Call as early as possible. If a debugger is already attached the arena is created right away.
    func checkOnLaunch() {
        if CemuBridge_JitIsReady() { state = .enabled; return }
        if CemuBridge_JitIsDebugged() {
            initializeArena()
        } else if autoRequest && canOpenStikDebug {
            requestJIT()
        }
    }

    var canOpenStikDebug: Bool {
        guard let url = URL(string: "stikdebug://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Opens StikDebug, which attaches to this process, then waits for CS_DEBUGGED.
    func requestJIT() {
        guard state != .enabled else { return }
        var comps = URLComponents()
        comps.scheme = "stikdebug"
        comps.host = "enable-jit"
        var items = [
            URLQueryItem(name: "bundle-id", value: Bundle.main.bundleIdentifier ?? "com.cruyfford.cemu"),
            URLQueryItem(name: "pid", value: String(getpid())),
        ]
        if usesTXM || jitMode == 1 {
            items.append(URLQueryItem(name: "script-name", value: "universal.js"))
        }
        comps.queryItems = items
        guard let url = comps.url else { return }
        state = .waitingForDebugger
        UIApplication.shared.open(url) { [weak self] opened in
            Task { @MainActor in
                if !opened { self?.state = .failed("StikDebug is not installed.") }
            }
        }
        startWaiting()
    }

    private func startWaiting() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            for _ in 0..<240 { // up to 2 minutes
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
                if CemuBridge_JitIsDebugged() {
                    await MainActor.run { self?.initializeArena() }
                    return
                }
            }
            await MainActor.run {
                if self?.state == .waitingForDebugger { self?.state = .failed("Timed out waiting for the debugger.") }
            }
        }
    }

    private func initializeArena() {
        // for the TXM protocol this runs the brk handshake and detaches the debugger again
        if CemuBridge_JitInitialize(Int32(jitMode), Int32(arenaMB)) {
            state = .enabled
        } else {
            state = .failed(takeString(CemuBridge_JitLastError()))
        }
    }

    var statusText: String {
        switch state {
        case .disabled: return "Off — interpreter (slow)"
        case .waitingForDebugger: return "Waiting for StikDebug…"
        case .enabled: return "On — recompiler"
        case .failed(let msg): return "Failed: \(msg)"
        }
    }
}
