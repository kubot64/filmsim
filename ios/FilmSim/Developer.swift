import CoreImage
import FilmSimCore
import ImageIO
import Photos
import UniformTypeIdentifiers

/// What `developAndSave` did. The screens turn this into Japanese status text.
/// `developFailed` and `savedDNGOnly` set `reason` only for a setup failure (kernels, or this
/// recipe's LUT). After setup, a RAW read or HEIC encode failure leaves it nil.
enum DevelopSaveResult {
    case permissionDenied
    case developFailed(reason: String?)
    case saveFailed(localizedDescription: String)
    case savedDNGOnly(reason: String?)
    case savedHEICAndDNG
    case savedHEIC

    /// Both the HEIC and any DNG asked for were saved.
    var isSuccess: Bool {
        switch self {
        case .savedHEICAndDNG, .savedHEIC: return true
        default: return false
        }
    }

    /// Japanese status text for the camera and develop screens.
    var message: String {
        switch self {
        case .permissionDenied:
            return "写真ライブラリへのアクセスが拒否されました"
        case .developFailed(let reason):
            return reason ?? "現像に失敗しました"
        case .saveFailed(let localizedDescription):
            return "保存に失敗しました: \(localizedDescription)"
        case .savedDNGOnly(let reason):
            return "DNG のみ保存しました（\(reason ?? "現像に失敗")）"
        case .savedHEICAndDNG:
            return "HEIC と DNG を保存しました"
        case .savedHEIC:
            return "HEIC を保存しました"
        }
    }
}

/// `DevelopSaveResult` plus the library ids of what was saved, for the shot log (#54).
struct DevelopSaveOutcome {
    let result: DevelopSaveResult
    var heicAssetID: String?
    var dngAssetID: String?
    /// A small JPEG of the HEIC for the camera screen's thumbnail. Nil when no HEIC was made.
    var thumbnailJPEG: Data?

    var message: String { result.message }
    var savedAnything: Bool { heicAssetID != nil || dngAssetID != nil }
}

/// One preview develop. `reason` is set only when this attempt failed during setup
/// (kernels, or this recipe's LUT). It stays nil when the RAW could not be developed,
/// and the screen uses its own wording then. An earlier LUT error is not carried here.
struct DisplayImageResult {
    var image: CGImage?
    var reason: String?
}

/// Ids of the assets a change block creates. The block runs off the main actor.
private final class CreatedAssetIDs: @unchecked Sendable {
    var heic: String?
    var dng: String?
}

/// Runs the FilmSimCore pipeline on a DNG and writes HEIC (+ optional DNG) to the photo library.
@MainActor
final class Developer {
    static let shared = Developer()

