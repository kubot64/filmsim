import FilmSimCore
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppPreferences.saveDNGKey) private var saveDNG = true
    @AppStorage(Recipe.storageKey) private var storedRecipe = Data()
    @AppStorage(ExposureCompensation.storageKey) private var exposureBias = 0.0
    @AppStorage(FocalLength.storageKey) private var focalLength = FocalLength.default
    @State private var rawSupport: [CameraRawSupport]?
    @State private var isSurveying = false

    private var recipe: Binding<Recipe> { Recipe.binding($storedRecipe) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FilmSimulationPicker(selection: recipe.filmSimulation)
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
}
