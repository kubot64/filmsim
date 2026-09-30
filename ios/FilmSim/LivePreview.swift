import AVFoundation
import AVKit
import CoreImage
import FilmSimCore
import MetalKit
import os
import SwiftUI

/// Draws camera frames through the film simulation for the live preview (#50).
///
/// The goal is the look, not a match with the saved HEIC: frames are the camera's processed
/// video, not RAW, so tone and highlights differ. Grain is left off. Frames arrive in the
/// sensor-native orientation and get the same focal-length crop as the develop step
/// (`croppedThreeByTwo`), then a 90° clockwise turn into the portrait view (`PreviewGeometry`).
final class PreviewRenderer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, MTKViewDelegate, @unchecked Sendable {
    let device: MTLDevice
    let sampleQueue = DispatchQueue(label: "PreviewRenderer.frames")
    private let commandQueue: MTLCommandQueue
    /// Same working space as `Developer`, so the pipeline sees linear P3.
    private let context: CIContext
    private let lock = NSLock()
    private var frame: CIImage?
    private var pipeline: Pipeline?
    private var recipe = Recipe()
    private var focalLength = FocalLength.stored()
    /// Drawn once per camera frame. The camera drops below 30fps when exposure reaches about 1/30s
    /// (a dark metering point), and a fixed 30fps redraw then repeats frames unevenly and judders.
    weak var view: MTKView?
    private var drawPending = false

