public struct BrightnessSnapshot: Equatable, Sendable {
    public var displays: [Display]
    public var selectedDisplay: Display?
    public var states: [String: DisplayState]
    public var lastError: String?

    public init(
        displays: [Display] = [],
        selectedDisplay: Display? = nil,
        states: [String: DisplayState] = [:],
        lastError: String? = nil
    ) {
        self.displays = displays
        self.selectedDisplay = selectedDisplay
        self.states = states
        self.lastError = lastError
    }
}

public actor BrightnessModel {
    private let controller: DisplayControlling
    private var errorRevision = 0
    private var nextCommandRevision: UInt64 = 0
    private var commandStartRevisions: [CommandKey: UInt64] = [:]
    private var stateRevision = 0
    private var stateRevisions: [String: Int] = [:]
    private var refreshGeneration = 0

    public private(set) var snapshot = BrightnessSnapshot()

    public init(controller: DisplayControlling) {
        self.controller = controller
    }

    public func refreshDisplays() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let startingErrorRevision = errorRevision
        let startingStateRevisions = stateRevisions
        let displays = await controller.discover()
        var refreshedStates: [String: DisplayState] = [:]

        for display in displays {
            refreshedStates[display.stableKey] = await controller.readState(for: display.id)
        }

        guard generation == refreshGeneration else {
            return
        }

        let selectedStableKey = snapshot.selectedDisplay?.stableKey
        let lastError = errorRevision == startingErrorRevision ? nil : snapshot.lastError
        if errorRevision == startingErrorRevision {
            errorRevision += 1
        }
        let states = mergedStates(
            refreshedStates,
            for: displays,
            startingStateRevisions: startingStateRevisions
        )
        snapshot = BrightnessSnapshot(
            displays: displays,
            selectedDisplay: selectedDisplay(in: displays, preserving: selectedStableKey),
            states: states,
            lastError: lastError
        )
        let displayKeys = Set(displays.map(\.stableKey))
        stateRevisions = stateRevisions.filter { displayKeys.contains($0.key) }
        commandStartRevisions = commandStartRevisions.filter { displayKeys.contains($0.key.stableKey) }
    }

    public func selectDisplay(stableKey: String) {
        snapshot.selectedDisplay = snapshot.displays.first { $0.stableKey == stableKey }
    }

    public func setBrightness(_ value: BrightnessValue) async throws {
        let stableKey: String
        do {
            stableKey = try selectedDisplay().stableKey
        } catch {
            throw recordUnscopedFailure(error)
        }

        try await setBrightness(value, forStableKey: stableKey)
    }

    public func setBrightness(_ value: BrightnessValue, forStableKey stableKey: String) async throws {
        let display: Display
        do {
            display = try resolveDisplay(forStableKey: stableKey)
        } catch {
            throw recordUnscopedFailure(error)
        }
        let stableKey = display.stableKey
        let commandKey = CommandKey(stableKey: stableKey, kind: .brightness)
        let commandRevision = startCommand(commandKey)

        do {
            guard display.supportLevel == .full || display.supportLevel == .brightnessOnly else {
                throw DisplayControlError.unsupported(display.supportLevel)
            }

            do {
                try Task.checkCancellation()
                try await controller.setBrightness(value, for: display.id)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw normalizedControlError(error)
            }

            completeSuccessfulCommand(commandKey, revision: commandRevision) { current in
                .init(brightness: value, boostEnabled: current.boostEnabled)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw recordFailure(error, for: commandKey, revision: commandRevision)
        }
    }

    public func setBoostEnabled(_ enabled: Bool) async throws {
        let stableKey: String
        do {
            stableKey = try selectedDisplay().stableKey
        } catch {
            throw recordUnscopedFailure(error)
        }

        try await setBoostEnabled(enabled, forStableKey: stableKey)
    }

    public func setBoostEnabled(_ enabled: Bool, forStableKey stableKey: String) async throws {
        let display: Display
        do {
            display = try resolveDisplay(forStableKey: stableKey)
        } catch {
            throw recordUnscopedFailure(error)
        }
        let stableKey = display.stableKey
        let commandKey = CommandKey(stableKey: stableKey, kind: .boost)
        let commandRevision = startCommand(commandKey)

        do {
            guard display.supportLevel == .full else {
                throw DisplayControlError.unsupported(display.supportLevel)
            }

            do {
                try Task.checkCancellation()
                try await controller.setBoostEnabled(enabled, for: display.id)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw normalizedControlError(error)
            }

            completeSuccessfulCommand(commandKey, revision: commandRevision) { current in
                .init(brightness: current.brightness, boostEnabled: enabled)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw recordFailure(error, for: commandKey, revision: commandRevision)
        }
    }

    private func selectedDisplay() throws -> Display {
        guard let display = snapshot.selectedDisplay else {
            throw DisplayControlError.displayNotFound
        }

        return display
    }

    private func resolveDisplay(forStableKey stableKey: String) throws -> Display {
        guard let display = snapshot.displays.first(where: { $0.stableKey == stableKey }) else {
            throw DisplayControlError.displayNotFound
        }

        return display
    }

    private func selectedDisplay(in displays: [Display], preserving stableKey: String?) -> Display? {
        if let stableKey,
           let display = displays.first(where: { $0.stableKey == stableKey }) {
            return display
        }

        return displays.first(where: \.isControllable)
    }

    private func mergedStates(
        _ refreshedStates: [String: DisplayState],
        for displays: [Display],
        startingStateRevisions: [String: Int]
    ) -> [String: DisplayState] {
        var states = refreshedStates
        for display in displays {
            let stableKey = display.stableKey
            let startingRevision = startingStateRevisions[stableKey] ?? 0
            let currentRevision = stateRevisions[stableKey] ?? 0
            if currentRevision > startingRevision,
               let currentState = snapshot.states[stableKey] {
                states[stableKey] = currentState
            }
        }
        return states
    }

    private func updateStateIfDisplayExists(
        stableKey: String,
        _ transform: (DisplayState) -> DisplayState
    ) {
        guard snapshot.displays.contains(where: { $0.stableKey == stableKey }) else {
            return
        }

        let current = snapshot.states[stableKey] ?? .init(brightness: .init(percent: 50), boostEnabled: false)
        snapshot.states[stableKey] = transform(current)
        stateRevision += 1
        stateRevisions[stableKey] = stateRevision
    }

    private func startCommand(_ commandKey: CommandKey) -> UInt64 {
        nextCommandRevision += 1
        commandStartRevisions[commandKey] = nextCommandRevision
        return nextCommandRevision
    }

    private func isLatestCommand(_ commandKey: CommandKey, revision: UInt64) -> Bool {
        commandStartRevisions[commandKey] == revision
    }

    private func isLatestGlobalCommand(revision: UInt64) -> Bool {
        nextCommandRevision == revision
    }

    private func completeSuccessfulCommand(
        _ commandKey: CommandKey,
        revision: UInt64,
        _ transform: (DisplayState) -> DisplayState
    ) {
        guard isLatestCommand(commandKey, revision: revision) else {
            return
        }

        clearLastErrorIfLatestGlobalCommand(revision: revision)
        updateStateIfDisplayExists(stableKey: commandKey.stableKey, transform)
    }

    private func recordFailure(_ error: any Error, for commandKey: CommandKey, revision: UInt64) -> DisplayControlError {
        let controlError = normalizedControlError(error)
        guard isLatestCommand(commandKey, revision: revision) else {
            return controlError
        }

        recordLastErrorIfLatestGlobalCommand(controlError, revision: revision)
        return controlError
    }

    private func clearLastErrorIfLatestGlobalCommand(revision: UInt64) {
        guard isLatestGlobalCommand(revision: revision) else {
            return
        }

        errorRevision += 1
        snapshot.lastError = nil
    }

    private func recordLastErrorIfLatestGlobalCommand(_ error: DisplayControlError, revision: UInt64) {
        guard isLatestGlobalCommand(revision: revision) else {
            return
        }

        errorRevision += 1
        snapshot.lastError = error.localizedDescription
    }

    private func recordUnscopedFailure(_ error: any Error) -> DisplayControlError {
        let controlError = normalizedControlError(error)
        nextCommandRevision += 1
        errorRevision += 1
        snapshot.lastError = controlError.localizedDescription
        return controlError
    }

    private func normalizedControlError(_ error: any Error) -> DisplayControlError {
        if let controlError = error as? DisplayControlError {
            return controlError
        }

        return .writeFailed(error.localizedDescription)
    }
}

private enum ControlKind: Hashable {
    case brightness
    case boost
}

private struct CommandKey: Hashable {
    let stableKey: String
    let kind: ControlKind
}

private extension Display {
    var isControllable: Bool {
        supportLevel == .full || supportLevel == .brightnessOnly
    }
}
