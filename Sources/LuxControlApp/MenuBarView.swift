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
        VStack(alignment: .leading, spacing: 14) {
            header

            if snapshot.displays.isEmpty {
                noDisplaysView
            } else {
                boostHero
                brightnessControl
                supportStatus
            }

            if let lastError = snapshot.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .padding(16)
        .onAppear {
            isMenuVisible = true
            startRefreshTask()
        }
        .onDisappear {
            isMenuVisible = false
            cancelTransientTasks()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("LuxControl")
                    .font(.headline)
                    .lineLimit(1)

                Text("Brighter displays")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !snapshot.displays.isEmpty {
                displayPicker
                    .frame(width: 172)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var noDisplaysView: some View {
        VStack(spacing: 10) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)

            Text("No displays detected.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 132)
    }

    private var displayPicker: some View {
        Picker("Display", selection: selectedDisplayBinding) {
            ForEach(snapshot.displays) { display in
                Text(display.name)
                    .tag(display.stableKey)
            }
        }
        .labelsHidden()
        .disabled(snapshot.displays.isEmpty)
    }

    private var boostHero: some View {
        Button {
            guard selectedDisplay(in: snapshot)?.supportLevel == .full else {
                return
            }
            boostBinding.wrappedValue.toggle()
        } label: {
            VStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: boostEnabled
                                    ? [
                                        Color(red: 1.0, green: 0.96, blue: 0.62),
                                        Color(red: 1.0, green: 0.72, blue: 0.0),
                                        Color(red: 1.0, green: 0.48, blue: 0.0),
                                    ]
                                    : [
                                        Color(nsColor: .controlBackgroundColor),
                                        Color(nsColor: .separatorColor).opacity(0.55),
                                    ],
                                center: .topLeading,
                                startRadius: 8,
                                endRadius: 72
                            )
                        )
                        .shadow(
                            color: boostEnabled ? .orange.opacity(0.34) : .clear,
                            radius: 22,
                            x: 0,
                            y: 8
                        )

                    VStack(spacing: 2) {
                        Image(systemName: boostEnabled ? "sun.max.fill" : "sun.max")
                            .font(.system(size: 26, weight: .semibold))

                        Text(boostEnabled ? "2x" : "1x")
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(boostEnabled ? .black.opacity(0.78) : .secondary)
                }
                .frame(width: 126, height: 126)
                .contentShape(Circle())

                VStack(spacing: 2) {
                    Text(boostEnabled ? "Boost active" : "Boost off")
                        .font(.callout.weight(.semibold))

                    Text(boostCaption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isChangingSelection || selectedDisplay(in: snapshot)?.supportLevel != .full)
    }

    private var brightnessControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Brightness", systemImage: "sun.max")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(isChangingSelection ? "--%" : "\(Int(brightness.rounded()))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                    .foregroundStyle(.secondary)

                Slider(
                    value: brightnessBinding,
                    in: 0...100,
                    onEditingChanged: handleBrightnessEditingChanged
                )
                    .disabled(isChangingSelection || !selectedDisplaySupportsBrightness)
                    .tint(.orange)

                Image(systemName: "sun.max")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var supportStatus: some View {
        Text(supportDescription(for: selectedDisplay(in: snapshot)))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                startRefreshTask()
            } label: {
                Label("Refresh Displays", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)

            Spacer()

            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.regular)
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
                do {
                    try await model.setBoostEnabled(enabled, forStableKey: targetStableKey)
                } catch {
                    // BrightnessModel records command failures in snapshot.lastError.
                }
                guard isTaskStillActive() else {
                    return
                }
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

    private var boostCaption: String {
        switch selectedDisplay(in: snapshot)?.supportLevel {
        case .full:
            return boostEnabled ? "Extended brightness enabled" : "Tap to enable extended brightness"
        case .brightnessOnly:
            return "Unavailable for this display"
        case .detectOnly, .unsupported:
            return "Display control unavailable"
        case nil:
            return "No display selected"
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
            do {
                try await model.setBrightness(.init(percent: percent), forStableKey: targetStableKey)
            } catch {
                // BrightnessModel records command failures in snapshot.lastError.
            }

            guard isTaskStillActive() else {
                return
            }
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

    private func cancelTransientTasks() {
        refreshTask?.cancel()
        selectTask?.cancel()
        refreshTask = nil
        selectTask = nil
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
