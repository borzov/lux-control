import Foundation
import LuxControlCore

public actor PublicDisplayController: DisplayControlling {
    private let discovery: any DisplayDiscovering
    private var states: [String: DisplayState] = [:]

    public init(discovery: any DisplayDiscovering = CGDisplayDiscovery()) {
        self.discovery = discovery
    }

    public func discover() async -> [Display] {
        await discovery.discover()
    }

    public func readState(for display: DisplayID) async -> DisplayState {
        let key = await stateKey(for: display)
        return states[key] ?? DisplayState(brightness: BrightnessValue(percent: 50), boostEnabled: false)
    }

    public func setBrightness(_ value: BrightnessValue, for display: DisplayID) async throws {
        let displays = await discover()
        guard let target = displays.first(where: { $0.id == display }) else {
            throw DisplayControlError.displayNotFound
        }
        guard target.supportLevel == .full || target.supportLevel == .brightnessOnly else {
            throw DisplayControlError.unsupported(target.supportLevel)
        }

        let key = target.stableKey
        let previous = states[key] ?? DisplayState(brightness: BrightnessValue(percent: 50), boostEnabled: false)
        states[key] = DisplayState(brightness: value, boostEnabled: previous.boostEnabled)
    }

    public func setBoostEnabled(_ enabled: Bool, for display: DisplayID) async throws {
        let displays = await discover()
        guard let target = displays.first(where: { $0.id == display }) else {
            throw DisplayControlError.displayNotFound
        }
        guard target.supportLevel == .full else {
            throw DisplayControlError.unsupported(target.supportLevel)
        }

        let key = target.stableKey
        let previous = states[key] ?? DisplayState(brightness: BrightnessValue(percent: 50), boostEnabled: false)
        states[key] = DisplayState(brightness: previous.brightness, boostEnabled: enabled)
    }

    private func stateKey(for display: DisplayID) async -> String {
        let displays = await discover()
        guard let target = displays.first(where: { $0.id == display }) else {
            return fallbackKey(for: display)
        }

        return target.stableKey
    }

    private func fallbackKey(for display: DisplayID) -> String {
        switch display {
        case .directDisplayID(let id):
            return "cg-\(id)"
        }
    }
}
