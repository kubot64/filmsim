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
