import XCTest
@testable import FilmSimCore

final class LookTests: XCTestCase {
    private func tinyLUT(_ title: String) throws -> CubeLUT {
        let rows = (0..<8).map { i in "\(i & 1) \((i >> 1) & 1) \((i >> 2) & 1)" }
        return try CubeLUT(text: "TITLE \"\(title)\"\nLUT_3D_SIZE 2\n" + rows.joined(separator: "\n"))
    }

    func testDisplayNamesAvoidTrademarks() {
        XCTAssertEqual(FilmSimulation.provia.displayName, "ナチュラル")
        XCTAssertEqual(FilmSimulation.classicChrome.displayName, "ネガフィルム")
        XCTAssertEqual(FilmSimulation.portra400vc.displayName, "アメリカ")
    }

    func testRecipesStoredBeforeImportsStillDecode() {
        let old = Data(#"{"filmSimulation":"classicChrome","exposureEV":0.5}"#.utf8)
        let r = Recipe.decoded(from: old)
        XCTAssertEqual(r.filmSimulation, .classicChrome)
        XCTAssertNil(r.importedLUT)
        XCTAssertEqual(r.look, .builtIn(.classicChrome))
    }

    func testChoosingAnImportKeepsTheBuiltInToFallBackTo() {
        var r = Recipe()
        r.look = .builtIn(.portra400vc)
        r.look = .imported("My LUT")
        XCTAssertEqual(r.look, .imported("My LUT"))
        XCTAssertEqual(r.filmSimulation, .portra400vc)
        XCTAssertEqual(Recipe.decoded(from: r.encoded).look, .imported("My LUT"))
        r.look = .builtIn(.provia)
        XCTAssertNil(r.importedLUT)
    }

    func testOfficialFujifilmImportsGetTheXSeriesFixes() {
        XCTAssertTrue(ImportedLUT.usesXSeriesShoulder(name: "FLog2_to_ETERNA_65grid_V.1.00"))
        XCTAssertTrue(ImportedLUT.appliesWarmHue(name: "FLog2_to_PROVIA_65grid_V.1.00"))
        XCTAssertFalse(ImportedLUT.appliesWarmHue(name: "FLog2_to_ETERNA_65grid_V.1.00"))
        XCTAssertFalse(ImportedLUT.usesXSeriesShoulder(name: "My Film Look"))
    }

    func testImportNamesStayOneFileInTheFolder() {
        XCTAssertEqual(ImportedLUT.name(forFileName: "FLog2_to_ETERNA_65grid_V.1.00.cube"), "FLog2_to_ETERNA_65grid_V.1.00")
        XCTAssertEqual(ImportedLUT.name(forFileName: "../evil.CUBE"), "_evil")
        XCTAssertEqual(ImportedLUT.name(forFileName: ".cube"), "LUT")
    }

    func testResolvePrefersTheImportAndFallsBackWhenItIsGone() throws {
        let builtIn = [FilmSimulation.provia: try tinyLUT("provia"), .portra400vc: try tinyLUT("portra")]
        var r = Recipe()
        r.look = .builtIn(.portra400vc)
        r.look = .imported("FLog2_to_PROVIA_x")

        let withImport = ResolvedLook.resolve(r, builtIn: builtIn, imported: ["FLog2_to_PROVIA_x": try tinyLUT("imp")])
        XCTAssertEqual(withImport?.lut.title, "imp")
        XCTAssertEqual(withImport?.xSeriesShoulder, true)
        XCTAssertEqual(withImport?.warmHue, true)

        let deleted = ResolvedLook.resolve(r, builtIn: builtIn, imported: [:])
        XCTAssertEqual(deleted?.lut.title, "portra")
        XCTAssertEqual(deleted?.xSeriesShoulder, false)
        XCTAssertEqual(r.effectiveLook(importedNames: []), .builtIn(.portra400vc))
        XCTAssertEqual(r.effectiveLook(importedNames: ["FLog2_to_PROVIA_x"]), .imported("FLog2_to_PROVIA_x"))
    }
}
