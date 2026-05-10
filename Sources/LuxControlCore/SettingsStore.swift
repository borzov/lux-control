import Foundation

public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func save(state: DisplayState, forStableKey stableKey: String) throws {
        let data = try JSONEncoder().encode(state)
        defaults.set(data, forKey: key(for: stableKey))
    }

    public func loadState(forStableKey stableKey: String) throws -> DisplayState? {
        guard let data = defaults.data(forKey: key(for: stableKey)) else {
            return nil
        }
        return try JSONDecoder().decode(DisplayState.self, from: data)
    }

    private func key(for stableKey: String) -> String {
        "displayState.\(stableKey)"
    }
}
