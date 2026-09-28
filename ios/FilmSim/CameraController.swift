import AVFoundation
import FilmSimCore
import SwiftUI

/// AVFoundation session configured for Bayer RAW. Requests the largest photo size, but 48MP
/// main cameras return 12MP Bayer RAW (DESIGN.md "入力形式").
@MainActor
final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    /// Frames for the live preview with the film simulation (#50).
    private let videoOutput = AVCaptureVideoDataOutput()
    let previewRenderer = PreviewRenderer()
    private var device: AVCaptureDevice?
    /// How the phone is held, for the shot's orientation (#44). The interface stays portrait.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var inflight: [Int64: PendingCapture] = [:]

    @Published var isReady = false
    @Published var status = "起動中…"
    /// 35mm-equivalent crop for the next shot. Stored under `FocalLength.storageKey`,
    /// which the settings and develop screens also write.
    @Published private(set) var focalLength = FocalLength.stored()
    /// Format width/height of the active camera. 4:3 until the format is known.
    @Published private(set) var sensorAspect = PreviewGeometry.defaultSensorAspect
    /// The part of the sensor the preview shows, which is what the shot keeps.
    var previewCrop: CGRect { PreviewGeometry.crop(sensorAspect: sensorAspect, focalLength: focalLength) }
    /// Capture-time exposure compensation in EV (`ExposureCompensation`), separate from the recipe's.
    /// Stored under `ExposureCompensation.storageKey`, which the settings screen also writes.
    @Published private(set) var exposureBias = ExposureCompensation.stored()
    /// Set by a long press on the preview; cleared by the next tap.
    @Published var isAEAFLocked = false
    /// Where focus and exposure are measured, as a point on the preview (0...1, top-left origin).
    /// Kept in screen terms like a camera's AF point (#46): changing the focal length keeps the
    /// frame where it is on screen and focuses on whatever is there now.
    @Published private(set) var focusViewPoint = CGPoint(x: 0.5, y: 0.5)

    struct PendingCapture {
        /// The recipe and focal length when the shutter was pressed; a later change applies to the next shot.
        let recipe: Recipe
        let focalLength: FocalLength
        var rawData: Data?
        var processedData: Data?
    }

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            status = "カメラの許可がありません"; return
        }
        // `.task` runs again each time the Camera tab reappears; configure the session only once.
        guard device == nil else {
            // The settings screen may have changed the stored values while this tab was away.
            applyStoredExposureBias()
            setFocalLength(FocalLength.stored())
            Task.detached { [session] in if !session.isRunning { session.startRunning() } }
            return
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            status = "広角カメラがありません"; return
        }
        switch PhotoSessionBuilder.configurePhotoSession(session, device: device, output: output) {
        case .failure(let message):
            status = message
            return
        case .success(let info):
            self.device = device
            if let aspect = info.sensorAspect { sensorAspect = aspect }
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            addPreviewOutput()
            setFocalLength(FocalLength.stored())
            applyStoredExposureBias()
            reportBayerStatus(maxPhotoSize: info.maxPhotoSize, dimensionList: info.dimensionList)
        }
        Task.detached { [session] in session.startRunning() }
    }

    /// Frames stay in the sensor-native orientation; `PreviewRenderer` crops and turns them.
    private func addPreviewOutput() {
        guard let previewRenderer else { return }
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(previewRenderer, queue: previewRenderer.sampleQueue)
        session.beginConfiguration()
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        session.commitConfiguration()
    }

    /// Film simulation for the live preview. Loads the LUT the same way the develop step does.
    func updatePreviewLook(_ recipe: Recipe) async {
        let pipeline = await Developer.shared.pipeline(for: recipe)
        previewRenderer?.setLook(pipeline, recipe: recipe)
    }

    private func reportBayerStatus(maxPhotoSize: String, dimensionList: String) {
        let bayer = output.bayerRAWFormats
        if maxPhotoSize.isEmpty {
            status = "写真フォーマットがありません"
            isReady = false
            return
        }
        // The requested size is not the RAW size: 48MP main cameras return 12MP Bayer RAW (#5).
        status = "Bayer RAW \(bayer.count)（写真の最大 \(maxPhotoSize)、候補 \(dimensionList)）"
        isReady = !bayer.isEmpty
        if !isReady {
            status += output.availableRawPhotoPixelFormatTypes.isEmpty ? " — RAW なし" : " — Bayer RAW なし"
        }
    }

    /// Only the crop changes: the whole sensor is still captured, and the preview crops to match.
    /// The focus frame stays put on screen, so the device point under it is set again.
    func setFocalLength(_ newValue: FocalLength) {
        focalLength = newValue
        UserDefaults.standard.set(newValue.rawValue, forKey: FocalLength.storageKey)
        previewRenderer?.setFocalLength(newValue)
        focusAndExpose(atView: focusViewPoint, lock: isAEAFLocked)
    }

    /// Moves the exposure compensation by `steps` thirds of a stop. The preview shows the change live.
    func stepExposureBias(by steps: Int) {
        setExposureBias(exposureBias, steps: steps)
    }

    private func applyStoredExposureBias() {
        setExposureBias(ExposureCompensation.stored(), steps: 0)
    }

    /// Snaps `ev + steps` thirds to the grid and the device range, sets it on the device and stores it.
    private func setExposureBias(_ ev: Float, steps: Int) {
        guard let device else { return }
        let target = ExposureCompensation.stepped(
            ev,
            by: steps,
            deviceRange: device.minExposureTargetBias...device.maxExposureTargetBias
        )
        do {
            try device.withLockedConfiguration {
                $0.setExposureTargetBias(target, completionHandler: nil)
            }
            exposureBias = target
            ExposureCompensation.store(target)
        } catch {
            status = "露出補正を変えられません: \(error.localizedDescription)"
        }
    }

    /// `viewPoint` is normalized to the preview (`PreviewGeometry`).
    /// A tap keeps focusing and metering at the point until the next tap, like a fixed AF point (#46);
    /// it does not go back to the centre when the scene changes. A long press (`lock`) measures once
    /// and holds until the next tap. The exposure compensation still applies while exposure is held.
    func focusAndExpose(atView viewPoint: CGPoint, lock: Bool) {
        focusViewPoint = viewPoint
        applyFocusAndExposure(
            at: PreviewGeometry.devicePoint(fromView: viewPoint, crop: previewCrop),
            focus: lock ? .autoFocus : .continuousAutoFocus,
            exposure: lock ? .autoExpose : .continuousAutoExposure,
            locked: lock,
            failureStatus: "ピントと露出を合わせられません"
        )
    }

    private func applyFocusAndExposure(
        at point: CGPoint,
        focus: AVCaptureDevice.FocusMode,
        exposure: AVCaptureDevice.ExposureMode,
        locked: Bool,
        failureStatus: String
    ) {
        guard let device else { return }
        do {
            try device.withLockedConfiguration {
                if $0.isFocusPointOfInterestSupported, $0.isFocusModeSupported(focus) {
                    $0.focusPointOfInterest = point
                    $0.focusMode = focus
                }
                if $0.isExposurePointOfInterestSupported, $0.isExposureModeSupported(exposure) {
                    $0.exposurePointOfInterest = point
                    $0.exposureMode = exposure
                }
            }
            isAEAFLocked = locked
        } catch {
            status = "\(failureStatus): \(error.localizedDescription)"
        }
    }

    func capture(recipe: Recipe) {
        guard let rawType = output.bayerRAWFormats.first else {
            status = "Bayer RAW のピクセルフォーマットがありません"; return
        }
        let settings = AVCapturePhotoSettings(rawPixelFormatType: rawType, processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc])
        settings.maxPhotoDimensions = output.maxPhotoDimensions
        // Record how the phone is held; the DNG keeps the sensor-native pixels and an orientation tag,
        // and the develop step crops before turning (#44).
        if let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture,
           let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        // photoQualityPrioritization must stay at its default: setting it on RAW settings throws.
        inflight[settings.uniqueID] = PendingCapture(recipe: recipe, focalLength: focalLength)
        output.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let id = photo.resolvedSettings.uniqueID
        let isRaw = photo.isRawPhoto
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            if isRaw { self.inflight[id]?.rawData = data } else { self.inflight[id]?.processedData = data }
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        let id = resolvedSettings.uniqueID
        let rawDims = resolvedSettings.rawPhotoDimensions
        Task { @MainActor in
            guard let pending = self.inflight.removeValue(forKey: id) else { return }
            if let err = error { self.status = "撮影に失敗しました: \(err.localizedDescription)"; return }
            guard let raw = pending.rawData else { self.status = "RAW データが返りませんでした"; return }
            let saved = await Developer.shared.developAndSave(
                rawData: raw,
                saveDNG: UserDefaults.standard.bool(forKey: AppPreferences.saveDNGKey),
                recipe: pending.recipe,
                focalLength: pending.focalLength
            )
            self.status = "RAW \(rawDims.width)x\(rawDims.height)、\(raw.count / 1_000_000)MB。\(saved.message)"
        }
    }
}
