import FilmSimCore
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            CameraView()
                .tabItem { Label("Camera", systemImage: "camera") }
            DevelopView()
                .tabItem { Label("Develop", systemImage: "slider.horizontal.3") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

struct SettingsView: View {
    @AppStorage("saveDNG") private var saveDNG = true
    @AppStorage(Recipe.storageKey) private var storedRecipe = Data()
    @AppStorage(ExposureCompensation.storageKey) private var exposureBias = 0.0
    @AppStorage(FocalLength.storageKey) private var focalLength = FocalLength.default
    @ObservedObject private var library = LUTLibrary.shared
    @State private var isImporting = false
    @State private var importMessage: String?
    @State private var importInput = LUTInput.fLog2
    @State private var rawSupport: [CameraRawSupport]?
    @State private var isSurveying = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LookPicker(title: "フィルムシミュレーション", selection: look)
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

    /// Clamped to ±3 here; the camera also clamps to the device's range when it applies the value.
    private func stepExposureBias(by steps: Int) {
        exposureBias = Double(ExposureCompensation.stepped(
            Float(exposureBias),
            by: steps,
            deviceRange: -ExposureCompensation.limitEV...ExposureCompensation.limitEV
        ))
    }

    private var look: Binding<Look> {
        Binding(
            get: { Recipe.decoded(from: storedRecipe).effectiveLook(importedNames: library.names) },
            set: { newValue in
                var r = Recipe.decoded(from: storedRecipe)
                r.look = newValue
                storedRecipe = r.encoded
            }
        )
    }

    /// Import .cube files from the Files app; swipe to delete. They join the look pickers.
    private var importSection: some View {
        Section {
            Picker("LUT の入力", selection: $importInput) {
                ForEach(LUTInput.allCases, id: \.self) { Text($0.displayName) }
            }
            Button("LUT を読み込む…") { isImporting = true }
            ForEach(library.names, id: \.self) { name in
                Text(name)
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
            Text("3D LUT（.cube）を読み込み、フィルムシミュレーションの一覧に足す。先に「LUT の入力」で、その LUT が何用に作られたかを選ぶ。S-Log3 用は読み込むときに F-Log2 用に作り直す。富士フイルムの公式 F-Log2 用 LUT はそのまま使え、ファイル名が FLog2_to_ で始まるものには標準の富士の色と同じ補正を掛ける。")
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [LUTLibrary.cubeType], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                do {
                    let added = try library.importFiles(urls, input: importInput)
                    importMessage = "\(added.count) 個の LUT を読み込みました"
                } catch {
                    importMessage = error.localizedDescription
                }
            case .failure(let error):
                importMessage = error.localizedDescription
            }
        }
    }
}

extension DevelopSaveResult {
    /// Japanese status text for the camera and develop screens.
    var message: String {
        switch self {
        case .permissionDenied:
            return "写真ライブラリへのアクセスが拒否されました"
        case .developFailed(let setupError):
            return setupError ?? "現像に失敗しました"
        case .saveFailed(let localizedDescription):
            return "保存に失敗しました: \(localizedDescription)"
        case .savedDNGOnly(let setupError):
            return "DNG のみ保存しました（\(setupError ?? "現像に失敗")）"
        case .savedHEICAndDNG:
            return "HEIC と DNG を保存しました"
        case .savedHEIC:
            return "HEIC を保存しました"
        }
    }
}
