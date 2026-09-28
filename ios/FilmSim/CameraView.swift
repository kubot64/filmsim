import FilmSimCore
import SwiftUI

/// Live preview with the film simulation (close in look, not a match: #50), shutter, RAW capture.
/// Tap the preview to focus and meter there until the next tap, long-press for AE/AF lock.
/// The ± buttons set capture-time exposure compensation; the mm button steps the focal length.
/// Shots are developed with the last-used recipe, shared with the develop screen (#8).
/// The film simulation can be switched here; other settings come from the develop screen.
struct CameraView: View {
    @StateObject private var camera = CameraController()
    @ObservedObject private var recipes = RecipeStore.shared

    private var currentRecipe: Recipe { recipes.selected.recipe }

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(
                renderer: camera.previewRenderer,
                focusPoint: camera.focusViewPoint,
                isLocked: camera.isAEAFLocked
            ) { point, lock in
                camera.focusAndExpose(atView: point, lock: lock)
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .ignoresSafeArea()
            VStack(spacing: 8) {
                Text(camera.status).font(.footnote).foregroundStyle(.white)
                exposureControl
                Button {
                    camera.capture(recipe: recipes.selected)
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
        .task(id: currentRecipe) { await camera.updatePreviewLook(currentRecipe) }
    }

    private var recipeBar: some View {
        let summary = currentRecipe.adjustmentSummary
        return VStack(spacing: 4) {
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
            if !summary.isEmpty {
                Text(summary)
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
            RecipePicker(title: "レシピ")
        } label: {
            Label(recipes.selected.name, systemImage: "camera.filters")
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
}
