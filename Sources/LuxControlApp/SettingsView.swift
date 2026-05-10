import SwiftUI
import LuxControlCore

struct SettingsView: View {
    let model: BrightnessModel

    @State private var snapshot = BrightnessSnapshot()
    @State private var isRefreshing = false
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        diagnosticsView
        .frame(width: 560, height: 360)
        .onAppear {
            startRefreshTask()
        }
        .onDisappear {
            cancelRefreshTask()
        }
    }

    private var diagnosticsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostics")
                    .font(.headline)

                Spacer()

                Button {
                    startRefreshTask()
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
            appVersion: appVersion,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            displays: snapshot.displays,
            states: snapshot.states
        )

        guard let lastError = snapshot.lastError else {
            return report
        }

        return "\(report)\nLast error: \(lastError)"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private func startRefreshTask() {
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task {
            await refreshDiagnostics()
            await MainActor.run {
                refreshTask = nil
            }
        }
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

        do {
            try Task.checkCancellation()
        } catch {
            await finishRefreshing()
            return
        }
        await model.refreshDisplays()
        do {
            try Task.checkCancellation()
        } catch {
            await finishRefreshing()
            return
        }
        await refreshSnapshot()
        await finishRefreshing()
    }

    private func refreshSnapshot() async {
        let snapshot = await model.snapshot
        do {
            try Task.checkCancellation()
        } catch {
            return
        }
        await MainActor.run {
            self.snapshot = snapshot
        }
    }

    private func finishRefreshing() async {
        await MainActor.run {
            isRefreshing = false
        }
    }

    private func cancelRefreshTask() {
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
    }
}
