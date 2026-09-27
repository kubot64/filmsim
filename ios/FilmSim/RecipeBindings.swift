import FilmSimCore
import SwiftUI

extension Recipe {
    /// `@AppStorage(Recipe.storageKey)` stores `Data`; this wraps decode / encode so screens
    /// can bind to `Recipe` (or one of its fields) without repeating the JSON boilerplate.
    static func binding(_ stored: Binding<Data>) -> Binding<Recipe> {
        Binding(
            get: { decoded(from: stored.wrappedValue) },
            set: { stored.wrappedValue = $0.encoded }
        )
    }
}
