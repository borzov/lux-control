import XCTest
@testable import LuxControlCore

final class SettingsStoreTests: XCTestCase {
    func testStoresPerDisplayState() throws {
        let defaults = try makeDefaults()
        let store = SettingsStore(defaults: defaults)
        let state = DisplayState(brightness: BrightnessValue(percent: 88), boostEnabled: true)

        try store.save(state: state, forStableKey: "1552-1-2")
        let loaded = try store.loadState(forStableKey: "1552-1-2")

        XCTAssertEqual(loaded, state)
    }

    func testMissingDisplayStateReturnsNil() throws {
        let defaults = try makeDefaults()
        let store = SettingsStore(defaults: defaults)

        XCTAssertNil(try store.loadState(forStableKey: "missing"))
    }

    func testStoresDisplayStatesIndependentlyByStableKey() throws {
        let defaults = try makeDefaults()
        let store = SettingsStore(defaults: defaults)
        let firstState = DisplayState(brightness: BrightnessValue(percent: 30), boostEnabled: false)
        let secondState = DisplayState(brightness: BrightnessValue(percent: 95), boostEnabled: true)

        try store.save(state: firstState, forStableKey: "1552-1-2")
        try store.save(state: secondState, forStableKey: "610-7-8")

        XCTAssertEqual(try store.loadState(forStableKey: "1552-1-2"), firstState)
        XCTAssertEqual(try store.loadState(forStableKey: "610-7-8"), secondState)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SettingsStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        return defaults
    }
}
