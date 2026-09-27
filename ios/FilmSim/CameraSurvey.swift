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
        switch PhotoSessionBuilder.configurePhotoSession(session, device: device, output: output) {
        case .failure(let message):
            return failed(message)
        case .success(let info):
            let bayer = !output.bayerRAWFormats.isEmpty
            // ProRAW formats are listed only while ProRAW is enabled.
            var proRAW = false
            if output.isAppleProRAWSupported {
                output.isAppleProRAWEnabled = true
                proRAW = output.availableRawPhotoPixelFormatTypes.contains {
                    AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
                }
            }

            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            session.removeOutput(output)
            session.commitConfiguration()

            return CameraRawSupport(
                id: device.uniqueID, name: name, bayerRAW: bayer, proRAW: proRAW,
                maxPhotoSize: info.maxPhotoSize, error: nil
            )
        }
    }
}
