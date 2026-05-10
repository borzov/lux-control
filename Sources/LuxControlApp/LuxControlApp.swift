import AppKit
import SwiftUI
import LuxControlCore
import LuxControlMac

@main
struct LuxControlApp: App {
    @Environment(\.openSettings) private var openSettings

    private let model = BrightnessModel(controller: PublicDisplayController())
    private let launchAtLoginService = LaunchAtLoginService()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = model
        let launchAtLoginService = launchAtLoginService
        Task {
            await Self.applyLaunchBoostIfNeeded(
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

    private static func applyLaunchBoostIfNeeded(
        model: BrightnessModel,
        launchAtLoginService: LaunchAtLoginService
    ) async {
        guard launchAtLoginService.isEnabled,
              UserDefaults.standard.bool(forKey: "launchBoostEnabled") else {
            return
        }

        await model.refreshDisplays()
        let snapshot = await model.snapshot
        guard let display = snapshot.selectedDisplay,
              display.supportLevel == .full else {
            return
        }

        try? await model.setBoostEnabled(true, forStableKey: display.stableKey)
    }
}
