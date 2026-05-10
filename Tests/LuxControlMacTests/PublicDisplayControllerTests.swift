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

    func testBoostWriteThrowsForUnsupportedDisplay() async throws {
        let controller = PublicDisplayController()
        let displays = await controller.discover()
        guard let display = displays.first(where: { $0.supportLevel != .full }) else {
            throw XCTSkip("No limited display available")
        }

        do {
            try await controller.setBoostEnabled(true, for: display.id)
            XCTFail("Expected unsupported error")
        } catch DisplayControlError.unsupported {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
