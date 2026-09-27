import SwiftUI

@main
struct FilmSimApp: App {
    init() {
        // @AppStorage shows this default, but bool(forKey:) is false until the key is written.
        UserDefaults.standard.register(defaults: [AppPreferences.saveDNGKey: true])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
