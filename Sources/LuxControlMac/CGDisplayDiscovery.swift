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

            displays.append(Display(
                id: .directDisplayID(id),
                name: isBuiltin ? "Built-in Display" : "External Display",
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
}
