import Testing
@testable import LuxControlCore

@Suite("Display types")
struct DisplayTypesTests {
    @Test("BrightnessValue clamps percent into display-safe range")
    func brightnessValueClampsPercent() {
        #expect(BrightnessValue(percent: -10).percent == 0)
        #expect(BrightnessValue(percent: 45).percent == 45)
        #expect(BrightnessValue(percent: 140).percent == 100)
    }

    @Test("Display stableKey uses full hardware identity")
    func stableKeyUsesVendorModelSerialIdentity() {
        let display = Display(
            id: .directDisplayID(123),
            name: "Studio Display",
            vendorNumber: 1552,
            modelNumber: 41006,
            serialNumber: 987654,
            isBuiltin: false,
            supportLevel: .full
        )

        #expect(display.stableKey == "1552-41006-987654")
    }

    @Test("Display stableKey falls back to CGDirectDisplayID without hardware identity")
    func stableKeyFallsBackToDirectDisplayID() {
        let display = Display(
            id: .directDisplayID(42),
            name: "Unknown Display",
            isBuiltin: false,
            supportLevel: .detectOnly
        )

        #expect(display.stableKey == "cg-42")
    }
}
