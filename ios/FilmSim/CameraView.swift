import FilmSimCore
import SwiftUI

/// The whole app opens here (#55): a full-screen camera, with Settings behind the gear.
/// Live preview with the recipe's look (close in look, not a match: #50). Tap the preview to focus
/// and meter there until the next tap, long-press for AE/AF lock.
/// Below the preview, from the top: focal-length buttons, the recipe strip, and the row of
/// thumbnail, shutter and exposure compensation. The screen is portrait-locked; held sideways,
/// everything stays where it is and only labels and icons turn (like the system Camera app).
/// Taking a photo darkens the preview for a moment. Volume buttons take one too (iOS 17.2+).
struct CameraView: View {
    @StateObject private var camera = CameraController()
    @ObservedObject private var recipes = RecipeStore.shared
    @ObservedObject private var shots = ShotStore.shared
    @AppStorage(AppPreferences.showStatusKey) private var showStatus = false
    @State private var showsSettings = false
    @State private var showsReview = false
    @State private var shownNotice: CameraController.Notice?
    /// The recipe strip's place shows the exposure dial (#56) while this is set.
    @State private var adjustingExposure = false
    /// Bumped on every dial movement, restarting the wait before the strip comes back.
    @State private var exposureTouches = 0
    /// Set while the dial is being swiped or is still gliding; the strip never comes back then.
    @State private var dialMoving = false

    private var currentRecipe: Recipe { recipes.selected.recipe }
    private var rotation: Double { camera.controlRotation }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            CameraPreview(
                renderer: camera.previewRenderer,
                focusPoint: camera.focusViewPoint,
                isLocked: camera.isAEAFLocked,
                controlRotation: rotation,
                shutterFlash: camera.shutterFlash,
                hardwareShutterEnabled: camera.isReady && !showsSettings && !showsReview,
                onFocus: { point, lock in
                    camera.focusAndExpose(atView: point, lock: lock)
                },
                onHardwareShutter: {
                    camera.capture(recipe: recipes.selected)
                }
            )
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
        .task(id: "\(exposureTouches) \(dialMoving)") {
            guard adjustingExposure, !dialMoving else { return }
            // A newer touch cancels this wait; a cancelled sleep throws, and must not close the dial.
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            withAnimation { adjustingExposure = false }
        }
        .task(id: camera.notice) {
            guard let notice = camera.notice else { return }
            withAnimation { shownNotice = notice }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
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
            if adjustingExposure {
                ExposureDial(value: camera.exposureBias, rotation: rotation) { ev in
                    camera.setExposureBias(to: ev)
                    exposureTouches += 1
                } onMoving: { moving in
                    dialMoving = moving
                }
                .transition(.opacity)
            } else {
                RecipeStrip(recipes: recipes.book.visible, selection: recipes.selection, rotation: rotation)
                    .transition(.opacity)
            }
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

    /// The last shot. Spins while the next one is developing, then shows that photo. Opens review (#57).
    private var thumbnail: some View {
        Button { showsReview = true } label: { thumbnailImage }
            .accessibilityLabel(camera.isDeveloping ? "現像中。撮った写真を見る" : "撮った写真を見る")
    }

    private var thumbnailImage: some View {
        ZStack {
            if let image = shots.latestThumbnail {
                Image(uiImage: image).resizable().scaledToFill()
            }
            if camera.isDeveloping {
                Color.black.opacity(0.45)
                ProgressView()
                    .tint(.white)
                    .accessibilityHidden(true)
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

    /// Capture-time exposure compensation. Pressing it swaps the recipe strip for the dial;
    /// pressing again, or leaving the dial alone for 3 seconds, brings the strip back.
    private var exposureButton: some View {
        Button {
            withAnimation { adjustingExposure.toggle() }
            exposureTouches += 1
        } label: {
            Text(ExposureCompensation.label(camera.exposureBias))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(camera.exposureBias == 0 ? Color.white : Color.yellow)
                .rotationEffect(.degrees(rotation))
                .frame(width: 52, height: 52)
                .background(.black.opacity(adjustingExposure ? 0.7 : 0.4), in: Circle())
                .overlay(Circle().stroke(adjustingExposure ? Color.yellow : .white.opacity(0.6), lineWidth: adjustingExposure ? 2 : 1))
        }
        .disabled(!camera.isReady)
        .accessibilityLabel("露出補正 \(ExposureCompensation.label(camera.exposureBias))")
        .accessibilityHint("押すと目盛りで変えられる")
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

/// Exposure compensation from −3 to +3 in thirds, like the X100's dial (#56). Swipe sideways; the
/// stop under the yellow mark in the middle is set at once, so the preview brightens or darkens
/// while the dial moves. Tapping a stop scrolls it to the middle. Whole stops are numbered.
private struct ExposureDial: View {
    let value: Float
    let rotation: Double
    let onChange: (Float) -> Void
    /// True from the finger touching down until the dial stops gliding (iOS 18 and later).
    let onMoving: (Bool) -> Void
    @State private var centred: Int?

    private let tick: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(ExposureCompensation.dialThirds, id: \.self) { thirds in
                        let whole = thirds % ExposureCompensation.stepsPerEV == 0
                        VStack(spacing: 4) {
                            Rectangle()
                                .fill(Color.white.opacity(whole ? 1 : 0.6))
                                .frame(width: 1.5, height: whole ? 14 : 8)
                            Text(whole ? ExposureCompensation.label(ExposureCompensation.ev(thirds: thirds)) : "")
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .fixedSize()
                                .rotationEffect(.degrees(rotation))
                                .frame(height: 18)
                        }
                        .frame(width: tick, height: 44, alignment: .top)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation { centred = thirds } }
                        .id(thirds)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, max(0, (geo.size.width - tick) / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centred, anchor: .center)
            .reportsScrolling(onMoving)
        }
        .frame(height: 44)
        .overlay(alignment: .top) {
            Capsule().fill(Color.yellow).frame(width: 3, height: 20).offset(y: -3)
        }
        .onAppear { centred = ExposureCompensation.thirds(value) }
        .onDisappear { onMoving(false) }
        .onChange(of: centred) { _, thirds in
            guard let thirds, thirds != ExposureCompensation.thirds(value) else { return }
            onChange(ExposureCompensation.ev(thirds: thirds))
        }
        // The device may clamp to a narrower range; follow what was actually set.
        .onChange(of: value) { _, ev in
            let thirds = ExposureCompensation.thirds(ev)
            if centred != thirds { withAnimation { centred = thirds } }
        }
        .sensoryFeedback(.selection, trigger: centred)
        .accessibilityElement()
        .accessibilityLabel("露出補正")
        .accessibilityValue(ExposureCompensation.label(value))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 1 : -1
            let next = ExposureCompensation.thirds(value) + step
            guard ExposureCompensation.dialThirds.contains(next) else { return }
            onChange(ExposureCompensation.ev(thirds: next))
        }
    }
}

private extension View {
    /// Calls `report` with whether the scroll view is being touched or still moving. iOS 17 has no
    /// scroll phase, so there it never reports and the dial simply closes 3 seconds after its last change.
    @ViewBuilder
    func reportsScrolling(_ report: @escaping (Bool) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            onScrollPhaseChange { _, phase in report(phase != .idle) }
        } else {
            self
        }
    }
}
