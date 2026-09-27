import AVFoundation
import FilmSimCore

/// Shared `.photo` preset session wiring for capture and the RAW survey.
enum PhotoSessionBuilder {
    struct Configured {
        let maxPhotoSize: String
        let sensorAspect: Double?
        let dimensionList: String
    }

    /// `Result`'s failure must be `Error`; Japanese status strings stay plain `String` here.
    enum Outcome {
        case success(Configured)
        case failure(String)
    }

    /// Adds a photo input/output for `device`, disables ProRAW listing noise, and sets the
    /// largest photo dimensions. Commits the configuration.
    static func configurePhotoSession(
        _ session: AVCaptureSession,
        device: AVCaptureDevice,
        output: AVCapturePhotoOutput
    ) -> Outcome {
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            return .failure("カメラを開けません: \(error.localizedDescription)")
        }
        session.beginConfiguration()
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return .failure("カメラ入力を追加できません")
        }
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return .failure("写真出力を追加できません")
        }
        session.addInput(input)
        session.addOutput(output)
        if output.isAppleProRAWSupported {
            output.isAppleProRAWEnabled = false
        }
        // Keep the format the .photo preset picks. The main camera lists two 48MP formats;
        // on iPhone 15 Pro Max only the preset's one offers Bayer RAW.
        let format = device.activeFormat
        var maxPhotoSize = ""
        var sensorAspect: Double?
        let dimensionList = format.supportedMaxPhotoDimensions
            .map { "\($0.width)x\($0.height)" }.joined(separator: ", ")
        if let dims = format.supportedMaxPhotoDimensions.last {
            output.maxPhotoDimensions = dims
            maxPhotoSize = "\(dims.width)x\(dims.height)"
            let video = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            if video.height > 0 {
                sensorAspect = Double(video.width) / Double(video.height)
            }
        }
        session.commitConfiguration()
        return .success(Configured(
            maxPhotoSize: maxPhotoSize,
            sensorAspect: sensorAspect,
            dimensionList: dimensionList
        ))
    }
}

extension AVCapturePhotoOutput {
    /// Bayer RAW pixel formats for the committed configuration (not ProRAW).
    var bayerRAWFormats: [OSType] {
        availableRawPhotoPixelFormatTypes.filter { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
    }
}

extension AVCaptureDevice {
    /// `lockForConfiguration` / unlock around `body`.
    func withLockedConfiguration(_ body: (AVCaptureDevice) throws -> Void) throws {
        try lockForConfiguration()
        defer { unlockForConfiguration() }
        try body(self)
    }
}
