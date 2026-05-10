import Foundation
import LuxControlCore

public actor PublicDisplayController: DisplayControlling {
    private let discovery: any DisplayDiscovering
    private let brightnessClient: any DisplayBrightnessClient
    private let boostClient: any DisplayBoostClient
    private var states: [String: DisplayState] = [:]

    public init(discovery: any DisplayDiscovering = CGDisplayDiscovery()) {
        self.discovery = discovery
        self.brightnessClient = DisplayServicesBrightnessClient()
        self.boostClient = EDRBoostClient.shared
    }

    init(
        discovery: any DisplayDiscovering,
        brightnessClient: any DisplayBrightnessClient,
        boostClient: any DisplayBoostClient
    ) {
        self.discovery = discovery
        self.brightnessClient = brightnessClient
        self.boostClient = boostClient
    }

    public func discover() async -> [Display] {
        await discovery.discover()
    }

    public func readState(for display: DisplayID) async -> DisplayState {
        let key = await stateKey(for: display)
        let previous = states[key] ?? DisplayState(brightness: BrightnessValue(percent: 50), boostEnabled: false)

        guard let directDisplayID = directDisplayID(for: display),
              let brightness = brightnessClient.readBrightness(for: directDisplayID)
        else {
            return previous
        }

        let percent = Int((brightness * 100).rounded())
        let boostEnabled = await boostClient.isBoostEnabled(for: directDisplayID)
        return DisplayState(brightness: BrightnessValue(percent: percent), boostEnabled: boostEnabled)
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
        if let directDisplayID = directDisplayID(for: display),
           brightnessClient.canChangeBrightness(for: directDisplayID) {
            do {
                try brightnessClient.setBrightness(Float(value.percent) / 100, for: directDisplayID)
            } catch {
                throw DisplayControlError.writeFailed(error.localizedDescription)
            }
        }
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
        if let directDisplayID = directDisplayID(for: display) {
            do {
                try await boostClient.setBoostEnabled(enabled, for: directDisplayID)
            } catch {
                throw DisplayControlError.writeFailed(error.localizedDescription)
            }
        }
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

    private func directDisplayID(for display: DisplayID) -> UInt32? {
        switch display {
        case .directDisplayID(let id):
            return id
        }
    }
}
