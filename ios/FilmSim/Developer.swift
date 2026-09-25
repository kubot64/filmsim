import CoreImage
import FilmSimCore
import Photos
import UIKit

/// Runs the FilmSimCore pipeline on a DNG and writes HEIC (+ optional DNG) to the photo library.
@MainActor
final class Developer {
    static let shared = Developer()

    private let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.linearDisplayP3)!])
    private(set) var pipeline: Pipeline?
    var recipe = Recipe()

    private init() {
        do {
            let kernel = try Pipeline.loadFLog2Kernel()
            var luts: [FilmSimulation: CubeLUT] = [:]
            for sim in FilmSimulation.allCases {
                if let url = Bundle.main.url(forResource: sim.lutFileName, withExtension: "cube") {
                    luts[sim] = try CubeLUT(contentsOf: url)
                }
            }
            pipeline = Pipeline(flog2Kernel: kernel, luts: luts)
        } catch {
            print("pipeline unavailable: \(error)")
        }
    }

    /// 35mm-equivalent crop of the 24mm main camera, then 3:2.
    func crop35mmThreeByTwo(_ image: CIImage) -> CIImage {
        let scale = 24.0 / 35.0
        let e = image.extent
        let w = e.width * scale
        let h = w * 2.0 / 3.0
        let rect = CGRect(x: e.midX - w / 2, y: e.midY - h / 2, width: w, height: h)
        return image.cropped(to: rect)
    }

    func render(rawData: Data) -> CIImage? {
        guard let pipeline, let linear = RawDeveloper.developLinear(rawData: rawData) else { return nil }
        return pipeline.render(crop35mmThreeByTwo(linear), recipe: recipe)
    }

    func developAndSave(rawData: Data, saveDNG: Bool) async {
        guard let out = render(rawData: rawData) else { print("render failed"); return }
        let space = CGColorSpace(name: CGColorSpace.itur_709)!
        guard let heic = context.heifRepresentation(of: out, format: .RGBA8, colorSpace: space) else { return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: heic, options: nil)
                if saveDNG {
                    let opts = PHAssetResourceCreationOptions()
                    opts.originalFilename = "FilmSim.DNG"
                    req.addResource(with: .alternatePhoto, data: rawData, options: opts)
                }
            }
        } catch {
            print("save failed: \(error)")
        }
    }
}