    private static let linearP3 = CGColorSpace(name: CGColorSpace.linearDisplayP3)!
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let log = Logger(subsystem: "com.morikubo.FilmSim", category: "PreviewRenderer")

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let commandQueue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = commandQueue
        // The same queue as the command buffers the frames are drawn and presented with.
        context = CIContext(mtlCommandQueue: commandQueue, options: [
            .workingColorSpace: Self.linearP3,
            .cacheIntermediates: false,
        ])
    }

    /// Nil `pipeline` (a LUT failed to load) shows the plain frame.
    func setLook(_ pipeline: Pipeline?, recipe: Recipe) {
        var previewRecipe = recipe
        previewRecipe.grainStrength = .off
        lock.withLock {
            self.pipeline = pipeline
            self.recipe = previewRecipe
        }
    }

    func setFocalLength(_ focalLength: FocalLength) {
        lock.withLock { self.focalLength = focalLength }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        let shouldDraw = lock.withLock { () -> Bool in
            frame = image
            defer { drawPending = true }
            return !drawPending
        }
        guard shouldDraw else { return }
        DispatchQueue.main.async { [weak self] in
            self?.lock.withLock { self?.drawPending = false }
            self?.view?.draw()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let (frame, pipeline, recipe, focalLength) = lock.withLock { (self.frame, self.pipeline, self.recipe, self.focalLength) }
        let size = view.drawableSize
        guard let frame, size.width > 0, size.height > 0,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Scale down before the look so the kernels run at screen size, not sensor size.
        var image = frame.livePreviewFrame(focalLength: focalLength, filling: size)

        // The pipeline's output is BT.709-gamma codes that are written as they are, like `Developer`
        // retags them as sRGB. The plain frame is converted to sRGB instead.
        let destination = CIRenderDestination(
            width: Int(size.width),
            height: Int(size.height),
            pixelFormat: view.colorPixelFormat,
            commandBuffer: commandBuffer,
            mtlTextureProvider: { drawable.texture }
        )
        if let pipeline, let looked = pipeline.render(image, recipe: recipe) {
            image = looked
            destination.colorSpace = Self.linearP3
        } else {
            destination.colorSpace = Self.sRGB
        }
        do {
            _ = try context.startTask(
                toRender: image,
                from: CGRect(origin: .zero, size: size),
                to: destination,
                at: .zero
            )
        } catch {
            // Skip the frame rather than present an unfinished drawable.
            Self.log.error("preview render failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

/// UIKit bridge for the live preview, the focus frame and the focus gestures.
/// Volume buttons take a photo through `onHardwareShutter` (iOS 17.2+).
struct CameraPreview: UIViewRepresentable {
    let renderer: PreviewRenderer?
    /// Where focus and exposure are measured, normalized to the preview (0...1, top-left origin).
    var focusPoint: CGPoint
    var isLocked: Bool
    /// Degrees the AE/AF LOCK label turns to read upright (`HoldingOrientation`).
    var controlRotation: Double
    /// Bumped by `CameraController` each time a capture starts. The preview darkens once per change.
    var shutterFlash: Int
    /// While false, volume buttons change the volume. Off when the camera can't shoot or another screen is up.
    var hardwareShutterEnabled: Bool
    /// Tapped point, normalized like `focusPoint`, and whether it was a long press (AE/AF lock).
    var onFocus: (CGPoint, Bool) -> Void
    /// Volume up, volume down, and the other hardware capture buttons. One photo per press.
    var onHardwareShutter: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(shutterFlash: shutterFlash)
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView(renderer: renderer)
        update(v)
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        update(uiView)
        if shutterFlash > context.coordinator.shutterFlash {
            uiView.flashShutter()
        }
        context.coordinator.shutterFlash = shutterFlash
    }

    private func update(_ v: PreviewView) {
        v.focusPoint = focusPoint
        v.isLocked = isLocked
        v.controlRotation = controlRotation
        v.onFocus = onFocus
        v.onHardwareShutter = onHardwareShutter
        v.setHardwareShutterEnabled(hardwareShutterEnabled)
        v.setNeedsLayout()
    }

    final class Coordinator {
        var shutterFlash: Int
        init(shutterFlash: Int) { self.shutterFlash = shutterFlash }
    }

    final class PreviewView: UIView {
        var focusPoint = CGPoint(x: 0.5, y: 0.5)
        var isLocked = false
        var controlRotation = 0.0
        var onFocus: ((CGPoint, Bool) -> Void)?
        /// Latest shutter for a hardware button. The capture interaction calls this on release.
        var onHardwareShutter: (() -> Void)?
        private let metalView: MTKView
        /// Covers the preview for a moment when a shot is taken.
        private let shutterVeil = UIView()
        /// `AVCaptureEventInteraction` once iOS is new enough to have it. Nil before 17.2.
        private var hardwareShutter: NSObject?
        /// Shown next to the frame while locked, on the holder's upper side.
        private let lockLabel = UILabel()
        /// Always shown where focus is measured (#46): white while following, yellow while locked.
        private let focusMark = UIView(frame: CGRect(x: 0, y: 0, width: 72, height: 72))

        init(renderer: PreviewRenderer?) {
            metalView = MTKView(frame: .zero, device: renderer?.device)
            super.init(frame: .zero)
            backgroundColor = .black
            clipsToBounds = true

            metalView.delegate = renderer
            renderer?.view = metalView
            metalView.colorPixelFormat = .bgra8Unorm
            metalView.framebufferOnly = false
            // Redrawn by `PreviewRenderer` when a frame arrives.
            metalView.isPaused = true
            metalView.enableSetNeedsDisplay = false
            metalView.isUserInteractionEnabled = false
            (metalView.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            addSubview(metalView)

            focusMark.layer.borderWidth = 1.5
            focusMark.isUserInteractionEnabled = false
            addSubview(focusMark)

            lockLabel.text = " AE/AF LOCK "
            lockLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            lockLabel.textColor = .black
            lockLabel.backgroundColor = .systemYellow
            lockLabel.layer.cornerRadius = 4
            lockLabel.layer.masksToBounds = true
            lockLabel.sizeToFit()
            lockLabel.isHidden = true
            addSubview(lockLabel)

            shutterVeil.backgroundColor = .black
            shutterVeil.alpha = 0
            shutterVeil.isUserInteractionEnabled = false
            addSubview(shutterVeil)

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

        /// Darkens the preview briefly. The photo output already plays the shutter sound.
        func flashShutter() {
            shutterVeil.frame = bounds
            bringSubviewToFront(shutterVeil)
            shutterVeil.layer.removeAllAnimations()
            shutterVeil.alpha = 0.92
            UIView.animate(withDuration: 0.2, delay: 0.04, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
                self.shutterVeil.alpha = 0
            }
        }

        /// Volume buttons take a photo on iOS 17.2 and later. Primary is volume down, secondary is
        /// volume up; both shoot. Disabled, they change the volume as usual. No extra sound:
        /// `AVCapturePhotoOutput` plays the shutter sound.
        func setHardwareShutterEnabled(_ enabled: Bool) {
            guard #available(iOS 17.2, *) else { return }
            if hardwareShutter == nil {
                let shoot: (AVCaptureEvent) -> Void = { [weak self] event in
                    // Release, not press down: a cancelled press must not take a photo.
                    guard event.phase == .ended else { return }
                    DispatchQueue.main.async { self?.onHardwareShutter?() }
                }
                let interaction = AVCaptureEventInteraction(primary: shoot, secondary: shoot)
                interaction.isEnabled = false
                addInteraction(interaction)
                hardwareShutter = interaction
            }
            (hardwareShutter as? AVCaptureEventInteraction)?.isEnabled = enabled
        }

        private func focus(at location: CGPoint, lock: Bool) {
            guard let p = PreviewGeometry.focusViewPoint(forTap: location, in: bounds, frameSize: focusMark.bounds.size) else { return }
            onFocus?(p, lock)
            focusMark.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            UIView.animate(withDuration: 0.2) { self.focusMark.transform = .identity }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            metalView.frame = bounds
            // Keep the veil's frame out of the shutter fade, which only animates its alpha.
            if shutterVeil.frame != bounds {
                UIView.performWithoutAnimation { shutterVeil.frame = bounds }
            }
            let image = PreviewGeometry.imageRect(in: bounds)
            focusMark.center = CGPoint(x: image.minX + focusPoint.x * image.width, y: image.minY + focusPoint.y * image.height)
            focusMark.layer.borderColor = (isLocked ? UIColor.systemYellow : UIColor.white).cgColor

            // Above the frame as the holder sees it; below it if that would leave the view.
            lockLabel.isHidden = !isLocked
            let turn = CGAffineTransform(rotationAngle: controlRotation * .pi / 180)
            lockLabel.transform = turn
            let gap = focusMark.bounds.height / 2 + 12
            let above = CGPoint(x: 0, y: -gap).applying(turn)
            let candidate = CGPoint(x: focusMark.center.x + above.x, y: focusMark.center.y + above.y)
            lockLabel.center = bounds.insetBy(dx: 40, dy: 12).contains(candidate)
                ? candidate
                : CGPoint(x: focusMark.center.x - above.x, y: focusMark.center.y - above.y)
        }
    }
}
