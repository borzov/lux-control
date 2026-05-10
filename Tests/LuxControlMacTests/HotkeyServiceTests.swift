import XCTest
@testable import LuxControlMac

final class HotkeyServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        HotkeyService.resetForTesting()
    }

    override func tearDown() {
        HotkeyService.resetForTesting()
        super.tearDown()
    }

    func testSimulateDispatchesCommandToHandler() {
        let recorder = CommandRecorder()
        let service = HotkeyService { command in
            recorder.record(command)
        }

        service.simulate(.toggle)

        XCTAssertEqual(recorder.command, .toggle)
    }

    func testRegisteredHotkeysRouteToOwningInstance() throws {
        let registrar = FakeHotkeySystemClient()
        let firstRecorder = CommandRecorder()
        let secondRecorder = CommandRecorder()
        let firstService = HotkeyService(systemClient: registrar.client) { command in
            firstRecorder.record(command)
        }
        let secondService = HotkeyService(systemClient: registrar.client) { command in
            secondRecorder.record(command)
        }

        try firstService.start([.toggle: .init(keyCode: 1, modifiers: 2)])
        try secondService.start([.toggle: .init(keyCode: 1, modifiers: 2)])

        XCTAssertTrue(HotkeyService.dispatchRegisteredHotkey(id: registrar.registeredIDs[0]))
        XCTAssertEqual(firstRecorder.command, .toggle)
        XCTAssertNil(secondRecorder.command)

        XCTAssertTrue(HotkeyService.dispatchRegisteredHotkey(id: registrar.registeredIDs[1]))
        XCTAssertEqual(secondRecorder.command, .toggle)
    }

    func testStopRemovesOnlyOwnedHotkeyRoutes() throws {
        let registrar = FakeHotkeySystemClient()
        let firstRecorder = CommandRecorder()
        let secondRecorder = CommandRecorder()
        let firstService = HotkeyService(systemClient: registrar.client) { command in
            firstRecorder.record(command)
        }
        let secondService = HotkeyService(systemClient: registrar.client) { command in
            secondRecorder.record(command)
        }

        try firstService.start([.toggle: .init(keyCode: 1, modifiers: 2)])
        try secondService.start([.toggle: .init(keyCode: 1, modifiers: 2)])
        firstService.stop()

        XCTAssertFalse(HotkeyService.dispatchRegisteredHotkey(id: registrar.registeredIDs[0]))
        XCTAssertTrue(HotkeyService.dispatchRegisteredHotkey(id: registrar.registeredIDs[1]))
        XCTAssertNil(firstRecorder.command)
        XCTAssertEqual(secondRecorder.command, .toggle)
    }

    func testPartialRegistrationFailureRollsBackOwnedRoutes() {
        let registrar = FakeHotkeySystemClient(failOnRegistration: 2)
        let service = HotkeyService(systemClient: registrar.client) { _ in }

        XCTAssertThrowsError(try service.start([
            .increase: .init(keyCode: 1, modifiers: 2),
            .decrease: .init(keyCode: 3, modifiers: 4),
        ]))

        XCTAssertEqual(registrar.unregisteredIDs, [registrar.registeredIDs[0]])
        XCTAssertFalse(HotkeyService.dispatchRegisteredHotkey(id: registrar.registeredIDs[0]))
    }

    func testEventHandlerInstallsOnlyOnceAcrossInstances() throws {
        let registrar = FakeHotkeySystemClient()
        let firstService = HotkeyService(systemClient: registrar.client) { _ in }
        let secondService = HotkeyService(systemClient: registrar.client) { _ in }

        try firstService.start([.toggle: .init(keyCode: 1, modifiers: 2)])
        try secondService.start([.increase: .init(keyCode: 3, modifiers: 4)])

        XCTAssertEqual(registrar.installCalls, 1)
    }
}

private final class CommandRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCommand: HotkeyService.Command?

    var command: HotkeyService.Command? {
        lock.lock()
        defer { lock.unlock() }
        return recordedCommand
    }

    func record(_ command: HotkeyService.Command) {
        lock.lock()
        recordedCommand = command
        lock.unlock()
    }
}

private final class FakeHotkeySystemClient: @unchecked Sendable {
    private let lock = NSLock()
    private let failOnRegistration: Int?
    private var registrationCount = 0
    private var installCallCount = 0
    private var ids: [UInt32] = []
    private var unregistered: [UInt32] = []

    var client: HotkeySystemClient {
        HotkeySystemClient(
            installEventHandler: { [self] in
                lock.lock()
                installCallCount += 1
                lock.unlock()
                return nil
            },
            registerHotkey: { [self] _, _, hotkeyID in
                lock.lock()
                defer { lock.unlock() }

                registrationCount += 1
                if registrationCount == failOnRegistration {
                    throw NSError(domain: "TestHotkeySystemClient", code: -1)
                }

                ids.append(hotkeyID.id)
                return HotkeyRegistration { [self] in
                    lock.lock()
                    unregistered.append(hotkeyID.id)
                    lock.unlock()
                }
            }
        )
    }

    var registeredIDs: [UInt32] {
        lock.lock()
        defer { lock.unlock() }
        return ids
    }

    var unregisteredIDs: [UInt32] {
        lock.lock()
        defer { lock.unlock() }
        return unregistered
    }

    var installCalls: Int {
        lock.lock()
        defer { lock.unlock() }
        return installCallCount
    }

    init(failOnRegistration: Int? = nil) {
        self.failOnRegistration = failOnRegistration
    }
}
