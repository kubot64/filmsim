import FilmSimCore
import SwiftUI

/// Plain preview (no film simulation live), shutter, RAW capture.
/// Shots are developed with the last-used recipe, shared with the develop screen (#8).
/// The film simulation can be switched here; other settings come from the develop screen.
struct CameraView: View {
    @StateObject private var camera = CameraController()
    @AppStorage(Recipe.storageKey) private var storedRecipe = Data()

    private var recipe: Recipe { Recipe.decoded(from: storedRecipe) }

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(session: camera.session, zoom: camera.previewZoom)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .ignoresSafeArea()
            VStack(spacing: 8) {
                Text(camera.status).font(.footnote).foregroundStyle(.white)
                Button {
                    camera.capture(recipe: recipe)
                } label: {
                    Circle().fill(.white).frame(width: 72, height: 72)
                }
                .disabled(!camera.isReady)
            }
            .padding(.bottom, 24)
        }
        .overlay(alignment: .top) { recipeBar.padding(.top, 8) }
        .background(Color.black)
        .task { await camera.start() }
    }

    private var recipeBar: some View {
        VStack(spacing: 4) {
            Menu {
                Picker("Film simulation", selection: filmSimulation) {
                    ForEach(FilmSimulation.allCases, id: \.self) { Text($0.displayName) }
                }
            } label: {
                Label(recipe.filmSimulation.displayName, systemImage: "camera.filters")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5), in: Capsule())
                    .foregroundStyle(.white)
            }
            if !recipe.adjustmentSummary.isEmpty {
                Text(recipe.adjustmentSummary)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.4), in: Capsule())
            }
        }
    }

    private var filmSimulation: Binding<FilmSimulation> {
        Binding(
            get: { recipe.filmSimulation },
            set: { newValue in
                var r = recipe
                r.filmSimulation = newValue
                storedRecipe = r.encoded
            }
        )
    }
}
