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

    private let lock = NSRecursiveLock()
    private let ownerID = UUID()
    private let handler: @Sendable (Command) -> Void
    private let systemClient: HotkeySystemClient
    private var registrations: [UInt32: HotkeyRegistration] = [:]

    fileprivate static let signature: OSType = 0x56465245
    private static let staticLock = NSRecursiveLock()
    private static let operationLock = NSRecursiveLock()
    nonisolated(unsafe) private static var routes: [UInt32: HotkeyRoute] = [:]
    nonisolated(unsafe) private static var nextHotkeyID: UInt32 = 1
    nonisolated(unsafe) private static var eventHandlerInstalled = false
    nonisolated(unsafe) private static var eventHandlerRef: EventHandlerRef?

    public convenience init(handler: @escaping @Sendable (Command) -> Void) {
        self.init(systemClient: .carbon, handler: handler)
    }

    init(
        systemClient: HotkeySystemClient,
        handler: @escaping @Sendable (Command) -> Void
    ) {
        self.systemClient = systemClient
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
        lock.lock()
        defer { lock.unlock() }

        try Self.installEventHandlerIfNeeded(using: systemClient)
        stopLocked()

        do {
            for (command, shortcut) in shortcuts {
                let id = Self.allocateHotkeyID()
                let hotkeyID = EventHotKeyID(signature: Self.signature, id: id)
                Self.operationLock.lock()
                let registration: HotkeyRegistration
                do {
                    registration = try systemClient.registerHotkey(
                        shortcut.keyCode,
                        shortcut.modifiers,
                        hotkeyID
                    )
                    Self.operationLock.unlock()
                } catch {
                    Self.operationLock.unlock()
                    throw error
                }

                registrations[id] = registration
                Self.addRoute(
                    id: id,
                    ownerID: ownerID,
                    command: command,
                    handler: handler
                )
            }
        } catch {
            stopLocked()
            throw error
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        stopLocked()
    }

    public func simulate(_ command: Command) {
        handler(command)
    }

    @discardableResult
    static func dispatchRegisteredHotkey(id: UInt32) -> Bool {
        staticLock.lock()
        let route = routes[id]
        staticLock.unlock()

        guard let route else {
            return false
        }

        route.handler(route.command)
        return true
    }

    private func stopLocked() {
        let ids = Array(registrations.keys)
        let currentRegistrations = registrations
        registrations.removeAll()
        Self.removeRoutes(ids: ids, ownerID: ownerID)

        for registration in currentRegistrations.values {
            Self.operationLock.lock()
            registration.unregister()
            Self.operationLock.unlock()
        }
    }

    static func resetForTesting() {
        staticLock.lock()
        routes.removeAll()
        nextHotkeyID = 1
        eventHandlerInstalled = false
        eventHandlerRef = nil
        staticLock.unlock()
    }

    private static func installEventHandlerIfNeeded(using systemClient: HotkeySystemClient) throws {
        staticLock.lock()
        defer { staticLock.unlock() }

        guard !eventHandlerInstalled else {
            return
        }

        eventHandlerRef = try systemClient.installEventHandler()
        eventHandlerInstalled = true
    }

    private static func allocateHotkeyID() -> UInt32 {
        staticLock.lock()
        defer { staticLock.unlock() }

        let id = nextHotkeyID
        nextHotkeyID &+= 1
        if nextHotkeyID == 0 {
            nextHotkeyID = 1
        }
        return id
    }

    private static func addRoute(
        id: UInt32,
        ownerID: UUID,
        command: Command,
        handler: @escaping @Sendable (Command) -> Void
    ) {
        staticLock.lock()
        routes[id] = HotkeyRoute(ownerID: ownerID, command: command, handler: handler)
        staticLock.unlock()
    }

    private static func removeRoutes(ids: [UInt32], ownerID: UUID) {
        staticLock.lock()
        for id in ids where routes[id]?.ownerID == ownerID {
            routes.removeValue(forKey: id)
        }
        staticLock.unlock()
    }

    fileprivate static func makeError(code: OSStatus) -> NSError {
        NSError(
            domain: "LuxControl.HotkeyService",
            code: Int(code),
            userInfo: nil
        )
    }
}

struct HotkeyRegistration: @unchecked Sendable {
    private let unregisterHandler: @Sendable () -> Void

    init(unregister: @escaping @Sendable () -> Void) {
        self.unregisterHandler = unregister
    }

    func unregister() {
        unregisterHandler()
    }
}

struct HotkeySystemClient: @unchecked Sendable {
    let installEventHandler: @Sendable () throws -> EventHandlerRef?
    let registerHotkey: @Sendable (
        _ keyCode: UInt32,
        _ modifiers: UInt32,
        _ hotkeyID: EventHotKeyID
    ) throws -> HotkeyRegistration

    static let carbon = HotkeySystemClient(
        installEventHandler: {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            var eventHandlerRef: EventHandlerRef?
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
                          hotkeyID.signature == HotkeyService.signature
                    else {
                        return OSStatus(eventNotHandledErr)
                    }

                    return HotkeyService.dispatchRegisteredHotkey(id: hotkeyID.id)
                        ? noErr
                        : OSStatus(eventNotHandledErr)
                },
                1,
                &eventType,
                nil,
                &eventHandlerRef
            )

            guard status == noErr else {
                throw HotkeyService.makeError(code: status)
            }

            return eventHandlerRef
        },
        registerHotkey: { keyCode, modifiers, hotkeyID in
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                keyCode,
                modifiers,
                hotkeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )

            guard status == noErr, let ref else {
                throw HotkeyService.makeError(code: status)
            }

            let reference = EventHotKeyReference(ref)
            return HotkeyRegistration {
                reference.unregister()
            }
        }
    )
}

private final class EventHotKeyReference: @unchecked Sendable {
    private let ref: EventHotKeyRef

    init(_ ref: EventHotKeyRef) {
        self.ref = ref
    }

    func unregister() {
        UnregisterEventHotKey(ref)
    }
}

private struct HotkeyRoute: Sendable {
    let ownerID: UUID
    let command: HotkeyService.Command
    let handler: @Sendable (HotkeyService.Command) -> Void
}
