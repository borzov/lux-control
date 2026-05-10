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

    @Test("refreshDisplays preserves newer selection changed while refresh is in flight")
    func refreshDisplaysPreservesNewerSelectionChangedWhileRefreshIsInFlight() async {
        let first = display(id: 6, name: "First", supportLevel: .full)
        let second = display(id: 7, name: "Second", supportLevel: .full)
        let controller = MockDisplayController(displays: [first, second])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()
        let refreshGate = AsyncGate()
        await controller.setOnDiscover {
            await refreshGate.suspend()
        }

        let refreshTask = Task {
            await model.refreshDisplays()
        }
        await refreshGate.waitUntilSuspended()
        await model.selectDisplay(stableKey: second.stableKey)
        await refreshGate.resume()
        await refreshTask.value

        #expect(await model.snapshot.selectedDisplay == second)
    }

    @Test("refreshDisplays clears existing lastError")
    func refreshDisplaysClearsExistingLastError() async {
        let full = display(id: 8, name: "Full", supportLevel: .full)
        let controller = MockDisplayController(displays: [full])
        await controller.setBrightnessError(TestWriteError(message: "transient failure"))
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()

        await #expect(throws: DisplayControlError.writeFailed("transient failure")) {
            try await model.setBrightness(.init(percent: 42))
        }
        #expect(await model.snapshot.lastError != nil)

        await model.refreshDisplays()

        #expect(await model.snapshot.lastError == nil)
    }

    @Test("refreshDisplays preserves newer write error recorded while refresh is in flight")
    func refreshDisplaysPreservesNewerWriteErrorRecordedWhileRefreshIsInFlight() async {
        let full = display(id: 9, name: "Full", supportLevel: .full)
        let controller = MockDisplayController(displays: [full])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()
        await controller.setBrightnessError(TestWriteError(message: "write failed during refresh"))
        let refreshGate = AsyncGate()
        await controller.setOnDiscover {
            await refreshGate.suspend()
        }

        let refreshTask = Task {
            await model.refreshDisplays()
        }
        await refreshGate.waitUntilSuspended()

        await #expect(throws: DisplayControlError.writeFailed("write failed during refresh")) {
            try await model.setBrightness(.init(percent: 42))
        }
        await refreshGate.resume()
        await refreshTask.value

        #expect(await model.snapshot.lastError == DisplayControlError.writeFailed("write failed during refresh").localizedDescription)
    }

    @Test("older successful brightness write does not clear newer write error")
    func olderSuccessfulBrightnessWriteDoesNotClearNewerWriteError() async throws {
        let full = display(id: 10, name: "Full", supportLevel: .full)
        let controller = MockDisplayController(displays: [full])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()
        let writeGate = AsyncGate()
        await controller.setOnSetBrightness {
            await controller.clearOnSetBrightness()
            await writeGate.suspend()
        }

        let olderWrite = Task {
            try await model.setBrightness(.init(percent: 66))
        }
        await writeGate.waitUntilSuspended()
        await controller.setBrightnessError(TestWriteError(message: "newer write failed"))

        await #expect(throws: DisplayControlError.writeFailed("newer write failed")) {
            try await model.setBrightness(.init(percent: 77))
        }
        await controller.clearBrightnessError()
        await writeGate.resume()
        try await olderWrite.value

        #expect(await model.snapshot.states["cg-10"]?.brightness == .init(percent: 50))
        #expect(await model.snapshot.lastError == DisplayControlError.writeFailed("newer write failed").localizedDescription)
    }

    @Test("refreshDisplays does not overwrite newer successful write state")
    func refreshDisplaysDoesNotOverwriteNewerSuccessfulWriteState() async throws {
        let full = display(id: 13, name: "Full", supportLevel: .full)
        let controller = MockDisplayController(displays: [full])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()
        let readGate = AsyncGate()
        await controller.setOnReadState {
            await controller.clearOnReadState()
            await readGate.suspend()
        }

        let refreshTask = Task {
            await model.refreshDisplays()
        }
        await readGate.waitUntilSuspended()
        try await model.setBrightness(.init(percent: 88))
        await readGate.resume()
        await refreshTask.value

        #expect(await model.snapshot.states["cg-13"]?.brightness == .init(percent: 88))
    }

    @Test("refreshDisplays keeps fresh read state for displays without newer local writes")
    func refreshDisplaysKeepsFreshReadStateForDisplaysWithoutNewerLocalWrites() async throws {
        let first = display(id: 14, name: "First", supportLevel: .full)
        let second = display(id: 15, name: "Second", supportLevel: .full)
        let controller = MockDisplayController(displays: [first, second])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()
        await controller.clearReadStateCalls()
        await controller.setStoredState(.init(brightness: .init(percent: 61), boostEnabled: false), for: first.id)
        await controller.setStoredState(.init(brightness: .init(percent: 72), boostEnabled: false), for: second.id)
        let readGate = AsyncGate()
        await controller.setOnReadState {
            if await controller.readStateCalls.count == 2 {
                await controller.clearOnReadState()
                await readGate.suspend()
            }
        }

        let refreshTask = Task {
            await model.refreshDisplays()
        }
        await readGate.waitUntilSuspended()
        try await model.setBrightness(.init(percent: 88))
        await readGate.resume()
        await refreshTask.value

        #expect(await model.snapshot.states["cg-14"]?.brightness == .init(percent: 88))
        #expect(await model.snapshot.states["cg-15"]?.brightness == .init(percent: 72))
    }

    @Test("older refresh completion does not overwrite newer refresh snapshot")
    func olderRefreshCompletionDoesNotOverwriteNewerRefreshSnapshot() async {
        let full = display(id: 17, name: "Full", supportLevel: .full)
        let controller = MockDisplayController(displays: [full])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()
        await controller.clearReadStateCalls()
        await controller.setStoredState(.init(brightness: .init(percent: 20), boostEnabled: false), for: full.id)
        let oldRefreshGate = AsyncGate()
        await controller.setOnReadState {
            await controller.clearOnReadState()
            await oldRefreshGate.suspend()
        }

        let oldRefresh = Task {
            await model.refreshDisplays()
        }
        await oldRefreshGate.waitUntilSuspended()
        await controller.setStoredState(.init(brightness: .init(percent: 90), boostEnabled: true), for: full.id)
        await model.refreshDisplays()
        #expect(await model.snapshot.states["cg-17"] == .init(brightness: .init(percent: 90), boostEnabled: true))

        await oldRefreshGate.resume()
        await oldRefresh.value

        #expect(await model.snapshot.states["cg-17"] == .init(brightness: .init(percent: 90), boostEnabled: true))
    }

    @Test("older failed brightness write does not overwrite newer successful write error state")
    func olderFailedBrightnessWriteDoesNotOverwriteNewerSuccessfulWriteErrorState() async throws {
        let full = display(id: 16, name: "Full", supportLevel: .full)
        let controller = MockDisplayController(displays: [full])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()
        let writeGate = AsyncGate()
        await controller.setOnSetBrightness {
            await controller.clearOnSetBrightness()
            await writeGate.suspend()
        }

        let olderWrite = Task {
            do {
                try await model.setBrightness(.init(percent: 66))
                Issue.record("Older write should fail")
            } catch {
                #expect(error as? DisplayControlError == .writeFailed("older write failed"))
            }
        }
        await writeGate.waitUntilSuspended()
        try await model.setBrightness(.init(percent: 77))
        await controller.setBrightnessError(TestWriteError(message: "older write failed"))
        await writeGate.resume()
        await olderWrite.value

        #expect(await model.snapshot.states["cg-16"]?.brightness == .init(percent: 77))
        #expect(await model.snapshot.lastError == nil)
    }

    @Test("older successful brightness write does not overwrite newer successful brightness state")
    func olderSuccessfulBrightnessWriteDoesNotOverwriteNewerSuccessfulBrightnessState() async throws {
        let full = display(id: 18, name: "Full", supportLevel: .full)
        let controller = MockDisplayController(displays: [full])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()
        let writeGate = AsyncGate()
        await controller.setOnSetBrightness {
            await controller.clearOnSetBrightness()
            await writeGate.suspend()
        }

        let olderWrite = Task {
            try await model.setBrightness(.init(percent: 66))
        }
        await writeGate.waitUntilSuspended()
        try await model.setBrightness(.init(percent: 77))
        await writeGate.resume()
        try await olderWrite.value

        #expect(await model.snapshot.states["cg-18"]?.brightness == .init(percent: 77))
        #expect(await model.snapshot.lastError == nil)
    }

    @Test("newer brightness write updates final state after older brightness completes first")
    func newerBrightnessWriteUpdatesFinalStateAfterOlderBrightnessCompletesFirst() async throws {
        let full = display(id: 20, name: "Full", supportLevel: .full)
        let controller = MockDisplayController(displays: [full])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()
        let olderGate = AsyncGate()
        let newerGate = AsyncGate()
        await controller.setOnSetBrightness {
            switch await controller.setBrightnessCalls.count {
            case 1:
                await olderGate.suspend()
            case 2:
                await newerGate.suspend()
            default:
                break
            }
        }

        let olderWrite = Task {
            try await model.setBrightness(.init(percent: 66))
        }
        await olderGate.waitUntilSuspended()
        let newerWrite = Task {
            try await model.setBrightness(.init(percent: 77))
        }
        await newerGate.waitUntilSuspended()

        await olderGate.resume()
        try await olderWrite.value
        #expect(await model.snapshot.states["cg-20"]?.brightness == .init(percent: 50))

        await newerGate.resume()
        try await newerWrite.value

        #expect(await model.snapshot.states["cg-20"]?.brightness == .init(percent: 77))
        #expect(await model.snapshot.lastError == nil)
    }

    @Test("older brightness success does not suppress newer brightness failure")
    func olderBrightnessSuccessDoesNotSuppressNewerBrightnessFailure() async throws {
        let full = display(id: 23, name: "Full", supportLevel: .full)
        let controller = MockDisplayController(displays: [full])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()
        let olderGate = AsyncGate()
        let newerGate = AsyncGate()
        await controller.setOnSetBrightness {
            switch await controller.setBrightnessCalls.count {
            case 1:
                await olderGate.suspend()
            case 2:
                await newerGate.suspend()
            default:
                break
            }
        }

        let olderWrite = Task {
            try await model.setBrightness(.init(percent: 66))
        }
        await olderGate.waitUntilSuspended()
        let newerWrite = Task {
            do {
                try await model.setBrightness(.init(percent: 77))
                Issue.record("Newer write should fail")
            } catch {
                #expect(error as? DisplayControlError == .writeFailed("newer write failed"))
            }
        }
        await newerGate.waitUntilSuspended()

        await olderGate.resume()
        try await olderWrite.value
        await controller.setBrightnessError(TestWriteError(message: "newer write failed"))
        await newerGate.resume()
        await newerWrite.value

        #expect(await model.snapshot.states["cg-23"]?.brightness == .init(percent: 50))
        #expect(await model.snapshot.lastError == DisplayControlError.writeFailed("newer write failed").localizedDescription)
    }

    @Test("older successful boost write does not overwrite newer successful boost state")
    func olderSuccessfulBoostWriteDoesNotOverwriteNewerSuccessfulBoostState() async throws {
        let full = display(id: 19, name: "Full", supportLevel: .full)
        let controller = MockDisplayController(displays: [full])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()
        let writeGate = AsyncGate()
        await controller.setOnSetBoost {
            await controller.clearOnSetBoost()
            await writeGate.suspend()
        }

        let olderWrite = Task {
            try await model.setBoostEnabled(true)
        }
        await writeGate.waitUntilSuspended()
        try await model.setBoostEnabled(false)
        await writeGate.resume()
        try await olderWrite.value

        #expect(await model.snapshot.states["cg-19"]?.boostEnabled == false)
        #expect(await model.snapshot.lastError == nil)
    }

    @Test("concurrent brightness and boost writes update independent fields")
    func concurrentBrightnessAndBoostWritesUpdateIndependentFields() async throws {
        let full = display(id: 24, name: "Full", supportLevel: .full)
        let controller = MockDisplayController(displays: [full])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()
        let brightnessGate = AsyncGate()
        let boostGate = AsyncGate()
        await controller.setOnSetBrightness {
            await brightnessGate.suspend()
        }
        await controller.setOnSetBoost {
            await boostGate.suspend()
        }

        let brightnessWrite = Task {
            try await model.setBrightness(.init(percent: 82))
        }
        await brightnessGate.waitUntilSuspended()
        let boostWrite = Task {
            try await model.setBoostEnabled(true)
        }
        await boostGate.waitUntilSuspended()

        await brightnessGate.resume()
        try await brightnessWrite.value
        await boostGate.resume()
        try await boostWrite.value

        #expect(await model.snapshot.states["cg-24"] == .init(brightness: .init(percent: 82), boostEnabled: true))
        #expect(await model.snapshot.lastError == nil)
    }

    @Test("older brightness success does not clear newer boost failure")
    func olderBrightnessSuccessDoesNotClearNewerBoostFailure() async throws {
        let full = display(id: 25, name: "Full", supportLevel: .full)
        let controller = MockDisplayController(displays: [full])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()
        let brightnessGate = AsyncGate()
        await controller.setOnSetBrightness {
            await controller.clearOnSetBrightness()
            await brightnessGate.suspend()
        }

        let brightnessWrite = Task {
            try await model.setBrightness(.init(percent: 68))
        }
        await brightnessGate.waitUntilSuspended()
        await controller.setBoostError(TestWriteError(message: "boost failed"))

        await #expect(throws: DisplayControlError.writeFailed("boost failed")) {
            try await model.setBoostEnabled(true)
        }
        await brightnessGate.resume()
        try await brightnessWrite.value

        #expect(await model.snapshot.states["cg-25"]?.brightness == .init(percent: 68))
        #expect(await model.snapshot.states["cg-25"]?.boostEnabled == false)
        #expect(await model.snapshot.lastError == DisplayControlError.writeFailed("boost failed").localizedDescription)
    }

    @Test("older boost failure does not overwrite newer brightness success")
    func olderBoostFailureDoesNotOverwriteNewerBrightnessSuccess() async throws {
        let full = display(id: 26, name: "Full", supportLevel: .full)
        let controller = MockDisplayController(displays: [full])
        let model = BrightnessModel(controller: controller)
        await model.refreshDisplays()
        let boostGate = AsyncGate()
        await controller.setOnSetBoost {
            await controller.clearOnSetBoost()
            await boostGate.suspend()
        }

        let boostWrite = Task {
            do {
                try await model.setBoostEnabled(true)
                Issue.record("Older boost write should fail")
            } catch {
                #expect(error as? DisplayControlError == .writeFailed("boost failed"))
            }
        }
        await boostGate.waitUntilSuspended()
        try await model.setBrightness(.init(percent: 79))
        await controller.setBoostError(TestWriteError(message: "boost failed"))
        await boostGate.resume()
        await boostWrite.value

        #expect(await model.snapshot.states["cg-26"]?.brightness == .init(percent: 79))
        #expect(await model.snapshot.states["cg-26"]?.boostEnabled == false)
        #expect(await model.snapshot.lastError == nil)
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

    @Test("setBoostEnabled throws displayNotFound when no display is selected")
    func setBoostEnabledThrowsDisplayNotFoundWhenNoDisplayIsSelected() async {
        let controller = MockDisplayController(displays: [])
        let model = BrightnessModel(controller: controller)

        await #expect(throws: DisplayControlError.displayNotFound) {
            try await model.setBoostEnabled(true)
        }
        #expect(await model.snapshot.lastError == DisplayControlError.displayNotFound.localizedDescription)
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
        await controller.setBrightnessError(TestWriteError(message: "previous failure"))

        await #expect(throws: DisplayControlError.writeFailed("previous failure")) {
            try await model.setBrightness(.init(percent: 10))
        }
        #expect(await model.snapshot.lastError == DisplayControlError.writeFailed("previous failure").localizedDescription)

        await controller.clearBrightnessError()
        await controller.setOnSetBrightness {
            await controller.setDisplays([second])
            await model.refreshDisplays()
        }

        try await model.setBrightness(.init(percent: 35))

        #expect(await controller.setBrightnessCalls == [first.id, first.id])
        #expect(await model.snapshot.displays == [second])
        #expect(await model.snapshot.states["cg-101"] == nil)
        #expect(await model.snapshot.states["cg-102"]?.brightness == .init(percent: 50))
        #expect(await model.snapshot.lastError == nil)
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
    var readStateCalls: [DisplayID]
    var setBrightnessCalls: [DisplayID]
    var setBoostCalls: [DisplayID]
    var brightnessError: (any Error)?
    var boostError: (any Error)?
    var onDiscover: (@Sendable () async -> Void)?
    var onReadState: (@Sendable () async -> Void)?
    var onSetBrightness: (@Sendable () async -> Void)?
    var onSetBoost: (@Sendable () async -> Void)?

    init(
        displays: [Display],
        states: [String: DisplayState] = [:],
        readStateCalls: [DisplayID] = [],
        setBrightnessCalls: [DisplayID] = [],
        setBoostCalls: [DisplayID] = [],
        brightnessError: (any Error)? = nil,
        boostError: (any Error)? = nil,
        onDiscover: (@Sendable () async -> Void)? = nil,
        onReadState: (@Sendable () async -> Void)? = nil,
        onSetBrightness: (@Sendable () async -> Void)? = nil,
        onSetBoost: (@Sendable () async -> Void)? = nil
    ) {
        self.displays = displays
        self.states = states
        self.readStateCalls = readStateCalls
        self.setBrightnessCalls = setBrightnessCalls
        self.setBoostCalls = setBoostCalls
        self.brightnessError = brightnessError
        self.boostError = boostError
        self.onDiscover = onDiscover
        self.onReadState = onReadState
        self.onSetBrightness = onSetBrightness
        self.onSetBoost = onSetBoost
    }

    func discover() async -> [Display] {
        if let onDiscover {
            await onDiscover()
        }
        return displays
    }

    func readState(for display: DisplayID) async -> DisplayState {
        readStateCalls.append(display)
        let state = states[stableKey(for: display)] ?? .init(brightness: .init(percent: 50), boostEnabled: false)
        if let onReadState {
            await onReadState()
        }
        return state
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

    func clearReadStateCalls() {
        readStateCalls = []
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

    func clearBrightnessError() {
        brightnessError = nil
    }

    func setBoostError(_ error: any Error) {
        boostError = error
    }

    func setOnSetBoost(_ action: @escaping @Sendable () async -> Void) {
        onSetBoost = action
    }

    func clearOnSetBoost() {
        onSetBoost = nil
    }

    func setOnSetBrightness(_ action: @escaping @Sendable () async -> Void) {
        onSetBrightness = action
    }

    func clearOnSetBrightness() {
        onSetBrightness = nil
    }

    func setOnDiscover(_ action: @escaping @Sendable () async -> Void) {
        onDiscover = action
    }

    func setOnReadState(_ action: @escaping @Sendable () async -> Void) {
        onReadState = action
    }

    func clearOnReadState() {
        onReadState = nil
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

private actor AsyncGate {
    private var suspendedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        suspendedContinuation?.resume()
        suspendedContinuation = nil

        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
    }

    func waitUntilSuspended() async {
        if resumeContinuation != nil {
            return
        }

        await withCheckedContinuation { continuation in
            suspendedContinuation = continuation
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}
