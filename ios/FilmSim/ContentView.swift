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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("フィルムシミュレーション", selection: filmSimulation) {
                        ForEach(FilmSimulation.allCases, id: \.self) { Text($0.displayName) }
                    }
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
            }
            .navigationTitle("Settings")
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

    private var filmSimulation: Binding<FilmSimulation> {
        Binding(
            get: { Recipe.decoded(from: storedRecipe).filmSimulation },
            set: { newValue in
                var r = Recipe.decoded(from: storedRecipe)
                r.filmSimulation = newValue
                storedRecipe = r.encoded
            }
        )
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
