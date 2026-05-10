import Testing
@testable import LuxControlCore

@Suite("Brightness model")
struct BrightnessModelTests {
    @Test("refreshDisplays loads displays and selects first controllable display")
    func refreshDisplaysLoadsDisplaysAndSelectsFirstControllable() async {
        let unsupported = display(id: 1, name: "Unsupported", supportLevel: .unsupported)
        let controllable = display(id: 2, name: "Controllable", supportLevel: .brightnessOnly)
        let full = display(id: 3, name: "Full", supportLevel: .full)
        let controller = MockDisplayController(displays: [unsupported, controllable, full])
        await controller.setStoredState(.init(brightness: .init(percent: 22), boostEnabled: false), for: controllable.id)
        await controller.setStoredState(.init(brightness: .init(percent: 88), boostEnabled: true), for: full.id)
        let model = BrightnessModel(controller: controller)

        await model.refreshDisplays()
        let snapshot = await model.snapshot

        #expect(snapshot.displays == [unsupported, controllable, full])
        #expect(snapshot.selectedDisplay == controllable)
        #expect(snapshot.states["cg-1"] == .init(brightness: .init(percent: 50), boostEnabled: false))
        #expect(snapshot.states["cg-2"] == .init(brightness: .init(percent: 22), boostEnabled: false))
        #expect(snapshot.states["cg-3"] == .init(brightness: .init(percent: 88), boostEnabled: true))
        #expect(snapshot.lastError == nil)
    }

    @Test("setBrightness routes to selected display and updates snapshot state")
    func setBrightnessRoutesToSelectedDisplayAndUpdatesSnapshotState() async throws {
        let selected = display(id: 11, name: "Selected", supportLevel: .full)
        let other = display(id: 12, name: "Other", supportLevel: .full)
        let controller = MockDisplayController(displays: [selected, other])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()

        try await model.setBrightness(.init(percent: 73))

        #expect(await controller.setBrightnessCalls == [selected.id])
        #expect(await controller.state(for: selected.id).brightness == .init(percent: 73))
        #expect(await model.snapshot.states["cg-11"]?.brightness == .init(percent: 73))
        #expect(await model.snapshot.states["cg-12"]?.brightness == .init(percent: 50))
    }

    @Test("setBoostEnabled throws unsupported for brightnessOnly display")
    func setBoostEnabledThrowsUnsupportedForBrightnessOnlyDisplay() async {
        let brightnessOnly = display(id: 21, name: "Brightness Only", supportLevel: .brightnessOnly)
        let controller = MockDisplayController(displays: [brightnessOnly])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()

        await #expect(throws: DisplayControlError.unsupported(.brightnessOnly)) {
            try await model.setBoostEnabled(true)
        }
        #expect(await controller.setBoostCalls.isEmpty)
        #expect(await model.snapshot.states["cg-21"]?.boostEnabled == false)
    }

    private func display(id: UInt32, name: String, supportLevel: DisplaySupportLevel) -> Display {
        Display(
            id: .directDisplayID(id),
            name: name,
            isBuiltin: false,
            supportLevel: supportLevel
        )
    }
}

actor MockDisplayController: DisplayControlling {
    var displays: [Display]
    var states: [String: DisplayState]
    var setBrightnessCalls: [DisplayID]
    var setBoostCalls: [DisplayID]

    init(
        displays: [Display],
        states: [String: DisplayState] = [:],
        setBrightnessCalls: [DisplayID] = [],
        setBoostCalls: [DisplayID] = []
    ) {
        self.displays = displays
        self.states = states
        self.setBrightnessCalls = setBrightnessCalls
        self.setBoostCalls = setBoostCalls
    }

    func discover() async -> [Display] {
        displays
    }

    func readState(for display: DisplayID) async -> DisplayState {
        states[stableKey(for: display)] ?? .init(brightness: .init(percent: 50), boostEnabled: false)
    }

    func setBrightness(_ value: BrightnessValue, for display: DisplayID) async throws {
        setBrightnessCalls.append(display)
        let key = stableKey(for: display)
        let current = states[key] ?? .init(brightness: .init(percent: 50), boostEnabled: false)
        states[key] = .init(brightness: value, boostEnabled: current.boostEnabled)
    }

    func setBoostEnabled(_ enabled: Bool, for display: DisplayID) async throws {
        setBoostCalls.append(display)
        let key = stableKey(for: display)
        let current = states[key] ?? .init(brightness: .init(percent: 50), boostEnabled: false)
        states[key] = .init(brightness: current.brightness, boostEnabled: enabled)
    }

    func setStoredState(_ state: DisplayState, for display: DisplayID) {
        states[stableKey(for: display)] = state
    }

    func state(for display: DisplayID) -> DisplayState {
        states[stableKey(for: display)] ?? .init(brightness: .init(percent: 50), boostEnabled: false)
    }

    private func stableKey(for display: DisplayID) -> String {
        switch display {
        case .directDisplayID(let displayID):
            return "cg-\(displayID)"
        }
    }
}
