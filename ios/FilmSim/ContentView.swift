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
