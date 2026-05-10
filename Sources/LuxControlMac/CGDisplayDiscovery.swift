import CoreGraphics
import Foundation
import LuxControlCore

public struct CGDisplayDiscovery: Sendable {
    public init() {}

    public func discover() async -> [Display] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)

        return ids.prefix(Int(count)).map { id in
            Display(
                id: .directDisplayID(id),
                name: CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "External Display \(id)",
                vendorNumber: CGDisplayVendorNumber(id),
                modelNumber: CGDisplayModelNumber(id),
                serialNumber: CGDisplaySerialNumber(id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                supportLevel: CGDisplayIsBuiltin(id) != 0 ? .brightnessOnly : .detectOnly
            )
        }
    }
}
