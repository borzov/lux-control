import SwiftUI
import LuxControlCore

struct SettingsView: View {
    let model: BrightnessModel

    @State private var snapshot = BrightnessSnapshot()
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("restoreOnQuit") private var restoreOnQuit = true

    var body: some View {
        TabView {
            Form {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Restore display state on quit", isOn: $restoreOnQuit)
            }
            .padding(20)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            diagnosticsTab
                .tabItem {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
        }
        .frame(width: 560, height: 360)
        .task {
            await refreshSnapshot()
        }
    }

    private var diagnosticsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostics")
                    .font(.headline)

                Spacer()

                Button {
                    Task {
                        await refreshDiagnostics()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            ScrollView {
                Text(diagnosticsText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
    }

    private var diagnosticsText: String {
        DiagnosticsReport.make(
            appVersion: "0.1.0",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            displays: snapshot.displays,
            states: snapshot.states
        )
    }

    private func refreshDiagnostics() async {
        await model.refreshDisplays()
        await refreshSnapshot()
    }

    private func refreshSnapshot() async {
        let snapshot = await model.snapshot
        await MainActor.run {
            self.snapshot = snapshot
        }
    }
}
