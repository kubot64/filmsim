import FilmSimCore
import SwiftUI

/// Built-in looks first, then the imported LUTs. Shared by the camera, develop and settings screens.
struct LookPicker: View {
    let title: String
    @Binding var selection: Look
    @ObservedObject private var library = LUTLibrary.shared

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(FilmSimulation.allCases, id: \.self) { sim in
                Text(sim.displayName).tag(Look.builtIn(sim))
            }
            if !library.names.isEmpty {
                Section("読み込んだ LUT") {
                    ForEach(library.names, id: \.self) { name in
                        Text(name).tag(Look.imported(name))
                    }
                }
            }
        }
    }
}
