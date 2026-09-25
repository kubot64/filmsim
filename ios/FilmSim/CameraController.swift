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
    /// Aspect-fill zoom so the 3:2 preview matches the 35mm crop. 4:3 until the format is known.
    @Published var previewZoom: CGFloat = 35.0 / 24.0

    struct PendingCapture {
        var rawData: Data?
        var processedData: Data?
    }

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            status = "カメラの許可がありません"; return
        }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else {
            status = "広角カメラがありません"; session.commitConfiguration(); return
        }
        self.device = device
        session.addInput(input)
        session.addOutput(output)
        if output.isAppleProRAWSupported {
            output.isAppleProRAWEnabled = false
        }

        // Pick the highest-resolution photo format (48MP on iPhone 15/16/17 main camera).
        var photoDims: CMVideoDimensions?
        var dimensionList = ""
        if let format = device.formats
            .filter({ $0.mediaType == .video })
            .max(by: { ($0.supportedMaxPhotoDimensions.last?.width ?? 0) < ($1.supportedMaxPhotoDimensions.last?.width ?? 0) }),
           let dims = format.supportedMaxPhotoDimensions.last {
            try? device.lockForConfiguration()
            device.activeFormat = format
            device.unlockForConfiguration()
            output.maxPhotoDimensions = dims
            let video = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            if video.height > 0 {
                previewZoom = CGFloat(SensorCrop.previewZoom(
                    videoAspectWidthOverHeight: Double(video.width) / Double(video.height)
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
            status = "写真 \(dims.width)x\(dims.height)、Bayer RAW \(bayer.count)（候補 \(dimensionList)）"
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
        settings.photoQualityPrioritization = .quality
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
        Task { @MainActor in
            guard let pending = self.inflight.removeValue(forKey: id) else { return }
            if let err = error { self.status = "撮影に失敗しました: \(err.localizedDescription)"; return }
            guard let raw = pending.rawData else { self.status = "RAW データが返りませんでした"; return }
            let saved = await Developer.shared.developAndSave(
                rawData: raw,
                saveDNG: UserDefaults.standard.bool(forKey: "saveDNG")
            )
            self.status = "RAW \(raw.count / 1_000_000)MB。\(saved)"
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

    /// The preview layer is a sublayer, larger than the view by `zoom`, so a 3:2 clip
    /// shows the same center crop `SensorCrop` applies to the saved image.
    final class PreviewView: UIView {
        let videoPreviewLayer = AVCaptureVideoPreviewLayer()
        var zoom: CGFloat = 35.0 / 24.0

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
        }
    }
}
