import SwiftUI
import LuxControlCore
import LuxControlMac

struct SettingsView: View {
    let model: BrightnessModel

    @AppStorage("launchBoostEnabled") private var launchBoostEnabled = false
    @State private var snapshot = BrightnessSnapshot()
    @State private var isRefreshing = false
    @State private var launchAtLoginEnabled = LaunchAtLoginService().isEnabled
    @State private var settingsError: String?
    @State private var refreshTask: Task<Void, Never>?

    private let launchAtLoginService = LaunchAtLoginService()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            generalSettings
            appInfo
            Divider()
            diagnosticsView
        }
        .padding(20)
        .frame(width: 560, height: 440)
        .onAppear {
            launchAtLoginEnabled = launchAtLoginService.isEnabled
            startRefreshTask()
        }
        .onDisappear {
            cancelRefreshTask()
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("General")
                .font(.headline)

            Toggle("Open LuxControl at login", isOn: launchAtLoginBinding)

            Toggle("Enable Boost when LuxControl opens at login", isOn: $launchBoostEnabled)
                .disabled(!launchAtLoginEnabled)
                .foregroundStyle(launchAtLoginEnabled ? .primary : .secondary)

            if let settingsError {
                Text(settingsError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var appInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("About")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    Text("Version")
                        .foregroundStyle(.secondary)
                    Text(appVersion)
                }
                GridRow {
                    Text("Developer")
                        .foregroundStyle(.secondary)
                    Text("Borzov")
                }
                GridRow {
                    Text("Repository")
                        .foregroundStyle(.secondary)
                    Text("lux-control")
                        .textSelection(.enabled)
                }
            }
            .font(.callout)
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
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            launchAtLoginEnabled
        } set: { enabled in
            do {
                try launchAtLoginService.setEnabled(enabled)
                launchAtLoginEnabled = launchAtLoginService.isEnabled
                if !launchAtLoginEnabled {
                    launchBoostEnabled = false
                }
                settingsError = nil
            } catch {
                launchAtLoginEnabled = launchAtLoginService.isEnabled
                settingsError = error.localizedDescription
            }
        }
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
