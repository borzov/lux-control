import AppKit
import SwiftUI
import LuxControlCore
import LuxControlMac

@main
struct LuxControlApp: App {
    @Environment(\.openSettings) private var openSettings

    private let model = BrightnessModel(controller: PublicDisplayController())

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("LuxControl", systemImage: "sun.max") {
            MenuBarView(model: model) {
                openSettings()
            }
                .frame(width: 320)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
