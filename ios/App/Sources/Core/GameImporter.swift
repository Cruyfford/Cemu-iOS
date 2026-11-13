import Foundation
import ZIPFoundation

/// Import helpers: unpacking .zip downloads and fixing raw NUS folders so Cemu can read them.
enum GameImporter {
    /// Raw NUS downloads name content files "0000000b" (no extension), the TMD "tmd" and the ticket "cetk".
    /// Cemu expects "0000000b.app", "title.tmd" and "title.tik". Renames in place, returns how many files changed.
    @discardableResult
    static func normalizeNUSFolders(in root: URL, maxDepth: Int = 4) -> Int {
        var changed = 0
        normalize(root, depth: 0, maxDepth: maxDepth, changed: &changed)
        return changed
    }

    private static func normalize(_ dir: URL, depth: Int, maxDepth: Int, changed: inout Int) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        let names = Set(items.map { $0.lastPathComponent.lowercased() })
        let isNUS = names.contains("tmd") || names.contains("title.tmd") || names.contains { $0.hasPrefix("tmd.") }

        if isNUS {
            for item in items {
                let name = item.lastPathComponent
                let lower = name.lowercased()
                var target: String?
                if isHex8(lower) {
                    target = lower + ".app"
                } else if lower.hasSuffix(".app"), isHex8(String(lower.dropLast(4))), name != lower {
                    target = lower
                } else if lower.hasSuffix(".h3"), isHex8(String(lower.dropLast(3))), name != lower {
                    target = lower
                } else if lower == "tmd" || (lower.hasPrefix("tmd.") && !names.contains("tmd")) {
                    target = "title.tmd"
                } else if lower == "cetk" || lower == "ticket" || lower == "title.tik" && name != lower {
                    target = "title.tik"
                } else if lower == "cert" {
                    target = "title.cert"
                }
                guard let target, target != name else { continue }
                let dest = dir.appendingPathComponent(target)
                if fm.fileExists(atPath: dest.path) && target.lowercased() != name.lowercased() { continue }
                do {
                    if target.lowercased() == name.lowercased() {
                        // case-only rename: go through a temporary name
                        let tmp = dir.appendingPathComponent(name + ".renaming")
                        try fm.moveItem(at: item, to: tmp)
                        try fm.moveItem(at: tmp, to: dest)
                    } else {
                        try fm.moveItem(at: item, to: dest)
                    }
                    changed += 1
                } catch {
                    continue
                }
            }
            return
        }

        guard depth < maxDepth else { return }
        for item in items where (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            normalize(item, depth: depth + 1, maxDepth: maxDepth, changed: &changed)
        }
    }

    private static func isHex8(_ s: String) -> Bool {
        s.count == 8 && s.allSatisfy { $0.isHexDigit }
    }

    /// Extracts a zip into `gamesDir/<zip name>/`, reporting progress 0...1.
    static func unzip(_ zip: URL, into gamesDir: URL, progress: @escaping (Double) -> Void) throws -> URL {
        let fm = FileManager.default
        var dest = gamesDir.appendingPathComponent(zip.deletingPathExtension().lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = gamesDir.appendingPathComponent("\(zip.deletingPathExtension().lastPathComponent) \(n)")
            n += 1
        }
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let p = Progress()
        let observation = p.observe(\.fractionCompleted, options: [.new]) { prog, _ in
            progress(prog.fractionCompleted)
        }
        defer { observation.invalidate() }
        do {
            try fm.unzipItem(at: zip, to: dest, progress: p)
        } catch {
            try? fm.removeItem(at: dest)
            throw error
        }
        // drop macOS metadata folders that some zips carry
        try? fm.removeItem(at: dest.appendingPathComponent("__MACOSX"))
        normalizeNUSFolders(in: dest)
        return dest
    }
}
