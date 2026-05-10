import XCTest
@testable import LuxControlMac

final class LaunchAtLoginServiceTests: XCTestCase {
    func testIsEnabledCanBeReadWithoutCrashing() {
        let service = LaunchAtLoginService()
        _ = service.isEnabled

        XCTAssertTrue(true)
    }

    func testSetEnabledRegistersOnlyWhenDisabled() throws {
        let client = FakeLaunchAtLoginClient(isEnabled: false)
        let service = LaunchAtLoginService(client: client)

        try service.setEnabled(true)
        try service.setEnabled(true)

        XCTAssertEqual(client.registerCalls, 1)
        XCTAssertEqual(client.unregisterCalls, 0)
        XCTAssertTrue(client.isEnabled)
    }

    func testSetEnabledUnregistersOnlyWhenEnabled() throws {
        let client = FakeLaunchAtLoginClient(isEnabled: true)
        let service = LaunchAtLoginService(client: client)

        try service.setEnabled(false)
        try service.setEnabled(false)

        XCTAssertEqual(client.registerCalls, 0)
        XCTAssertEqual(client.unregisterCalls, 1)
        XCTAssertFalse(client.isEnabled)
    }

    func testSetEnabledPropagatesClientErrors() {
        let expectedError = NSError(domain: "LaunchAtLoginTest", code: 42)
        let client = FakeLaunchAtLoginClient(isEnabled: false, registerError: expectedError)
        let service = LaunchAtLoginService(client: client)

        XCTAssertThrowsError(try service.setEnabled(true)) { error in
            XCTAssertEqual(error as NSError, expectedError)
        }
    }
}

private final class FakeLaunchAtLoginClient: LaunchAtLoginClient, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool
    private let registerError: Error?
    private let unregisterError: Error?
    private var registerCallCount = 0
    private var unregisterCallCount = 0

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }

    var registerCalls: Int {
        lock.lock()
        defer { lock.unlock() }
        return registerCallCount
    }

    var unregisterCalls: Int {
        lock.lock()
        defer { lock.unlock() }
        return unregisterCallCount
    }

    init(
        isEnabled: Bool,
        registerError: Error? = nil,
        unregisterError: Error? = nil
    ) {
        self.enabled = isEnabled
        self.registerError = registerError
        self.unregisterError = unregisterError
    }

    func register() throws {
        lock.lock()
        registerCallCount += 1
        lock.unlock()

        if let registerError {
            throw registerError
        }

        lock.lock()
        enabled = true
        lock.unlock()
    }

    func unregister() throws {
        lock.lock()
        unregisterCallCount += 1
        lock.unlock()

        if let unregisterError {
            throw unregisterError
        }

        lock.lock()
        enabled = false
        lock.unlock()
    }
}
