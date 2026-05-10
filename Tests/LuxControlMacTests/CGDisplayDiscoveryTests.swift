import XCTest
@testable import LuxControlMac

final class CGDisplayDiscoveryTests: XCTestCase {
    func testDiscoveryReturnsMainDisplayInNormalMacSession() async throws {
        let discovery = CGDisplayDiscovery()
        let displays = await discovery.discover()

        guard !displays.isEmpty else {
            throw XCTSkip("No active displays available in this test session")
        }

        XCTAssertTrue(displays.allSatisfy { !$0.name.isEmpty })
    }
}
