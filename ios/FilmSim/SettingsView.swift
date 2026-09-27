import FilmSimCore
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppPreferences.saveDNGKey) private var saveDNG = true
    @AppStorage(Recipe.storageKey) private var storedRecipe = Data()
    @AppStorage(ExposureCompensation.storageKey) private var exposureBias = 0.0
    @AppStorage(FocalLength.storageKey) private var focalLength = FocalLength.default
    @ObservedObject private var library = LUTLibrary.shared
    @State private var isImporting = false
    @State private var importMessage: String?
    /// The import being renamed, and the text field's contents.
    @State private var renaming: String?
    @State private var newName = ""
    @State private var rawSupport: [CameraRawSupport]?
    @State private var isSurveying = false

    private var recipe: Binding<Recipe> { Recipe.binding($storedRecipe) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LookPicker(title: "フィルムシミュレーション", recipe: recipe)
                    Picker("画角", selection: $focalLength) {
                        ForEach(FocalLength.allCases, id: \.self) { Text($0.displayName) }
                    }
                    Stepper(
                        onIncrement: { stepExposureBias(by: 1) },
                        onDecrement: { stepExposureBias(by: -1) }
                    ) {
                        HStack {
                            Text("露出補正")
                            Spacer()
                            Text(ExposureCompensation.label(Float(exposureBias))).monospacedDigit()
                        }
                    }
                } header: {
                    Text("撮影")
                } footer: {
                    Text("カメラ画面と同じ設定。アプリを終了しても次に起動したときに残る。")
                }
                importSection
                Section("保存") {
                    Toggle("DNG も写真ライブラリに保存", isOn: $saveDNG)
                    Text("開発中はオン。パイプラインが安定したらオフにする。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                rawSupportSection
            }
            .navigationTitle("Settings")
        }
    }

    /// Development check: which cameras give Bayer RAW / ProRAW (`CameraSurvey`).
    private var rawSupportSection: some View {
        Section {
            Button(isSurveying ? "調べています…" : "調べる") {
                isSurveying = true
                Task {
                    rawSupport = await CameraSurvey.run()
                    isSurveying = false
                }
            }
            .disabled(isSurveying)
            if let rawSupport {
                if rawSupport.isEmpty {
                    Text("カメラが見つかりません")
                }
                ForEach(rawSupport) { camera in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(camera.name)
                        if let error = camera.error {
                            Text(error).font(.footnote).foregroundStyle(.red)
                        } else {
                            Text("Bayer RAW \(camera.bayerRAW ? "○" : "×")　ProRAW \(camera.proRAW ? "○" : "×")")
                                .font(.footnote.monospaced())
                            if !camera.maxPhotoSize.isEmpty {
                                Text("写真の最大 \(camera.maxPhotoSize)")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("カメラの RAW 対応（開発用）")
        } footer: {
            Text("インカメラや超広角・望遠で RAW が撮れるかを調べる。撮影には影響しない。")
        }
    }

    /// Import .cube files from the Files app; swipe to delete. They join the look pickers.
    private var importSection: some View {
        Section {
            Button("LUT を読み込む…") { isImporting = true }
            ForEach(library.names, id: \.self) { name in
                Button {
                    newName = library.displayName(for: name)
                    renaming = name
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(library.displayName(for: name)).foregroundStyle(.primary)
                        if library.displayName(for: name) != name {
                            Text(name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                // Take the names first: each delete refreshes the list and shifts the offsets.
                let targets = offsets.map { library.names[$0] }
                for name in targets { library.delete(name) }
            }
            if let importMessage {
                Text(importMessage).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("LUT の読み込み")
        } footer: {
            Text("3D LUT（.cube）を読み込み、フィルムシミュレーションの一覧に足す。F-Log2 用と S-Log3（S-Gamut3.Cine / S-Gamut3）用に対応し、何用かはファイル名と中身の書き込みから判定する。判定できないものや未対応のものは読み込まない。富士フイルムの公式 F-Log2 用 LUT はそのまま使える。")
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [LUTLibrary.cubeType], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                importMessage = library.importFiles(urls).lines.joined(separator: "\n")
            case .failure(let error):
                importMessage = error.localizedDescription
            }
        }
        .alert("名前を変える", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名前", text: $newName)
            Button("保存") {
                if let renaming { library.rename(renaming, to: newName) }
                renaming = nil
            }
            Button("キャンセル", role: .cancel) { renaming = nil }
        } message: {
            Text("空にすると、ファイル名に戻ります。")
        }
    }

    /// Clamped to ±3 here; the camera also clamps to the device's range when it applies the value.
    private func stepExposureBias(by steps: Int) {
        exposureBias = Double(ExposureCompensation.stepped(
            Float(exposureBias),
            by: steps,
            deviceRange: -ExposureCompensation.limitEV...ExposureCompensation.limitEV
        ))
    }
}
