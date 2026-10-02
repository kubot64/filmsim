import Foundation
import XCTest

/// The research pipeline's outputs on seeded random inputs, for the per-pixel transforms both
/// sides implement. Written by research/filmsim/fixtures.py, which says how to rewrite it.
struct TransformFixtures: Decodable {
    struct Case: Decodable, CustomStringConvertible {
        /// Set by `cases(_:)`, so a failure names the transform.
        var transform = ""
        let `in`: [Double]
        let params: [Double]?
        let out: [Double]

        private enum CodingKeys: String, CodingKey { case `in`, params, out }

        var rgbIn: SIMD3<Double> { SIMD3(`in`[0], `in`[1], `in`[2]) }
        var rgbOut: SIMD3<Double> { SIMD3(out[0], out[1], out[2]) }
        /// Tone-curve cases carry (highlight, shadow).
        var tone: (highlight: Double, shadow: Double) { (params?[0] ?? 0, params?[1] ?? 0) }
        var description: String { "\(transform) in=\(`in`) params=\(params ?? []) expected=\(out)" }
    }

    let seed: Int
    let transforms: [String: [Case]]

    /// Read from the research tree, found from this file like MetalKernelTests finds the .metal.
    static let shared: TransformFixtures = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // FilmSimCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // FilmSimCore
            .deletingLastPathComponent()  // ios
            .deletingLastPathComponent()  // repository
            .appendingPathComponent("research/tests/fixtures/transforms.json")
        do {
            return try JSONDecoder().decode(TransformFixtures.self, from: Data(contentsOf: url))
        } catch {
            fatalError("could not read \(url.path): \(error)")
        }
    }()

    /// The cases for one transform; fails the test when the name is not in the file.
    static func cases(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> [Case] {
        guard let cases = shared.transforms[name], !cases.isEmpty else {
            XCTFail("no fixture cases for \(name); run `make fixtures`", file: file, line: line)
            return []
        }
        return cases.map {
            var c = $0; c.transform = name; return c
        }
    }
}
