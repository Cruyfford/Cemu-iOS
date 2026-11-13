import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// UIKit document picker. SwiftUI's .fileImporter breaks when several importers live in the same
/// hierarchy (the Open button stops responding), so imports go through this instead.
struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    var allowsMultiple = true
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = allowsMultiple
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

enum ImportKind: String, Identifiable {
    case games, keys
    var id: String { rawValue }

    var types: [UTType] {
        switch self {
        case .keys: return [.plainText, .text, .data]
        case .games:
            var t: [UTType] = [.folder, .zip, .data]
            for ext in ["wua", "wux", "wud", "rpx", "elf", "wuhb"] {
                if let u = UTType(filenameExtension: ext) { t.append(u) }
            }
            return t
        }
    }
}

extension View {
    /// Presents the document picker for `kind` and routes the result to the core.
    func importSheet(_ kind: Binding<ImportKind?>) -> some View {
        sheet(item: kind) { k in
            DocumentPicker(types: k.types, allowsMultiple: k == .games) { urls in
                let core = EmulatorCore.shared
                switch k {
                case .games:
                    SoundManager.shared.play(.open)
                    core.importGames(urls)
                case .keys:
                    if let url = urls.first {
                        core.importKeys(from: url)
                        SoundManager.shared.play(.select)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
}
