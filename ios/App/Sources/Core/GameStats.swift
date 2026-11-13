import Foundation
import SwiftUI

/// Per-game play time, last played date and favorites, kept in UserDefaults.
@MainActor
final class GameStats: ObservableObject {
    static let shared = GameStats()

    struct Entry: Codable {
        var playSeconds: TimeInterval = 0
        var lastPlayed: Date?
        var favorite = false
        var launches = 0
    }

    @Published private(set) var entries: [String: Entry] = [:]
    private var sessionStart: Date?
    private var sessionTitle: String?
    private let key = "gameStats.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let e = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = e
        }
    }

    func entry(_ game: GameEntry) -> Entry { entries[game.titleId] ?? Entry() }
    func isFavorite(_ game: GameEntry) -> Bool { entry(game).favorite }

    func toggleFavorite(_ game: GameEntry) {
        var e = entry(game)
        e.favorite.toggle()
        entries[game.titleId] = e
        save()
    }

    func sessionStarted(_ game: GameEntry) {
        sessionStart = Date()
        sessionTitle = game.titleId
        var e = entry(game)
        e.lastPlayed = Date()
        e.launches += 1
        entries[game.titleId] = e
        save()
    }

    func sessionEnded() {
        guard let start = sessionStart, let id = sessionTitle else { return }
        var e = entries[id] ?? Entry()
        e.playSeconds += Date().timeIntervalSince(start)
        e.lastPlayed = Date()
        entries[id] = e
        sessionStart = nil
        sessionTitle = nil
        save()
    }

    var currentSessionLength: TimeInterval {
        sessionStart.map { Date().timeIntervalSince($0) } ?? 0
    }

    func forget(_ game: GameEntry) {
        entries[game.titleId] = nil
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: key) }
    }
}
