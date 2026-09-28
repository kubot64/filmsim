import FilmSimCore
import SwiftUI

/// Live preview with the film simulation (close in look, not a match: #50), shutter, RAW capture.
/// Tap the preview to focus and meter there until the next tap, long-press for AE/AF lock.
/// The ± buttons (bottom right) set capture-time exposure compensation; the mm button steps the focal length.
/// The screen is portrait-locked; the controls turn and move so they sit where the holder expects
/// them in landscape too (#43). The shutter stays at the bottom centre.
/// Shots are developed with the last-used recipe, shared with the develop screen (#8).
/// The film simulation can be switched here; other settings come from the develop screen.
struct CameraView: View {
    @StateObject private var camera = CameraController()
    @AppStorage(Recipe.storageKey) private var storedRecipe = Data()
    /// Observed so the menu label updates when an imported LUT is deleted.
    @ObservedObject private var library = LUTLibrary.shared

    private var recipe: Binding<Recipe> { Recipe.binding($storedRecipe) }
    private var currentRecipe: Recipe { recipe.wrappedValue }

    var body: some View {
        ZStack {
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
                Spacer()
                // Kept clear of the exposure control at the bottom right (52pt wide, 16pt from the edge)
                // on both sides so it stays centred; long messages wrap instead of running under "+".
                Text(camera.status)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 76)
                Button {
                    camera.capture(recipe: currentRecipe)
                } label: {
                    Circle().fill(.white).frame(width: 72, height: 72)
                }
                .disabled(!camera.isReady)
            }
            .padding(.bottom, 24)
            HolderFrame(rotation: camera.controlRotation) {
                recipeBar
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                exposureControl
                    .padding(.trailing, 16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
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
            LookPicker(title: "Look", recipe: recipe)
        } label: {
            Label(
                library.title(for: currentRecipe.effectiveLook(importedNames: library.names)),
                systemImage: "camera.filters"
            )
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.5), in: Capsule())
                .foregroundStyle(.white)
        }
    }

    /// Capture-time exposure compensation, 1/3 EV per press. Stacked so it fits beside the shutter.
    /// Each button is 44pt, and taps between them are caught here so they do not reach the
    /// preview and move the focus.
    private var exposureControl: some View {
        VStack(spacing: 0) {
            Button { camera.stepExposureBias(by: 1) } label: {
                Image(systemName: "plus").frame(width: 44, height: 44)
            }
            .accessibilityLabel("露出補正を上げる")
            Text(ExposureCompensation.label(camera.exposureBias))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 44, minHeight: 24)
            Button { camera.stepExposureBias(by: -1) } label: {
                Image(systemName: "minus").frame(width: 44, height: 44)
            }
            .accessibilityLabel("露出補正を下げる")
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(camera.exposureBias == 0 ? Color.white : Color.yellow)
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(.black.opacity(0.5), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture {}
        .disabled(!camera.isReady)
    }
}

/// Lays `content` out in the frame the holder sees, then turns it by `rotation`, so alignments
/// such as `.bottomTrailing` mean the holder's bottom right even with the phone sideways.
private struct HolderFrame<Content: View>: View {
    let rotation: Double
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geo in
            let sideways = HoldingOrientation.isSideways(rotation)
            ZStack { content }
                .frame(
                    width: sideways ? geo.size.height : geo.size.width,
                    height: sideways ? geo.size.width : geo.size.height
                )
                .rotationEffect(.degrees(rotation))
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeInOut(duration: 0.25), value: rotation)
    }
}
