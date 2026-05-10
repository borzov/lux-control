import CoreGraphics
import Foundation
import LuxControlCore

public struct CGDisplayDiscovery: Sendable {
    public init() {}

    public func discover() async -> [Display] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return [] }
        guard count > 0 else { return [] }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }

        return ids.prefix(Int(count)).compactMap { id in
            guard id != 0 else { return nil }

            let isBuiltin = CGDisplayIsBuiltin(id) != 0

            return Display(
                id: .directDisplayID(id),
                name: isBuiltin ? "Built-in Display" : "External Display",
                vendorNumber: nonZero(CGDisplayVendorNumber(id)),
                modelNumber: nonZero(CGDisplayModelNumber(id)),
                serialNumber: nonZero(CGDisplaySerialNumber(id)),
                isBuiltin: isBuiltin,
                supportLevel: isBuiltin ? .brightnessOnly : .detectOnly
            )
        }
    }

    private func nonZero(_ value: UInt32) -> UInt32? {
        value == 0 ? nil : value
    }
}
