import Foundation

public enum DisplayID: Hashable, Sendable {
    case directDisplayID(UInt32)
}

public enum DisplaySupportLevel: String, Codable, Sendable {
    case full
    case brightnessOnly
    case detectOnly
    case unsupported
}

public struct BrightnessValue: Equatable, Codable, Sendable {
    public let percent: Int

    public init(percent: Int) {
        self.percent = min(max(percent, 0), 100)
    }
}

public struct Display: Equatable, Identifiable, Sendable {
    public let id: DisplayID
    public let name: String
    public let vendorNumber: UInt32?
    public let modelNumber: UInt32?
    public let serialNumber: UInt32?
    public let isBuiltin: Bool
    public let supportLevel: DisplaySupportLevel

    public init(
        id: DisplayID,
        name: String,
        vendorNumber: UInt32? = nil,
        modelNumber: UInt32? = nil,
        serialNumber: UInt32? = nil,
        isBuiltin: Bool,
        supportLevel: DisplaySupportLevel
    ) {
        self.id = id
        self.name = name
        self.vendorNumber = vendorNumber
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.isBuiltin = isBuiltin
        self.supportLevel = supportLevel
    }

    public var stableKey: String {
        if let vendorNumber, let modelNumber, let serialNumber {
            return "\(vendorNumber)-\(modelNumber)-\(serialNumber)"
        }

        switch id {
        case .directDisplayID(let displayID):
            return "cg-\(displayID)"
        }
    }
}

public struct DisplayState: Equatable, Codable, Sendable {
    public let brightness: BrightnessValue
    public let boostEnabled: Bool

    public init(brightness: BrightnessValue, boostEnabled: Bool) {
        self.brightness = brightness
        self.boostEnabled = boostEnabled
    }
}

public enum DisplayControlError: Error, Equatable, LocalizedError, Sendable {
    case displayNotFound
    case unsupported(DisplaySupportLevel)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .displayNotFound:
            return "Display not found."
        case .unsupported(let supportLevel):
            return "Display control is unsupported for support level \(supportLevel.rawValue)."
        case .writeFailed(let message):
            return "Failed to write display setting: \(message)"
        }
    }
}
