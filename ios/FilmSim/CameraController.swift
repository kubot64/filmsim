import AVFoundation
import FilmSimCore
import SwiftUI

/// AVFoundation session configured for Bayer RAW. Requests the largest photo size, but 48MP
/// main cameras return 12MP Bayer RAW (DESIGN.md "入力形式").
@MainActor
final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var inflight: [Int64: PendingCapture] = [:]

    @Published var isReady = false
    @Published var status = "起動中…"
    /// 35mm-equivalent crop for the next shot. Stored under `FocalLength.storageKey`,
    /// which the settings and develop screens also write.
    @Published private(set) var focalLength = FocalLength.stored()
    /// Format width/height of the active camera. 4:3 until the format is known.
    private var sensorAspect = PreviewFraming.defaultSensorAspect
    /// Aspect-fill zoom so the portrait 2:3 preview matches the focal-length crop.
    @Published private(set) var previewZoom = CGFloat(1)
    /// Capture-time exposure compensation in EV (`ExposureCompensation`), separate from the recipe's.
    /// Stored under `ExposureCompensation.storageKey`, which the settings screen also writes.
    @Published private(set) var exposureBias = ExposureCompensation.stored()
    /// Set by a long press on the preview; cleared by the next tap.
    @Published var isAEAFLocked = false
    private var subjectAreaObserver: NSObjectProtocol?

    struct PendingCapture {
        /// The recipe and focal length when the shutter was pressed; a later change applies to the next shot.
        let recipe: Recipe
        let focalLength: FocalLength
        var rawData: Data?
        var processedData: Data?
    }

    override init() {
        super.init()
        updatePreviewZoom()
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
            subjectAreaObserver = NotificationCenter.default.addObserver(
                forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: device, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.resumeContinuousFocusAndExposure() }
            }
            output.maxPhotoQualityPrioritization = .quality
            setFocalLength(FocalLength.stored())
            applyStoredExposureBias()
            reportBayerStatus(maxPhotoSize: info.maxPhotoSize, dimensionList: info.dimensionList)
        }
        Task.detached { [session] in session.startRunning() }
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

    /// Only the crop changes: the whole sensor is still captured, and the preview zooms to match.
    func setFocalLength(_ newValue: FocalLength) {
        focalLength = newValue
        UserDefaults.standard.set(newValue.rawValue, forKey: FocalLength.storageKey)
        updatePreviewZoom()
    }

    private func updatePreviewZoom() {
        previewZoom = CGFloat(PreviewFraming.zoom(
            sensorAspectWidthOverHeight: sensorAspect,
            focalLength: focalLength
        ))
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

    /// `devicePoint` is in the device's normalized space (0...1, sensor orientation).
    /// `.autoFocus` and `.autoExpose` measure once at the point and then hold. A tap goes back
    /// to continuous auto when the scene changes; a long press (`lock`) holds until the next tap.
    /// The exposure compensation still applies while exposure is held.
    func focusAndExpose(at devicePoint: CGPoint, lock: Bool) {
        applyFocusAndExposure(
            at: devicePoint,
            focus: .autoFocus,
            exposure: .autoExpose,
            monitorSubjectArea: !lock,
            locked: lock,
            failureStatus: "ピントと露出を合わせられません"
        )
    }

    /// After a tap, the scene changed: back to continuous auto on the frame center.
    private func resumeContinuousFocusAndExposure() {
        guard !isAEAFLocked else { return }
        applyFocusAndExposure(
            at: CGPoint(x: 0.5, y: 0.5),
            focus: .continuousAutoFocus,
            exposure: .continuousAutoExposure,
            monitorSubjectArea: false,
            locked: false,
            failureStatus: "ピントと露出を自動に戻せません"
        )
    }

    private func applyFocusAndExposure(
        at point: CGPoint,
        focus: AVCaptureDevice.FocusMode,
        exposure: AVCaptureDevice.ExposureMode,
        monitorSubjectArea: Bool,
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
                $0.isSubjectAreaChangeMonitoringEnabled = monitorSubjectArea
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

/// UIKit bridge for the live preview.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var zoom: CGFloat
    /// Device point (normalized, sensor orientation) and whether it was a long press (AE/AF lock).
    var onFocus: (CGPoint, Bool) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.zoom = zoom
        v.onFocus = onFocus
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.zoom = zoom
        uiView.onFocus = onFocus
        uiView.setNeedsLayout()
    }

    /// The preview layer is a sublayer, larger than the view by `zoom`, so a 2:3 clip
    /// shows the same center crop `SensorCrop` applies before the shot is turned upright.
    final class PreviewView: UIView {
        let videoPreviewLayer = AVCaptureVideoPreviewLayer()
        var zoom: CGFloat = 1
        var onFocus: ((CGPoint, Bool) -> Void)?
        /// Square drawn where the user tapped. Fades after a tap, stays while locked.
        private let focusMark = UIView(frame: CGRect(x: 0, y: 0, width: 72, height: 72))

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            videoPreviewLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(videoPreviewLayer)

            focusMark.layer.borderColor = UIColor.systemYellow.cgColor
            focusMark.layer.borderWidth = 1.5
            focusMark.isUserInteractionEnabled = false
            focusMark.alpha = 0
            addSubview(focusMark)

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.require(toFail: longPress)
            addGestureRecognizer(longPress)
            addGestureRecognizer(tap)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        @objc private func handleTap(_ g: UITapGestureRecognizer) {
            focus(at: g.location(in: self), lock: false)
        }

        @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began else { return }
            focus(at: g.location(in: self), lock: true)
        }

        /// The preview layer is larger than the view and rotated, so convert through the layer:
        /// it accounts for the zoom offset, aspect fill and the 90° rotation.
        private func focus(at viewPoint: CGPoint, lock: Bool) {
            let layerPoint = videoPreviewLayer.convert(viewPoint, from: layer)
            onFocus?(videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint), lock)

            focusMark.layer.removeAllAnimations()
            focusMark.center = viewPoint
            focusMark.alpha = 1
            focusMark.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            UIView.animate(withDuration: 0.2) { self.focusMark.transform = .identity }
            guard !lock else { return }
            UIView.animate(withDuration: 0.3, delay: 1.0, options: []) { self.focusMark.alpha = 0 }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let b = bounds
            let z = zoom > 0 ? zoom : 1
            videoPreviewLayer.frame = CGRect(
                x: b.midX - b.width * z / 2,
                y: b.midY - b.height * z / 2,
                width: b.width * z,
                height: b.height * z
            )
            applyPortraitRotationIfNeeded()
        }

        /// The interface is portrait-locked. The connection exists once the session
        /// configuration is committed, which can be before the first layout. Write 90°
        /// only when the current angle is something else, so a reset is corrected
        /// without assigning on every layout.
        private func applyPortraitRotationIfNeeded() {
            guard let connection = videoPreviewLayer.connection,
                  connection.isVideoRotationAngleSupported(90),
                  connection.videoRotationAngle != 90 else { return }
            connection.videoRotationAngle = 90
        }
    }
}