    /// Working space matches the linear P3 the matrix expects. Output pixels are retagged
    /// as sRGB without converting them. The codes are BT.709 gamma; the sRGB tag matches
    /// the EOTF used for ΔE.
    private let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.linearDisplayP3)!,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.linearDisplayP3)!
    ])
    private var kernels: Pipeline.Kernels?
    private var luts: [FilmSimulation: CubeLUT] = [:]
    /// Bundle resource was not found.
    private var missingLUTs: Set<FilmSimulation> = []
    /// Bundle resource existed but `CubeLUT(contentsOf:)` failed; value is the load error text.
    private var unreadableLUTs: [FilmSimulation: String] = [:]
    private var lutLoads: [FilmSimulation: Task<LUTLoadOutcome, Never>] = [:]
    /// Imported LUTs read so far, by `ImportedLUT` name. Emptied by `reloadImportedLUTs`.
    private var importedLUTs: [String: CubeLUT] = [:]
    /// Bumped by `reloadImportedLUTs`, so a read that started before it is not cached.
    private var importedGeneration = 0
    /// Set only when the kernels fail to load. A missing or unreadable LUT is reported
    /// on that develop and is not kept here, so a later failure shows its own reason.
    private var setupError: String?

    private enum LUTLoadOutcome {
        case loaded(CubeLUT)
        case missing
        case unreadable(String)
    }

    private init() {
        do {
            kernels = try Pipeline.Kernels.load()
        } catch {
            setupError = "パイプラインを初期化できません: \(error.localizedDescription)"
        }
    }

    /// Called by `LUTLibrary` after an import or a delete. The next render reads the file again,
    /// since an import can replace a file under the same name.
    func reloadImportedLUTs() {
        importedLUTs = [:]
        importedGeneration += 1
    }

    /// Both screens pass the stored last-used recipe (`Recipe.storageKey`, #8).
    func displayCGImage(rawData: Data, scaleFactor: Float = 1, recipe: Recipe, focalLength: FocalLength) async
        -> DisplayImageResult
    {
        guard let pipeline = await pipeline(for: recipe) else {
            return DisplayImageResult(image: nil, reason: setupFailure(for: recipe))
        }
        let box = RenderBox(
            pipeline: pipeline, context: context, recipe: recipe, focalLength: focalLength,
            rawData: rawData, scaleFactor: scaleFactor
        )
        let image = await Task.detached(priority: .userInitiated) { box.cgImage() }.value
        return DisplayImageResult(image: image, reason: nil)
    }

    func developAndSave(rawData: Data, saveDNG: Bool, recipe: Recipe, focalLength: FocalLength) async
        -> DevelopSaveOutcome
    {
        guard await authorizeAdd() else { return DevelopSaveOutcome(result: .permissionDenied) }
        var heic: Data?
        var thumbnail: Data?
        let pipeline = await pipeline(for: recipe)
        if let pipeline {
            let box = RenderBox(
                pipeline: pipeline, context: context, recipe: recipe, focalLength: focalLength,
                rawData: rawData, scaleFactor: 1
            )
            (heic, thumbnail) = await Task.detached(priority: .userInitiated) { () -> (Data?, Data?) in
                let heic = box.heic()
                return (heic, heic.flatMap(RenderBox.thumbnailJPEG(fromHEIC:)))
            }.value
        }
        // Only a setup failure for this recipe. A RAW or encode failure leaves `reason` nil
        // so the screen does not repeat an older LUT message.
        let reason = pipeline == nil ? setupFailure(for: recipe) : nil
        if heic == nil && !saveDNG {
            return DevelopSaveOutcome(result: .developFailed(reason: reason))
        }
        let ids = CreatedAssetIDs()
        do {
            // Two separate assets, created in one change block so both or neither land.
            // Photos rejects the DNG as the HEIC's .alternatePhoto (PHPhotosErrorDomain 3300) on
            // iPhone 15 Pro Max / iOS 26.6.2, while each saves fine alone. Likely because the HEIC
            // is cropped and graded, so Photos does not treat it as the same picture as the RAW.
            try await PHPhotoLibrary.shared().performChanges {
                if let heic {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: heic, options: nil)
                    ids.heic = request.placeholderForCreatedAsset?.localIdentifier
                }
                if saveDNG {
                    let opts = PHAssetResourceCreationOptions()
                    opts.originalFilename = "FilmSim.DNG"
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: rawData, options: opts)
                    ids.dng = request.placeholderForCreatedAsset?.localIdentifier
                }
            }
        } catch {
            return DevelopSaveOutcome(result: .saveFailed(localizedDescription: error.localizedDescription))
        }
        let result: DevelopSaveResult
        if heic == nil {
            result = .savedDNGOnly(reason: reason)
        } else {
            result = saveDNG ? .savedHEICAndDNG : .savedHEIC
        }
        return DevelopSaveOutcome(result: result, heicAssetID: ids.heic, dngAssetID: ids.dng, thumbnailJPEG: thumbnail)
    }

    /// Kernels plus the LUT `recipe` renders with (`ResolvedLook`). An imported LUT is used when
    /// its file still reads; otherwise the built-in simulation is, as `ResolvedLook` falls back.
    /// LUTs load off the main actor on first use; a missing or corrupt built-in file only
    /// disables that simulation.
    func pipeline(for recipe: Recipe) async -> Pipeline? {
        guard let kernels else { return nil }
        if let name = recipe.importedLUT, let lut = await loadImportedLUT(name) {
            return Pipeline(kernels: kernels, luts: [:], importedLUTs: [name: lut])
        }
        guard let lut = await loadLUT(recipe.filmSimulation) else { return nil }
        return Pipeline(kernels: kernels, luts: [recipe.filmSimulation: lut])
    }

    /// Nil when the import is gone or no longer parses; the recipe then renders with its
    /// built-in simulation, like before the import.
    private func loadImportedLUT(_ name: String) async -> CubeLUT? {
        if let lut = importedLUTs[name] { return lut }
        guard let url = LUTLibrary.shared.fileURL(forImported: name) else { return nil }
        let generation = importedGeneration
        let lut = await Task.detached(priority: .userInitiated) { try? CubeLUT(contentsOf: url) }.value
        if let lut, generation == importedGeneration { importedLUTs[name] = lut }
        return lut
    }

    private func loadLUT(_ simulation: FilmSimulation) async -> CubeLUT? {
        if let lut = luts[simulation] { return lut }
        if missingLUTs.contains(simulation) || unreadableLUTs[simulation] != nil {
            return nil
        }
        let task =
            lutLoads[simulation]
            ?? Task.detached(priority: .userInitiated) { () -> LUTLoadOutcome in
                guard let url = Bundle.main.url(forResource: simulation.lutFileName, withExtension: "cube") else {
                    return .missing
                }
                do {
                    return .loaded(try CubeLUT(contentsOf: url))
                } catch {
                    return .unreadable(error.localizedDescription)
                }
            }
        lutLoads[simulation] = task
        let outcome = await task.value
        lutLoads[simulation] = nil
        switch outcome {
        case .loaded(let lut):
            luts[simulation] = lut
            return lut
        case .missing:
            missingLUTs.insert(simulation)
            return nil
        case .unreadable(let message):
            unreadableLUTs[simulation] = message
            return nil
        }
    }

    /// Why `pipeline(for:)` returned nil. Kernels, or this recipe's built-in LUT.
    /// Call only in that case: a recipe whose imported LUT rendered must not pick up
    /// another simulation's missing LUT. An imported file that is gone is not an error;
    /// rendering falls back to the built-in look.
    private func setupFailure(for recipe: Recipe) -> String? {
        if kernels == nil { return setupError }
        let simulation = recipe.filmSimulation
        if missingLUTs.contains(simulation) {
            return "LUT がありません: \(simulation.displayName)"
        }
        if let detail = unreadableLUTs[simulation] {
            return "\(simulation.displayName) の LUT を読めません: \(detail)"
        }
        return nil
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
    let focalLength: FocalLength
    let rawData: Data
    let scaleFactor: Float

    init(
        pipeline: Pipeline, context: CIContext, recipe: Recipe, focalLength: FocalLength, rawData: Data,
        scaleFactor: Float
    ) {
        self.pipeline = pipeline
        self.context = context
        self.recipe = recipe
        self.focalLength = focalLength
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
        guard
            let dest = CGImageDestinationCreateWithData(
                data as CFMutableData, UTType.heic.identifier as CFString, 1, nil)
        else {
            return nil
        }
        let props =
            [
                kCGImageDestinationLossyCompressionQuality as String: 0.95,
                kCGImagePropertyTIFFDictionary as String: [kCGImagePropertyTIFFSoftware as String: AppVersion.software]
            ] as CFDictionary
        CGImageDestinationAddImage(dest, cg, props)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// About 240px on the long side, enough for the 44pt thumbnail at 3x with room to spare.
    static func thumbnailJPEG(fromHEIC heic: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(heic as CFData, nil),
            let thumb = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 240
                ] as CFDictionary)
        else { return nil }
        let data = NSMutableData()
        guard
            let dest = CGImageDestinationCreateWithData(
                data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else {
            return nil
        }
        CGImageDestinationAddImage(dest, thumb, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    private func rendered() -> CIImage? {
        var options = RawDeveloper.Options()
        options.scaleFactor = scaleFactor
        options.focalLength = focalLength
        guard let linear = RawDeveloper.developLinear(rawData: rawData, options: options) else { return nil }
        return pipeline.render(linear, recipe: recipe, grainPixelScale: Double(scaleFactor))
    }

    private static let linearP3 = CGColorSpace(name: CGColorSpace.linearDisplayP3)!
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func displayCGImage(_ image: CIImage, context: CIContext) -> CGImage? {
        let rect = image.extent.integral
        guard rect.width > 1, rect.height > 1,
            let rendered = context.createCGImage(image, from: rect, format: .RGBA8, colorSpace: linearP3),
            let tagged = retag(rendered, as: sRGB)
        else { return nil }
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
