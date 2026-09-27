import Foundation

/// What the look pickers offer: a built-in film simulation or a LUT the user imported.
public enum Look: Hashable, Sendable {
    case builtIn(FilmSimulation)
    case imported(String)

    public var displayName: String {
        switch self {
        case .builtIn(let sim): return sim.displayName
        case .imported(let name): return name
        }
    }
}

extension Recipe {
    /// The picker's view of `filmSimulation` and `importedLUT`. Choosing an imported LUT keeps
    /// the last built-in simulation, which is what rendering falls back to if the file goes away.
    public var look: Look {
        get { importedLUT.map(Look.imported) ?? .builtIn(filmSimulation) }
        set {
            switch newValue {
            case .builtIn(let sim):
                filmSimulation = sim
                importedLUT = nil
            case .imported(let name):
                importedLUT = name
            }
        }
    }
}

extension Recipe {
    /// The look that will actually render, given the imported LUTs that exist: one whose file is
    /// gone falls back to the built-in simulation (`ResolvedLook`), and the screens should say so.
    public func effectiveLook(importedNames: [String]) -> Look {
        if let name = importedLUT, importedNames.contains(name) { return .imported(name) }
        return .builtIn(filmSimulation)
    }
}

/// LUTs the user imports from the Files app. They take F-Log2 / F-Gamut codes like the built-in
/// ones, so Fujifilm's official F-Log2 LUTs can be used as they are.
public enum ImportedLUT {
    /// Fujifilm names its official files "FLog2_to_<SIMULATION>_<grid>_V.x.xx.cube". Those get the
    /// same X-series fixes as the built-in Fujifilm looks; any other LUT is used as it is.
    /// Mirrors research/filmsim/cube.py `film_sim_key`.
    public static func usesXSeriesShoulder(name: String) -> Bool {
        name.uppercased().hasPrefix("FLOG2_TO_")
    }

    public static func appliesWarmHue(name: String) -> Bool {
        usesXSeriesShoulder(name: name) && name.uppercased().contains("PROVIA")
    }

    /// The name an imported file is stored and listed under: the file name without ".cube", with
    /// path separators and leading dots removed so it stays one file in the app's folder.
    public static func name(forFileName fileName: String) -> String {
        var base = fileName
        if base.lowercased().hasSuffix(".cube") { base.removeLast(5) }
        base = base.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        while base.hasPrefix(".") { base.removeFirst() }
        return base.isEmpty ? "LUT" : base
    }
}

/// The LUT a recipe renders with, and which fixes it gets.
public struct ResolvedLook {
    public let lut: CubeLUT
    public let xSeriesShoulder: Bool
    public let warmHue: Bool

    /// An imported LUT wins when it is loaded; otherwise the built-in simulation is used, so a
    /// deleted import still develops the shot instead of failing it.
    public static func resolve(
        _ recipe: Recipe,
        builtIn: [FilmSimulation: CubeLUT],
        imported: [String: CubeLUT]
    ) -> ResolvedLook? {
        if let name = recipe.importedLUT, let lut = imported[name] {
            return ResolvedLook(
                lut: lut,
                xSeriesShoulder: ImportedLUT.usesXSeriesShoulder(name: name),
                warmHue: ImportedLUT.appliesWarmHue(name: name)
            )
        }
        guard let lut = builtIn[recipe.filmSimulation] else { return nil }
        return ResolvedLook(
            lut: lut,
            xSeriesShoulder: recipe.filmSimulation.usesXSeriesShoulder,
            warmHue: WarmHue.applies(to: recipe.filmSimulation)
        )
    }
}
