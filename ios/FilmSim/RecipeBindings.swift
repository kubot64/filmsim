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

/// Film-simulation picker shared by Camera, Develop, and Settings.
struct FilmSimulationPicker: View {
    @Binding var selection: FilmSimulation
    var title: String = "フィルムシミュレーション"

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(FilmSimulation.allCases, id: \.self) { Text($0.displayName) }
        }
    }
}
