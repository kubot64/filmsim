import Foundation

/// Decides what an imported .cube was made for, so users do not have to pick it (and cannot
/// pick it wrong). A .cube has no field for its input log, but real files name it: Fujifilm's
/// "FLog2_to_PROVIA_...", Sony's "SLog3SGamut3.CineToLC-709...", or a TITLE / comment line.
/// Only the file name, TITLE and comment lines are read. Anything unclear or not supported is
/// refused rather than guessed: a LUT read with the wrong log shows wrong colours with no error.
public enum LUTInputDetection {
    public enum Result: Equatable, Sendable {
        case supported(LUTInput)
        /// Japanese reason shown to the user.
        case unsupported(String)
    }

    public static func detect(fileName: String, cubeText: String) -> Result {
        let text = ([fileName] + headerLines(of: cubeText)).joined(separator: "\n")
        func has(_ pattern: String) -> Bool {
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        // Separators seen in real names: "F-Log2", "FLog2", "F_Log2", "F Log2", "S-Gamut3.Cine".
        let sep = "[-_ .]?"
        let fLog2C = has("f\(sep)log\(sep)2\(sep)c(?![a-z])")
        let fLog2 = has("f\(sep)log\(sep)2(?![0-9])")
        let fLog1 = has("f\(sep)log(?!\(sep)[0-9])")
        let sLog3 = has("s\(sep)log\(sep)3(?![0-9])")
        let sGamut3Cine = has("s\(sep)gamut\(sep)3\(sep)cine")
        let sGamut3 = has("s\(sep)gamut\(sep)3(?!\(sep)cine)(?![0-9])")

        if fLog2C { return .unsupported("F-Log2 C 用の LUT には対応していません") }
        if fLog2 && sLog3 { return .unsupported("F-Log2 と S-Log3 の両方が書かれていて、どちら用か判定できません") }
        if fLog2 { return .supported(.fLog2) }
        if sLog3 {
            if sGamut3Cine && !sGamut3 { return .supported(.sLog3SGamut3Cine) }
            if sGamut3 && !sGamut3Cine { return .supported(.sLog3SGamut3) }
            return .unsupported("S-Log3 用ですが、S-Gamut3.Cine か S-Gamut3 かが判定できません")
        }
        if fLog1 { return .unsupported("F-Log（初代）用の LUT には対応していません。F-Log2 用を使ってください") }
        for (pattern, name) in otherLogs where has(pattern) {
            return .unsupported("\(name) 用の LUT には対応していません")
        }
        return .unsupported("何用の LUT か判定できません。ファイル名か中身に F-Log2 か S-Log3 と書いてある LUT だけ読み込めます")
    }

    /// Logs we recognise only to name them in the refusal.
    private static let otherLogs: [(String, String)] = [
        ("s[-_ .]?log[-_ .]?2(?![0-9])", "S-Log2"),
        ("v[-_ .]?log", "V-Log"),
        ("c[-_ .]?log", "C-Log"),
        ("n[-_ .]?log", "N-Log"),
        ("l[-_ .]?log", "L-Log"),
        ("d[-_ .]?log", "D-Log"),
        ("log[-_ .]?c(?![a-z])", "ARRI LogC"),
        ("log3g10", "RED Log3G10"),
    ]

    /// TITLE and comment lines before the table. The table itself is only numbers.
    static func headerLines(of cubeText: String) -> [String] {
        var lines: [String] = []
        for raw in cubeText.split(whereSeparator: \.isNewline).prefix(200) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            // Long lines are cut: a name never needs more, and a huge line would slow every pattern.
            if line.hasPrefix("#") || line.uppercased().hasPrefix("TITLE") { lines.append(String(line.prefix(500))) }
        }
        return lines
    }
}
