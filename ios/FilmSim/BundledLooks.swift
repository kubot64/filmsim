import FilmSimCore
import Foundation

/// The built-in looks whose LUT is in this build, in `FilmSimulation` order. Debug builds carry
/// all of them. The Release build, which goes to the App Store, leaves out Fujifilm's LUTs because
/// they may not be redistributed (ADR 0010); the user imports them from the Files app instead.
enum BundledLooks {
    static let available: [FilmSimulation] = FilmSimulation.allCases.filter {
        Bundle.main.url(forResource: $0.lutFileName, withExtension: "cube") != nil
    }
}
