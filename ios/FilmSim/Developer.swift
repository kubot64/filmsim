import CoreImage
import FilmSimCore
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

/// Runs the FilmSimCore pipeline on a DNG and writes HEIC (+ optional DNG) to the photo library.
@MainActor
final class Developer {
    static let shared = Developer()

    private static let linearP3 = CGColorSpace(name: CGColorSpace.linearDisplayP3)!
    private static let bt709 = CGColorSpace(name: CGColorSpace.itur_709)!

    /// Working space matches the linear P3 the matrix expects. Output pixels are retagged
    /// as BT.709 without a second conversion — the LUT already emitted 709-gamma code values.
    private let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.linearDisplayP3)!,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.linearDisplayP3)!,
    ])
    private(set) var pipeline: Pipeline?
    /// Set when kernels or LUT files are missing. Rendering a loaded simulation still works.
    private(set) var setupError: String?
    var recipe = Recipe()

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

    func render(rawData: Data, scaleFactor: Float = 1) -> CIImage? {
        guard let pipeline else { return nil }
        var options = RawDeveloper.Options()
        options.scaleFactor = scaleFactor
        guard let linear = RawDeveloper.developLinear(rawData: rawData, options: options) else { return nil }
        return pipeline.render(
            linear.cropped35mmThreeByTwo(),
            recipe: recipe,
            grainPixelScale: Double(scaleFactor)
        )
    }

    func uiImage(from image: CIImage) -> UIImage? {
        guard let cg = displayCGImage(from: image) else { return nil }
        return UIImage(cgImage: cg)
    }

    func developAndSave(rawData: Data, saveDNG: Bool) async -> String {
        guard await authorizeAdd() else { return "写真ライブラリへのアクセスが拒否されました" }
        let heic = render(rawData: rawData).flatMap { heicData(from: $0) }
        if heic == nil && !saveDNG {
            return setupError ?? "現像に失敗しました"
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
            return "保存に失敗しました: \(error.localizedDescription)"
        }
        if heic == nil { return "DNG のみ保存しました（\(setupError ?? "現像に失敗")）" }
        return saveDNG ? "HEIC と DNG を保存しました" : "HEIC を保存しました"
    }

    private func authorizeAdd() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }

    private func displayCGImage(from image: CIImage) -> CGImage? {
        let rect = image.extent.integral
        guard rect.width > 1, rect.height > 1,
              let rendered = context.createCGImage(image, from: rect, format: .RGBA8, colorSpace: Self.linearP3),
              let tagged = Self.retag(rendered, as: Self.bt709) else { return nil }
        return tagged
    }

    private func heicData(from image: CIImage) -> Data? {
        guard let cg = displayCGImage(from: image) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.heic.identifier as CFString, 1, nil) else {
            return nil
        }
        let props = [kCGImageDestinationLossyCompressionQuality as String: 0.95] as CFDictionary
        CGImageDestinationAddImage(dest, cg, props)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Replace the color space tag without touching pixels.
    private static func retag(_ image: CGImage, as colorSpace: CGColorSpace) -> CGImage? {
        guard let data = image.dataProvider?.data, let provider = CGDataProvider(data: data) else { return nil }
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
