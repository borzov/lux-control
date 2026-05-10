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

    public private(set) var snapshot = BrightnessSnapshot()

    public init(controller: DisplayControlling) {
        self.controller = controller
    }

    public func refreshDisplays() async {
        let displays = await controller.discover()
        var states: [String: DisplayState] = [:]

        for display in displays {
            states[display.stableKey] = await controller.readState(for: display.id)
        }

        snapshot = BrightnessSnapshot(
            displays: displays,
            selectedDisplay: displays.first(where: \.isControllable),
            states: states,
            lastError: nil
        )
    }

    public func selectDisplay(stableKey: String) {
        snapshot.selectedDisplay = snapshot.displays.first { $0.stableKey == stableKey }
    }

    public func setBrightness(_ value: BrightnessValue) async throws {
        let display = try selectedDisplay()

        guard display.supportLevel == .full || display.supportLevel == .brightnessOnly else {
            throw DisplayControlError.unsupported(display.supportLevel)
        }

        try await controller.setBrightness(value, for: display.id)
        let current = snapshot.states[display.stableKey] ?? .init(brightness: .init(percent: 50), boostEnabled: false)
        snapshot.states[display.stableKey] = .init(brightness: value, boostEnabled: current.boostEnabled)
    }

    public func setBoostEnabled(_ enabled: Bool) async throws {
        let display = try selectedDisplay()

        guard display.supportLevel == .full else {
            throw DisplayControlError.unsupported(display.supportLevel)
        }

        try await controller.setBoostEnabled(enabled, for: display.id)
        let current = snapshot.states[display.stableKey] ?? .init(brightness: .init(percent: 50), boostEnabled: false)
        snapshot.states[display.stableKey] = .init(brightness: current.brightness, boostEnabled: enabled)
    }

    private func selectedDisplay() throws -> Display {
        guard let display = snapshot.selectedDisplay else {
            throw DisplayControlError.displayNotFound
        }

        return display
    }
}

private extension Display {
    var isControllable: Bool {
        supportLevel == .full || supportLevel == .brightnessOnly
    }
}
