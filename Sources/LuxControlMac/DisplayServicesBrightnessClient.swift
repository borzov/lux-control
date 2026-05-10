import CoreGraphics
import Darwin
import Foundation

protocol DisplayBrightnessClient: Sendable {
    func canChangeBrightness(for displayID: UInt32) -> Bool
    func readBrightness(for displayID: UInt32) -> Float?
    func setBrightness(_ value: Float, for displayID: UInt32) throws
}

struct DisplayServicesBrightnessClient: DisplayBrightnessClient {
    private typealias CanChangeBrightness = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let functions: DisplayServicesFunctions?

    init() {
        self.functions = DisplayServicesFunctions.load()
    }

    func canChangeBrightness(for displayID: UInt32) -> Bool {
        guard let functions else {
            return false
        }

        return functions.canChangeBrightness(displayID)
    }

    func readBrightness(for displayID: UInt32) -> Float? {
        guard let functions else {
            return nil
        }

        var brightness: Float = 0
        guard functions.getBrightness(displayID, &brightness) == 0 else {
            return nil
        }

        return min(1, max(0, brightness))
    }

    func setBrightness(_ value: Float, for displayID: UInt32) throws {
        guard let functions else {
            throw makeError(message: "DisplayServices is unavailable")
        }

        let clampedValue = min(1, max(0, value))
        let status = functions.setBrightness(displayID, clampedValue)
        guard status == 0 else {
            throw makeError(message: "DisplayServicesSetBrightness failed with status \(status)")
        }
    }

    private func makeError(message: String) -> NSError {
        NSError(
            domain: "LuxControl.DisplayServicesBrightnessClient",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private struct DisplayServicesFunctions: Sendable {
        let canChangeBrightness: CanChangeBrightness
        let getBrightness: GetBrightness
        let setBrightness: SetBrightness

        static func load() -> DisplayServicesFunctions? {
            guard let handle = dlopen(
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                RTLD_NOW
            ) else {
                return nil
            }

            guard let canChange = dlsym(handle, "DisplayServicesCanChangeBrightness"),
                  let get = dlsym(handle, "DisplayServicesGetBrightness"),
                  let set = dlsym(handle, "DisplayServicesSetBrightness")
            else {
                return nil
            }

            return DisplayServicesFunctions(
                canChangeBrightness: unsafeBitCast(canChange, to: CanChangeBrightness.self),
                getBrightness: unsafeBitCast(get, to: GetBrightness.self),
                setBrightness: unsafeBitCast(set, to: SetBrightness.self)
            )
        }
    }
}
