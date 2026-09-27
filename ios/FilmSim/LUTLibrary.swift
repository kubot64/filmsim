import FilmSimCore
import Foundation
import UniformTypeIdentifiers

/// LUTs the user imported from the Files app, kept in Application Support/ImportedLUTs.
/// The look pickers list `names`; `Developer` loads the files into the pipeline.
@MainActor
final class LUTLibrary: ObservableObject {
    static let shared = LUTLibrary()

    static let cubeType = UTType(filenameExtension: "cube", conformingTo: .data) ?? .data

    @Published private(set) var names: [String] = []
    /// Names the user gave the imports, kept across launches.
    @Published private(set) var displayNames = LUTDisplayNames.decoded(
        from: UserDefaults.standard.data(forKey: LUTDisplayNames.storageKey) ?? Data()
    )

    private let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ImportedLUTs", isDirectory: true)
    }()

    private init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        refresh()
    }

    /// One line per file, for the settings screen.
    struct ImportReport {
        var lines: [String] = []
    }

    /// Each file must parse as a 3D LUT and name what it was made for (`LUTInputDetection`);
    /// anything else is refused, not guessed. A LUT for S-Log3 is re-baked to take F-Log2 codes
    /// first, so the pipeline never needs to know. A file with the same name replaces the
    /// earlier import.
    func importFiles(_ urls: [URL]) -> ImportReport {
        var report = ImportReport()
        for url in urls {
            let file = url.lastPathComponent
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                report.lines.append("\(file)：読めません"); continue
            }
            guard let lut = try? CubeLUT(text: text) else {
                report.lines.append("\(file)：3D LUT（.cube）ではありません"); continue
            }
            switch LUTInputDetection.detect(fileName: file, cubeText: text) {
            case .unsupported(let reason):
                report.lines.append("\(file)：読み込みませんでした。\(reason)")
            case .supported(let input):
                let name = ImportedLUT.name(forFileName: file)
                let stored = input == .fLog2 ? text : lut.convertedToFLog2(from: input).cubeText
                do {
                    try stored.write(to: fileURL(for: name), atomically: true, encoding: .utf8)
                    report.lines.append("\(file)：\(input.displayName) 用として読み込みました")
                } catch {
                    report.lines.append("\(file)：保存できません（\(error.localizedDescription)）")
                }
            }
        }
        refresh()
        Developer.shared.reloadImportedLUTs()
        return report
    }

    /// The label shown in the pickers and the list.
    func displayName(for name: String) -> String {
        displayNames.displayName(for: name)
    }

    /// Only the label changes; recipes keep the stored name, so the chosen look stays chosen.
    func rename(_ name: String, to newName: String) {
        displayNames.rename(name, to: newName)
        UserDefaults.standard.set(displayNames.encoded, forKey: LUTDisplayNames.storageKey)
    }

    func delete(_ name: String) {
        displayNames.remove(name)
        UserDefaults.standard.set(displayNames.encoded, forKey: LUTDisplayNames.storageKey)
        try? FileManager.default.removeItem(at: fileURL(for: name))
        refresh()
        Developer.shared.reloadImportedLUTs()
    }

    /// Parses every imported file. Ones that no longer parse are left out, not fatal.
    func loadAll() -> [String: CubeLUT] {
        var luts: [String: CubeLUT] = [:]
        for name in names {
            if let lut = try? CubeLUT(contentsOf: fileURL(for: name)) { luts[name] = lut }
        }
        return luts
    }

    private func fileURL(for name: String) -> URL {
        folder.appendingPathComponent(name).appendingPathExtension("cube")
    }

    private func refresh() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        names = files
            .filter { $0.pathExtension.lowercased() == "cube" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
