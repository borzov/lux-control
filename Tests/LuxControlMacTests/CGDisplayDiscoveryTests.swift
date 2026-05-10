import XCTest
@testable import LuxControlMac

final class CGDisplayDiscoveryTests: XCTestCase {
    func testDiscoveryReturnsMainDisplayInNormalMacSession() async {
        let discovery = CGDisplayDiscovery()
        let displays = await discovery.discover()

        XCTAssertFalse(displays.isEmpty)
        XCTAssertTrue(displays.contains(where: { !$0.name.isEmpty }))
    }
}
