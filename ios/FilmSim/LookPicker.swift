import FilmSimCore
import SwiftUI

/// Built-in looks first, then the imported LUTs. The develop screen uses it to change the selected recipe's look.
/// Shows the look that will actually render (`effectiveLook`), so a deleted import reads as the
/// built-in simulation it falls back to.
struct LookPicker: View {
    let title: String
    @Binding var recipe: Recipe
    @ObservedObject private var library = LUTLibrary.shared

    private var selection: Binding<Look> {
        Binding(
            get: { recipe.effectiveLook(importedNames: library.names) },
            set: { recipe.look = $0 }
        )
    }

    var body: some View {
        Picker(title, selection: selection) {
            ForEach(FilmSimulation.allCases, id: \.self) { sim in
                Text(sim.displayName).tag(Look.builtIn(sim))
            }

            if !library.names.isEmpty {
                Section("読み込んだ LUT") {
                    ForEach(library.names, id: \.self) { name in
                        Text(library.displayName(for: name)).tag(Look.imported(name))
                    }
                }
            }
        }
    }
}
