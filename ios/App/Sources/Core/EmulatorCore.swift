import Foundation
import SwiftUI
import AVFoundation
import UIKit

struct GameEntry: Identifiable, Codable, Hashable {
    let titleId: String
    let name: String
    let path: String
    let version: Int
    let region: String
    let format: String
    let hasUpdate: Bool
    let hasDLC: Bool
    var id: String { titleId }
    var titleIdValue: UInt64 { UInt64(titleId, radix: 16) ?? 0 }
}

enum LaunchError: LocalizedError {
    case code(CemuLaunchResult)

    var errorDescription: String? {
        switch self {
        case .code(let r):
            switch r {
            case CemuLaunch_AlreadyRunning: return "A game is already running."
            case CemuLaunch_BaseNotFound: return "The base game files were not found. Updates and DLC need the base game in the games folder."
            case CemuLaunch_UnableToMount: return "Unable to mount the title. Make sure the file is still in the games folder."
            case CemuLaunch_InvalidRPX: return "The executable could not be loaded."
            case CemuLaunch_NoDiscKey: return "Could not decrypt the title. Add the disc key to keys.txt."
            case CemuLaunch_NoTitleTik: return "Could not decrypt the title because title.tik is missing."
            case CemuLaunch_NoRenderSurface: return "The display is not ready yet."
            default: return "Failed to launch the game."
            }
        }
    }
}

/// Owns the Cemu core and exposes its state to SwiftUI.
@MainActor
final class EmulatorCore: ObservableObject {
    static let shared = EmulatorCore()

    @Published private(set) var initialized = false
    @Published private(set) var games: [GameEntry] = []
    @Published private(set) var isScanning = false
    @Published var runningGame: GameEntry?
    @Published var errorMessage: String?
    @Published private(set) var fps: Double = 0
    @Published var showGamePadOnTV = false {
        didSet { CemuBridge_SetShowGamePadOnTV(showGamePadOnTV) }
    }

    let documentsURL: URL
    let gamesURL: URL
    let iconsURL: URL
    let cachesURL: URL

    private var pollTimer: Timer?

    private init() {
        documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Cemu")
        gamesURL = documentsURL.appendingPathComponent("games")
        iconsURL = cachesURL.appendingPathComponent("icons")
        for url in [gamesURL, iconsURL, cachesURL] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    var keysURL: URL { documentsURL.appendingPathComponent("keys.txt") }
    var hasKeys: Bool {
        guard let text = try? String(contentsOf: keysURL) else { return false }
        return text.split(separator: "\n").contains { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !t.isEmpty && !t.hasPrefix("#")
        }
    }

    func start() {
        guard !initialized else { return }
        configureAudioSession()
        let resources = Bundle.main.bundleURL.appendingPathComponent("CemuData").path
        let ok = CemuBridge_Initialize(documentsURL.path, cachesURL.path, resources)
        initialized = ok
        collectCoreError()
        startPolling()
        refreshGames()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        let scanning = CemuBridge_IsScanning()
        if isScanning && !scanning { reloadGameList() }
        isScanning = scanning
        if runningGame != nil {
            fps = CemuBridge_GetFPS()
            if CemuBridge_ConsumeGameExitRequest() { stopGame() }
        }
        collectCoreError()
    }

    private func collectCoreError() {
        let msg = takeString(CemuBridge_ConsumeErrorMessage())
        if !msg.isEmpty { errorMessage = msg }
    }

    // MARK: game list

    func refreshGames() {
        guard initialized else { return }
        CemuBridge_RefreshGameList()
        isScanning = true
        reloadGameList()
    }

    func reloadGameList() {
        let json = takeString(CemuBridge_GetGameListJSON())
        guard let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([GameEntry].self, from: data) else { return }
        games = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated func iconURL(for game: GameEntry) -> URL? {
        let url = iconsURL.appendingPathComponent("\(game.titleId).tga")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        return CemuBridge_ExtractIcon(game.titleIdValue, url.path) ? url : nil
    }

    func importGames(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let dest = gamesURL.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) { continue }
            do {
                // moving is instant inside the same volume (Files "On My iPhone"), copy otherwise
                if url.path.hasPrefix(documentsURL.path) {
                    try FileManager.default.moveItem(at: url, to: dest)
                } else {
                    try FileManager.default.copyItem(at: url, to: dest)
                }
            } catch {
                errorMessage = "Import failed: \(error.localizedDescription)"
            }
        }
        refreshGames()
    }

    func importKeys(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url)
            try text.write(to: keysURL, atomically: true, encoding: .utf8)
            refreshGames()
        } catch {
            errorMessage = "Could not import keys.txt: \(error.localizedDescription)"
        }
    }

    func deleteGame(_ game: GameEntry) {
        try? FileManager.default.removeItem(atPath: game.path)
        try? FileManager.default.removeItem(at: iconsURL.appendingPathComponent("\(game.titleId).tga"))
        refreshGames()
    }

    // MARK: emulation

    func launch(_ game: GameEntry) throws {
        let result = CemuBridge_LaunchGame(game.path)
        guard result == CemuLaunch_OK else {
            collectCoreError()
            throw LaunchError.code(result)
        }
        runningGame = game
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stopGame() {
        CemuBridge_StopGame()
        runningGame = nil
        fps = 0
        showGamePadOnTV = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: settings

    func loadSettings() -> [String: Any] {
        let json = takeString(CemuBridge_GetSettingsJSON())
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    func saveSettings(_ values: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: values),
              let json = String(data: data, encoding: .utf8) else { return }
        _ = CemuBridge_SetSettingsJSON(json)
    }
}

/// Takes ownership of a string returned by the bridge.
func takeString(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
    guard let ptr else { return "" }
    defer { CemuBridge_FreeString(ptr) }
    return String(cString: ptr)
}
