import XCTest
@testable import LuxControlMac

final class HotkeyServiceTests: XCTestCase {
    func testSimulateDispatchesCommandToHandler() {
        let recorder = CommandRecorder()
        let service = HotkeyService { command in
            recorder.record(command)
        }

        service.simulate(.toggle)

        XCTAssertEqual(recorder.command, .toggle)
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
