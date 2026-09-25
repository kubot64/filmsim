import FilmSimCore
import PhotosUI
import SwiftUI

/// Pick a DNG from the library, re-develop with a recipe, save.
struct DevelopView: View {
    @State private var picked: PhotosPickerItem?
    @State private var rawData: Data?
    @State private var preview: UIImage?
    @State private var recipe = Recipe()
    @State private var message: String?
    @State private var renderTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack {
                if let preview {
                    Image(uiImage: preview).resizable().scaledToFit()
                } else {
                    ContentUnavailableView("DNG を選択", systemImage: "photo")
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Form {
                    Picker("Film simulation", selection: $recipe.filmSimulation) {
                        ForEach(FilmSimulation.allCases, id: \.self) { Text($0.displayName) }
                    }
                    slider("Exposure", value: $recipe.exposureEV, range: -2...2, step: 0.25, format: "%+.2f")
                    slider("WB R", value: $recipe.wbShiftR, range: -9...9, step: 1, format: "%+.0f")
                    slider("WB B", value: $recipe.wbShiftB, range: -9...9, step: 1, format: "%+.0f")
                    slider("Highlight", value: $recipe.highlight, range: -2...4, step: 1, format: "%+.0f")
                    slider("Shadow", value: $recipe.shadow, range: -2...4, step: 1, format: "%+.0f")
                    Picker("Grain", selection: $recipe.grainStrength) {
                        ForEach(GrainStrength.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    Picker("Grain size", selection: $recipe.grainSize) {
                        ForEach(GrainSize.allCases, id: \.self) { Text($0.rawValue) }
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
            .onChange(of: recipe) { _, _ in scheduleRender() }
        }
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String
    ) -> some View {
        LabeledContent("\(title) \(String(format: format, value.wrappedValue))") {
            Slider(value: value, in: range, step: step)
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            rawData = try await LibraryRaw.load(from: item)
            message = nil
            await rerender()
        } catch {
            rawData = nil
            preview = nil
            message = error.localizedDescription
        }
    }

    private func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task { await rerender() }
    }

    private func rerender() async {
        guard let rawData else { return }
        let current = recipe
        Developer.shared.recipe = current
        guard let out = Developer.shared.render(rawData: rawData, scaleFactor: 0.25),
              let image = Developer.shared.uiImage(from: out) else {
            guard !Task.isCancelled else { return }
            preview = nil
            message = Developer.shared.setupError ?? "RAW として現像できません"
            return
        }
        guard !Task.isCancelled, self.recipe == current else { return }
        preview = image
        message = nil
    }

    private func save() async {
        guard let rawData else { return }
        Developer.shared.recipe = recipe
        message = await Developer.shared.developAndSave(rawData: rawData, saveDNG: false)
    }
}
