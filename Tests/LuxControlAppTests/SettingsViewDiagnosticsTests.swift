import Testing
@testable import LuxControlApp

@Suite("Settings diagnostics visibility")
struct SettingsViewDiagnosticsTests {
    @Test("diagnostics are hidden in release-compatible builds")
    @MainActor
    func diagnosticsAreHiddenByDefault() {
        #expect(SettingsView.includesDiagnostics == false)
    }
}
