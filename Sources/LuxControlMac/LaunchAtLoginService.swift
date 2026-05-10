import ServiceManagement

public struct LaunchAtLoginService: Sendable {
    private let client: any LaunchAtLoginClient

    public init() {
        self.init(client: SMAppServiceLaunchAtLoginClient())
    }

    init(client: any LaunchAtLoginClient) {
        self.client = client
    }

    public var isEnabled: Bool {
        client.isEnabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard !client.isEnabled else {
                return
            }

            try client.register()
        } else {
            guard client.isEnabled else {
                return
            }

            try client.unregister()
        }
    }
}

protocol LaunchAtLoginClient: Sendable {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

private struct SMAppServiceLaunchAtLoginClient: LaunchAtLoginClient {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
