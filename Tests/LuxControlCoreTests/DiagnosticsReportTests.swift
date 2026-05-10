import Testing
@testable import LuxControlCore

@Suite("Diagnostics report")
struct DiagnosticsReportTests {
    @Test("make includes app, OS, display support, brightness, and boost state")
    func makeIncludesDisplayDiagnostics() {
        let display = Display(
            id: .directDisplayID(123),
            name: "Studio Display",
            vendorNumber: 1552,
            modelNumber: 41006,
            serialNumber: 987654,
            isBuiltin: false,
            supportLevel: .brightnessOnly
        )
        let state = DisplayState(brightness: .init(percent: 72), boostEnabled: false)

        let report = DiagnosticsReport.make(
            appVersion: "0.1.0",
            osVersion: "macOS 15.0",
            displays: [display],
            states: [display.stableKey: state]
        )

        #expect(report.contains("LuxControl 0.1.0"))
        #expect(report.contains("macOS 15.0"))
        #expect(report.contains("Studio Display"))
        #expect(report.contains("brightnessOnly"))
        #expect(report.contains("brightness: 72"))
        #expect(report.contains("boost: false"))
    }
}
