import CoreImage
import FilmSimCore
import ImageIO
import Photos
import UniformTypeIdentifiers

/// What `developAndSave` did. Screens share `developSaveMessage` for the Japanese status text.
enum DevelopSaveResult {
    case permissionDenied
    case developFailed(setupError: String?)
    case saveFailed(localizedDescription: String)
    case savedDNGOnly(setupError: String?)
    case savedHEICAndDNG
    case savedHEIC
}

func developSaveMessage(_ result: DevelopSaveResult) -> String {
    switch result {
    case .permissionDenied:
        return "写真ライブラリへのアクセスが拒否されました"
    case .developFailed(let setupError):
        return setupError ?? "現像に失敗しました"
    case .saveFailed(let localizedDescription):
        return "保存に失敗しました: \(localizedDescription)"
    case .savedDNGOnly(let setupError):
        return "DNG のみ保存しました（\(setupError ?? "現像に失敗")）"
    case .savedHEICAndDNG:
        return "HEIC と DNG を保存しました"
    case .savedHEIC:
        return "HEIC を保存しました"
    }
}

/// Runs the FilmSimCore pipeline on a DNG and writes HEIC (+ optional DNG) to the photo library.
@MainActor
final class Developer {
    static let shared = Developer()

    /// Working space matches the linear P3 the matrix expects. Output pixels are retagged
    /// as BT.709 without a second conversion — the LUT already emitted 709-gamma code values.
    private let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.linearDisplayP3)!,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.linearDisplayP3)!,
    ])
    private(set) var pipeline: Pipeline?
    /// Set when kernels or LUT files are missing. Rendering a loaded simulation still works.
    private(set) var setupError: String?

    private init() {
        do {
            let kernels = try Pipeline.Kernels.load()
            var luts: [FilmSimulation: CubeLUT] = [:]
            var missing: [String] = []
            for sim in FilmSimulation.allCases {
                if let url = Bundle.main.url(forResource: sim.lutFileName, withExtension: "cube") {
                    luts[sim] = try CubeLUT(contentsOf: url)
                } else {
                    missing.append(sim.displayName)
                }
            }
            pipeline = Pipeline(kernels: kernels, luts: luts)
            if !missing.isEmpty {
                setupError = "LUT がありません: \(missing.joined(separator: ", "))"
            }
        } catch {
            setupError = "パイプラインを初期化できません: \(error.localizedDescription)"
        }
    }

    /// The develop screen passes its recipe. The camera uses the default, so the two screens do not share one.
    func displayCGImage(rawData: Data, scaleFactor: Float = 1, recipe: Recipe) async -> CGImage? {
        guard let pipeline else { return nil }
        let box = RenderBox(pipeline: pipeline, context: context, recipe: recipe, rawData: rawData, scaleFactor: scaleFactor)
        return await Task.detached(priority: .userInitiated) { box.cgImage() }.value
    }

    func developAndSave(rawData: Data, saveDNG: Bool, recipe: Recipe = Recipe()) async -> DevelopSaveResult {
        guard await authorizeAdd() else { return .permissionDenied }
        let heic: Data?
        if let pipeline {
            let box = RenderBox(pipeline: pipeline, context: context, recipe: recipe, rawData: rawData, scaleFactor: 1)
            heic = await Task.detached(priority: .userInitiated) { box.heic() }.value
        } else {
            heic = nil
        }
        if heic == nil && !saveDNG {
            return .developFailed(setupError: setupError)
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                if let heic {
                    req.addResource(with: .photo, data: heic, options: nil)
                }
                if saveDNG {
                    let opts = PHAssetResourceCreationOptions()
                    opts.originalFilename = "FilmSim.DNG"
                    req.addResource(with: heic == nil ? .photo : .alternatePhoto, data: rawData, options: opts)
                }
            }
        } catch {
            return .saveFailed(localizedDescription: error.localizedDescription)
        }
        if heic == nil { return .savedDNGOnly(setupError: setupError) }
        return saveDNG ? .savedHEICAndDNG : .savedHEIC
    }

    private func authorizeAdd() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }
}

/// CIContext is safe to render from a background queue. The box keeps that work off the main actor
/// so a slider change can cancel the published result before the next frame is shown.
private final class RenderBox: @unchecked Sendable {
    let pipeline: Pipeline
    let context: CIContext
    let recipe: Recipe
    let rawData: Data
    let scaleFactor: Float

    init(pipeline: Pipeline, context: CIContext, recipe: Recipe, rawData: Data, scaleFactor: Float) {
        self.pipeline = pipeline
        self.context = context
        self.recipe = recipe
        self.rawData = rawData
        self.scaleFactor = scaleFactor
    }

    func cgImage() -> CGImage? {
        guard let image = rendered() else { return nil }
        return Self.displayCGImage(image, context: context)
    }

    func heic() -> Data? {
        guard let cg = cgImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.heic.identifier as CFString, 1, nil) else {
            return nil
        }
        let props = [kCGImageDestinationLossyCompressionQuality as String: 0.95] as CFDictionary
        CGImageDestinationAddImage(dest, cg, props)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private func rendered() -> CIImage? {
        var options = RawDeveloper.Options()
        options.scaleFactor = scaleFactor
        guard let linear = RawDeveloper.developLinear(rawData: rawData, options: options) else { return nil }
        return pipeline.render(linear, recipe: recipe, grainPixelScale: Double(scaleFactor))
    }

    private static let linearP3 = CGColorSpace(name: CGColorSpace.linearDisplayP3)!
    private static let bt709 = CGColorSpace(name: CGColorSpace.itur_709)!

    private static func displayCGImage(_ image: CIImage, context: CIContext) -> CGImage? {
        let rect = image.extent.integral
        guard rect.width > 1, rect.height > 1,
              let rendered = context.createCGImage(image, from: rect, format: .RGBA8, colorSpace: linearP3),
              let tagged = retag(rendered, as: bt709) else { return nil }
        return tagged
    }

    /// Replace the color space tag. The new image keeps the same data provider, so the pixels are not copied.
    private static func retag(_ image: CGImage, as colorSpace: CGColorSpace) -> CGImage? {
        guard let provider = image.dataProvider else { return nil }
        let info = CGBitmapInfo(rawValue: image.bitmapInfo.rawValue | image.alphaInfo.rawValue)
        return CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: image.bitsPerComponent,
            bitsPerPixel: image.bitsPerPixel,
            bytesPerRow: image.bytesPerRow,
            space: colorSpace,
            bitmapInfo: info,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
