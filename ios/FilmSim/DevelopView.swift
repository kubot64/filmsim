import FilmSimCore
import PhotosUI
import SwiftUI

/// Pick a DNG from the library, re-develop with a recipe, save.
struct DevelopView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var picked: PhotosPickerItem?
    @State private var rawData: Data?

    /// Only when opened without a DNG (from Settings) is there a button to pick one.
    private let picksRaw: Bool
    /// The shot being re-developed, when opened from the review screen. Saves then join the shot
    /// log as new shots of the same RAW, so they show in the review screen next to the original.
    private let source: ShotRecord?

    /// `rawData` opens with that DNG already loaded, for re-developing `source` from the review screen.
    init(rawData: Data? = nil, source: ShotRecord? = nil) {
        _rawData = State(initialValue: rawData)
        picksRaw = rawData == nil
        self.source = source
    }
    @State private var preview: UIImage?
    /// The selected saved recipe; the sliders edit it, and the camera develops new shots with it.
    @ObservedObject private var recipes = RecipeStore.shared
    /// Shared with the camera and settings screens. The DNG holds the whole sensor, so any choice works.
    @AppStorage(FocalLength.storageKey) private var focalLength = FocalLength.default
    @State private var message: String?
    /// One preview develop runs at a time. A newer recipe only replaces the single waiting request.
    @State private var renderGeneration = 0
    @State private var renderTask: Task<Void, Never>?

    private var recipe: Binding<Recipe> { recipes.current }

    var body: some View {
        NavigationStack {
            VStack {
                if let preview {
                    Image(uiImage: preview).resizable().scaledToFit()
                } else if picksRaw {
                    ContentUnavailableView("RAW を選ぶ", systemImage: "photo", description: Text("左上の「RAW を選ぶ」から、写真ライブラリの DNG を選ぶ"))
                } else if message == nil {
                    // Opened with the RAW already loaded; the first develop is on its way.
                    ProgressView("現像しています…").frame(maxHeight: .infinity)
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Form {
                    Section {
                    LookPicker(title: "ルック", recipe: recipe)
                    Picker("画角", selection: $focalLength) {
                        ForEach(FocalLength.allCases, id: \.self) { Text($0.displayName) }
                    }
                    slider("明るさ", value: recipe.exposureEV, range: -2...2, step: 0.25, format: "%+.2f")
                    slider("WB R", value: recipe.wbShiftR, range: -9...9, step: 1, format: "%+.0f")
                    slider("WB B", value: recipe.wbShiftB, range: -9...9, step: 1, format: "%+.0f")
                    slider("ハイライト", value: recipe.highlight, range: -2...4, step: 1, format: "%+.0f")
                    slider("シャドウ", value: recipe.shadow, range: -2...4, step: 1, format: "%+.0f")
                    Picker("グレイン", selection: recipe.grainStrength) {
                        ForEach(GrainStrength.allCases, id: \.self) { Text($0.label) }
                    }
                    Picker("グレインの大きさ", selection: recipe.grainSize) {
                        ForEach(GrainSize.allCases, id: \.self) { Text($0.label) }
                    }
                    } footer: {
                        Text("「写真を保存」で、この設定で現像した写真を写真ライブラリに新しく足す。元の写真と RAW はそのまま残る。ここで変えた調整は、選んでいるレシピに入り、カメラの撮影にも効く。")
                    }
                }
            }
            .navigationTitle("現像し直す")
            .toolbar {
                // Opened full screen from the review screen, where swiping down does not close it.
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                if picksRaw {
                    ToolbarItem(placement: .topBarLeading) {
                        PhotosPicker(
                            "RAW を選ぶ",
                            selection: $picked,
                            matching: .images,
                            photoLibrary: .shared()
                        )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("写真を保存") { Task { await save() } }.disabled(rawData == nil)
                }
            }
            .onChange(of: picked) { _, item in Task { await load(item) } }
            .onAppear { scheduleRender() }
            .onChange(of: recipes.selected.recipe) { _, _ in scheduleRender() }
            .onChange(of: focalLength) { _, _ in scheduleRender() }
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
            scheduleRender()
        } catch {
            rawData = nil
            preview = nil
            renderGeneration += 1
            message = error.localizedDescription
        }
    }

    /// Starts a preview develop, or remembers that the latest recipe still needs one.
    /// The in-flight develop runs to completion; its image is shown only if no newer request arrived.
    /// `drainRenders` keeps going while `renderGeneration` advanced during the await, so an
    /// `onChange` that fires mid-render does not race the published preview.
    private func scheduleRender() {
        guard rawData != nil else { return }
        renderGeneration += 1
        guard renderTask == nil else { return }
        renderTask = Task { await drainRenders() }
    }

    private func drainRenders() async {
        defer { renderTask = nil }
        while !Task.isCancelled {
            guard let rawData else { return }
            let current = recipe.wrappedValue
            let currentFocal = focalLength
            let epoch = renderGeneration
            let rendered = await Developer.shared.displayCGImage(
                rawData: rawData, scaleFactor: 0.25, recipe: current, focalLength: currentFocal
            )
            if Task.isCancelled { return }
            if renderGeneration != epoch || recipe.wrappedValue != current || focalLength != currentFocal {
                guard renderGeneration != epoch, self.rawData != nil else { return }
                continue
            }
            if let cg = rendered.image {
                preview = UIImage(cgImage: cg)
                message = nil
            } else {
                preview = nil
                message = rendered.reason ?? "RAW として現像できません"
            }
            return
        }
    }

    private func save() async {
        guard let rawData else { return }
        let recipe = recipes.selected
        let focal = focalLength
        let result = await Developer.shared.developAndSave(
            rawData: rawData, saveDNG: false, recipe: recipe.recipe, focalLength: focal
        )
        if let source, let heic = result.heicAssetID {
            ShotStore.shared.append(ShotRecord(
                date: Date(), heicAssetID: heic, dngAssetID: source.dngAssetID,
                recipeName: recipe.name, recipe: recipe.recipe, focalLength: focal
            ), thumbnailJPEG: result.thumbnailJPEG)
        }
        message = result.message
    }
}

private extension GrainStrength {
    var label: String {
        switch self {
        case .off: return "なし"
        case .weak: return "弱"
        case .strong: return "強"
        }
    }
}

private extension GrainSize {
    var label: String {
        switch self {
        case .small: return "小"
        case .large: return "大"
        }
    }
}
