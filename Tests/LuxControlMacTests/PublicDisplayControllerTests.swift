import XCTest
import LuxControlCore
@testable import LuxControlMac

final class PublicDisplayControllerTests: XCTestCase {
    func testControllerDiscoversDisplaysWithSupportLevels() async throws {
        let controller = PublicDisplayController()
        let displays = await controller.discover()

        guard !displays.isEmpty else {
            throw XCTSkip("No active displays available in this test session")
        }

        XCTAssertTrue(displays.allSatisfy { !$0.name.isEmpty })
    }

    func testDefaultReadStateForKnownDisplay() async {
        let display = makeDisplay(id: 1, supportLevel: .full)
        let controller = PublicDisplayController(discovery: MockDisplayDiscovery(displays: [display]))

        let state = await controller.readState(for: display.id)

        XCTAssertEqual(state, DisplayState(brightness: BrightnessValue(percent: 50), boostEnabled: false))
    }

    func testBrightnessUpdateUsesStableKeyAcrossDirectDisplayIDChange() async throws {
        let firstDisplay = makeDisplay(id: 1, supportLevel: .full)
        let secondDisplay = makeDisplay(id: 2, supportLevel: .full)
        let discovery = MockDisplayDiscovery(displays: [firstDisplay])
        let controller = PublicDisplayController(discovery: discovery)

        try await controller.setBrightness(BrightnessValue(percent: 82), for: firstDisplay.id)
        await discovery.setDisplays([secondDisplay])

        let state = await controller.readState(for: secondDisplay.id)

        XCTAssertEqual(state.brightness, BrightnessValue(percent: 82))
        XCTAssertFalse(state.boostEnabled)
    }

    func testBrightnessWriteSucceedsForBrightnessOnlyDisplay() async throws {
        let display = makeDisplay(id: 1, supportLevel: .brightnessOnly)
        let controller = PublicDisplayController(discovery: MockDisplayDiscovery(displays: [display]))

        try await controller.setBrightness(BrightnessValue(percent: 65), for: display.id)

        let state = await controller.readState(for: display.id)
        XCTAssertEqual(state.brightness, BrightnessValue(percent: 65))
    }

    func testBrightnessWriteThrowsUnsupportedForDetectOnlyDisplay() async throws {
        try await assertBrightnessUnsupported(for: .detectOnly)
    }

    func testBrightnessWriteThrowsUnsupportedForUnsupportedDisplay() async throws {
        try await assertBrightnessUnsupported(for: .unsupported)
    }

    func testBoostWriteThrowsUnsupportedWithSupportLevel() async throws {
        let display = makeDisplay(id: 1, supportLevel: .brightnessOnly)
        let controller = PublicDisplayController(discovery: MockDisplayDiscovery(displays: [display]))

        do {
            try await controller.setBoostEnabled(true, for: display.id)
            XCTFail("Expected unsupported error")
        } catch DisplayControlError.unsupported(let supportLevel) {
            XCTAssertEqual(supportLevel, .brightnessOnly)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWriteThrowsDisplayNotFoundForUnknownDisplay() async throws {
        let display = makeDisplay(id: 1, supportLevel: .full)
        let controller = PublicDisplayController(discovery: MockDisplayDiscovery(displays: [display]))

        do {
            try await controller.setBrightness(BrightnessValue(percent: 70), for: .directDisplayID(404))
            XCTFail("Expected displayNotFound error")
        } catch DisplayControlError.displayNotFound {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func assertBrightnessUnsupported(
        for supportLevel: DisplaySupportLevel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let display = makeDisplay(id: 1, supportLevel: supportLevel)
        let controller = PublicDisplayController(discovery: MockDisplayDiscovery(displays: [display]))

        do {
            try await controller.setBrightness(BrightnessValue(percent: 70), for: display.id)
            XCTFail("Expected unsupported error", file: file, line: line)
        } catch DisplayControlError.unsupported(let actualSupportLevel) {
            XCTAssertEqual(actualSupportLevel, supportLevel, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func makeDisplay(
        id: UInt32,
        supportLevel: DisplaySupportLevel,
        vendorNumber: UInt32? = 111,
        modelNumber: UInt32? = 222,
        serialNumber: UInt32? = 333
    ) -> Display {
        Display(
            id: .directDisplayID(id),
            name: "Test Display",
            vendorNumber: vendorNumber,
            modelNumber: modelNumber,
            serialNumber: serialNumber,
            isBuiltin: false,
            supportLevel: supportLevel
        )
    }
}

private actor MockDisplayDiscovery: DisplayDiscovering {
    private var displays: [Display]

    init(displays: [Display]) {
        self.displays = displays
    }

    func discover() async -> [Display] {
        displays
    }

    func setDisplays(_ displays: [Display]) {
        self.displays = displays
    }
}
