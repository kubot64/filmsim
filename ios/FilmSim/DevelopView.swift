import FilmSimCore
import PhotosUI
import SwiftUI

/// Pick a DNG from the library, re-develop with a recipe, save.
struct DevelopView: View {
    @State private var picked: PhotosPickerItem?
    @State private var rawData: Data?
    @State private var preview: UIImage?
    @State private var recipe = Recipe()

    var body: some View {
        NavigationStack {
            VStack {
                if let preview {
                    Image(uiImage: preview).resizable().scaledToFit()
                } else {
                    ContentUnavailableView("DNG を選択", systemImage: "photo")
                }
                Form {
                    Picker("Film simulation", selection: $recipe.filmSimulation) {
                        ForEach(FilmSimulation.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    LabeledContent("Exposure") { Slider(value: $recipe.exposureEV, in: -2...2, step: 0.25) }
                    LabeledContent("WB R") { Slider(value: $recipe.wbShiftR, in: -9...9, step: 1) }
                    LabeledContent("WB B") { Slider(value: $recipe.wbShiftB, in: -9...9, step: 1) }
                    LabeledContent("Highlight") { Slider(value: $recipe.highlight, in: -2...4, step: 1) }
                    LabeledContent("Shadow") { Slider(value: $recipe.shadow, in: -2...4, step: 1) }
                    Picker("Grain", selection: $recipe.grainStrength) {
                        ForEach(GrainStrength.allCases, id: \.self) { Text($0.rawValue) }
                    }
                }
            }
            .navigationTitle("Develop")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PhotosPicker("Open", selection: $picked, matching: .images)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }.disabled(rawData == nil)
                }
            }
            .onChange(of: picked) { _, item in Task { await load(item) } }
            .onChange(of: recipe) { _, _ in Task { await rerender() } }
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        rawData = data
        await rerender()
    }

    private func rerender() async {
        guard let rawData else { return }
        Developer.shared.recipe = recipe
        guard let out = Developer.shared.render(rawData: rawData) else { return }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
        let ctx = CIContext()
        if let cg = ctx.createCGImage(scaled, from: scaled.extent) { preview = UIImage(cgImage: cg) }
    }

    private func save() async {
        guard let rawData else { return }
        Developer.shared.recipe = recipe
        await Developer.shared.developAndSave(rawData: rawData, saveDNG: false)
    }
}
