import FilmSimCore
import Foundation
import SwiftUI

/// The saved recipes (`RecipeBook`), shared by every screen. Stored in UserDefaults under
/// `RecipeBook.storageKey`. The first launch after #54 migrates the single last-used recipe
/// (`Recipe.storageKey`).
@MainActor
final class RecipeStore: ObservableObject {
    static let shared = RecipeStore()

    @Published private(set) var book: RecipeBook {
        didSet { UserDefaults.standard.set(book.encoded, forKey: RecipeBook.storageKey) }
    }

    private init() {
        let defaults = UserDefaults.standard
        let last = defaults.data(forKey: Recipe.storageKey).map(Recipe.decoded(from:))
        var book = RecipeBook.decoded(from: defaults.data(forKey: RecipeBook.storageKey) ?? Data(), migrating: last)
        let library = LUTLibrary.shared
        book.addMissingImportedLUTs(library.names.map { ($0, library.displayName(for: $0)) })
        self.book = book
        defaults.set(book.encoded, forKey: RecipeBook.storageKey)
    }

    var selected: SavedRecipe { book.selected }

    /// The recipe in use, for screens that edit its settings (the develop screen's sliders).
    var current: Binding<Recipe> {
        Binding(get: { self.book.selected.recipe }, set: { self.book.updateSelected($0) })
    }

    /// The selected recipe's id, for pickers that choose among the saved recipes.
    var selection: Binding<UUID> {
        Binding(get: { self.book.selected.id }, set: { self.book.select($0) })
    }

    func lutImported(named name: String, displayName: String) {
        book.addImportedLUT(named: name, displayName: displayName)
    }

    func lutRenamed(named name: String, from oldDisplayName: String, to newDisplayName: String) {
        book.renameImportedLUT(named: name, from: oldDisplayName, to: newDisplayName)
    }

    func lutDeleted(named name: String) {
        book.removeImportedLUT(named: name)
    }
}

/// Shots taken with the camera screen (`ShotLog`), kept in Application Support/Shots.json, with a
/// small JPEG per shot in Application Support/Thumbnails for the camera's thumbnail. Keeping our own
/// thumbnail means the camera screen never needs permission to read the photo library.
@MainActor
final class ShotStore: ObservableObject {
    static let shared = ShotStore()

    @Published private(set) var log: ShotLog
    /// The newest shot's thumbnail, for the camera screen.
    @Published private(set) var latestThumbnail: UIImage?

    private static let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    private let url = base.appendingPathComponent("Shots.json")
    private let thumbnails = base.appendingPathComponent("Thumbnails", isDirectory: true)

    private init() {
        log = ShotLog.decoded(from: (try? Data(contentsOf: url)) ?? Data())
        latestThumbnail = log.newestFirst.lazy.compactMap { self.thumbnail(for: $0) }.first
    }

    func thumbnail(for shot: ShotRecord) -> UIImage? {
        UIImage(contentsOfFile: thumbnailURL(for: shot).path)
    }

    /// Forgets a shot whose photos were deleted, with its thumbnail.
    func remove(_ shot: ShotRecord) {
        log.remove(id: shot.id)
        try? FileManager.default.removeItem(at: thumbnailURL(for: shot))
        latestThumbnail = log.newestFirst.lazy.compactMap { self.thumbnail(for: $0) }.first
        save()
    }

    private func thumbnailURL(for shot: ShotRecord) -> URL {
        thumbnails.appendingPathComponent("\(shot.id.uuidString).jpg")
    }

    func append(_ shot: ShotRecord, thumbnailJPEG: Data?) {
        if let thumbnailJPEG {
            try? FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
            try? thumbnailJPEG.write(to: thumbnailURL(for: shot), options: .atomic)
            latestThumbnail = UIImage(data: thumbnailJPEG)
        }
        log.append(shot)
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try log.encoded.write(to: url, options: .atomic)
        } catch {
            // The photo is already in the library; only the review screen loses this entry.
            print("ShotStore: could not save: \(error.localizedDescription)")
        }
    }
}

/// Picks one of the saved recipes (visible ones). Used by the camera and settings screens until
/// the recipe strip (#55) replaces it.
struct RecipePicker: View {
    let title: String
    @ObservedObject private var store = RecipeStore.shared

    var body: some View {
        Picker(title, selection: store.selection) {
            ForEach(store.book.visible) { Text($0.name).tag($0.id) }
        }
    }
}
