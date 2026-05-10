import XCTest
@testable import LuxControlMac

final class LaunchAtLoginServiceTests: XCTestCase {
    func testIsEnabledCanBeReadWithoutCrashing() {
        let service = LaunchAtLoginService()
        _ = service.isEnabled

        XCTAssertTrue(true)
    }
}
