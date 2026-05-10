import SwiftUI
import LuxControlCore

struct MenuBarView: View {
    let model: BrightnessModel

    @State private var snapshot = BrightnessSnapshot()
    @State private var brightness = 50.0
    @State private var boostEnabled = false
    @State private var isRefreshing = false
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
                Task {
                    await refreshDisplays()
                }
            } label: {
                Label("Refresh Displays", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .task {
            await refreshDisplays()
        }
    }

    private var header: some View {
        Text("LuxControl")
            .font(.headline)
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
        .disabled(snapshot.selectedDisplay?.supportLevel != .full)
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
                    .disabled(!selectedDisplaySupportsBrightness)

                Image(systemName: "sun.max")
                    .foregroundStyle(.secondary)

                Text("\(Int(brightness.rounded()))%")
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
        Text(supportDescription(for: snapshot.selectedDisplay))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedDisplayBinding: Binding<String> {
        Binding {
            snapshot.selectedDisplay?.stableKey ?? ""
        } set: { stableKey in
            Task {
                await model.selectDisplay(stableKey: stableKey)
                await refreshSnapshot()
            }
        }
    }

    private var boostBinding: Binding<Bool> {
        Binding {
            boostEnabled
        } set: { enabled in
            boostEnabled = enabled
            Task {
                do {
                    try await model.setBoostEnabled(enabled)
                } catch {
                    // BrightnessModel records command failures in snapshot.lastError.
                }
                await refreshSnapshot()
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
        switch snapshot.selectedDisplay?.supportLevel {
        case .full, .brightnessOnly:
            return true
        case .detectOnly, .unsupported, nil:
            return false
        }
    }

    @MainActor
    private func applySnapshot(_ snapshot: BrightnessSnapshot) {
        self.snapshot = snapshot

        guard let selectedDisplay = snapshot.selectedDisplay,
              let state = snapshot.states[selectedDisplay.stableKey] else {
            brightness = 50
            boostEnabled = false
            return
        }

        brightness = Double(state.brightness.percent)
        boostEnabled = state.boostEnabled
    }

    private func refreshDisplays() async {
        await MainActor.run {
            isRefreshing = true
        }
        await model.refreshDisplays()
        await refreshSnapshot()
        await MainActor.run {
            isRefreshing = false
        }
    }

    private func refreshSnapshot() async {
        let snapshot = await model.snapshot
        applySnapshot(snapshot)
    }

    private func handleBrightnessEditingChanged(_ isEditing: Bool) {
        guard !isEditing else {
            return
        }

        brightnessWriteTask?.cancel()
        let percent = Int(brightness.rounded())
        brightnessWriteTask = Task {
            do {
                try await model.setBrightness(.init(percent: percent))
            } catch {
                // BrightnessModel records command failures in snapshot.lastError.
            }

            guard !Task.isCancelled else {
                return
            }
            await refreshSnapshot()
        }
    }

    private func supportDescription(for display: Display?) -> String {
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
