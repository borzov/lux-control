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

    public private(set) var snapshot = BrightnessSnapshot()

    public init(controller: DisplayControlling) {
        self.controller = controller
    }

    public func refreshDisplays() async {
        let startingErrorRevision = errorRevision
        let displays = await controller.discover()
        var states: [String: DisplayState] = [:]

        for display in displays {
            states[display.stableKey] = await controller.readState(for: display.id)
        }

        let selectedStableKey = snapshot.selectedDisplay?.stableKey
        let lastError = errorRevision == startingErrorRevision ? nil : snapshot.lastError
        if errorRevision == startingErrorRevision {
            errorRevision += 1
        }
        snapshot = BrightnessSnapshot(
            displays: displays,
            selectedDisplay: selectedDisplay(in: displays, preserving: selectedStableKey),
            states: states,
            lastError: lastError
        )
    }

    public func selectDisplay(stableKey: String) {
        snapshot.selectedDisplay = snapshot.displays.first { $0.stableKey == stableKey }
    }

    public func setBrightness(_ value: BrightnessValue) async throws {
        do {
            let display = try selectedDisplay()
            let stableKey = display.stableKey

            guard display.supportLevel == .full || display.supportLevel == .brightnessOnly else {
                throw DisplayControlError.unsupported(display.supportLevel)
            }

            do {
                try await controller.setBrightness(value, for: display.id)
            } catch {
                throw normalizedControlError(error)
            }

            clearLastError()
            updateStateIfDisplayExists(stableKey: stableKey) { current in
                .init(brightness: value, boostEnabled: current.boostEnabled)
            }
        } catch {
            throw recordFailure(error)
        }
    }

    public func setBoostEnabled(_ enabled: Bool) async throws {
        do {
            let display = try selectedDisplay()
            let stableKey = display.stableKey

            guard display.supportLevel == .full else {
                throw DisplayControlError.unsupported(display.supportLevel)
            }

            do {
                try await controller.setBoostEnabled(enabled, for: display.id)
            } catch {
                throw normalizedControlError(error)
            }

            clearLastError()
            updateStateIfDisplayExists(stableKey: stableKey) { current in
                .init(brightness: current.brightness, boostEnabled: enabled)
            }
        } catch {
            throw recordFailure(error)
        }
    }

    private func selectedDisplay() throws -> Display {
        guard let display = snapshot.selectedDisplay else {
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

    private func updateStateIfDisplayExists(
        stableKey: String,
        _ transform: (DisplayState) -> DisplayState
    ) {
        guard snapshot.displays.contains(where: { $0.stableKey == stableKey }) else {
            return
        }

        let current = snapshot.states[stableKey] ?? .init(brightness: .init(percent: 50), boostEnabled: false)
        snapshot.states[stableKey] = transform(current)
    }

    private func recordFailure(_ error: any Error) -> DisplayControlError {
        let controlError = normalizedControlError(error)
        errorRevision += 1
        snapshot.lastError = controlError.localizedDescription
        return controlError
    }

    private func clearLastError() {
        errorRevision += 1
        snapshot.lastError = nil
    }

    private func normalizedControlError(_ error: any Error) -> DisplayControlError {
        if let controlError = error as? DisplayControlError {
            return controlError
        }

        return .writeFailed(error.localizedDescription)
    }
}

private extension Display {
    var isControllable: Bool {
        supportLevel == .full || supportLevel == .brightnessOnly
    }
}
