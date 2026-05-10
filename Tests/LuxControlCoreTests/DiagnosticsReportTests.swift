import Testing
@testable import LuxControlCore

@Suite("Diagnostics report")
struct DiagnosticsReportTests {
    @Test("make includes display diagnostics without serial-derived identifiers")
    func makeIncludesDisplayDiagnosticsWithoutSerialDerivedIdentifiers() {
        let display = Display(
            id: .directDisplayID(123),
            name: "Studio Display",
            vendorNumber: 1552,
            modelNumber: 610,
            serialNumber: 99,
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

        #expect(report == """
        LuxControl 0.1.0
        OS: macOS 15.0
        Displays: 1
        - Studio Display
          builtin: false
          support: brightnessOnly
          brightness: 72%
          boost: false
        """)
        #expect(!report.contains("stableKey"))
        #expect(!report.contains("1552-610-99"))
    }
}
