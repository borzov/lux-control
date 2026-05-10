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
        let controller = PublicDisplayController(
            discovery: MockDisplayDiscovery(displays: [display]),
            brightnessClient: MockBrightnessClient(readValues: [:]),
            boostClient: MockBoostClient()
        )

        let state = await controller.readState(for: display.id)

        XCTAssertEqual(state, DisplayState(brightness: BrightnessValue(percent: 50), boostEnabled: false))
    }

    func testReadStateUsesSystemBrightnessWhenAvailable() async {
        let display = makeDisplay(id: 1, supportLevel: .brightnessOnly)
        let brightnessClient = MockBrightnessClient(readValues: [1: 1.0])
        let controller = PublicDisplayController(
            discovery: MockDisplayDiscovery(displays: [display]),
            brightnessClient: brightnessClient,
            boostClient: MockBoostClient()
        )

        let state = await controller.readState(for: display.id)

        XCTAssertEqual(state.brightness, BrightnessValue(percent: 100))
    }

    func testBrightnessUpdateUsesStableKeyAcrossDirectDisplayIDChange() async throws {
        let firstDisplay = makeDisplay(id: 1, supportLevel: .full)
        let secondDisplay = makeDisplay(id: 2, supportLevel: .full)
        let discovery = MockDisplayDiscovery(displays: [firstDisplay])
        let controller = PublicDisplayController(
            discovery: discovery,
            brightnessClient: MockBrightnessClient(readValues: [:]),
            boostClient: MockBoostClient()
        )

        try await controller.setBrightness(BrightnessValue(percent: 82), for: firstDisplay.id)
        await discovery.setDisplays([secondDisplay])

        let state = await controller.readState(for: secondDisplay.id)

        XCTAssertEqual(state.brightness, BrightnessValue(percent: 82))
        XCTAssertFalse(state.boostEnabled)
    }

    func testBrightnessWriteSucceedsForBrightnessOnlyDisplay() async throws {
        let display = makeDisplay(id: 1, supportLevel: .brightnessOnly)
        let controller = PublicDisplayController(
            discovery: MockDisplayDiscovery(displays: [display]),
            brightnessClient: MockBrightnessClient(readValues: [:]),
            boostClient: MockBoostClient()
        )

        try await controller.setBrightness(BrightnessValue(percent: 65), for: display.id)

        let state = await controller.readState(for: display.id)
        XCTAssertEqual(state.brightness, BrightnessValue(percent: 65))
    }

    func testBrightnessWriteUpdatesSystemBrightness() async throws {
        let display = makeDisplay(id: 1, supportLevel: .brightnessOnly)
        let brightnessClient = MockBrightnessClient(readValues: [1: 0.5])
        let controller = PublicDisplayController(
            discovery: MockDisplayDiscovery(displays: [display]),
            brightnessClient: brightnessClient,
            boostClient: MockBoostClient()
        )

        try await controller.setBrightness(BrightnessValue(percent: 82), for: display.id)

        XCTAssertEqual(brightnessClient.writes, [1: 0.82])
    }

    func testBrightnessWriteThrowsUnsupportedForDetectOnlyDisplay() async throws {
        try await assertBrightnessUnsupported(for: .detectOnly)
    }

    func testBrightnessWriteThrowsUnsupportedForUnsupportedDisplay() async throws {
        try await assertBrightnessUnsupported(for: .unsupported)
    }

    func testBoostWriteThrowsUnsupportedWithSupportLevel() async throws {
        let display = makeDisplay(id: 1, supportLevel: .brightnessOnly)
        let controller = PublicDisplayController(
            discovery: MockDisplayDiscovery(displays: [display]),
            brightnessClient: MockBrightnessClient(readValues: [:]),
            boostClient: MockBoostClient()
        )

        do {
            try await controller.setBoostEnabled(true, for: display.id)
            XCTFail("Expected unsupported error")
        } catch DisplayControlError.unsupported(let supportLevel) {
            XCTAssertEqual(supportLevel, .brightnessOnly)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBoostWriteUpdatesBoostClient() async throws {
        let display = makeDisplay(id: 1, supportLevel: .full)
        let boostClient = MockBoostClient()
        let controller = PublicDisplayController(
            discovery: MockDisplayDiscovery(displays: [display]),
            brightnessClient: MockBrightnessClient(readValues: [:]),
            boostClient: boostClient
        )

        try await controller.setBoostEnabled(true, for: display.id)

        let writes = await boostClient.writes
        XCTAssertEqual(writes, [1: true])
    }

    func testWriteThrowsDisplayNotFoundForUnknownDisplay() async throws {
        let display = makeDisplay(id: 1, supportLevel: .full)
        let controller = PublicDisplayController(
            discovery: MockDisplayDiscovery(displays: [display]),
            brightnessClient: MockBrightnessClient(readValues: [:]),
            boostClient: MockBoostClient()
        )

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
        let controller = PublicDisplayController(
            discovery: MockDisplayDiscovery(displays: [display]),
            brightnessClient: MockBrightnessClient(readValues: [:]),
            boostClient: MockBoostClient()
        )

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

private final class MockBrightnessClient: DisplayBrightnessClient, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UInt32: Float]
    private var writtenValues: [UInt32: Float] = [:]

    var writes: [UInt32: Float] {
        lock.lock()
        defer { lock.unlock() }
        return writtenValues
    }

    init(readValues: [UInt32: Float]) {
        self.values = readValues
    }

    func canChangeBrightness(for displayID: UInt32) -> Bool {
        true
    }

    func readBrightness(for displayID: UInt32) -> Float? {
        lock.lock()
        defer { lock.unlock() }
        return values[displayID]
    }

    func setBrightness(_ value: Float, for displayID: UInt32) throws {
        lock.lock()
        values[displayID] = value
        writtenValues[displayID] = value
        lock.unlock()
    }
}

private actor MockBoostClient: DisplayBoostClient {
    private var values: [UInt32: Bool] = [:]
    private var writtenValues: [UInt32: Bool] = [:]

    var writes: [UInt32: Bool] {
        writtenValues
    }

    func canBoost(for displayID: UInt32) async -> Bool {
        true
    }

    func isBoostEnabled(for displayID: UInt32) async -> Bool {
        return values[displayID] ?? false
    }

    func setBoostEnabled(_ enabled: Bool, for displayID: UInt32) async throws {
        values[displayID] = enabled
        writtenValues[displayID] = enabled
    }
}
