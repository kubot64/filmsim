import AVFoundation
import FilmSimCore
import SwiftUI

/// AVFoundation session configured for Bayer RAW at the sensor's full resolution.
@MainActor
final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var inflight: [Int64: PendingCapture] = [:]

    @Published var isReady = false
    @Published var status = "起動中…"
    /// Aspect-fill zoom so the portrait 2:3 preview matches the 35mm crop. 4:3 until the format is known.
    @Published var previewZoom: CGFloat = PreviewFraming.defaultZoom

    struct PendingCapture {
        var rawData: Data?
        var processedData: Data?
    }

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            status = "カメラの許可がありません"; return
        }
        // `.task` runs again each time the Camera tab reappears; configure the session only once.
        guard device == nil else {
            Task.detached { [session] in if !session.isRunning { session.startRunning() } }
            return
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            status = "広角カメラがありません"; return
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            status = "カメラを開けません: \(error.localizedDescription)"; return
        }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddInput(input) else {
            status = "カメラ入力を追加できません"; session.commitConfiguration(); return
        }
        guard session.canAddOutput(output) else {
            status = "写真出力を追加できません"; session.commitConfiguration(); return
        }
        self.device = device
        session.addInput(input)
        session.addOutput(output)
        if output.isAppleProRAWSupported {
            output.isAppleProRAWEnabled = false
        }

        // Keep the format the .photo preset picks. The main camera lists two 48MP formats;
        // on iPhone 15 Pro Max only the preset's one offers Bayer RAW,
        // so choosing "the largest format" ourselves can land on one with no RAW at all.
        let format = device.activeFormat
        var photoDims: CMVideoDimensions?
        var dimensionList = ""
        if let dims = format.supportedMaxPhotoDimensions.last {
            output.maxPhotoDimensions = dims
            let video = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            if video.height > 0 {
                previewZoom = CGFloat(PreviewFraming.zoom(
                    sensorAspectWidthOverHeight: Double(video.width) / Double(video.height)
                ))
            }
            photoDims = dims
            dimensionList = format.supportedMaxPhotoDimensions.map { "\($0.width)x\($0.height)" }.joined(separator: ", ")
        } else {
            status = "写真フォーマットがありません"
        }
        output.maxPhotoQualityPrioritization = .quality
        session.commitConfiguration()

        // Raw formats are valid only after the configuration is committed.
        if let dims = photoDims {
            let bayer = output.availableRawPhotoPixelFormatTypes.filter { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
            // The requested size is not the RAW size: 48MP main cameras return 12MP Bayer RAW (#5).
            // The real size is shown after the first capture.
            status = "Bayer RAW \(bayer.count)（写真の最大 \(dims.width)x\(dims.height)、候補 \(dimensionList)）"
            isReady = !bayer.isEmpty
            if !isReady {
                status += output.availableRawPhotoPixelFormatTypes.isEmpty ? " — RAW なし" : " — Bayer RAW なし"
            }
        }

        Task.detached { [session] in session.startRunning() }
    }

    func capture() {
        // Bayer RAW (not ProRAW): works on non-Pro models too.
        guard let rawType = output.availableRawPhotoPixelFormatTypes.first(where: { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }) else {
            status = "Bayer RAW のピクセルフォーマットがありません"; return
        }
        let settings = AVCapturePhotoSettings(rawPixelFormatType: rawType, processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc])
        settings.maxPhotoDimensions = output.maxPhotoDimensions
        // photoQualityPrioritization must stay at its default: setting it on RAW settings throws.
        inflight[settings.uniqueID] = PendingCapture()
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
                saveDNG: UserDefaults.standard.bool(forKey: "saveDNG")
            )
            self.status = "RAW \(rawDims.width)x\(rawDims.height)、\(raw.count / 1_000_000)MB。\(saved.message)"
        }
    }
}

/// UIKit bridge for the live preview.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var zoom: CGFloat

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.zoom = zoom
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.zoom = zoom
        uiView.setNeedsLayout()
    }

    /// The preview layer is a sublayer, larger than the view by `zoom`, so a 2:3 clip
    /// shows the same center crop `SensorCrop` applies before the shot is turned upright.
    final class PreviewView: UIView {
        let videoPreviewLayer = AVCaptureVideoPreviewLayer()
        var zoom: CGFloat = PreviewFraming.defaultZoom

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            videoPreviewLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(videoPreviewLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
