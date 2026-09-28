import AVFoundation
import CoreImage
import FilmSimCore
import MetalKit
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

    private static let linearP3 = CGColorSpace(name: CGColorSpace.linearDisplayP3)!
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let commandQueue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = commandQueue
        context = CIContext(mtlDevice: device, options: [
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
        lock.withLock { frame = image }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let (frame, pipeline, recipe, focalLength) = lock.withLock { (self.frame, self.pipeline, self.recipe, self.focalLength) }
        let size = view.drawableSize
        guard let frame, size.width > 0, size.height > 0,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Scale down before the look so the kernels run at screen size, not sensor size.
        var image = frame.croppedThreeByTwo(focalLength: focalLength).oriented(.right)
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let scale = max(size.width / image.extent.width, size.height / image.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        image = image.transformed(by: CGAffineTransform(
            translationX: (size.width - image.extent.width) / 2,
            y: (size.height - image.extent.height) / 2
        ))

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
        _ = try? context.startTask(
            toRender: image.cropped(to: CGRect(origin: .zero, size: size)),
            from: CGRect(origin: .zero, size: size),
            to: destination,
            at: .zero
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

/// UIKit bridge for the live preview, the focus frame and the focus gestures.
struct CameraPreview: UIViewRepresentable {
    let renderer: PreviewRenderer?
    /// `PreviewGeometry.crop` for the current focal length.
    var crop: CGRect
    /// Where focus and exposure are measured (device point, `PreviewGeometry`).
    var focusPoint: CGPoint
    var isLocked: Bool
    /// Device point and whether it was a long press (AE/AF lock).
    var onFocus: (CGPoint, Bool) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView(renderer: renderer)
        update(v)
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        update(uiView)
    }

    private func update(_ v: PreviewView) {
        v.crop = crop
        v.focusPoint = focusPoint
        v.isLocked = isLocked
        v.onFocus = onFocus
        v.setNeedsLayout()
    }

    final class PreviewView: UIView {
        var crop = PreviewGeometry.crop(sensorAspect: PreviewGeometry.defaultSensorAspect, focalLength: .default)
        var focusPoint = CGPoint(x: 0.5, y: 0.5)
        var isLocked = false
        var onFocus: ((CGPoint, Bool) -> Void)?
        private let metalView: MTKView
        /// Always shown where focus is measured (#46): white while following, yellow while locked.
        private let focusMark = UIView(frame: CGRect(x: 0, y: 0, width: 72, height: 72))

        init(renderer: PreviewRenderer?) {
            metalView = MTKView(frame: .zero, device: renderer?.device)
            super.init(frame: .zero)
            backgroundColor = .black
            clipsToBounds = true

            metalView.delegate = renderer
            metalView.colorPixelFormat = .bgra8Unorm
            metalView.framebufferOnly = false
            metalView.preferredFramesPerSecond = 30
            metalView.isUserInteractionEnabled = false
            (metalView.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            addSubview(metalView)

            focusMark.layer.borderWidth = 1.5
            focusMark.isUserInteractionEnabled = false
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

        private func focus(at location: CGPoint, lock: Bool) {
            let image = imageRect
            let p = CGPoint(x: (location.x - image.minX) / image.width, y: (location.y - image.minY) / image.height)
            onFocus?(PreviewGeometry.devicePoint(fromView: p, crop: crop), lock)
            focusMark.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            UIView.animate(withDuration: 0.2) { self.focusMark.transform = .identity }
        }

        /// The 2:3 image aspect-filled into the view, as `PreviewRenderer` draws it.
        private var imageRect: CGRect {
            let b = bounds
            let s = max(b.width / 2, b.height / 3)
            return CGRect(x: b.midX - s, y: b.midY - s * 1.5, width: s * 2, height: s * 3)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            metalView.frame = bounds
            // Re-placed from the device point, so it stays on the subject when the focal length changes.
            let v = PreviewGeometry.viewPoint(fromDevice: focusPoint, crop: crop)
            let image = imageRect
            focusMark.center = CGPoint(x: image.minX + v.x * image.width, y: image.minY + v.y * image.height)
            focusMark.isHidden = !(0...1).contains(v.x) || !(0...1).contains(v.y)
            focusMark.layer.borderColor = (isLocked ? UIColor.systemYellow : UIColor.white).cgColor
        }
    }
}
