import Carbon
import Foundation

public final class HotkeyService: @unchecked Sendable {
    public enum Command: UInt32, Sendable {
        case increase = 1
        case decrease = 2
        case toggle = 3
    }

    public struct Shortcut: Sendable {
        public let keyCode: UInt32
        public let modifiers: UInt32

        public init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
    }

    private let handler: @Sendable (Command) -> Void
    private var refs: [UInt32: EventHotKeyRef] = [:]

    private static let signature: OSType = 0x56465245
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [UInt32: @Sendable (Command) -> Void] = [:]
    nonisolated(unsafe) private static var eventHandlerInstalled = false

    public init(handler: @escaping @Sendable (Command) -> Void) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    public func startDefaultHotkeys() throws {
        try start([
            .increase: Shortcut(keyCode: 24, modifiers: UInt32(cmdKey | optionKey)),
            .decrease: Shortcut(keyCode: 27, modifiers: UInt32(cmdKey | optionKey)),
            .toggle: Shortcut(keyCode: 49, modifiers: UInt32(cmdKey | optionKey)),
        ])
    }

    public func start(_ shortcuts: [Command: Shortcut]) throws {
        try Self.installEventHandlerIfNeeded()
        stop()

        for (command, shortcut) in shortcuts {
            let hotkeyID = EventHotKeyID(signature: Self.signature, id: command.rawValue)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.modifiers,
                hotkeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )

            guard status == noErr, let ref else {
                stop()
                throw Self.makeError(code: status)
            }

            refs[command.rawValue] = ref
            Self.lock.lock()
            Self.handlers[command.rawValue] = handler
            Self.lock.unlock()
        }
    }

    public func stop() {
        for (rawCommand, ref) in refs {
            UnregisterEventHotKey(ref)
            Self.lock.lock()
            Self.handlers.removeValue(forKey: rawCommand)
            Self.lock.unlock()
        }

        refs.removeAll()
    }

    public func simulate(_ command: Command) {
        handler(command)
    }

    private static func installEventHandlerIfNeeded() throws {
        lock.lock()
        let shouldInstall = !eventHandlerInstalled
        lock.unlock()

        guard shouldInstall else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotkeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )

                guard parameterStatus == noErr,
                      hotkeyID.signature == HotkeyService.signature,
                      let command = Command(rawValue: hotkeyID.id)
                else {
                    return OSStatus(eventNotHandledErr)
                }

                HotkeyService.lock.lock()
                let handler = HotkeyService.handlers[hotkeyID.id]
                HotkeyService.lock.unlock()

                guard let handler else {
                    return OSStatus(eventNotHandledErr)
                }

                handler(command)
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )

        guard status == noErr else {
            throw makeError(code: status)
        }

        lock.lock()
        eventHandlerInstalled = true
        lock.unlock()
    }

    private static func makeError(code: OSStatus) -> NSError {
        NSError(
            domain: "LuxControl.HotkeyService",
            code: Int(code),
            userInfo: nil
        )
    }
}
