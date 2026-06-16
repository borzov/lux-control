import AppKit
import CoreGraphics
import Foundation
import LuxControlCore

public protocol DisplayDiscovering: Sendable {
    func discover() async -> [Display]
}

public struct CGDisplayDiscovery: DisplayDiscovering {
    public init() {}

    public func discover() async -> [Display] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return [] }
        guard count > 0 else { return [] }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        let brightnessClient = DisplayServicesBrightnessClient()
        let boostClient = EDRBoostClient.shared
        let localizedNames = await Self.localizedNames()

        var displays: [Display] = []
        for id in ids.prefix(Int(count)) {
            guard id != 0 else { continue }

            let isBuiltin = CGDisplayIsBuiltin(id) != 0
            let supportLevel: DisplaySupportLevel
            if await boostClient.canBoost(for: id) {
                supportLevel = .full
            } else if brightnessClient.canChangeBrightness(for: id) || isBuiltin {
                supportLevel = .brightnessOnly
            } else {
                supportLevel = .detectOnly
            }

            let fallbackName = isBuiltin ? "Built-in Display" : "External Display"
            displays.append(Display(
                id: .directDisplayID(id),
                name: localizedNames[id] ?? fallbackName,
                vendorNumber: nonZero(CGDisplayVendorNumber(id)),
                modelNumber: nonZero(CGDisplayModelNumber(id)),
                serialNumber: nonZero(CGDisplaySerialNumber(id)),
                isBuiltin: isBuiltin,
                supportLevel: supportLevel
            ))
        }
        return displays
    }

    private func nonZero(_ value: UInt32) -> UInt32? {
        value == 0 ? nil : value
    }

    /// Maps `CGDirectDisplayID` to the OS-localized display name (e.g. "DELL
    /// U2720Q") so multiple external monitors are distinguishable in the picker.
    @MainActor
    private static func localizedNames() -> [UInt32: String] {
        var names: [UInt32: String] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                continue
            }

            let name = screen.localizedName
            if !name.isEmpty {
                names[number.uint32Value] = name
            }
        }
        return names
    }
}
