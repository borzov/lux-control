import SwiftUI
import LuxControlCore

struct SettingsView: View {
    let model: BrightnessModel

    @State private var snapshot = BrightnessSnapshot()
    @State private var isRefreshing = false

    var body: some View {
        diagnosticsView
        .frame(width: 560, height: 360)
        .task {
            await refreshSnapshot()
        }
    }

    private var diagnosticsView: some View {
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
                .disabled(isRefreshing)
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
        let report = DiagnosticsReport.make(
            appVersion: "0.1.0",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            displays: snapshot.displays,
            states: snapshot.states
        )

        guard let lastError = snapshot.lastError else {
            return report
        }

        return "\(report)\nLast error: \(lastError)"
    }

    private func refreshDiagnostics() async {
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

        await model.refreshDisplays()
        await refreshSnapshot()
        await MainActor.run {
            isRefreshing = false
        }
    }

    private func refreshSnapshot() async {
        let snapshot = await model.snapshot
        await MainActor.run {
            self.snapshot = snapshot
        }
    }
}
