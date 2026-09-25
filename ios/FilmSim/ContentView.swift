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

    var body: some View {
        NavigationStack {
            Form {
                Section("保存") {
                    Toggle("DNG も写真ライブラリに保存", isOn: $saveDNG)
                    Text("開発中はオン。パイプラインが安定したらオフにする。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
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
