import Foundation

public enum DiagnosticsReport {
    public static func make(
        appVersion: String,
        osVersion: String,
        displays: [Display],
        states: [String: DisplayState]
    ) -> String {
        var lines: [String] = [
            "LuxControl \(appVersion)",
            "OS: \(osVersion)",
            "Displays: \(displays.count)"
        ]

        for display in displays {
            let state = states[display.stableKey]
            lines.append("- \(display.name)")
            lines.append("  builtin: \(display.isBuiltin)")
            lines.append("  support: \(display.supportLevel.rawValue)")
            lines.append("  brightness: \(state.map { "\($0.brightness.percent)%" } ?? "unknown")")
            lines.append("  boost: \(state?.boostEnabled.description ?? "unknown")")
        }

        return lines.joined(separator: "\n")
    }
}
