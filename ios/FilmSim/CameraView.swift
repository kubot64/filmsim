import FilmSimCore
import SwiftUI

/// Plain preview (no film simulation live), shutter, RAW capture.
/// Tap the preview to focus and meter there, long-press for AE/AF lock.
/// The ± buttons set capture-time exposure compensation; the mm button steps the focal length.
/// Shots are developed with the last-used recipe, shared with the develop screen (#8).
/// The film simulation can be switched here; other settings come from the develop screen.
struct CameraView: View {
    @StateObject private var camera = CameraController()
    @AppStorage(Recipe.storageKey) private var storedRecipe = Data()

    private var recipe: Recipe { Recipe.decoded(from: storedRecipe) }

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(session: camera.session, zoom: camera.previewZoom) { point, lock in
                camera.focusAndExpose(at: point, lock: lock)
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .ignoresSafeArea()
            VStack(spacing: 8) {
                Text(camera.status).font(.footnote).foregroundStyle(.white)
                exposureControl
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
            HStack(spacing: 8) {
                filmSimulationMenu
                Button {
                    camera.setFocalLength(camera.focalLength.next)
                } label: {
                    Text(camera.focalLength.displayName)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("画角 \(camera.focalLength.displayName)")
            }
            if camera.isAEAFLocked {
                Text("AE/AF LOCK")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.yellow, in: Capsule())
                    .foregroundStyle(.black)
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

    private var filmSimulationMenu: some View {
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
    }

    /// Capture-time exposure compensation, 1/3 EV per press.
    private var exposureControl: some View {
        HStack(spacing: 20) {
            Button { camera.stepExposureBias(by: -1) } label: {
                Image(systemName: "minus.circle")
            }
            .accessibilityLabel("露出補正を下げる")
            Text(ExposureCompensation.label(camera.exposureBias))
                .monospacedDigit()
                .frame(minWidth: 56)
            Button { camera.stepExposureBias(by: 1) } label: {
                Image(systemName: "plus.circle")
            }
            .accessibilityLabel("露出補正を上げる")
        }
        .font(.title2)
        .foregroundStyle(camera.exposureBias == 0 ? Color.white : Color.yellow)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(.black.opacity(0.5), in: Capsule())
        .disabled(!camera.isReady)
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
