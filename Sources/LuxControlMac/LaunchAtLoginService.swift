import ServiceManagement

public struct LaunchAtLoginService: Sendable {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard !isEnabled else {
                return
            }

            try SMAppService.mainApp.register()
        } else {
            guard isEnabled else {
                return
            }

            try SMAppService.mainApp.unregister()
        }
    }
}
