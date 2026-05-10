import XCTest
@testable import LuxControlCore

final class SettingsStoreTests: XCTestCase {
    func testStoresPerDisplayState() throws {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        let state = DisplayState(brightness: BrightnessValue(percent: 88), boostEnabled: true)

        try store.save(state: state, forStableKey: "1552-1-2")
        let loaded = try store.loadState(forStableKey: "1552-1-2")

        XCTAssertEqual(loaded, state)
    }

    func testMissingDisplayStateReturnsNil() throws {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)

        XCTAssertNil(try store.loadState(forStableKey: "missing"))
    }
}
