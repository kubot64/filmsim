import AVFoundation
import Photos
import SwiftUI

/// AVFoundation session configured for Bayer RAW at the sensor's full resolution.
@MainActor
final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var inflight: [Int64: PendingCapture] = [:]

    @Published var isReady = false
    @Published var status = "starting…"

    struct PendingCapture {
        var rawData: Data?
        var processedData: Data?
    }

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            status = "camera permission denied"; return
        }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else {
            status = "no wide camera"; session.commitConfiguration(); return
        }
        self.device = device
        session.addInput(input)
        session.addOutput(output)

        // Pick the highest-resolution photo format (48MP on iPhone 15/16/17 main camera).
        if let format = device.formats
            .filter({ $0.mediaType == .video })
            .max(by: { ($0.supportedMaxPhotoDimensions.last?.width ?? 0) < ($1.supportedMaxPhotoDimensions.last?.width ?? 0) }),
           let dims = format.supportedMaxPhotoDimensions.last {
            try? device.lockForConfiguration()
            device.activeFormat = format
            device.unlockForConfiguration()
            output.maxPhotoDimensions = dims
            status = "max photo \(dims.width)x\(dims.height), raw formats: \(output.availableRawPhotoPixelFormatTypes.count)"
        }
        output.maxPhotoQualityPrioritization = .quality
        session.commitConfiguration()

        Task.detached { [session] in session.startRunning() }
        isReady = !output.availableRawPhotoPixelFormatTypes.isEmpty
        if !isReady { status += " — no Bayer RAW format available" }
    }

    func capture() {
        // Bayer RAW (not ProRAW): works on non-Pro models too.
        guard let rawType = output.availableRawPhotoPixelFormatTypes.first(where: { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }) ?? output.availableRawPhotoPixelFormatTypes.first else {
            status = "no RAW pixel format"; return
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
            if let err = error { self.status = "capture failed: \(err.localizedDescription)"; return }
            guard let raw = pending.rawData else { self.status = "no RAW data returned"; return }
            self.status = "RAW \(raw.count / 1_000_000) MB captured"
            await Developer.shared.developAndSave(rawData: raw, saveDNG: UserDefaults.standard.bool(forKey: "saveDNG"))
        }
    }
}

/// UIKit bridge for the live preview.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspect
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
