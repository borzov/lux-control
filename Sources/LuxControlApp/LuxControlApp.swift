import AppKit
import SwiftUI
import LuxControlCore
import LuxControlMac

@main
struct LuxControlApp: App {
    @Environment(\.openSettings) private var openSettings

    private static let brightnessStep = 10

    private let model = BrightnessModel(
        controller: PublicDisplayController(),
        store: SettingsStore()
    )
    private let launchAtLoginService = LaunchAtLoginService()
    private let hotkeyService: HotkeyService

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = model
        let launchAtLoginService = launchAtLoginService

        hotkeyService = HotkeyService { command in
            Task {
                await Self.handleHotkey(command, model: model)
            }
        }
        // Global hotkeys: ⌘⌥= brighter, ⌘⌥- dimmer, ⌘⌥Space toggle Boost.
        // Registration can fail (e.g. another app owns the shortcut); the menu
        // bar controls remain fully usable in that case.
        try? hotkeyService.startDefaultHotkeys()

        Task {
            await Self.applyStartupState(
                model: model,
                launchAtLoginService: launchAtLoginService
            )
        }
    }

    var body: some Scene {
        MenuBarExtra("LuxControl", systemImage: "sun.max") {
            MenuBarView(model: model) {
                openSettings()
            }
                .frame(width: 340)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }

    private static func handleHotkey(
        _ command: HotkeyService.Command,
        model: BrightnessModel
    ) async {
        // The menu may never have been opened, so the snapshot can be empty.
        if await model.snapshot.selectedDisplay == nil {
            await model.refreshDisplays()
        }

        do {
            switch command {
            case .increase:
                try await model.adjustBrightness(by: brightnessStep)
            case .decrease:
                try await model.adjustBrightness(by: -brightnessStep)
            case .toggle:
                try await model.toggleBoost()
            }
        } catch {
            // Failures are recorded in snapshot.lastError and surfaced in the menu.
        }
    }

    private static func applyStartupState(
        model: BrightnessModel,
        launchAtLoginService: LaunchAtLoginService
    ) async {
        await model.refreshDisplays()
        // Re-apply per-display Boost that was active when the app last ran.
        await model.restorePersistedBoosts()

        // The "Enable Boost when LuxControl opens at login" preference additionally
        // forces Boost on the selected display, even if it was off last time.
        guard launchAtLoginService.isEnabled,
              UserDefaults.standard.bool(forKey: "launchBoostEnabled") else {
            return
        }

        let snapshot = await model.snapshot
        guard let display = snapshot.selectedDisplay,
              display.supportLevel == .full else {
            return
        }

        try? await model.setBoostEnabled(true, forStableKey: display.stableKey)
    }
}
