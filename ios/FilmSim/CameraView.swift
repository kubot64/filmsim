import FilmSimCore
import SwiftUI

/// The whole app opens here (#55): a full-screen camera, with Settings behind the gear.
/// Live preview with the recipe's look (close in look, not a match: #50). Tap the preview to focus
/// and meter there until the next tap, long-press for AE/AF lock.
/// Below the preview, from the top: focal-length buttons, the recipe strip, and the row of
/// thumbnail, shutter and exposure compensation. The screen is portrait-locked; held sideways,
/// everything stays where it is and only labels and icons turn (like the system Camera app).
struct CameraView: View {
    @StateObject private var camera = CameraController()
    @ObservedObject private var recipes = RecipeStore.shared
    @ObservedObject private var shots = ShotStore.shared
    @AppStorage(AppPreferences.showStatusKey) private var showStatus = false
    @State private var showsSettings = false
    @State private var showsReview = false
    @State private var shownNotice: CameraController.Notice?

    private var currentRecipe: Recipe { recipes.selected.recipe }
    private var rotation: Double { camera.controlRotation }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            CameraPreview(
                renderer: camera.previewRenderer,
                focusPoint: camera.focusViewPoint,
                isLocked: camera.isAEAFLocked,
                controlRotation: rotation
            ) { point, lock in
                camera.focusAndExpose(atView: point, lock: lock)
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            VStack(spacing: 0) {
                topBar
                if let shownNotice { noticeView(shownNotice.text) }
                Spacer(minLength: 0)
                if showStatus {
                    Text(camera.status)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }
                controls
            }
        }
        .animation(.easeInOut(duration: 0.25), value: rotation)
        .sheet(isPresented: $showsSettings, onDismiss: camera.applyStoredSettings) { SettingsView() }
        .fullScreenCover(isPresented: $showsReview) { ReviewView() }
        .task { await camera.start() }
        .task(id: currentRecipe) { await camera.updatePreviewLook(currentRecipe) }
        .task(id: camera.notice) {
            guard let notice = camera.notice else { return }
            withAnimation { shownNotice = notice }
            try? await Task.sleep(for: .seconds(3))
            withAnimation { if shownNotice == notice { shownNotice = nil } }
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button { showsSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(rotation))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .accessibilityLabel("設定")
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private func noticeView(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.7), in: Capsule())
            .rotationEffect(.degrees(rotation))
            .padding(.top, 8)
            .transition(.opacity)
    }

    /// Taps anywhere on this panel stay here, so a near miss on a button does not reach the
    /// preview and move the focus.
    private var controls: some View {
        VStack(spacing: 10) {
            focalLengthButtons
            RecipeStrip(recipes: recipes.book.visible, selection: recipes.selection, rotation: rotation)
            HStack {
                thumbnail
                Spacer()
                shutter
                Spacer()
                exposureButton
            }
            .padding(.horizontal, 28)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.35))
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var focalLengthButtons: some View {
        HStack(spacing: 8) {
            ForEach(FocalLength.allCases, id: \.self) { focal in
                let selected = focal == camera.focalLength
                Button { camera.setFocalLength(focal) } label: {
                    Text("\(focal.rawValue)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(selected ? Color.yellow : Color.white)
                        .rotationEffect(.degrees(rotation))
                        .frame(width: 40, height: 32)
                        .background(.black.opacity(selected ? 0.6 : 0.3), in: Capsule())
                }
                .accessibilityLabel("画角 \(focal.displayName)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    /// The last shot. Opens the review screen (#57).
    private var thumbnail: some View {
        Button { showsReview = true } label: { thumbnailImage }
            .accessibilityLabel("撮った写真を見る")
    }

    private var thumbnailImage: some View {
        Group {
            if let image = shots.latestThumbnail {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.clear
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.6), lineWidth: 1))
        .rotationEffect(.degrees(rotation))
    }

    private var shutter: some View {
        Button {
            camera.capture(recipe: recipes.selected)
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                Circle().fill(.white).frame(width: 64, height: 64)
            }
        }
        .disabled(!camera.isReady)
        .accessibilityLabel("シャッター")
    }

    /// Shows the capture-time exposure compensation. Turns into a dial in #56; until then it is
    /// changed in Settings.
    private var exposureButton: some View {
        Text(ExposureCompensation.label(camera.exposureBias))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(camera.exposureBias == 0 ? Color.white : Color.yellow)
            .rotationEffect(.degrees(rotation))
            .frame(width: 52, height: 52)
            .background(.black.opacity(0.4), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
            .accessibilityLabel("露出補正 \(ExposureCompensation.label(camera.exposureBias))")
    }
}

/// The saved recipes in a row that scrolls sideways; the one in the middle is the one in use.
/// Tapping a name scrolls it to the middle. Held sideways, each name turns to read upright and
/// the row gets taller to fit it.
private struct RecipeStrip: View {
    let recipes: [SavedRecipe]
    @Binding var selection: UUID
    let rotation: Double
    @State private var centred: UUID?

    var body: some View {
        let sideways = HoldingOrientation.isSideways(rotation)
        let item = sideways ? CGSize(width: 44, height: 100) : CGSize(width: 108, height: 34)
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(recipes) { recipe in
                        let selected = recipe.id == selection
                        Text(recipe.name)
                            .font(.subheadline.weight(selected ? .bold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(selected ? Color.yellow : Color.white.opacity(0.8))
                            .frame(width: 100, height: 30)
                            .rotationEffect(.degrees(rotation))
                            .frame(width: item.width, height: item.height)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation { centred = recipe.id } }
                            .id(recipe.id)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, max(0, (geo.size.width - item.width) / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centred, anchor: .center)
        }
        .frame(height: item.height)
        .onAppear { centred = selection }
        .onChange(of: centred) { _, id in
            if let id, id != selection { selection = id }
        }
        .onChange(of: selection) { _, id in
            if centred != id { withAnimation { centred = id } }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("レシピ")
    }
}
