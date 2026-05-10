public protocol DisplayControlling: Sendable {
    func discover() async -> [Display]
    func readState(for display: DisplayID) async -> DisplayState
    func setBrightness(_ value: BrightnessValue, for display: DisplayID) async throws
    func setBoostEnabled(_ enabled: Bool, for display: DisplayID) async throws
}
