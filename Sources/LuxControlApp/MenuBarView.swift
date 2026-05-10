import AppKit
import SwiftUI
import LuxControlCore

struct MenuBarView: View {
    let model: BrightnessModel
    let openSettings: () -> Void

    @State private var snapshot = BrightnessSnapshot()
    @State private var selectedStableKey = ""
    @State private var pendingSelectedKey: String?
    @State private var brightness = 50.0
    @State private var boostEnabled = false
    @State private var isRefreshing = false
    @State private var isMenuVisible = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var selectTask: Task<Void, Never>?
    @State private var boostWriteTask: Task<Void, Never>?
    @State private var brightnessWriteTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if snapshot.displays.isEmpty {
                Text("No displays detected.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                displayPicker
                boostToggle
                brightnessControl
                supportStatus
            }

            if let lastError = snapshot.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                startRefreshTask()
            } label: {
                Label("Refresh Displays", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .onAppear {
            isMenuVisible = true
            startRefreshTask()
        }
        .onDisappear {
            isMenuVisible = false
            cancelPendingTasks()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("LuxControl")
                .font(.headline)

            Spacer()

            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .labelStyle(.iconOnly)
            .help("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .labelStyle(.iconOnly)
            .help("Quit LuxControl")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayPicker: some View {
        Picker("Display", selection: selectedDisplayBinding) {
            ForEach(snapshot.displays) { display in
                Text(display.name)
                    .tag(display.stableKey)
            }
        }
        .disabled(snapshot.displays.isEmpty)
    }

    private var boostToggle: some View {
        Toggle(isOn: boostBinding) {
            Label("Boost", systemImage: "sun.max.fill")
        }
        .disabled(isChangingSelection || selectedDisplay(in: snapshot)?.supportLevel != .full)
    }

    private var brightnessControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                    .foregroundStyle(.secondary)

                Slider(
                    value: brightnessBinding,
                    in: 0...100,
                    step: 1,
                    onEditingChanged: handleBrightnessEditingChanged
                )
                    .disabled(isChangingSelection || !selectedDisplaySupportsBrightness)

                Image(systemName: "sun.max")
                    .foregroundStyle(.secondary)

                Text(isChangingSelection ? "--%" : "\(Int(brightness.rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }

            Text("Brightness")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var supportStatus: some View {
        Text(supportDescription(for: selectedDisplay(in: snapshot)))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedDisplayBinding: Binding<String> {
        Binding {
            pendingSelectedKey ?? selectedStableKey
        } set: { stableKey in
            pendingSelectedKey = stableKey
            selectTask?.cancel()
            selectTask = Task {
                do {
                    try Task.checkCancellation()
                } catch {
                    return
                }
                await model.selectDisplay(stableKey: stableKey)
                guard isTaskStillActive() else {
                    return
                }
                await refreshSnapshot()
                await MainActor.run {
                    selectTask = nil
                }
            }
        }
    }

    private var isChangingSelection: Bool {
        pendingSelectedKey != nil
    }

    private var boostBinding: Binding<Bool> {
        Binding {
            boostEnabled
        } set: { enabled in
            guard let targetStableKey = selectedStableKeyForCommand else {
                return
            }

            boostEnabled = enabled
            boostWriteTask?.cancel()
            boostWriteTask = Task {
                do {
                    try Task.checkCancellation()
                } catch {
                    return
                }
                await model.selectDisplay(stableKey: targetStableKey)
                do {
                    try Task.checkCancellation()
                } catch {
                    return
                }
                do {
                    try await model.setBoostEnabled(enabled)
                } catch {
                    // BrightnessModel records command failures in snapshot.lastError.
                }
                guard isTaskStillActive() else {
                    return
                }
                await restoreSelectedDisplayIfNeeded(commandTargetStableKey: targetStableKey)
                await refreshSnapshot()
                await MainActor.run {
                    boostWriteTask = nil
                }
            }
        }
    }

    private var brightnessBinding: Binding<Double> {
        Binding {
            brightness
        } set: { value in
            brightness = value.rounded()
        }
    }

    private var selectedDisplaySupportsBrightness: Bool {
        switch selectedDisplay(in: snapshot)?.supportLevel {
        case .full, .brightnessOnly:
            return true
        case .detectOnly, .unsupported, nil:
            return false
        }
    }

    @MainActor
    private func applySnapshot(_ snapshot: BrightnessSnapshot) {
        self.snapshot = snapshot
        updateSelectedStableKey(with: snapshot)
        clearPendingSelectionIfResolved(with: snapshot)

        guard let selectedDisplay = selectedDisplay(in: snapshot),
              let state = snapshot.states[selectedDisplay.stableKey] else {
            brightness = 50
            boostEnabled = false
            return
        }

        brightness = Double(state.brightness.percent)
        boostEnabled = state.boostEnabled
    }

    private func startRefreshTask() {
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task {
            await refreshDisplays()
            await MainActor.run {
                if isMenuVisible {
                    refreshTask = nil
                }
            }
        }
    }

    private func refreshDisplays() async {
        let shouldRefresh = await MainActor.run {
            guard !isRefreshing else {
                return false
            }
            isRefreshing = true
            return true
        }
        guard shouldRefresh else {
            return
        }

        guard isTaskStillActive() else {
            finishRefreshingIfVisible()
            return
        }

        await model.refreshDisplays()
        guard isTaskStillActive() else {
            finishRefreshingIfVisible()
            return
        }
        await refreshSnapshot()
        finishRefreshingIfVisible()
    }

    @MainActor
    private func isTaskStillActive() -> Bool {
        isMenuVisible && !Task.isCancelled
    }

    @MainActor
    private func finishRefreshingIfVisible() {
        if isMenuVisible {
            isRefreshing = false
        }
    }

    private func refreshSnapshot() async {
        let snapshot = await model.snapshot
        guard isTaskStillActive() else {
            return
        }
        applySnapshot(snapshot)
    }

    private func handleBrightnessEditingChanged(_ isEditing: Bool) {
        guard !isEditing else {
            return
        }
        guard let targetStableKey = selectedStableKeyForCommand else {
            return
        }

        brightnessWriteTask?.cancel()
        let percent = Int(brightness.rounded())
        brightnessWriteTask = Task {
            do {
                try Task.checkCancellation()
            } catch {
                return
            }
            await model.selectDisplay(stableKey: targetStableKey)
            do {
                try Task.checkCancellation()
            } catch {
                return
            }
            do {
                try await model.setBrightness(.init(percent: percent))
            } catch {
                // BrightnessModel records command failures in snapshot.lastError.
            }

            guard isTaskStillActive() else {
                return
            }
            await restoreSelectedDisplayIfNeeded(commandTargetStableKey: targetStableKey)
            await refreshSnapshot()
            await MainActor.run {
                brightnessWriteTask = nil
            }
        }
    }

    private var selectedStableKeyForCommand: String? {
        let stableKey = selectedStableKey
        guard !stableKey.isEmpty else {
            return nil
        }
        return stableKey
    }

    @MainActor
    private func updateSelectedStableKey(with snapshot: BrightnessSnapshot) {
        if pendingSelectedKey != nil {
            return
        }

        if !selectedStableKey.isEmpty,
           snapshot.displays.contains(where: { $0.stableKey == selectedStableKey }) {
            return
        }

        selectedStableKey = snapshot.selectedDisplay?.stableKey ?? ""
    }

    @MainActor
    private func clearPendingSelectionIfResolved(with snapshot: BrightnessSnapshot) {
        guard let pendingSelectedKey,
              snapshot.selectedDisplay?.stableKey == pendingSelectedKey,
              snapshot.states[pendingSelectedKey] != nil else {
            return
        }

        selectedStableKey = pendingSelectedKey
        self.pendingSelectedKey = nil
    }

    private func selectedDisplay(in snapshot: BrightnessSnapshot) -> Display? {
        snapshot.displays.first { $0.stableKey == (pendingSelectedKey ?? selectedStableKey) } ?? snapshot.selectedDisplay
    }

    private func restoreSelectedDisplayIfNeeded(commandTargetStableKey: String) async {
        let desiredStableKey = await MainActor.run {
            pendingSelectedKey ?? selectedStableKey
        }

        guard !desiredStableKey.isEmpty,
              desiredStableKey != commandTargetStableKey else {
            return
        }

        do {
            try Task.checkCancellation()
        } catch {
            return
        }
        await model.selectDisplay(stableKey: desiredStableKey)
    }

    private func cancelPendingTasks() {
        refreshTask?.cancel()
        selectTask?.cancel()
        boostWriteTask?.cancel()
        brightnessWriteTask?.cancel()
        refreshTask = nil
        selectTask = nil
        boostWriteTask = nil
        brightnessWriteTask = nil
        pendingSelectedKey = nil
        isRefreshing = false
    }

    private func supportDescription(for display: Display?) -> String {
        if isChangingSelection {
            return "Updating selected display..."
        }

        guard let display else {
            return "No display selected."
        }

        switch display.supportLevel {
        case .full:
            return "Brightness and boost supported."
        case .brightnessOnly:
            return "Brightness supported. Boost unavailable."
        case .detectOnly:
            return "Display detected. Brightness controls unavailable."
        case .unsupported:
            return "Display control unsupported."
        }
    }
}
