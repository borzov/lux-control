import AppKit
import SwiftUI
import LuxControlCore
import LuxControlMac

@main
struct LuxControlApp: App {
    private let model = BrightnessModel(controller: PublicDisplayController())

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("LuxControl", systemImage: "sun.max") {
            MenuBarView(model: model)
                .frame(width: 320)
        }

        Settings {
            SettingsView(model: model)
        }
    }
}
