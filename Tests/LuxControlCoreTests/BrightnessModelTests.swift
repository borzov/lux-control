import Foundation
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

    @Test("refreshDisplays preserves selected display when it is still present")
    func refreshDisplaysPreservesSelectedDisplayWhenItIsStillPresent() async {
        let first = display(id: 4, name: "First", supportLevel: .full)
        let second = display(id: 5, name: "Second", supportLevel: .full)
        let controller = MockDisplayController(displays: [first, second])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()

        await model.selectDisplay(stableKey: second.stableKey)
        await model.refreshDisplays()

        #expect(await model.snapshot.selectedDisplay == second)
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

    @Test("setBrightness succeeds for brightnessOnly display")
    func setBrightnessSucceedsForBrightnessOnlyDisplay() async throws {
        let brightnessOnly = display(id: 31, name: "Brightness Only", supportLevel: .brightnessOnly)
        let controller = MockDisplayController(displays: [brightnessOnly])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()

        try await model.setBrightness(.init(percent: 64))

        #expect(await controller.setBrightnessCalls == [brightnessOnly.id])
        #expect(await model.snapshot.states["cg-31"]?.brightness == .init(percent: 64))
        #expect(await model.snapshot.lastError == nil)
    }

    @Test("setBoostEnabled succeeds for full display and updates snapshot state")
    func setBoostEnabledSucceedsForFullDisplayAndUpdatesSnapshotState() async throws {
        let full = display(id: 41, name: "Full", supportLevel: .full)
        let controller = MockDisplayController(displays: [full])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()

        try await model.setBoostEnabled(true)

        #expect(await controller.setBoostCalls == [full.id])
        #expect(await model.snapshot.states["cg-41"]?.boostEnabled == true)
        #expect(await model.snapshot.lastError == nil)
    }

    @Test("selectDisplay routes subsequent brightness command to selected display")
    func selectDisplayRoutesSubsequentBrightnessCommandToSelectedDisplay() async throws {
        let first = display(id: 51, name: "First", supportLevel: .full)
        let second = display(id: 52, name: "Second", supportLevel: .full)
        let controller = MockDisplayController(displays: [first, second])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()

        await model.selectDisplay(stableKey: second.stableKey)
        try await model.setBrightness(.init(percent: 12))

        #expect(await controller.setBrightnessCalls == [second.id])
        #expect(await model.snapshot.states["cg-51"]?.brightness == .init(percent: 50))
        #expect(await model.snapshot.states["cg-52"]?.brightness == .init(percent: 12))
    }

    @Test("setBrightness throws displayNotFound when no display is selected")
    func setBrightnessThrowsDisplayNotFoundWhenNoDisplayIsSelected() async {
        let controller = MockDisplayController(displays: [])
        let model = BrightnessModel(controller: controller)

        await #expect(throws: DisplayControlError.displayNotFound) {
            try await model.setBrightness(.init(percent: 42))
        }
        #expect(await model.snapshot.lastError == DisplayControlError.displayNotFound.localizedDescription)
    }

    @Test("setBrightness throws unsupported for detectOnly display")
    func setBrightnessThrowsUnsupportedForDetectOnlyDisplay() async {
        let detectOnly = display(id: 61, name: "Detect Only", supportLevel: .detectOnly)
        let controller = MockDisplayController(displays: [detectOnly])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()

        await model.selectDisplay(stableKey: detectOnly.stableKey)
        await #expect(throws: DisplayControlError.unsupported(.detectOnly)) {
            try await model.setBrightness(.init(percent: 42))
        }
        #expect(await controller.setBrightnessCalls.isEmpty)
        #expect(await model.snapshot.lastError == DisplayControlError.unsupported(.detectOnly).localizedDescription)
    }

    @Test("controller write failure maps to writeFailed and updates lastError")
    func controllerWriteFailureMapsToWriteFailedAndUpdatesLastError() async {
        let full = display(id: 71, name: "Full", supportLevel: .full)
        let controller = MockDisplayController(displays: [full])
        await controller.setBrightnessError(TestWriteError(message: "hardware denied"))
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()

        await #expect(throws: DisplayControlError.writeFailed("hardware denied")) {
            try await model.setBrightness(.init(percent: 42))
        }
        #expect(await model.snapshot.states["cg-71"]?.brightness == .init(percent: 50))
        #expect(await model.snapshot.lastError == DisplayControlError.writeFailed("hardware denied").localizedDescription)
    }

    @Test("DisplayControlError from controller passes through unchanged")
    func displayControlErrorFromControllerPassesThroughUnchanged() async {
        let full = display(id: 81, name: "Full", supportLevel: .full)
        let controller = MockDisplayController(displays: [full])
        await controller.setBoostError(DisplayControlError.writeFailed("ddc failed"))
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()

        await #expect(throws: DisplayControlError.writeFailed("ddc failed")) {
            try await model.setBoostEnabled(true)
        }
        #expect(await model.snapshot.states["cg-81"]?.boostEnabled == false)
        #expect(await model.snapshot.lastError == DisplayControlError.writeFailed("ddc failed").localizedDescription)
    }

    @Test("setBrightness updates original display state after selection changes during write")
    func setBrightnessUpdatesOriginalDisplayStateAfterSelectionChangesDuringWrite() async throws {
        let first = display(id: 91, name: "First", supportLevel: .full)
        let second = display(id: 92, name: "Second", supportLevel: .full)
        let controller = MockDisplayController(displays: [first, second])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()
        await controller.setOnSetBrightness {
            await model.selectDisplay(stableKey: second.stableKey)
        }

        try await model.setBrightness(.init(percent: 25))

        #expect(await controller.setBrightnessCalls == [first.id])
        #expect(await model.snapshot.selectedDisplay == second)
        #expect(await model.snapshot.states["cg-91"]?.brightness == .init(percent: 25))
        #expect(await model.snapshot.states["cg-92"]?.brightness == .init(percent: 50))
    }

    @Test("setBrightness skips snapshot update when original display disappears during write")
    func setBrightnessSkipsSnapshotUpdateWhenOriginalDisplayDisappearsDuringWrite() async throws {
        let first = display(id: 101, name: "First", supportLevel: .full)
        let second = display(id: 102, name: "Second", supportLevel: .full)
        let controller = MockDisplayController(displays: [first, second])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()
        await controller.setOnSetBrightness {
            await controller.setDisplays([second])
            await model.refreshDisplays()
        }

        try await model.setBrightness(.init(percent: 35))

        #expect(await controller.setBrightnessCalls == [first.id])
        #expect(await model.snapshot.displays == [second])
        #expect(await model.snapshot.states["cg-101"] == nil)
        #expect(await model.snapshot.states["cg-102"]?.brightness == .init(percent: 50))
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
    var brightnessError: (any Error)?
    var boostError: (any Error)?
    var onSetBrightness: (@Sendable () async -> Void)?
    var onSetBoost: (@Sendable () async -> Void)?

    init(
        displays: [Display],
        states: [String: DisplayState] = [:],
        setBrightnessCalls: [DisplayID] = [],
        setBoostCalls: [DisplayID] = [],
        brightnessError: (any Error)? = nil,
        boostError: (any Error)? = nil,
        onSetBrightness: (@Sendable () async -> Void)? = nil,
        onSetBoost: (@Sendable () async -> Void)? = nil
    ) {
        self.displays = displays
        self.states = states
        self.setBrightnessCalls = setBrightnessCalls
        self.setBoostCalls = setBoostCalls
        self.brightnessError = brightnessError
        self.boostError = boostError
        self.onSetBrightness = onSetBrightness
        self.onSetBoost = onSetBoost
    }

    func discover() async -> [Display] {
        displays
    }

    func readState(for display: DisplayID) async -> DisplayState {
        states[stableKey(for: display)] ?? .init(brightness: .init(percent: 50), boostEnabled: false)
    }

    func setBrightness(_ value: BrightnessValue, for display: DisplayID) async throws {
        setBrightnessCalls.append(display)
        if let onSetBrightness {
            await onSetBrightness()
        }
        if let brightnessError {
            throw brightnessError
        }
        let key = stableKey(for: display)
        let current = states[key] ?? .init(brightness: .init(percent: 50), boostEnabled: false)
        states[key] = .init(brightness: value, boostEnabled: current.boostEnabled)
    }

    func setBoostEnabled(_ enabled: Bool, for display: DisplayID) async throws {
        setBoostCalls.append(display)
        if let onSetBoost {
            await onSetBoost()
        }
        if let boostError {
            throw boostError
        }
        let key = stableKey(for: display)
        let current = states[key] ?? .init(brightness: .init(percent: 50), boostEnabled: false)
        states[key] = .init(brightness: current.brightness, boostEnabled: enabled)
    }

    func setStoredState(_ state: DisplayState, for display: DisplayID) {
        states[stableKey(for: display)] = state
    }

    func setDisplays(_ displays: [Display]) {
        self.displays = displays
    }

    func state(for display: DisplayID) -> DisplayState {
        states[stableKey(for: display)] ?? .init(brightness: .init(percent: 50), boostEnabled: false)
    }

    func setBrightnessError(_ error: any Error) {
        brightnessError = error
    }

    func setBoostError(_ error: any Error) {
        boostError = error
    }

    func setOnSetBrightness(_ action: @escaping @Sendable () async -> Void) {
        onSetBrightness = action
    }

    private func stableKey(for display: DisplayID) -> String {
        switch display {
        case .directDisplayID(let displayID):
            return "cg-\(displayID)"
        }
    }
}

private struct TestWriteError: Error, LocalizedError, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }
}
