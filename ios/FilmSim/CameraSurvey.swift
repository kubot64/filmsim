import AVFoundation

/// What one physical camera offers under the `.photo` preset, the same setup `CameraController` uses.
struct CameraRawSupport: Identifiable, Sendable {
    let id: String
    let name: String
    let bayerRAW: Bool
    let proRAW: Bool
    /// Largest photo size of the preset's format, e.g. "8064x6048". Empty if none.
    let maxPhotoSize: String
    /// Set when the camera could not be configured; the other fields are then false/empty.
    let error: String?
}

/// Checks which cameras can give Bayer RAW or ProRAW, to decide how the front camera and the
/// Pro ultra-wide / telephoto could join the pipeline (ROADMAP). It only reports; capture is unchanged.
///
/// Each camera goes into its own session that is configured but never started, so the camera
/// screen's running session keeps the hardware. RAW formats are listed once the configuration
/// is committed; running is not needed (the camera screen reads them before starting, too).
enum CameraSurvey {
    static func run() async -> [CameraRawSupport] {
        await Task.detached(priority: .userInitiated) {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
                mediaType: .video,
                position: .unspecified
            )
            // Back cameras first (wide, ultra-wide, telephoto), then front.
            let devices = discovery.devices.sorted { a, b in
                if a.position != b.position { return a.position == .back }
                return Self.order(a.deviceType) < Self.order(b.deviceType)
            }
            return devices.map { Self.check($0) }
        }.value
    }

    private static func order(_ type: AVCaptureDevice.DeviceType) -> Int {
        switch type {
        case .builtInWideAngleCamera: return 0
        case .builtInUltraWideCamera: return 1
        default: return 2
        }
    }

    private static func check(_ device: AVCaptureDevice) -> CameraRawSupport {
        let name = "\(device.position == .front ? "前面" : "背面") \(device.localizedName)"
        func failed(_ message: String) -> CameraRawSupport {
            CameraRawSupport(id: device.uniqueID, name: name, bayerRAW: false, proRAW: false, maxPhotoSize: "", error: message)
        }

        let session = AVCaptureSession()
        let output = AVCapturePhotoOutput()
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            return failed(error.localizedDescription)
        }
        session.beginConfiguration()
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            return failed("セッションに追加できません")
        }
        session.addInput(input)
        session.addOutput(output)
        let format = device.activeFormat
        if let dims = format.supportedMaxPhotoDimensions.last {
            output.maxPhotoDimensions = dims
        }
        session.commitConfiguration()

        let bayer = output.availableRawPhotoPixelFormatTypes.contains { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
        // ProRAW formats are listed only while ProRAW is enabled.
        var proRAW = false
        if output.isAppleProRAWSupported {
            output.isAppleProRAWEnabled = true
            proRAW = output.availableRawPhotoPixelFormatTypes.contains { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }
        }
        let size = format.supportedMaxPhotoDimensions.last.map { "\($0.width)x\($0.height)" } ?? ""

        session.beginConfiguration()
        session.removeOutput(output)
        session.removeInput(input)
        session.commitConfiguration()

        return CameraRawSupport(id: device.uniqueID, name: name, bayerRAW: bayer, proRAW: proRAW, maxPhotoSize: size, error: nil)
    }
}
